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
  property int barsRouteStep: 0
  property int iconsNoScrollStep: 0
  property bool panelIdempotenceStarted: false
  property var stablePanelItem: null
  property int healthLifecycleStep: 0
  property var lifecycleHealthService: null
  property int lifecycleReportEpoch: 0
  property int activeBarStatusStep: 0
  property bool statusStockHost: false
  property bool statusV2Layout: false
  property real widestActiveBarStatus: 0

  Control.PluginUpdateTestService { id: pluginUpdateService }

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
    property int restoreCancelWrites: 0
    property string restoredWidgetId: ""
    property string restoredPage: ""
    property bool restoreNeedsReplacement: false
    property string pendingWidgetRestoreId: ""
    property var pendingWidgetRestoreOwner: null
    property string pendingWidgetRestoreScreenName: ""
    property bool lastSplitValue: false
    property var clickTargets: root.clickTargets
    property var visualTokens: ({
      shellStyle: "shibumi",
      v2Shell: false,
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
      panelRadius: 12,
      widgetHasFill: function(settings) {
        return settings && settings.color === "color05"
      },
      widgetFillColor: function(settings) {
        return settings && settings.color === "color05"
          ? "#cc8844" : "transparent"
      },
      widgetSurfaceOpacity: function(settings) {
        return settings && settings.surfaceOpacity !== undefined
          ? Number(settings.surfaceOpacity) : 1
      },
      widgetContentColor: function(settings, fallback) {
        return settings && settings.color === "color05"
          && settings.tone === "background" ? "#111111" : fallback
      }
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

    function scheduleOpenControlCenterRestores(page, needsReplacement,
        owner, screenName) {
      const existing = widgetRestorePendingForOutput(
        "hancore.shibumi.control-center", owner, screenName)
      if (!existing) scheduleWidgetRestore(
        "hancore.shibumi.control-center", page, needsReplacement,
        owner, screenName)
      return existing ? [] : [{
        id: "hancore.shibumi.control-center",
        owner: owner,
        screenName: String(screenName || "")
      }]
    }

    function cancelCreatedWidgetRestores(records) {
      const values = Array.isArray(records) ? records : []
      for (let index = 0; index < values.length; index++) {
        const record = values[index]
        cancelWidgetRestore(record.id, record.owner, record.screenName)
      }
      return values.length > 0
    }

    function widgetRestorePendingForOutput(pluginId, owner, screenName) {
      void(owner)
      return pendingWidgetRestoreId === String(pluginId || "")
        && pendingWidgetRestoreScreenName === String(screenName || "")
    }

    function widgetRestorePendingForOwner(pluginId, owner, screenName) {
      return widgetRestorePendingForOutput(pluginId, owner, screenName)
        && pendingWidgetRestoreOwner === owner
    }

    function scheduleWidgetRestore(pluginId, page, needsReplacement,
        owner, screenName) {
      restoredWidgetId = String(pluginId || "")
      restoredPage = String(page || "")
      restoreNeedsReplacement = needsReplacement === true
      void(owner)
      void(screenName)
      restoreWrites++
      return true
    }

    function cancelWidgetRestore(pluginId, owner, screenName) {
      void(owner)
      void(screenName)
      if (String(pluginId || "") !== restoredWidgetId) return false
      restoreCancelWrites++
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

  QtObject {
    id: tileController

    property real controlRadius: 4
    property color controlHoverFillColor: "#222222"
    property color controlFillColor: "#111111"
    property real controlBorderWidth: 1
    property color controlBorderColor: "#444444"
    property string marketFont: "sans"
    property color marketBackground: "#000000"

    function accentColor(name) {
      return String(name || "") === "color03" ? "#336699" : "#ffffff"
    }
  }

  QtObject {
    id: fakeStatusState
    function paletteColor(name) {
      return name === "color03" ? "#33aa55" : "#ffffff"
    }
  }

  Control.ActiveBarStatus {
    id: activeBarStatusProbe
    visible: false
    stockOmarchyHost: root.statusStockHost
    v2LayoutActive: root.statusV2Layout
    stateService: fakeStatusState
    neutralColor: "#aabbcc"
    fontFamily: "monospace"
  }

  Control.WidgetModuleTile {
    id: favoriteTileProbe
    visible: false
    controller: tileController
    glyph: "extension"
    label: "Favorite probe"
    favorite: true
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
        pluginUpdateServiceOverride: pluginUpdateService
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
        root.widestActiveBarStatus = Math.max(root.widestActiveBarStatus,
          activeBarStatusProbe.implicitWidth)
        if (root.activeBarStatusStep === 0) {
          if (activeBarStatusProbe.statusText !== "SHIBUMI V1 ACTIVE"
              || activeBarStatusProbe.Accessible.role !== Accessible.StaticText
              || activeBarStatusProbe.Accessible.name !== "SHIBUMI V1 ACTIVE"
              || String(activeBarStatusProbe.renderedDotColor) !== "#33aa55"
              || String(activeBarStatusProbe.renderedLabelColor) !== "#aabbcc")
            return root.fail("V1 active-bar header status")
          root.statusV2Layout = true
          root.activeBarStatusStep = 1
          return
        }
        if (root.activeBarStatusStep === 1) {
          if (activeBarStatusProbe.statusText !== "SHIBUMI V2 ACTIVE"
              || activeBarStatusProbe.Accessible.name !== "SHIBUMI V2 ACTIVE")
            return root.fail("V2 active-bar header status")
          root.statusStockHost = true
          root.activeBarStatusStep = 2
          return
        }
        if (root.activeBarStatusStep === 2) {
          if (activeBarStatusProbe.statusText !== "OMARCHY BAR ACTIVE"
              || activeBarStatusProbe.Accessible.name !== "OMARCHY BAR ACTIVE"
              || activeBarStatusProbe.implicitWidth <= 0
              || root.widestActiveBarStatus >= 240)
            return root.fail("Omarchy active-bar header status geometry")
          root.activeBarStatusStep = 3
        }
        if (String(favoriteTileProbe.favoriteStatusColor) !== "#336699"
            || String(favoriteTileProbe.favoriteGlyphColor) !== "#336699"
            || favoriteTileProbe.favoriteGlyphText !== "󰓎")
          return root.fail("favorite star does not use the color03 Nerd Font glyph")
        if (widget.moduleName !== "hancore.shibumi.control-center"
            || widget.panelLoaded || widget.iconMode
            || !widget.shibumiWordmark
            || widget.launcherConfig.text !== "shibumi"
            || root.clickTargets.length !== 1)
          return root.fail("closed G1 lifecycle or identity")

        if (typeof widget.triggerPress !== "function"
            || widget.triggerPress(Qt.RightButton) || widget.opened
            || !widget.triggerPress(Qt.LeftButton) || !widget.opened)
          return root.fail("G1 host click forwarding contract")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!widget || !widget.panelLoaded || !widget.panelItem
            || root.ticks < 3) return
        const panel = widget.panelItem

        if (!root.panelIdempotenceStarted) {
          root.panelIdempotenceStarted = true
          root.stablePanelItem = panel
          widget.syncPanelLoader()
          widget.syncPanelLoader()
          root.ticks = 0
          return
        }
        if (panel !== root.stablePanelItem)
          return root.fail("unchanged panel sync rebuilt the loader item")

        if (!panel.open || panel.ownerWidget !== widget
            || panel.stateService !== stateService
            || !panel.settingsReady || !panel.settingsFitsWidth
            || panel.settingsPage !== "quick"
            || !panel.settingsPageItem || !panel.settingsPageItem.ready
            || panel.barPosition !== "top"
            || fakeBar.activePopout !== widget)
          return root.fail("panel injection, layout, or popout ownership")

        if (!panel.setGroupSetting("G4", "compact", true)
            || !panel.setBarPresentation("accent", "color06")
            || !panel.setBarPresentation("radius", "small")
            || !panel.setWorkspacePreference("mode", "5")
            || !panel.setImagePickerStyle("tanzaku")
            || !panel.setMediaPickerStyle("hearthstone")
            || !panel.setReactorMode(8))
          return root.fail("state mutation facade rejected valid values")
        const layoutRestoreWrites = fakeBar.restoreWrites
        if (!panel.setLayoutProtection("v1", true)
            || fakeBar.restoreWrites !== layoutRestoreWrites + 1
            || fakeBar.restoredPage !== "quick"
            || fakeBar.restoreNeedsReplacement
            || panel.setLayoutProtection("v3", true)
            || fakeBar.restoreCancelWrites !== 0)
          return root.fail("layout protection restore contract failed")

        if (stateService.groupAppearanceSettingForVariant(
              "G4", "v1", "compact", false) !== true
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "compact", false) !== false
            || stateService.config.presentation.accent !== "color06"
            || stateService.config.presentation.radius !== "small"
            || panel.controlRadius !== 4
            || stateService.config.workspace.mode !== "5"
            || stateService.config.picker.imageStyle !== "tanzaku"
            || stateService.config.picker.mediaStyle !== "hearthstone"
            || stateService.config.picker.style !== "hearthstone"
            || stateService.config.reactor.mode !== 8
            || panel.v1LayoutProtected !== true
            || panel.v2LayoutProtected !== false
            || fakeShell.writes !== 8)
          return root.fail("state mutations did not persist")

        fakeBar.pendingWidgetRestoreId = ""
        fakeBar.pendingWidgetRestoreOwner = null
        fakeBar.pendingWidgetRestoreScreenName = ""
        const unchangedProtectionRestoreWrites = fakeBar.restoreWrites
        const unchangedProtectionCancelWrites = fakeBar.restoreCancelWrites
        if (panel.setLayoutProtection("v1", true)
            || fakeBar.restoreWrites
              !== unchangedProtectionRestoreWrites + 1
            || fakeBar.restoreCancelWrites
              !== unchangedProtectionCancelWrites + 1)
          return root.fail("unchanged layout protection left a pending restore")

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
            || fakeBar.restoreWrites !== 5
            || fakeBar.restoredWidgetId !== "hancore.shibumi.control-center"
            || fakeBar.restoredPage !== "functions"
            || !fakeBar.restoreNeedsReplacement
            || stateService.config.presentation.shellStyle !== "full"
            || fakeShell.writes !== 11)
          return root.fail("bar presentation changes did not preserve the open page"
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
            || panel.settingsPageItem.activeWidgetCount !== 12
            || panel.settingsPageItem.inactiveWidgetCount !== 6
            || !panel.settingsPageItem.allWidgetModesReady)
          return root.fail("appearance page did not instantiate")

        const appearance = panel.settingsPageItem
        const v1OverviewPanelHeight = panel.compactIconsPanelHeight
        panel.v2LayoutActive = true
        if (Math.abs(panel.compactIconsPanelHeight
              - v1OverviewPanelHeight) > 0.5)
          return root.fail("Icons overview height differed between V1 and V2")
        panel.v2LayoutActive = false
        if (!appearance.resetActionVisible
            || appearance.resetConfirmationPending
            || appearance.activeResetVariant !== "v1"
            || appearance.resetActionLabel !== "RESET V1 DEFAULTS"
            || !Qt.colorEqual(appearance.resetActionColor,
              panel.accentColor("color03"))
            || !appearance.controller.setGroupSetting(
              "G4", "color", "color05")
            || !appearance.controller.setGroupSetting(
              "G9", "mediaStyle", "full")
            || !stateService.setGroupAppearanceSettingForVariant(
              "G:hancore.shibumi.storage", "v1", "displayMode", "icon")
            || !stateService.setGroupAppearanceSettingForVariant(
              "G2", "v2", "color", "color05"))
          return root.fail("V1 global reset fixture was rejected")
        const launcherBeforeV1Reset = JSON.stringify(
          stateService.config.launcher)
        if (!appearance.requestAppearanceReset()
            || !appearance.resetConfirmationPending
            || appearance.resetActionLabel !== "CONFIRM V1 RESET"
            || !Qt.colorEqual(appearance.resetActionColor,
              panel.accentColor("color01"))
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v1", "color", "") !== "color05")
          return root.fail("V1 global reset did not require confirmation")
        appearance.motionActive = false
        if (appearance.resetActionVisible
            || appearance.resetConfirmationPending
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v1", "color", "") !== "color05")
          return root.fail("hidden V1 global reset remained armed")
        appearance.motionActive = true
        if (!appearance.resetActionVisible
            || !Qt.colorEqual(appearance.resetActionColor,
              panel.accentColor("color03"))
            || !appearance.requestAppearanceReset()
            || !appearance.resetConfirmationPending
            || !Qt.colorEqual(appearance.resetActionColor,
              panel.accentColor("color01")))
          return root.fail("V1 global reset could not be re-armed")
        if (!appearance.requestAppearanceReset()
            || appearance.resetConfirmationPending
            || appearance.resetActionLabel !== "RESET V1 DEFAULTS"
            || !Qt.colorEqual(appearance.resetActionColor,
              panel.accentColor("color03"))
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v1", "color", "") !== "inherit"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v1", "mediaStyle", "") !== "default"
            || stateService.groupAppearanceSettingForVariant(
              "G:hancore.shibumi.storage", "v1", "displayMode", "")
                !== "full"
            || stateService.groupAppearanceSettingForVariant(
              "G2", "v2", "color", "") !== "color05"
            || JSON.stringify(stateService.config.launcher)
              !== launcherBeforeV1Reset)
          return root.fail("V1 global reset did not restore isolated defaults")
        if (!stateService.resetGroupAppearanceForVariant("G2", "v2"))
          return root.fail("V1 global reset fixture cleanup failed")

        panel.v2LayoutActive = true
        if (!appearance.resetActionVisible
            || appearance.resetConfirmationPending
            || appearance.activeResetVariant !== "v2"
            || appearance.resetActionLabel !== "RESET V2 DEFAULTS"
            || !Qt.colorEqual(appearance.resetActionColor,
              panel.accentColor("color03"))
            || !appearance.controller.setGroupSetting(
              "G4", "displayMode", "text")
            || !appearance.controller.setGroupSetting(
              "G9", "mediaStyle", "full")
            || !appearance.controller.setGroupSetting(
              "G18", "widgetRadius", "round")
            || !stateService.setGroupAppearanceSettingForVariant(
              "G2", "v1", "color", "color04"))
          return root.fail("V2 global reset fixture was rejected")
        const launcherBeforeV2Reset = JSON.stringify(
          stateService.config.launcher)
        if (!appearance.requestAppearanceReset()
            || !appearance.resetConfirmationPending
            || appearance.resetActionLabel !== "CONFIRM V2 RESET"
            || !Qt.colorEqual(appearance.resetActionColor,
              panel.accentColor("color01")))
          return root.fail("V2 global reset did not require confirmation")
        if (!appearance.requestAppearanceReset()
            || appearance.resetConfirmationPending
            || appearance.resetActionLabel !== "RESET V2 DEFAULTS"
            || !Qt.colorEqual(appearance.resetActionColor,
              panel.accentColor("color03"))
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "displayMode", "") !== "full"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v2", "mediaStyle", "") !== "default"
            || stateService.groupAppearanceSettingForVariant(
              "G18", "v2", "widgetRadius", "") !== "auto"
            || stateService.groupAppearanceSettingForVariant(
              "G2", "v1", "color", "") !== "color04"
            || JSON.stringify(stateService.config.launcher)
              !== launcherBeforeV2Reset)
          return root.fail("V2 global reset did not restore isolated defaults")
        if (!stateService.resetGroupAppearanceForVariant("G2", "v1"))
          return root.fail("V2 global reset fixture cleanup failed")

        panel.v2LayoutActive = false
        if (appearance.widgetDetailOpen
            || !appearance.openWidgetDetails("G1", "")
            || !appearance.widgetDetailOpen
            || appearance.resetActionVisible)
          return root.fail("Icons did not open Launcher details")
        const v1SelectionPanelHeight = panel.compactIconsSelectionPanelHeight
        panel.v2LayoutActive = true
        if (!panel.compactIconsSelection
            || Math.abs(panel.compactIconsSelectionPanelHeight
              - v1SelectionPanelHeight) > 0.5)
          return root.fail(
            "Icons selection height differed between V1 and V2")
        panel.v2LayoutActive = false
        if (!panel.setLauncherSelection("icon", "shibumi"))
          return root.fail("V1 Launcher tint fixture was rejected")
        if (!appearance.controller.setGroupSetting("G1", "color", "color05")
            || !appearance.controller.setGroupSetting(
              "G1", "tone", "background")
            || !appearance.controller.setGroupSetting(
              "G1", "surfaceOpacity", 0.4))
          return root.fail("V1 Launcher appearance settings were rejected")
        widget.settings = stateService.groupSettingsForVariant("G1", "v1")
        if (!widget.nativePillSurfaceVisible
            || !widget.v1CustomFill
            || !widget.v1TintedLauncherIconVisible
            || Math.abs(widget.renderedPillFillColor.a - 0.4) > 0.001
            || stateService.groupAppearanceSettingForVariant(
              "G1", "v2", "color", "inherit") !== "inherit")
          return root.fail("V1 Launcher appearance was not isolated")
        if (!appearance.controller.resetGroupAppearance("G1"))
          return root.fail("V1 Launcher appearance reset was rejected")
        widget.settings = stateService.groupSettingsForVariant("G1", "v1")
        if (widget.v1CustomFill || widget.v1TintedLauncherIconVisible)
          return root.fail("V1 Launcher appearance reset drifted")
        appearance.controller.setGroupSetting("G1", "displayMode", "text")
        if (!widget.iconMode)
          return root.fail("V1 generic presentation overrode launcher icon")
        if (!panel.setLauncherSelection("text", "arch"))
          return root.fail("V1 launcher wordmark selection was rejected")
        appearance.controller.setGroupSetting("G1", "displayMode", "icon")
        if (widget.iconMode || widget.effectiveLauncherText !== "arch")
          return root.fail("V1 generic presentation overrode launcher wordmark")
        panel.v2LayoutActive = true
        appearance.controller.setGroupSetting("G1", "displayMode", "text")
        if (!panel.setLauncherSelection("icon", "mark") || !widget.iconMode)
          return root.fail("V2 launcher icon did not own its presentation")
        appearance.controller.setGroupSetting("G1", "displayMode", "icon")
        if (!panel.setLauncherSelection("text", "shibumi")
            || widget.iconMode
            || widget.effectiveLauncherText !== "shibumi")
          return root.fail("V2 launcher wordmark did not own its presentation")
        if (!panel.setLauncherSelection("icon", "hyprland"))
          return root.fail("launcher contract fixture did not restore")
        appearance.controller.setGroupSetting("G1", "displayMode", "full")
        panel.v2LayoutActive = false
        appearance.showWidgetOverview()
        if (!appearance.openWidgetDetails("G4", "")
            || !appearance.widgetDetailOpen)
          return root.fail("Icons overview did not drill into one widget")
        const v1RequiredSelectionHeight = appearance.implicitHeight
          + panel.configureDetailPanelChromeHeight
        if (panel.compactIconsSelectionPanelHeight + 0.5
            < v1RequiredSelectionHeight)
          return root.fail("V1 Icons selection requires scrolling"
            + " actual=" + panel.compactIconsSelectionPanelHeight
            + " required=" + v1RequiredSelectionHeight)
        const modeBeforeCycle = appearance.selectedWidgetMode
        const expectedModeAfterCycle = modeBeforeCycle === "full"
          ? "icon" : "full"
        if (!appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== expectedModeAfterCycle)
          return root.fail("V1 Default/Compact choice did not cycle")
        if (stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "displayMode", "") !== "full")
          return root.fail("V1 mode change leaked into V2")
        appearance.showWidgetOverview()
        if (!appearance.openWidgetDetails("G5", "")
            || !appearance.selectedV1Appearance
            || appearance.selectedV1CpuCompact
            || appearance.selectedWidgetModeOptions.length !== 2
            || appearance.selectedWidgetModeOptions[0].value !== "full"
            || appearance.selectedWidgetModeOptions[0].label !== "Default"
            || appearance.selectedWidgetModeOptions[1].value !== "icon"
            || appearance.selectedWidgetModeOptions[1].label !== "Compact")
          return root.fail("CPU V1 did not expose Default/Compact controls")
        if (!appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== "icon"
            || !appearance.selectedV1CpuCompact
            || !appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== "full"
            || appearance.selectedV1CpuCompact)
          return root.fail("CPU preview did not separate Default and Compact")
        const v1AppearanceGroups = [
          "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9",
          "G10", "G11", "G12", "G13", "G14", "G15", "G16", "G17", "G18"
        ]
        for (let index = 0; index < v1AppearanceGroups.length; index++) {
          if (!appearance.openWidgetDetails(v1AppearanceGroups[index], "")
              || !appearance.selectedV1Appearance)
            return root.fail("V1 appearance rollout missed "
              + v1AppearanceGroups[index])
        }
        if (!appearance.openWidgetDetails("G5", "")
            || !appearance.controller.setGroupSetting(
              "G5", "color", "color05")
            || !appearance.controller.setGroupSetting(
              "G5", "tone", "background")
            || !appearance.controller.setGroupSetting(
              "G5", "surfaceOpacity", 0.6)
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v1", "color", "") !== "color05"
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v1", "tone", "") !== "background"
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v1", "surfaceOpacity", 0) !== 0.6
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v2", "color", "inherit") !== "inherit"
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v2", "tone", "auto") !== "auto"
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v2", "surfaceOpacity", 1) !== 1
            || appearance.selectedWidgetTone !== "background"
            || appearance.selectedWidgetOpacity !== 0.6
            || !appearance.widgetUsesCustomAppearance("G5"))
          return root.fail("CPU V1 fill/tone/opacity did not persist")
        if (!appearance.controller.resetGroupAppearance("G5")
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v1", "color", "") !== "inherit"
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v1", "tone", "") !== "auto"
            || stateService.groupAppearanceSettingForVariant(
              "G5", "v1", "surfaceOpacity", 0) !== 1
            || appearance.widgetUsesCustomAppearance("G5"))
          return root.fail("CPU V1 appearance reset did not restore defaults")
        appearance.showWidgetOverview()
        if (!appearance.openWidgetDetails("G9", "")
            || appearance.selectedWidgetMode !== "default"
            || !appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== "full"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v2", "mediaStyle", "") !== "default")
          return root.fail("V1 Now Playing style contract drifted")
        if (!appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== "default")
          return root.fail("V1 Now Playing style did not restore")
        if (!appearance.controller.setGroupSetting("G9", "color", "color05")
            || !appearance.controller.setGroupSetting(
              "G9", "tone", "foreground")
            || !appearance.controller.setGroupSetting(
              "G9", "surfaceOpacity", 0.4)
            || appearance.selectedWidgetMode !== "default"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v1", "mediaStyle", "") !== "default"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v1", "color", "") !== "color05"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v1", "tone", "") !== "foreground"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v1", "surfaceOpacity", 0) !== 0.4
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v2", "color", "inherit") !== "inherit"
            || !appearance.widgetUsesCustomAppearance("G9"))
          return root.fail(
            "V1 Now Playing appearance changed its existing style contract")
        if (!appearance.controller.resetGroupAppearance("G9")
            || appearance.selectedWidgetMode !== "default"
            || appearance.widgetUsesCustomAppearance("G9"))
          return root.fail("V1 Now Playing appearance reset drifted")
        panel.v2LayoutActive = true
        if (!appearance.openWidgetDetails("G9", "")
            || appearance.selectedWidgetMode !== "default"
            || !appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== "full"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v1", "mediaStyle", "") !== "default")
          return root.fail("V2 Now Playing style contract drifted")
        if (!appearance.openWidgetDetails("G4", "")
            || appearance.selectedWidgetMode !== "full")
          return root.fail("V2 appearance did not remain independent")
        const opacityBeforeCycle = appearance.selectedWidgetOpacity
        const expectedOpacityAfterCycle = opacityBeforeCycle > 0.9 ? 0.8
          : opacityBeforeCycle > 0.7 ? 0.6
          : opacityBeforeCycle > 0.5 ? 0.4 : 1
        if (!appearance.cycleSelectedWidgetOpacity()
            || appearance.selectedWidgetOpacity !== expectedOpacityAfterCycle)
          return root.fail("single Opacity button did not cycle its value")
        const surfaceBeforeCycle = appearance.selectedWidgetSurface
        const expectedSurfaceAfterCycle = surfaceBeforeCycle === "none" ? "fill"
          : surfaceBeforeCycle === "fill" ? "border"
          : surfaceBeforeCycle === "border" ? "both" : "none"
        if (!appearance.cycleSelectedWidgetSurface()
            || appearance.selectedWidgetSurface !== expectedSurfaceAfterCycle)
          return root.fail("single Surface button did not cycle its value")
        if (appearance.selectedWidgetSurface !== "border"
            && appearance.selectedWidgetSurface !== "both")
          appearance.cycleSelectedWidgetSurface()
        if (appearance.selectedWidgetSurface !== "border"
            && appearance.selectedWidgetSurface !== "both")
          appearance.cycleSelectedWidgetSurface()
        if (appearance.selectedWidgetSurface !== "border"
            && appearance.selectedWidgetSurface !== "both")
          return root.fail("Surface cycle could not enable an outline")
        appearance.controller.setGroupSetting("G4", "displayMode", "text")
        appearance.controller.setGroupSetting("G4", "colorMode", "both")
        appearance.controller.setGroupSetting("G4", "widgetBorder", true)
        appearance.controller.setGroupSetting("G4", "color", "color05")
        appearance.controller.setGroupSetting("G4", "tone", "background")
        appearance.controller.setGroupSetting("G4", "widgetRadius", "round")
        appearance.controller.setGroupSetting("G4", "widgetPadding", "roomy")
        appearance.controller.setGroupSetting("G4", "surfaceOpacity", 0.8)
        appearance.controller.setGroupSetting("G4", "widgetBorderWidth", 1.5)
        appearance.controller.setGroupSetting(
          "G4", "widgetBorderColor", "color03")
        const v2RequiredSelectionHeight = appearance.implicitHeight
          + panel.configureDetailPanelChromeHeight
        if (panel.compactIconsSelectionPanelHeight + 0.5
            < v2RequiredSelectionHeight)
          return root.fail("V2 Icons selection requires scrolling"
            + " actual=" + panel.compactIconsSelectionPanelHeight
            + " required=" + v2RequiredSelectionHeight)

        if (stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "displayMode", "") !== "text"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "compact", true) !== false
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "colorMode", "") !== "both"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "widgetBorder", false) !== true
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "color", "") !== "color05"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "tone", "") !== "background"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "widgetRadius", "") !== "round"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "widgetPadding", "") !== "roomy"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "surfaceOpacity", 0) !== 0.8
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "widgetBorderWidth", 0) !== 1.5
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "widgetBorderColor", "") !== "color03")
          return root.fail("per-widget appearance contract did not persist")
        if (!appearance.widgetUsesCustomAppearance("G4"))
          return root.fail("Icons missed a real custom appearance")
        if (!appearance.controller.resetGroupAppearance("G4")
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "displayMode", "") !== "full"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "color", "") !== "inherit"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "widgetPadding", "") !== "auto"
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v2", "widgetBorderColor", "") !== "inherit")
          return root.fail("appearance reset did not preserve nonvisual state")
        if (appearance.widgetUsesCustomAppearance("G4"))
          return root.fail("Icons marked a reset widget as customized")
        appearance.controller.setGroupSetting("G4", "displayMode", "full")
        appearance.controller.setGroupSetting("G4", "colorMode", "fill")
        appearance.controller.setGroupSetting("G4", "widgetBorder", false)
        appearance.controller.setGroupSetting("G4", "color", "inherit")
        appearance.controller.setGroupSetting("G4", "tone", "auto")
        appearance.controller.setGroupSetting("G4", "widgetRadius", "auto")
        appearance.controller.setGroupSetting("G4", "widgetPadding", "auto")
        appearance.controller.setGroupSetting("G4", "surfaceOpacity", 1)
        appearance.controller.setGroupSetting("G4", "widgetBorderWidth", 1)
        appearance.controller.setGroupSetting(
          "G4", "widgetBorderColor", "inherit")
        appearance.controller.setGroupSetting(
          "G4", "widgetBorderUsesSurfaceColor", false)
        if (appearance.widgetUsesCustomAppearance("G4"))
          return root.fail("Icons treated explicit defaults as customization")
        appearance.controller.resetGroupAppearance("G4")
        panel.v2LayoutActive = false
        appearance.showWidgetOverview()
        appearance.controller.setGroupSetting("G4", "color", "color05")
        if (appearance.setWidgetEnabled("G1", false)
            || !stateService.groupEnabledForVariant("G1", "v1"))
          return root.fail("Icons allowed Control Center self-disable")
        if (!appearance.setWidgetEnabled("G4", false)
            || appearance.activeWidgetCount !== 11
            || appearance.inactiveWidgetCount !== 7
            || stateService.groupEnabledForVariant("G4", "v1")
            || !stateService.groupEnabledForVariant("G4", "v2")
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v1", "color", "") !== "color05"
            || !appearance.openWidgetDetails("G4", "")
            || appearance.selectedWidgetActive)
          return root.fail("Icons did not deactivate Memory without style loss")
        if (!appearance.setWidgetEnabled("G4", true)
            || appearance.activeWidgetCount !== 12
            || appearance.inactiveWidgetCount !== 6
            || !stateService.groupEnabledForVariant("G4", "v1")
            || !stateService.groupEnabledForVariant("G4", "v2")
            || stateService.groupAppearanceSettingForVariant(
              "G4", "v1", "color", "") !== "color05"
            || !appearance.widgetDetailOpen
            || !appearance.selectedWidgetActive)
          return root.fail("Icons did not reactivate Memory with its style")
        appearance.controller.resetGroupAppearance("G4")
        appearance.showWidgetOverview()
        if (!appearance.openWidgetDetails(
              "G18", "hancore.shibumi.storage")
            || appearance.selectedWidgetActive
            || !appearance.selectedV1Appearance)
          return root.fail("V1 Icons did not expose inactive Storage appearance")
        const inactiveModeBeforeCycle = appearance.selectedWidgetMode
        const expectedInactiveModeAfterCycle = inactiveModeBeforeCycle === "full"
          ? "icon" : "full"
        if (appearance.selectedWidgetModeOptions.length !== 2
            || appearance.selectedWidgetModeOptions[0].label !== "Default"
            || appearance.selectedWidgetModeOptions[1].label !== "Compact"
            || !appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== expectedInactiveModeAfterCycle
            || stateService.groupAppearanceSettingForVariant(
              "G:hancore.shibumi.storage", "v1", "displayMode", "")
                !== expectedInactiveModeAfterCycle)
          return root.fail("V1 Storage did not expose Default/Compact"
            + " before=" + inactiveModeBeforeCycle
            + " after=" + appearance.selectedWidgetMode
            + " expected=" + expectedInactiveModeAfterCycle
            + " options=" + JSON.stringify(appearance.selectedWidgetModeOptions)
            + " stored=" + stateService.groupAppearanceSettingForVariant(
              "G:hancore.shibumi.storage", "v1", "displayMode", ""))
        panel.v2LayoutActive = true
        if (appearance.activeWidgetCount !== 15
            || appearance.inactiveWidgetCount !== 3
            || !appearance.widgetDetailOpen
            || !appearance.selectedWidgetActive
            || !appearance.openWidgetDetails(
              "G18", "hancore.shibumi.storage"))
          return root.fail("V2 Icons did not expose its active widget set")
        if (!appearance.setWidgetEnabled("G18", false)
            || appearance.activeWidgetCount !== 14
            || appearance.inactiveWidgetCount !== 4
            || appearance.selectedWidgetActive)
          return root.fail("V2 Icons did not move Storage to inactive")
        if (!appearance.setWidgetEnabled("G18", true)
            || appearance.activeWidgetCount !== 15
            || appearance.inactiveWidgetCount !== 3
            || !appearance.selectedWidgetActive)
          return root.fail("V2 Icons did not restore Storage to active")
        panel.v2LayoutActive = false
        if (appearance.activeWidgetCount !== 12
            || appearance.inactiveWidgetCount !== 6
            || !appearance.widgetDetailOpen
            || appearance.selectedWidgetActive)
          return root.fail("Icons did not preserve inactive detail across V1/V2")
        if (!panel.showSettingsPage("plugins"))
          return root.fail("Plugins page rejected")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (!panel || !panel.settingsPageReady
            || panel.settingsPage !== "plugins"
            || !panel.settingsPageItem
            || !panel.settingsPageItem.ready)
          return root.fail("Plugins page did not instantiate")
        const plugins = panel.settingsPageItem
        if (plugins.activeCountColor !== panel.accentColor("color03")
            || plugins.availableCountColor !== panel.accentColor("color02"))
          return root.fail("plugin counts do not follow theme colors")
        if (plugins.shibumiProviderCount !== 2
            || plugins.omarchyProviderCount !== 1
            || plugins.thirdPartyProviderCount !== 1)
          return root.fail("plugin provider summary is ambiguous")
        if (pluginUpdateService.checkCount !== 1
            || pluginUpdateService.consumerCount !== 1
            || !pluginUpdateService.checked
            || panel.pluginUpdateCount !== 2
            || pluginUpdateService.checkedCount !== 3
            || panel.pluginUpdateShortStatusText !== "2 available"
            || panel.pluginUpdateStatusText !== "2 updates available")
          return root.fail("plugin update text did not expose the scan state: checks="
            + pluginUpdateService.checkCount + " consumers="
            + pluginUpdateService.consumerCount + " checked="
            + pluginUpdateService.checked + " updates=" + panel.pluginUpdateCount
            + " checkedCount=" + pluginUpdateService.checkedCount
            + " motion=" + plugins.motionActive
            + " favorites=" + plugins.favoritesOnly
            + " consumerActive=" + plugins.pluginUpdateConsumerActive
            + " effective=" + (panel.effectivePluginUpdateService !== null)
            + " shortStatus=" + panel.pluginUpdateShortStatusText
            + " status=" + panel.pluginUpdateStatusText)
        plugins.feedbackProgress = 2
        if (plugins.boundedFeedbackProgress !== 1
            || Math.abs(plugins.feedbackProgressRenderedWidth
              - plugins.feedbackProgressAvailableWidth) > 0.01)
          return root.fail("plugin feedback progress upper clamp")
        plugins.feedbackProgress = -1
        if (plugins.boundedFeedbackProgress !== 0
            || plugins.feedbackProgressRenderedWidth !== 0)
          return root.fail("plugin feedback progress lower clamp")
        plugins.feedbackProgress = 0
        if (!plugins.togglePluginById("omarchy.audio")
            || !plugins.feedbackVisible
            || !plugins.feedbackCountdownRunning
            || plugins.feedbackProgress <= 0
            || plugins.feedbackProgressInset < panel.controlRadius
            || plugins.feedbackProgressAvailableWidth <= 0
            || Math.abs(plugins.feedbackProgressAvailableWidth
              - Math.max(0, plugins.width
                - 2 * plugins.feedbackProgressInset)) > 0.01
            || plugins.feedbackProgressRenderedWidth <= 0
            || plugins.feedbackProgressRenderedWidth
              > plugins.feedbackProgressAvailableWidth + 0.01
            || plugins.feedbackProgressInset
              + plugins.feedbackProgressRenderedWidth
              > plugins.width - plugins.feedbackProgressInset + 0.01
            || plugins.feedbackTitle !== "Omarchy Audio activated"
            || plugins.feedbackDetail.indexOf("hidden") < 0
            || !plugins.undoGroupStates.G6
            || plugins.undoGroupStates.G6.v1 !== true
            || plugins.undoGroupStates.G6.v2 !== false
            || !plugins.undoProviderSnapshot
            || plugins.undoProviderSnapshot.token
              !== "audio-provider-snapshot"
            || panel.pluginEntries[0].installedInBar
            || !panel.pluginEntries[0].replaced
            || !panel.pluginEntries[1].installedInBar
            || !panel.pluginEntries[1].replacementInEffect)
          return root.fail(
            "provider switch did not expose replacement feedback")
        const providerRestoreWrites = fakeBar.restoreWrites
        const providerRestoreCancelWrites = fakeBar.restoreCancelWrites
        panel.rejectProviderRestore = true
        if (plugins.undoLastChange()
            || fakeBar.restoreWrites !== providerRestoreWrites + 1
            || fakeBar.restoreCancelWrites
              !== providerRestoreCancelWrites + 1
            || !plugins.feedbackVisible
            || !plugins.feedbackCountdownRunning
            || plugins.feedbackProgress <= 0
            || !plugins.undoGroupStates.G6)
          return root.fail("failed provider restore discarded Undo")
        panel.rejectProviderRestore = false
        if (!plugins.undoLastChange()
            || fakeBar.restoreWrites !== providerRestoreWrites + 2
            || fakeBar.restoreCancelWrites
              !== providerRestoreCancelWrites + 1
            || plugins.feedbackVisible
            || plugins.feedbackCountdownRunning
            || plugins.feedbackProgress !== 0
            || !panel.pluginEntries[0].installedInBar
            || panel.pluginEntries[0].replaced
            || panel.pluginEntries[1].installedInBar)
          return root.fail("provider-switch undo did not restore Shibumi")
        if (plugins.activeExpanded || plugins.availableExpanded
            || plugins.displayedActiveEntries.length !== 0
            || plugins.displayedAvailableEntries.length !== 0)
          return root.fail("large plugin catalog is not collapsed by default")
        plugins.focusPluginSearch()
        plugins.setPluginSearchQuery("shi")
        if (plugins.searchSuggestions.length < 2
            || plugins.searchGhostText === "")
          return root.fail("plugin search did not expose ranked completions")
        if (!plugins.blurPluginSearch()
            || plugins.pluginQuery !== "shi"
            || plugins.searchSuggestions.length !== 0)
          return root.fail(
            "plugin search click-away semantics did not preserve the query")
        plugins.focusPluginSearch()
        plugins.setPluginSearchQuery("shi")
        if (!plugins.moveSearchSuggestion(1)
            || plugins.activeSearchSuggestion !== 1
            || !plugins.acceptSearchSuggestion(
              plugins.activeSearchSuggestion)
            || plugins.pluginQuery === "")
          return root.fail("plugin completion selection failed")
        plugins.setPluginSearchQuery("audio")
        if (plugins.filteredEntries.length !== 2
            || plugins.filteredEntries.some(function(entry) {
              return entry.id === "hancore.shibumi.bluetooth"
            }))
          return root.fail(
            "description-only Bluetooth relation polluted Audio search")
        plugins.selectedProvider = "Active"
        plugins.setPluginSearchQuery("acme")
        if (plugins.selectedProvider !== "All"
            || plugins.filteredEntries.length !== 1
            || plugins.filteredEntries[0].id !== "acme.weather")
          return root.fail(
            "search did not reveal a disabled plugin behind Active")
        plugins.setPluginSearchQuery("marchy aud")
        if (plugins.filteredEntries.length !== 1
            || plugins.filteredEntries[0].id !== "omarchy.audio")
          return root.fail("multi-fragment plugin search did not rank Audio")
        plugins.setPluginSearchQuery("acm wthr")
        if (plugins.filteredEntries.length !== 1
            || plugins.filteredEntries[0].id !== "acme.weather")
          return root.fail("fuzzy fallback did not find the weather plugin")
        plugins.setPluginSearchQuery("shi")
        if (plugins.dismissPluginSearch() !== "suggestions"
            || plugins.pluginQuery !== "shi"
            || plugins.searchSuggestions.length !== 0
            || plugins.dismissPluginSearch() !== "clear"
            || plugins.pluginQuery !== "")
          return root.fail("plugin search Escape staging failed")
        plugins.setPluginSearchQuery("acme")
        if (plugins.filteredEntries.length !== 1
            || plugins.displayedAvailableEntries.length !== 1)
          return root.fail("plugin search did not reveal the matching entry")
        if (!plugins.toggleFavoriteById("acme.weather")
            || !panel.pluginFavorite("acme.weather")
            || stateService.config.plugins.favorites.indexOf(
              "acme.weather") < 0)
          return root.fail("plugin favorite was not persisted")
        plugins.setPluginSearchQuery("")
        plugins.favoritesOnly = true
        if (plugins.filteredEntries.length !== 1
            || plugins.filteredEntries[0].id !== "acme.weather")
          return root.fail("Favorites route did not scope the plugin catalog")
        if (!plugins.toggleFavoriteById("acme.weather")
            || panel.pluginFavorite("acme.weather")
            || plugins.filteredEntries.length !== 0)
          return root.fail("plugin favorite could not be removed")
        plugins.favoritesOnly = false
        if (!plugins.requestPluginRemovalById("acme.weather")
            || !plugins.removalConfirmationVisible
            || !plugins.confirmPluginRemoval()
            || plugins.entryById("acme.weather") !== null
            || plugins.feedbackTitle !== "Acme Weather removed")
          return root.fail("third-party plugin removal flow failed")
        if (!panel.showSettingsPage("splits"))
          return root.fail("Legacy layout route did not resolve")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (!panel || !panel.settingsPageReady
            || panel.settingsPage !== "bars")
          return root.fail("legacy layout route did not resolve to Bars")
        panel.v2LayoutActive = true
        if (!panel.showSettingsPage("bars"))
          return root.fail("V2 Bars page rejected")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (root.barsRouteStep === 0) {
          if (!panel || !panel.settingsPageReady
              || panel.settingsPage !== "bars"
              || !panel.settingsPageItem
              || panel.settingsPageItem.surfaceEffectOptionCount !== 2
              || panel.settingsPageItem.surfaceEffectPreviewCount !== 0
              || panel.settingsPageItem.splitActionPreviewCount !== 0
              || panel.settingsPageItem.surfaceRadiusOptionCount !== 0
              || panel.settingsPageItem.layoutActionCount !== 3
              || panel.settingsPageItem.layoutActionControlWidth < 88
              || !panel.settingsPageItem.layoutActionLabelsFit
              || !panel.compactBarsPage
              || panel.compactBarsPanelHeight > 656
              || Math.abs(panel.compactBarsPanelHeight
                - (panel.configureDetailPanelChromeHeight
                  + panel.settingsPageItem.implicitHeight)) > 0.5
              || panel.settingsPageItem.childRouteAvailable
              || panel.settingsPageItem.activeLayoutProtected)
            return root.fail("V2 exposed V1 Bar Surface settings"
              + " effects=" + (panel && panel.settingsPageItem
                ? panel.settingsPageItem.surfaceEffectOptionCount : "missing")
              + " radii=" + (panel && panel.settingsPageItem
                ? panel.settingsPageItem.surfaceRadiusOptionCount : "missing")
              + " active=" + (panel ? panel.v2LayoutActive : "missing")
              + " page-v2=" + (panel && panel.settingsPageItem
                ? panel.settingsPageItem.v2Active : "missing")
              + " shell=" + (panel ? panel.activeShell : "missing"))
          // Reproduce a lock click while the variant-switch restore still
          // owns the handoff. The lock mutation must neither restart nor
          // downgrade that stronger replacement-owner restore.
          fakeBar.pendingWidgetRestoreId =
            "hancore.shibumi.control-center"
          // The restored replacement owner differs from the outgoing owner;
          // output identity, not owner identity, must preserve the handoff.
          fakeBar.pendingWidgetRestoreOwner = null
          fakeBar.pendingWidgetRestoreScreenName = ""
          fakeBar.restoreNeedsReplacement = true
          const v2LayoutRestoreWrites = fakeBar.restoreWrites
          if (!panel.settingsPageItem.toggleActiveLayoutProtection()
              || stateService.config.layoutProtection.v2 !== true
              || !panel.settingsPageItem.activeLayoutProtected
              || fakeBar.restoreWrites !== v2LayoutRestoreWrites
              || !fakeBar.restoreNeedsReplacement)
            return root.fail("V2 layout protection disturbed variant handoff")
          fakeBar.pendingWidgetRestoreId = ""
          fakeBar.pendingWidgetRestoreOwner = null
          fakeBar.pendingWidgetRestoreScreenName = ""
          panel.v2LayoutActive = false
          if (panel.settingsPageItem.surfaceEffectOptionCount !== 3
              || panel.settingsPageItem.surfaceEffectPreviewCount !== 3
              || panel.settingsPageItem.splitActionPreviewCount !== 2
              || panel.settingsPageItem.surfaceRadiusOptionCount !== 2
              || panel.settingsPageItem.layoutActionCount !== 3
              || panel.settingsPageItem.layoutActionControlWidth < 88
              || !panel.settingsPageItem.layoutActionLabelsFit
              || !panel.compactBarsPage
              || panel.compactBarsPanelHeight > 656
              || Math.abs(panel.compactBarsPanelHeight
                - (panel.configureDetailPanelChromeHeight
                  + panel.settingsPageItem.implicitHeight)) > 0.5
              || !panel.settingsPageItem.childRouteAvailable
              || !panel.settingsPageItem.activeLayoutProtected
              || panel.settingsPageItem.childRouteLabel !== "Gap Animations"
              || !panel.showSettingsPage("bars-motion"))
            return root.fail("V1 Gap Animations child route was unavailable")
          root.barsRouteStep = 1
          root.ticks = 0
          return
        }
        if (root.barsRouteStep === 1) {
          if (panel.settingsPage !== "bars-motion"
              || !panel.settingsPageItem
              || !panel.settingsPageItem.motionDetailOpen
              || panel.settingsPageItem.reactorOptions.length !== 9
              || !panel.setReactorMode(5)
              || stateService.config.reactor.mode !== 5
              || !panel.showSettingsPage("bars"))
            return root.fail("V1 Gap Animations route or selection failed")
          root.barsRouteStep = 2
          root.ticks = 0
          return
        }
        if (panel.settingsPage !== "bars"
            || panel.settingsPageItem.motionDetailOpen
            || panel.settingsPageItem.surfaceEffectOptionCount !== 3
            || panel.settingsPageItem.surfaceEffectPreviewCount !== 3
            || panel.settingsPageItem.splitActionPreviewCount !== 2
            || panel.settingsPageItem.surfaceRadiusOptionCount !== 2
            || panel.settingsPageItem.layoutActionCount !== 3
            || panel.settingsPageItem.layoutActionControlWidth < 88
            || !panel.settingsPageItem.layoutActionLabelsFit
            || !panel.compactBarsPage
            || panel.compactBarsPanelHeight > 656
            || Math.abs(panel.compactBarsPanelHeight
              - (panel.configureDetailPanelChromeHeight
                + panel.settingsPageItem.implicitHeight)) > 0.5)
          return root.fail("Bars return navigation did not restore V1")
        panel.healthService.report = {
          schemaVersion: 1,
          generatedEpoch: 1785570000,
          overall: "error",
          summary: "Runtime error detected",
          checks: [{
            id: "runtime-errors",
            group: "runtime",
            label: "Recent runtime errors",
            status: "error",
            value: "1 loader error",
            detail: "Unable to assign Example.qml:42",
            component: "hancore.shibumi.example",
            action: "Review the affected component."
          }]
        }
        if (!panel.showSettingsPage("preferences"))
          return root.fail("legacy Advanced route did not open Health")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (root.healthLifecycleStep === 0) {
          if (!panel || !panel.settingsPageReady
              || panel.settingsPage !== "health"
              || !panel.settingsPageItem
              || panel.headerHealthErrorCount !== 1
              || panel.settingsPageItem.attentionChecks.length !== 1)
            return root.fail("Health page did not instantiate")
          const health = panel.settingsPageItem
          const v1HealthPanelHeight = panel.compactHealthPanelHeight
          panel.v2LayoutActive = true
          if (!panel.compactHealthPage
              || Math.abs(panel.compactHealthPanelHeight
                - health.implicitHeight
                - panel.configureDetailPanelChromeHeight) > 0.5
              || Math.abs(panel.compactHealthPanelHeight
                - v1HealthPanelHeight) > 0.5)
            return root.fail("Health did not fit its content height")
          panel.v2LayoutActive = false
          const error = health.attentionChecks[0]
          const issueUrl = health.diagnosticIssueUrl(error)
          if (health.diagnosticCode(error)
                !== "SHIBUMI-HEALTH/RUNTIME-ERRORS"
              || health.diagnosticReport(error).indexOf(
                "Component: hancore.shibumi.example") < 0
              || issueUrl.indexOf(
                "github.com/HANCORE-linux/Shibumi-Shell/issues/new?title=") < 0
              || decodeURIComponent(issueUrl).indexOf(
                "Code: SHIBUMI-HEALTH/RUNTIME-ERRORS") < 0)
            return root.fail("Health error report or issue URL is incomplete")
          health.copyDiagnostic(error)
          if (health.copiedCheckId !== "runtime-errors")
            return root.fail("Health error report was not copied")

          const stableReport = panel.healthService.report
          if (panel.healthService.acceptReport("{broken")
              || panel.healthService.report !== stableReport
              || panel.healthService.failure === "")
            return root.fail("malformed Health result replaced the last report")
          panel.healthService.failure = ""
          root.lifecycleHealthService = panel.healthService
          root.lifecycleReportEpoch = Number(stableReport.generatedEpoch || 0)
          if (!panel.healthService.runChecks(false))
            return root.fail("Health check did not start")
          root.healthLifecycleStep = 1
          root.ticks = 0
          return
        }

        if (root.healthLifecycleStep === 1) {
          if (!panel || panel.settingsPage !== "health"
              || !root.lifecycleHealthService
              || !root.lifecycleHealthService.running
              || root.lifecycleHealthService.runChecks(false))
            return root.fail("Health did not serialize overlapping checks")
          if (!panel.showSettingsPage("main"))
            return root.fail("Health page did not navigate away during a check")
          widget.close()
          root.healthLifecycleStep = 2
          root.ticks = 0
          return
        }

        if (root.healthLifecycleStep === 2) {
          if (widget.panelLoaded || widget.opened
              || !root.lifecycleHealthService.running)
            return root.fail("closing the panel stopped or destroyed Health")
          if (!widget.openPage("health"))
            return root.fail("Health panel did not reopen during a check")
          root.healthLifecycleStep = 3
          root.ticks = 0
          return
        }

        if (root.healthLifecycleStep === 3) {
          if (!panel || panel.healthService !== root.lifecycleHealthService
              || panel.settingsPage !== "health"
              || !root.lifecycleHealthService.running
              || Number(root.lifecycleHealthService.report.generatedEpoch || 0)
                !== root.lifecycleReportEpoch)
            return root.fail("reopened Health lost the in-flight owner or report")
          if (!panel.showSettingsPage("main"))
            return root.fail("Health did not navigate away after reopen")
          widget.close()
          root.healthLifecycleStep = 4
          root.ticks = 0
          return
        }

        if (root.healthLifecycleStep === 4) {
          if (root.lifecycleHealthService.running) return
          if (root.lifecycleHealthService.failure !== ""
              || Number(root.lifecycleHealthService.report.generatedEpoch || 0)
                <= root.lifecycleReportEpoch)
            return root.fail("background Health result was not retained")
          if (!widget.openPage("health"))
            return root.fail("completed Health report did not reopen")
          root.healthLifecycleStep = 5
          root.ticks = 0
          return
        }

        if (!panel || panel.healthService !== root.lifecycleHealthService
            || panel.settingsPage !== "health"
            || Number(panel.healthReport.generatedEpoch || 0)
              <= root.lifecycleReportEpoch)
          return root.fail("reopened Health did not expose the completed report")
        if (!panel.showSettingsPage("workspaces"))
          return root.fail("Health page did not continue to Workspaces")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (panel && panel.settingsPage === "workspaces") {
          const workspaces = panel.settingsPageItem
          if (!panel.settingsPageReady || !workspaces
              || !panel.compactWorkspacesPage
              || Math.abs(panel.compactWorkspacesPanelHeight
                - workspaces.implicitHeight
                - panel.configureDetailPanelChromeHeight) > 0.5)
            return root.fail("Workspaces did not fit its content height")
          const v1WorkspacesPageHeight = workspaces.implicitHeight
          const v1WorkspacesPanelHeight = panel.compactWorkspacesPanelHeight
          panel.v2LayoutActive = true
          if (Math.abs(workspaces.implicitHeight - v1WorkspacesPageHeight) > 0.5
              || Math.abs(panel.compactWorkspacesPanelHeight
                - v1WorkspacesPanelHeight) > 0.5)
            return root.fail(
              "Workspaces height differed between V1 and V2")
          panel.v2LayoutActive = false
          if (!panel.showSettingsPage("main"))
            return root.fail("Workspaces page did not return to overview")
          root.ticks = 0
          return
        }
        if (!panel || !panel.settingsPageReady || panel.settingsPage !== "main"
            || !widget.iconMode || widget.launcherConfig.icon !== "hyprland")
          return root.fail("overview page or G1 presentation did not restore")
        if (!panel.focusPredictiveSettingsSearch()
            || !panel.setPredictiveSettingsQuery("audio")
            || panel.settingsSearchResults.some(function(entry) {
              return entry.id === "hancore.shibumi.bluetooth"
            }))
          return root.fail(
            "global Audio search included description-only Bluetooth relation")
        if (!panel.blurPredictiveSettingsSearch()
            || panel.settingsSearchSuggestions.length !== 0
            || panel.settingsSearchResults.length === 0)
          return root.fail(
            "settings search click-away semantics did not preserve results")
        panel.focusPredictiveSettingsSearch()
        panel.dismissSettingsSearch()
        panel.dismissSettingsSearch()
        if (!panel.focusPredictiveSettingsSearch()
            || !panel.setPredictiveSettingsQuery("sur")
            || panel.settingsSearchSuggestions.length < 1
            || panel.settingsSearchResults.length < 2)
          return root.fail("settings search did not expose shared completions")
        if (panel.dismissSettingsSearch() !== "suggestions"
            || panel.settingsSearchSuggestions.length !== 0
            || panel.dismissSettingsSearch() !== "clear"
            || panel.settingsSearchResults.length !== 0)
          return root.fail("settings search Escape staging failed")
        if (!panel.showSettingsPage("quick"))
          return root.fail("Quick page rejected before return-only test")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 8) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        const quick = panel ? panel.settingsPageItem : null
        if (!panel || panel.settingsPage !== "quick" || !quick || !quick.ready
            || quick.barOptionCount !== 3 || quick.actionCount !== 8
            || quick.barOptions[2].label !== "Omarchy Bar")
          return root.fail("compact Quick switch/action deck did not instantiate")
        const activeBeforePreview = quick.activeBarId
        quick.hoveredBarIndex = 1
        if (quick.previewBar.id !== "v2"
            || quick.activeBarId !== activeBeforePreview)
          return root.fail("bar hover preview changed the active bar")
        quick.hoveredBarIndex = -1
        if (!quick.activateAction("reload") || panel.reloadCalls !== 1
            || !quick.activateAction("screensaver")
            || panel.lastQuickSystemAction !== "screensaver")
          return root.fail("Quick action deck did not delegate to its owners")
        if (!quick.activateAction("add-plugin")
            || !panel.pluginInstallerOpen)
          return root.fail("direct plugin installer did not open")
        const pluginRepository =
          "https://github.com/robzolkos/omarchy-github.git"
        const pluginCommand = "omarchy plugin add " + pluginRepository
          + " --enable"
        if (panel.extractPluginInstallUrl(pluginRepository)
              !== pluginRepository
            || panel.extractPluginInstallUrl(pluginCommand)
              !== pluginRepository
            || panel.extractPluginInstallUrl(
              "$ omarchy plugin add 'git@github.com:owner/plugin.git' --enable")
              !== "git@github.com:owner/plugin.git"
            || panel.extractPluginInstallUrl(
              "omarchy plugin add \"ssh://git@github.com/owner/plugin.git\"")
              !== "ssh://git@github.com/owner/plugin.git"
            || panel.extractPluginInstallUrl(pluginRepository + " "
              + "https://github.com/other/plugin.git") !== ""
            || panel.extractPluginInstallUrl(
              "omarchy plugin add '" + pluginRepository) !== "")
          return root.fail("plugin installer command extraction")
        const normalizedInstallCommand =
          panel.pluginInstallCommandFor(pluginCommand)
        if (JSON.stringify(normalizedInstallCommand) !== JSON.stringify([
              "omarchy", "plugin", "add", pluginRepository, "--yes"
            ]))
          return root.fail("plugin installer argv normalization")
        if (panel.setPluginInstallInput(pluginCommand) !== pluginRepository
            || !panel.validPluginInstallUrl
            || !panel.pluginInstallInputWasCommand
            || panel.normalizedPluginInstallUrl !== pluginRepository
            || !panel.normalizePluginInstallInput()
            || panel.pluginInstallUrl !== pluginRepository
            || panel.pluginInstallInputWasCommand)
          return root.fail("plugin installer input normalization")
        if (!panel.handleEscape() || panel.pluginInstallerOpen
            || !panel.open || !widget.opened)
          return root.fail("direct plugin installer staged Escape failed")
        if (!quick.activateAction("bars") || panel.settingsPage !== "bars"
            || !panel.showSettingsPage("quick"))
          return root.fail("Quick Bars tile did not open its existing editor")
        if (!quick.activateAction("pickers") || panel.settingsPage !== "pickers"
            || !panel.settingsPageItem || !panel.settingsPageItem.ready
            || panel.settingsPageItem.previewCardCount !== 6
            || !panel.showSettingsPage("quick"))
          return root.fail("Quick Pickers tile did not open its existing page")
        if (!quick.activateAction("reboot") || quick.pendingAction !== "reboot"
            || quick.confirmationButtonCount !== 2
            || quick.confirmationActionLabel !== "Reboot now"
            || panel.lastQuickSystemAction === "reboot")
          return root.fail("destructive Quick action skipped confirmation")
        if (!quick.cancelPendingAction() || quick.pendingAction !== ""
            || quick.confirmationButtonCount !== 0)
          return root.fail("destructive Quick action could not be cancelled")
        if (!quick.activateAction("shutdown")
            || quick.confirmationActionLabel !== "Shutdown now"
            || !quick.confirmPendingAction()
            || panel.lastQuickSystemAction !== "shutdown"
            || quick.pendingAction !== "")
          return root.fail("destructive Quick action confirmation did not execute")
        if (!panel.showSettingsPage("functions"))
          return root.fail("Quick page did not continue to Icons height check")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        const appearance = panel ? panel.settingsPageItem : null
        if (!panel || panel.settingsPage !== "functions" || !appearance
            || !appearance.ready)
          return root.fail("Icons no-scroll check did not instantiate")
        if (root.iconsNoScrollStep === 0) {
          panel.v2LayoutActive = false
          if (!appearance.openWidgetDetails("G4", ""))
            return root.fail("V1 Icons no-scroll detail did not open")
          root.iconsNoScrollStep = 1
          root.ticks = 0
          return
        }
        if (root.iconsNoScrollStep === 1) {
          const requiredV1 = appearance.implicitHeight
            + panel.configureDetailPanelChromeHeight
          if (panel.compactIconsSelectionPanelHeight + 0.5 < requiredV1)
            return root.fail("V1 Icons selection requires scrolling"
              + " actual=" + panel.compactIconsSelectionPanelHeight
              + " required=" + requiredV1)
          panel.v2LayoutActive = true
          appearance.controller.setGroupSetting("G4", "colorMode", "both")
          appearance.controller.setGroupSetting("G4", "widgetBorder", true)
          root.iconsNoScrollStep = 2
          root.ticks = 0
          return
        }
        const requiredV2 = appearance.implicitHeight
          + panel.configureDetailPanelChromeHeight
        if (panel.compactIconsSelectionPanelHeight + 0.5 < requiredV2)
          return root.fail("V2 Icons selection requires scrolling"
            + " actual=" + panel.compactIconsSelectionPanelHeight
            + " required=" + requiredV2)
        appearance.controller.resetGroupAppearance("G4")
        panel.v2LayoutActive = false
        panel.activeShell = "omarchy"
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 10) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        const quick = panel ? panel.settingsPageItem : null
        if (!panel || !panel.stockOmarchyHost || !quick || !quick.returnOnly
            || quick.actionCount !== 0 || panel.settingsPageOptions.length !== 0
            || panel.showSettingsPage("plugins")
            || panel.focusPredictiveSettingsSearch()
            || quick.activateAction("lock")
            || panel.lastQuickSystemAction !== "shutdown")
          return root.fail("Omarchy host exposed Shibumi controls")
        if (!quick.activateBar("v1") || panel.lastSwitchTarget !== "v1")
          return root.fail("Omarchy host did not retain the return switch")
        panel.switchService.status = {
          schemaVersion: 1, target: "v1", phase: "complete", detail: "",
          updatedEpoch: Math.floor(Date.now() / 1000)
        }
        panel.activeShell = "shibumi"
        widget.close()
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 11) {
        if (!widget || root.ticks < 3) return
        if (widget.opened || widget.panelLoaded || fakeBar.activePopout !== null)
          return root.fail("panel did not release on close")
        fakeShell.activeBarId = "omarchy.bar"
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 12) {
        if (!widget || root.ticks < 2) return
        if (!widget.stockOmarchyHost || !widget.iconMode
            || widget.nativePillSurfaceVisible)
          return root.fail("stock Omarchy return icon was not neutral")
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
