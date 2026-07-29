import QtQuick
import Quickshell
import "update" as Update

ShellRoot {
  id: root

  property int removeCalls: 0
  property int reinstallCalls: 0
  property int reviewCalls: 0
  property var fullPanelComponent: null

  function fail(message) {
    console.error("update-center-ui-smoke:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    fullPanelComponent = Qt.createComponent(
      Qt.resolvedUrl("update/UpdateCenterPanel.qml"))
  }

  QtObject {
    id: fakeBar
    property color foreground: "#e8e8e8"
    property color urgent: "#ff6b6b"
    property string fontFamily: "monospace"
  }

  QtObject {
    id: fakePanel
    property var bar: fakeBar
    property var shibumiTokens: null
    property color controlForeground: fakeBar.foreground
    property color controlMuted: "#909090"
    property color controlAccent: fakeBar.urgent
    property color controlBorderColor: "#404040"
    property color controlHoverBorderColor: fakeBar.urgent
    property color controlFillColor: "#181818"
    property color controlHoverFillColor: "#242424"
    property color controlActiveFillColor: "#302020"
    property color controlPrimaryHoverColor: "#ff8585"
    property color dividerColor: "#303030"
    property real controlBorderWidth: 1
  }

  QtObject {
    id: fakeService
    property var packageState: ({
      schemaVersion: 1,
      checkedEpoch: Math.floor(Date.now() / 1000),
      state: "updates",
      count: 1,
      packages: [
        { name: "linux", installed: "6.1-1", target: "6.1-2" }
      ]
    })
    property var themeState: ({
      schemaVersion: 1,
      checkedEpoch: Math.floor(Date.now() / 1000),
      total: 2,
      reachable: 2,
      outdated: 1,
      actionable: 1,
      blocked: 0,
      review: 0,
      degraded: false,
      themes: [
        {
          name: "demo",
          state: "update",
          current: false,
          behind: 2,
          ahead: 0,
          reason: "",
          files: [],
          remoteUrl: "https://github.com/example/omarchy-demo-theme.git",
          baseCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          targetCommit: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        {
          name: "current",
          state: "clean",
          current: true,
          behind: 0,
          ahead: 0,
          reason: "",
          files: [],
          remoteUrl: "https://github.com/example/omarchy-current-theme.git",
          baseCommit: "cccccccccccccccccccccccccccccccccccccccc",
          targetCommit: "cccccccccccccccccccccccccccccccccccccccc"
        }
      ]
    })
    property bool packageRefreshing: false
    property bool themeRefreshing: false
    property string packageError: ""
    property string themeError: ""
    property string actionName: ""
    property string actionKind: ""
    property string actionStatus: ""
    property string actionError: ""
    property bool currentThemeNeedsReapply: true

    function currentTheme() { return themeState.themes[1] }
    function refreshPackages() {}
    function refreshThemes() {}
    function launchPackageUpdate() {}
    function updateTheme(_theme) { return true }
    function updateAllThemes() { return true }
    function reapplyCurrentTheme() { return true }
    function viewThemeChanges(_theme) {
      root.reviewCalls++
      return true
    }
    function reinstallTheme(_theme) {
      root.reinstallCalls++
      return true
    }
    function removeTheme(_theme) {
      root.removeCalls++
      return true
    }
  }

  Update.PackagesTab {
    id: packagesPanel
    width: 500
    height: 360
    visible: false
    updateService: fakeService
    panel: fakePanel
  }

  Update.ThemesTab {
    id: themesPanel
    width: 500
    height: 360
    visible: false
    updateService: fakeService
    panel: fakePanel
  }

  Timer {
    interval: 150
    running: true
    onTriggered: {
      if (!root.fullPanelComponent
          || root.fullPanelComponent.status !== Component.Ready)
        return root.fail("full update panel component did not load: "
          + (root.fullPanelComponent
            ? root.fullPanelComponent.errorString() : "missing component"))
      const demo = fakeService.themeState.themes[0]
      if (packagesPanel.packages.length !== 1
          || packagesPanel.summaryText().indexOf("1 official package") !== 0)
        return root.fail("package table did not render structured state")
      if (themesPanel.themes.length !== 2
          || !themesPanel.canReview(demo)
          || !themesPanel.canUpdate(demo)
          || !themesPanel.canReinstall(demo)
          || !themesPanel.canRemove(demo))
        return root.fail("theme row capabilities were not preserved")

      fakeService.viewThemeChanges(demo)
      themesPanel.armAction("reinstall", demo)
      themesPanel.confirmActionFor(demo)
      themesPanel.armAction("remove", demo)
      themesPanel.confirmActionFor(demo)
      if (root.reviewCalls !== 1 || root.reinstallCalls !== 1
          || root.removeCalls !== 1 || themesPanel.confirmAction !== "")
        return root.fail("theme actions or confirmation lifecycle drifted")

      console.log("update center UI smoke passed")
      Qt.quit()
    }
  }
}
