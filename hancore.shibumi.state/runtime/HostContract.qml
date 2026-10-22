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
  readonly property var nativeSections: ["left", "centerBegin", "center", "centerEnd", "right", "tray"]
  readonly property string trayDrawerDiagnostic: "Tray-drawer bar widgets are preserved but not shown by Shibumi. Open Control Center > Bars and switch to Omarchy (stock bar) to use them."

  // The public Util.barSections capability, not layout contents or a version
  // guess, selects native default-placement semantics. Its absence is the
  // admitted legacy contract. An unknown present contract fails closed.
  function nativeDefaultSection(value, hostSections) {
    const section = value === undefined ? "center" : value
    if (nativeSections.indexOf(section) < 0) return ""
    if (hostSections === undefined) return section
    if (JSON.stringify(hostSections) !== JSON.stringify(nativeSections)) return ""
    return section === "center" ? "centerEnd" : section
  }

  function isFirstPartyService(id) {
    return firstPartyServices.indexOf(String(id || "")) >= 0
  }
  function path(home, key) { return home + "/" + contract[key] }
  function fileName(key) { return contract[key].split("/").pop() }
}
