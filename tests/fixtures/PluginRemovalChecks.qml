import QtQuick

// The runner injects the exact ControlCenterPanel.removePlugin method here.
// Only the process properties are faked: no command can execute in this helper.
Item {
  id: checks
  required property var bar
  property var pluginEntries: []
  readonly property bool stockOmarchyHost: false
  readonly property bool v2LayoutActive: bar.layoutController.v2Mode
  property bool nativeCatalogRequired: false
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
