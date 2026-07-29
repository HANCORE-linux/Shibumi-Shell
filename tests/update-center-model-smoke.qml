import QtQuick
import Quickshell
import "Model.js" as Model

ShellRoot {
  id: root

  property bool passed: false

  function fail(message) {
    console.error("update-center-model-smoke:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    const packages = Model.parsePackageStatus(JSON.stringify({
      schemaVersion: 1,
      checkedEpoch: 1784400000,
      available: true,
      state: "updates",
      reason: "",
      packages: [{ name: "linux", installed: "6.1-1", target: "6.1-2" }]
    }))
    if (packages.state !== "updates" || packages.count !== 1
        || packages.packages[0].target !== "6.1-2")
      return fail("valid package state was not preserved")

    const inconsistent = Model.parsePackageStatus(JSON.stringify({
      schemaVersion: 1,
      available: true,
      state: "current",
      packages: [{ name: "linux", installed: "6.1-1", target: "6.1-2" }]
    }))
    if (inconsistent.state !== "invalid" || inconsistent.count !== 0)
      return fail("inconsistent package state did not fail closed")

    const themes = Model.parseThemeStatus(JSON.stringify({
      schemaVersion: 1,
      total: 99,
      degraded: false,
      themes: [
        { name: "active", state: "update", current: true, behind: 2,
          ahead: 0, remoteUrl: "https://github.com/example/omarchy-active-theme.git",
          baseCommit: "a", targetCommit: "b" },
        { name: "clean", state: "clean", current: false, behind: 0,
          ahead: 0, baseCommit: "c", targetCommit: "c" }
      ]
    }))
    if (themes.total !== 2 || themes.outdated !== 1 || themes.actionable !== 1
        || themes.themes[0].remoteUrl !== "https://github.com/example/omarchy-active-theme.git"
        || Model.themeStateLabel(themes.themes[0]) !== "Update available"
        || Model.preferredTab(0, 1, 0, false, "") !== "themes")
      return fail("theme state normalization or preferred tab drifted")

    if (!Model.canReinstallTheme({
          name: "active",
          remoteUrl: "https://github.com/example/omarchy-active-theme.git"
        })
        || Model.canReinstallTheme({
          name: "active",
          remoteUrl: "https://github.com/example/omarchy-other-theme.git"
        })
        || Model.canReinstallTheme({
          name: "../active",
          remoteUrl: "https://github.com/example/omarchy-active-theme.git"
        }))
      return fail("theme reinstall provenance validation drifted")

    const unknown = Model.parseThemeStatus(JSON.stringify({
      schemaVersion: 1,
      themes: [{ name: "unsafe", state: "unknown-state" }]
    }))
    if (!unknown.degraded || unknown.themes.length !== 0)
      return fail("unknown theme state did not fail closed")

    passed = true
  }

  Timer {
    interval: 50
    running: root.passed
    onTriggered: {
      console.log("update center model smoke passed")
      Qt.quit()
    }
  }
}
