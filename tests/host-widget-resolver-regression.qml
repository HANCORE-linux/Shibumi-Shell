import QtQuick
import "../services" as Services

Item {
  id: root

  function fail(message) {
    console.error("host-widget-resolver-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakePluginRegistry

    signal pluginsChanged()

    property var installedPlugins: ({
      "omarchy.test": {
        id: "omarchy.test",
        kinds: ["bar-widget"],
        entryPoints: { barWidget: "ResolverTestWidget.qml" }
      }
    })

    function entryPointUrl(manifest, kind) {
      return manifest && kind === "barWidget"
        ? Qt.resolvedUrl("fixtures/ResolverTestWidget.qml") : ""
    }
  }

  QtObject {
    id: fakeBar

    property var pluginRegistry: fakePluginRegistry
    // A replacement bar must not depend on this host-owned stale handle.
    property var barWidgetRegistry: ({
      widgets: { "omarchy.test": { component: null } }
    })
  }

  Services.HostWidgetResolver {
    id: resolver
    bar: fakeBar
  }

  Timer {
    interval: 0
    running: true
    onTriggered: {
      const first = resolver.ensureComponent("omarchy.test")
      const second = resolver.componentFor("omarchy.test")
      if (!first || first.status !== Component.Ready)
        return root.fail("manifest entry point did not resolve")
      if (first !== second)
        return root.fail("component handle was not retained by the resolver")
      if (resolver.ensureComponent("omarchy.missing") !== null)
        return root.fail("missing manifest resolved unexpectedly")

      const item = first.createObject(null)
      if (!item || item.marker !== "resolver-owned")
        return root.fail("resolved component could not create the fixture")
      item.destroy()
      console.log("host widget resolver regression passed")
      Qt.quit()
    }
  }
}
