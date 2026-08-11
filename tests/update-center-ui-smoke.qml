import QtQuick
import Quickshell
import "update" as Update

ShellRoot {
  id: root

  property int removeCalls: 0
  property int reinstallCalls: 0
  property int reviewCalls: 0
  property int themeCheckCalls: 0
  property int themeUpdateCalls: 0
  property int themeReapplyCalls: 0
  property int packageLaunchCalls: 0
  property int packageRefreshCalls: 0
  property int panelCloseCalls: 0
  property var externalActionOrder: []
  property var fullPanelComponent: null

  function fail(message) {
    console.error("update-center-ui-smoke:", message)
    Qt.exit(1)
  }

  function findObject(parent, objectName) {
    if (!parent) return null
    if (String(parent.objectName || "") === objectName) return parent
    const children = parent.children || []
    for (let index = 0; index < children.length; index++) {
      const match = findObject(children[index], objectName)
      if (match) return match
    }
    return null
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
    id: fakeOwnerWidget
    function close() {
      root.panelCloseCalls++
      root.externalActionOrder.push("close")
    }
  }

  QtObject {
    id: fakePanel
    property var bar: fakeBar
    property var ownerWidget: fakeOwnerWidget
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
      total: 3,
      reachable: 3,
      outdated: 2,
      actionable: 1,
      blocked: 1,
      review: 1,
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
        },
        {
          name: "blocked",
          state: "local-edits",
          current: false,
          behind: 3,
          ahead: 0,
          reason: "tracked-edits",
          files: ["colors.toml"],
          remoteUrl: "https://github.com/example/omarchy-blocked-theme.git",
          baseCommit: "dddddddddddddddddddddddddddddddddddddddd",
          targetCommit: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
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
    property bool allowThemeReview: true

    function currentTheme() {
      for (let index = 0; index < themeState.themes.length; index++)
        if (themeState.themes[index].current === true)
          return themeState.themes[index]
      return null
    }
    function refreshPackages() { root.packageRefreshCalls++ }
    function refreshThemes() { root.themeCheckCalls++ }
    function launchPackageUpdate() {
      root.packageLaunchCalls++
      root.externalActionOrder.push("launch")
    }
    function updateTheme(_theme) { return true }
    function updateAllThemes() {
      root.themeUpdateCalls++
      return true
    }
    function reapplyCurrentTheme() {
      root.themeReapplyCalls++
      return true
    }
    function viewThemeChanges(_theme) {
      if (!allowThemeReview) return false
      root.reviewCalls++
      root.externalActionOrder.push("review-launch")
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
    visible: true
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
      const blocked = fakeService.themeState.themes[2]
      if (packagesPanel.packages.length !== 1
          || packagesPanel.summaryText().indexOf("1 official package") !== 0)
        return root.fail("package table did not render structured state")
      const packageRefreshButton = root.findObject(
        packagesPanel, "packageFooterRefresh")
      const systemUpdateButton = root.findObject(
        packagesPanel, "packageFooterSystemUpdate")
      if (!packageRefreshButton || !systemUpdateButton
          || !packageRefreshButton.enabled || !systemUpdateButton.enabled
          || systemUpdateButton.text !== "Full system update (1)"
          || systemUpdateButton.iconText !== "\uf019")
        return root.fail("full system update action did not render")
      systemUpdateButton.clicked()
      if (root.packageLaunchCalls !== 1 || root.panelCloseCalls !== 1
          || root.externalActionOrder.join(",") !== "launch,close")
        return root.fail("system updater did not close its source panel")
      packageRefreshButton.clicked()
      if (root.packageRefreshCalls !== 1 || root.panelCloseCalls !== 1)
        return root.fail("package refresh unexpectedly closed the panel")
      if (themesPanel.themes.length !== 3
          || !themesPanel.canReview(demo)
          || !themesPanel.canUpdate(demo)
          || !themesPanel.canReinstall(demo)
          || !themesPanel.canRemove(demo)
          || blocked.state !== "local-edits"
          || Number(blocked.behind || 0) <= 0)
        return root.fail("theme row capabilities were not preserved")

      if (!themesPanel.openThemeReview(demo)
          || root.reviewCalls !== 1 || root.panelCloseCalls !== 2
          || root.externalActionOrder.join(",")
            !== "launch,close,review-launch,close")
        return root.fail("theme review did not close its source panel")
      fakeService.allowThemeReview = false
      if (themesPanel.openThemeReview(demo)
          || root.reviewCalls !== 1 || root.panelCloseCalls !== 2)
        return root.fail("rejected theme review unexpectedly closed the panel")
      themesPanel.armAction("reinstall", demo)
      themesPanel.confirmActionFor(demo)
      themesPanel.armAction("remove", demo)
      themesPanel.confirmActionFor(demo)
      if (root.reviewCalls !== 1 || root.reinstallCalls !== 1
          || root.removeCalls !== 1 || themesPanel.confirmAction !== "")
        return root.fail("theme actions or confirmation lifecycle drifted")

      const footerRow = root.findObject(themesPanel, "themeFooterActions")
      const reapplyButton = root.findObject(
        themesPanel, "themeFooterReapply")
      const checkButton = root.findObject(themesPanel, "themeFooterCheck")
      const updateButton = root.findObject(themesPanel, "themeFooterUpdate")
      if (!footerRow || !reapplyButton || !checkButton || !updateButton)
        return root.fail("theme footer buttons were not instantiated")
      footerRow.forceLayout()
      const tolerance = 0.5
      if (!reapplyButton.visible || !checkButton.visible
          || !updateButton.visible
          || !reapplyButton.enabled || !checkButton.enabled
          || !updateButton.enabled
          || reapplyButton.text !== "Re-Apply current"
          || checkButton.text !== "Check themes"
          || updateButton.text !== "Update clean (1)"
          || reapplyButton.iconText !== ""
          || checkButton.iconText !== ""
          || updateButton.iconText !== "\uf019"
          || reapplyButton.width <= 0
          || Math.abs(reapplyButton.x) > tolerance
          || Math.abs(checkButton.x - reapplyButton.width
              - footerRow.spacing) > tolerance
          || Math.abs(updateButton.x - checkButton.x
              - checkButton.width - footerRow.spacing) > tolerance
          || Math.abs(updateButton.x + updateButton.width
              - footerRow.width) > tolerance
          || Math.abs(reapplyButton.width - checkButton.width) > tolerance
          || Math.abs(checkButton.width - updateButton.width) > tolerance)
        return root.fail("three-action theme footer layout drifted: "
          + JSON.stringify({
            row: { width: footerRow.width, spacing: footerRow.spacing },
            reapply: {
              visible: reapplyButton.visible,
              enabled: reapplyButton.enabled,
              text: reapplyButton.text,
              icon: reapplyButton.iconText,
              x: reapplyButton.x,
              width: reapplyButton.width
            },
            check: {
              visible: checkButton.visible,
              enabled: checkButton.enabled,
              text: checkButton.text,
              icon: checkButton.iconText,
              x: checkButton.x,
              width: checkButton.width
            },
            update: {
              visible: updateButton.visible,
              enabled: updateButton.enabled,
              text: updateButton.text,
              icon: updateButton.iconText,
              x: updateButton.x,
              width: updateButton.width
            }
          }))

      reapplyButton.clicked()
      checkButton.clicked()
      updateButton.clicked()
      if (root.themeReapplyCalls !== 1 || root.themeCheckCalls !== 1
          || root.themeUpdateCalls !== 1)
        return root.fail("theme footer actions crossed their labels")
      if (root.panelCloseCalls !== 2)
        return root.fail("theme footer action unexpectedly closed the panel")

      fakeService.packageState = Object.assign({}, fakeService.packageState, {
        state: "current",
        count: 0,
        packages: []
      })
      fakeService.themeState = Object.assign({}, fakeService.themeState, {
        total: 2,
        reachable: 2,
        outdated: 2,
        actionable: 1,
        blocked: 1,
        review: 1,
        themes: [demo, blocked]
      })
      Qt.callLater(function() {
        footerRow.forceLayout()
        if (reapplyButton.visible || !checkButton.visible
            || !updateButton.visible || !checkButton.enabled
            || !updateButton.enabled || checkButton.width <= 0
            || Math.abs(checkButton.x) > tolerance
            || Math.abs(updateButton.x - checkButton.width
                - footerRow.spacing) > tolerance
            || Math.abs(updateButton.x + updateButton.width
                - footerRow.width) > tolerance
            || Math.abs(checkButton.width - updateButton.width) > tolerance)
          return root.fail("two-action theme footer fallback drifted")
        if (!systemUpdateButton.enabled
            || systemUpdateButton.text !== "Open system updater")
          return root.fail("empty package updater action drifted")
        systemUpdateButton.clicked()
        if (root.packageLaunchCalls !== 2 || root.panelCloseCalls !== 3
            || root.externalActionOrder.join(",")
              !== "launch,close,review-launch,close,launch,close")
          return root.fail("empty system updater did not close its source panel")
        console.log("update center UI smoke passed")
        Qt.quit()
      })
    }
  }
}
