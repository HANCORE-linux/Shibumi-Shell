pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "state" as State
import "control" as Control

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property var clickTargets: []

  function fail(message) {
    console.error("control-center-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeShell

    property int writes: 0
    property string activeBarId: "hancore.shibumi.bar"
    property var shellConfig: ({ version: 1, bar: { shibumi: { version: 1 } } })

    function mutateShellConfig(mutator) {
      const next = JSON.parse(JSON.stringify(shellConfig))
      mutator(next)
      shellConfig = next
      writes++
    }

    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.state" ? stateService : null
    }
  }

  QtObject {
    id: fakeBar

    property var shell: fakeShell
    property bool vertical: false
    property int barSize: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#d75f5f"
    property var activePopout: null
    property int positionWrites: 0
    property int splitWrites: 0
    property int resetWrites: 0
    property int restoreWrites: 0
    property string restoredWidgetId: ""
    property string restoredPage: ""
    property bool lastSplitValue: false
    property var clickTargets: root.clickTargets
    property var visualTokens: ({
      pillHeight: 24,
      pillRadius: 12,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      panelBackground: "#202020",
      panelBorder: "#404040",
      panelBorderWidth: 1,
      panelRadius: 12
    })

    function registerClickTarget(target) {
      if (root.clickTargets.indexOf(target) < 0)
        root.clickTargets = root.clickTargets.concat([target])
    }

    function unregisterClickTarget(target) {
      root.clickTargets = root.clickTargets.filter(item => item !== target)
    }

    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }

    function scheduleWidgetRestore(pluginId, page) {
      restoredWidgetId = String(pluginId || "")
      restoredPage = String(page || "")
      restoreWrites++
      return true
    }

    function setBarPosition(value) {
      const next = String(value || "")
      if (next !== "top" && next !== "bottom") return false
      position = next
      positionWrites++
      return true
    }

    function setAllSplits(value) {
      if (typeof value !== "boolean") return false
      lastSplitValue = value
      splitWrites++
      return true
    }

    function resetBarLayout() {
      resetWrites++
      return true
    }
  }

  State.Service {
    id: stateService
    shell: fakeShell
  }

  Loader {
    id: widgetLoader
    active: true
    sourceComponent: Component {
      Control.BarWidget {
        bar: fakeBar
        panelSource: Qt.resolvedUrl("fixtures/ControlCenterTestPanel.qml")
      }
    }
  }

  Timer {
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      root.ticks++
      const widget = widgetLoader.item

      if (root.phase === 0) {
        if (!stateService.ready || !widget || root.ticks < 3) return
        if (widget.moduleName !== "hancore.shibumi.control-center"
            || widget.panelLoaded || widget.iconMode
            || !widget.shibumiWordmark
            || widget.launcherConfig.text !== "shibumi"
            || root.clickTargets.length !== 1)
          return root.fail("closed G1 lifecycle or identity")

        widget.open()
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!widget || !widget.panelLoaded || !widget.panelItem
            || root.ticks < 3) return
        const panel = widget.panelItem
        if (!panel.open || panel.ownerWidget !== widget
            || panel.stateService !== stateService
            || !panel.settingsReady || !panel.settingsFitsWidth
            || panel.barPosition !== "top"
            || fakeBar.activePopout !== widget)
          return root.fail("panel injection, layout, or popout ownership")

        if (!panel.setGroupSetting("G4", "compact", true)
            || !panel.setBarPresentation("accent", "color06")
            || !panel.setBarPresentation("radius", "small")
            || !panel.setWorkspacePreference("mode", "5")
            || !panel.setImagePickerStyle("omarchy")
            || !panel.setMediaPickerStyle("hearthstone")
            || !panel.setReactorMode(8))
          return root.fail("state mutation facade rejected valid values")

        if (stateService.groupSetting("G4", "compact", false) !== true
            || stateService.config.presentation.accent !== "color06"
            || stateService.config.presentation.radius !== "small"
            || panel.controlRadius !== 4
            || stateService.config.workspace.mode !== "5"
            || stateService.config.picker.imageStyle !== "omarchy"
            || stateService.config.picker.mediaStyle !== "hearthstone"
            || stateService.config.picker.style !== "hearthstone"
            || stateService.config.reactor.mode !== 8
            || fakeShell.writes !== 7)
          return root.fail("state mutations did not persist")

        if (!panel.setBarPosition("bottom")
            || !panel.setAllSplits(true)
            || !panel.resetBarLayout()
            || fakeBar.positionWrites !== 1
            || fakeBar.splitWrites !== 1 || !fakeBar.lastSplitValue
            || fakeBar.resetWrites !== 1 || panel.barPosition !== "bottom")
          return root.fail("host layout facade did not receive mutations")

        if (!panel.activateLauncherMode("icon")
            || !panel.activateLauncherMode("icon"))
          return root.fail("launcher state mutation failed")

        if (!panel.showSettingsPage("functions"))
          return root.fail("appearance page rejected")
        if (!panel.open || !widget.opened
            || typeof fakeBar.scheduleWidgetRestore !== "function")
          return root.fail("restore precondition missing open=" + panel.open
            + " owner=" + widget.opened
            + " type=" + typeof fakeBar.scheduleWidgetRestore)
        if (!panel.setBarPresentation("shellStyle", "full")
            || fakeBar.restoreWrites !== 1
            || fakeBar.restoredWidgetId !== "hancore.shibumi.control-center"
            || fakeBar.restoredPage !== "functions"
            || stateService.config.presentation.shellStyle !== "full"
            || fakeShell.writes !== 10)
          return root.fail("shell-style change did not preserve the open page"
            + " restore=" + fakeBar.restoreWrites
            + " id=" + fakeBar.restoredWidgetId
            + " page=" + fakeBar.restoredPage
            + " style=" + stateService.config.presentation.shellStyle
            + " writes=" + fakeShell.writes)

        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (!panel || !panel.settingsPageReady
            || panel.settingsPage !== "functions"
            || !panel.settingsPageItem
            || !panel.settingsPageItem.ready
            || !panel.settingsPageItem.workbenchReady
            || panel.settingsPageItem.widgetOptionCount !== 18
            || !panel.settingsPageItem.allWidgetModesReady
            || panel.settingsPageItem.colorSwatchCount !== 9
            || panel.settingsPageItem.colorColumnCount !== 9
            || panel.settingsPageItem.firstColorRadius !== 4)
          return root.fail("appearance page did not instantiate")

        const appearance = panel.settingsPageItem
        appearance.setWidgetMode("G18", "text")
        appearance.setWidgetSurface("G18", "both")
        appearance.controller.setGroupSetting("G18", "color", "color05")
        appearance.controller.setGroupSetting("G18", "tone", "background")
        appearance.controller.setGroupSetting("G18", "widgetRadius", "round")
        appearance.controller.setGroupSetting("G18", "widgetPadding", "roomy")
        appearance.controller.setGroupSetting("G18", "surfaceOpacity", 0.8)
        appearance.controller.setGroupSetting("G18", "separator", true)
        appearance.controller.setGroupSetting("G18", "widgetBorderWidth", 2)

        if (stateService.groupSetting("G18", "displayMode", "") !== "text"
            || stateService.groupSetting("G18", "compact", true) !== false
            || stateService.groupSetting("G18", "colorMode", "") !== "both"
            || stateService.groupSetting("G18", "widgetBorder", false) !== true
            || stateService.groupSetting("G18", "color", "") !== "color05"
            || stateService.groupSetting("G18", "tone", "") !== "background"
            || stateService.groupSetting("G18", "widgetRadius", "") !== "round"
            || stateService.groupSetting("G18", "widgetPadding", "") !== "roomy"
            || stateService.groupSetting("G18", "surfaceOpacity", 0) !== 0.8
            || stateService.groupSetting("G18", "separator", false) !== true
            || stateService.groupSetting("G18", "widgetBorderWidth", 0) !== 2)
          return root.fail("per-widget appearance contract did not persist")
        if (!appearance.controller.resetGroupAppearance("G18")
            || stateService.groupSetting("G18", "displayMode", "full") !== "full"
            || stateService.groupSetting("G18", "color", "inherit") !== "inherit"
            || stateService.groupSetting("G18", "widgetPadding", "auto") !== "auto"
            || stateService.groupSetting("G18", "separator", false) !== true
            || !panel.showSettingsPage("splits"))
          return root.fail("appearance reset did not preserve nonvisual state")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (!panel || !panel.settingsPageReady
            || panel.settingsPage !== "splits"
            || !panel.showSettingsPage("preferences"))
          return root.fail("splits page did not instantiate")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (!panel || !panel.settingsPageReady
            || panel.settingsPage !== "preferences"
            || !panel.showSettingsPage("main"))
          return root.fail("advanced page did not instantiate")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (!panel || !panel.settingsPageReady || panel.settingsPage !== "main"
            || !widget.iconMode || widget.launcherConfig.icon !== "hyprland")
          return root.fail("overview page or G1 presentation did not restore")
        widget.close()
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (!widget || root.ticks < 3) return
        if (widget.opened || widget.panelLoaded || fakeBar.activePopout !== null)
          return root.fail("panel did not release on close")
        fakeShell.activeBarId = "omarchy.bar"
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (!widget || root.ticks < 2) return
        if (!widget.stockOmarchyHost || !widget.iconMode)
          return root.fail("stock Omarchy host identity was not detected")
        widgetLoader.active = false
        root.phase++
        root.ticks = 0
        return
      }

      if (root.ticks < 3) return
      if (root.clickTargets.length !== 0 || fakeBar.activePopout !== null)
        return root.fail("destruction cleanup")

      stop()
      console.log("control center smoke passed")
      Qt.quit()
    }
  }
}
