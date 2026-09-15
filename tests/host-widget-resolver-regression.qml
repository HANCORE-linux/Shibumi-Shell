import QtQuick
import "../hancore.shibumi.bar/services" as Services

Item {
  id: root

  function fail(message) {
    console.error("host-widget-resolver-regression:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  QtObject {
    id: fakePluginRegistry

    signal pluginsChanged()
    property string selectedId: "omarchy.test"
    property var installedPlugins: ({
      "omarchy.test": {
        id: "omarchy.test", name: "Original",
        kinds: ["bar-widget"],
        entryPoints: { barWidget: "ResolverTestWidget.qml" }
      },
      "local.test": {
        id: "local.test", name: "Local clone",
        kinds: ["bar-widget"],
        omarchy: { clonedFrom: "omarchy.test" },
        entryPoints: { barWidget: "ResolverReplacementWidget.qml" }
      }
    })

    function resolveEnabledId(id) {
      return id === "omarchy.test" ? selectedId : id
    }
    function entryPointUrl(manifest, kind) {
      return manifest && kind === "barWidget" && manifest.entryPoints
        ? Qt.resolvedUrl("fixtures/" + manifest.entryPoints.barWidget) : ""
    }
  }

  QtObject {
    id: legacyRegistry
    signal pluginsChanged()
    readonly property var installedPlugins: fakePluginRegistry.installedPlugins
    function entryPointUrl(manifest, kind) {
      return fakePluginRegistry.entryPointUrl(manifest, kind)
    }
  }

  QtObject {
    id: fakeBar
    property var pluginRegistry: fakePluginRegistry
    property var barWidgetRegistry: ({
      widgets: { "omarchy.test": { component: null } }
    })
  }

  Services.HostWidgetResolver { id: resolver; bar: fakeBar }

  Timer {
    interval: 0
    running: true
    onTriggered: {
      const first = resolver.ensureComponent("omarchy.test")
      if (!first || first.status !== Component.Ready
          || first !== resolver.componentFor("omarchy.test"))
        return root.fail("original manifest/component resolution")
      const item = first.createObject(null)
      if (!item || item.marker !== "resolver-owned")
        return root.fail("original fixture creation")
      item.destroy()
      fakePluginRegistry.pluginsChanged()
      if (resolver.ensureComponent("omarchy.test") !== first)
        return root.fail("settings-only refresh recreated the component")
      if (resolver.ensureComponent("omarchy.missing") !== null)
        return root.fail("missing manifest resolved")

      fakePluginRegistry.selectedId = "local.test"
      if (resolver.componentFor("omarchy.test") !== null)
        return root.fail("stale original survived clone selection")
      fakePluginRegistry.pluginsChanged()
      const clone = resolver.ensureComponent("omarchy.test")
      if (!clone || clone === first
          || resolver.manifestFor("omarchy.test").id !== "local.test")
        return root.fail("enabled clone or its metadata was not selected")
      const cloneItem = clone.createObject(null)
      if (!cloneItem || cloneItem.marker !== "resolver-replaced")
        return root.fail("clone component content")
      cloneItem.destroy()
      fakePluginRegistry.pluginsChanged()
      if (resolver.ensureComponent("omarchy.test") !== clone)
        return root.fail("unchanged clone refresh replaced its handle")

      // Disabling a clone makes the host choose the original again.
      fakePluginRegistry.selectedId = "omarchy.test"
      fakePluginRegistry.pluginsChanged()
      if (!resolver.ensureComponent("omarchy.test")
          || resolver.manifestFor("omarchy.test").id !== "omarchy.test")
        return root.fail("clone disable did not restore host resolution")

      // A removal race must not turn an unavailable selected clone into an
      // unauthorized original. The host can select the original afterwards.
      fakePluginRegistry.selectedId = "local.test"
      fakePluginRegistry.installedPlugins = ({
        "omarchy.test": fakePluginRegistry.installedPlugins["omarchy.test"]
      })
      fakePluginRegistry.pluginsChanged()
      if (resolver.ensureComponent("omarchy.test") !== null
          || resolver.componentFor("omarchy.test") !== null)
        return root.fail("missing selected clone fell back to the original")
      fakePluginRegistry.selectedId = ""
      if (resolver.ensureComponent("omarchy.test") !== null
          || resolver.manifestFor("omarchy.test") !== null)
        return root.fail("explicit host refusal fell back to original")

      // Older hosts without clone resolution retain direct lookup.
      fakeBar.pluginRegistry = legacyRegistry
      resolver.syncRegistry()
      if (!resolver.ensureComponent("omarchy.test"))
        return root.fail("legacy registry without clone API")
      console.log("host widget resolver regression passed")
      Qt.quit()
    }
  }
}
