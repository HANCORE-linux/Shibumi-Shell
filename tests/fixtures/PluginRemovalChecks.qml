import QtQuick

// The runner injects exact ControlCenterPanel methods here. Only process and
// catalog dependencies are controlled; no command can execute in this helper.
Item {
  id: checks
  required property var bar
  property var pluginEntries: []
  readonly property bool stockOmarchyHost: false
  readonly property bool v2LayoutActive: bar.layoutController.v2Mode
  property bool nativeCatalogRequired: false
  property int pluginRevision: 0
  property var pluginRegistry: null
  property var pluginCatalogSnapshot: null
  property var stateConfig: ({ widgets: ({}) })
  property bool legacyCatalogEnabled: false
  property int installedPluginReads: 0
  property string removalPluginId: ""
  property bool removalPluginWasInBar: false
  property var removalReplacementGroups: []
  property string pluginActionError: ""
  QtObject {
    id: pluginRemoval
    property var command: []
    property bool running: false
  }

  // INJECT_REMOVE_PLUGIN
  // INJECT_BUILD_PLUGIN_ENTRIES

  function catalogFailure(message) {
    console.error("plugin catalog registry isolation regression: " + message)
    Qt.exit(1)
    throw new Error(message)
  }

  function catalogManifest() {
    return {
      id: "acme.service",
      name: "Acme Service",
      kinds: ["service"],
      "x-shibumi": ({}),
      __isFirstParty: false,
      description: "Controlled catalog service",
      author: "Acme",
      version: "1.0.0",
      tags: ["controlled"],
      barWidget: ({})
    }
  }

  function registrySpy(manifest) {
    const installed = ({ "acme.service": manifest })
    const registry = {
      isEnabled: function(pluginId) {
        return pluginId === "acme.service" && checks.legacyCatalogEnabled
      }
    }
    Object.defineProperty(registry, "installedPlugins", {
      enumerable: true,
      get: function() {
        checks.installedPluginReads++
        return installed
      }
    })
    return registry
  }

  function nativeSnapshot(enabled) {
    const row = Object.freeze({
      id: "acme.service",
      name: "Acme Service",
      kinds: Object.freeze(["service"]),
      enabled: enabled === true,
      active: enabled === true,
      firstParty: false,
      description: "Controlled catalog service",
      author: "Acme",
      version: "1.0.0",
      tags: Object.freeze(["controlled"]),
      barWidget: Object.freeze(({})),
      canDisable: true,
      clonedFrom: ""
    })
    const byId = Object.create(null)
    byId[row.id] = row
    Object.freeze(byId)
    return Object.freeze({
      entries: Object.freeze([row]),
      byId: byId
    })
  }

  function verifyPluginCatalogRegistryIsolation() {
    pluginRegistry = registrySpy(catalogManifest())
    nativeCatalogRequired = true
    installedPluginReads = 0

    const emptyById = Object.create(null)
    Object.freeze(emptyById)
    pluginCatalogSnapshot = Object.freeze({
      entries: Object.freeze([]),
      byId: emptyById
    })
    if (buildPluginEntries().length !== 0 || installedPluginReads !== 0)
      catalogFailure("valid empty native catalog read the legacy registry")

    pluginCatalogSnapshot = Object.freeze({
      entries: Object.freeze([]),
      byId: ({})
    })
    if (buildPluginEntries().length !== 0 || installedPluginReads !== 0)
      catalogFailure("malformed native catalog fell back to the legacy registry")

    for (const enabled of [false, true]) {
      legacyCatalogEnabled = enabled
      pluginCatalogSnapshot = nativeSnapshot(enabled)
      installedPluginReads = 0
      const nativeEntries = buildPluginEntries()
      if (installedPluginReads !== 0)
        catalogFailure("native catalog parity read the legacy registry")

      nativeCatalogRequired = false
      const legacyEntries = buildPluginEntries()
      if (installedPluginReads === 0)
        catalogFailure("legacy catalog did not read installedPlugins")
      if (JSON.stringify(nativeEntries) !== JSON.stringify(legacyEntries))
        catalogFailure("native and legacy catalog snapshots diverged after current update")
      nativeCatalogRequired = true
    }

    nativeCatalogRequired = false
    return true
  }

  function verify(pluginId, allowed) {
    nativeCatalogRequired = false
    pluginEntries = [{ id: pluginId, removable: true, barWidget: true,
      installedInBar: true, replacementGroups: [] }]
    pluginActionError = "old unrelated error"
    const accepted = removePlugin(pluginId)
    const valid = accepted === allowed && pluginRemoval.running === allowed
      && (allowed
        ? pluginActionError === "" && JSON.stringify(pluginRemoval.command) === JSON.stringify(
          ["omarchy", "plugin", "remove", pluginId, "--yes"])
        : pluginRemoval.command.length === 0 && removalPluginId === ""
          && !removalPluginWasInBar && removalReplacementGroups.length === 0
          && pluginActionError.indexOf("extra bar slot") >= 0)
    pluginRemoval.running = false
    pluginRemoval.command = []
    removalPluginId = ""
    removalPluginWasInBar = false
    removalReplacementGroups = []
    if (!valid) {
      console.error("plugin removal preflight regression: expected allowed=" + allowed)
      Qt.exit(1)
      throw new Error("plugin removal preflight failure")
    }
    return true
  }

  function verifyScopedActive(pluginId, replacementGroups) {
    nativeCatalogRequired = true
    pluginEntries = [{ id: pluginId, removable: true, barWidget: true,
      installedInBar: true,
      replacementGroups: Array.isArray(replacementGroups)
        ? replacementGroups.slice() : [] }]
    pluginActionError = ""
    const accepted = removePlugin(pluginId)
    const valid = !accepted && !pluginRemoval.running
      && pluginRemoval.command.length === 0 && removalPluginId === ""
      && !removalPluginWasInBar && removalReplacementGroups.length === 0
      && pluginActionError.indexOf("Deactivate this plugin") >= 0
    nativeCatalogRequired = false
    if (!valid) {
      console.error("scoped active plugin removal started without cleanup authority")
      Qt.exit(1)
      throw new Error("scoped active plugin removal preflight failure")
    }
    return true
  }
}
