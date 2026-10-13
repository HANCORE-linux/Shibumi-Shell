pragma Singleton

import QtQuick

// Revision-bound host identifiers only; no runtime authority or workers.
QtObject {
  id: contract
  readonly property var firstPartyServices: ["omarchy.idle", "omarchy.media", "omarchy.notifications"]
  readonly property string stateRoot: ".local/state/omarchy"
  readonly property string togglesDir: stateRoot + "/toggles"
  readonly property string barOffMarker: togglesDir + "/bar-off"
  // Suite-side legacy alias, not a pinned host path; retained for compatibility.
  readonly property string barHiddenMarker: togglesDir + "/bar-hidden"
  readonly property string themeDir: stateRoot + "/current/theme"
  readonly property string themeColorsFile: themeDir + "/colors.toml"
  readonly property string themeNameFile: stateRoot + "/current/theme.name"
  readonly property var ipcTargets: ({
    bar: "omarchy.bar", audio: "omarchy.audio",
    bluetooth: "omarchy.bluetooth", network: "omarchy.network"
  })
  readonly property string shellCommand: "omarchy-shell"

  function isFirstPartyService(id) {
    return firstPartyServices.indexOf(String(id || "")) >= 0
  }
  function path(home, key) { return home + "/" + contract[key] }
  function fileName(key) { return contract[key].split("/").pop() }
}
