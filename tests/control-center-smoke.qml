pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "hancore.shibumi.state" as State
import "control" as Control
import "control/HostIdentity.js" as HostIdentity

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property var clickTargets: []
  property int barsRouteStep: 0
  property int iconsNoScrollStep: 0
  property bool panelIdempotenceStarted: false
  property bool requestedPreviewChecked: false
  property var stablePanelItem: null
  property int healthLifecycleStep: 0
  property int healthProjectionStep: 0
  property string projectionReportJson: ""
  property var stableHealthReport: null
  property var lifecycleHealthService: null
  property int lifecycleReportEpoch: 0
  property int activeBarStatusStep: 0
  property bool statusStockHost: false
  property bool statusV2Layout: false
  property real widestActiveBarStatus: 0
  property int paletteLifecycleStep: 0
  property int paletteInitialTileCount: 0
  property int quickBarIdentityStep: 0
  property var quickBarDelegatesBefore: []
  property var quickBarPointersBefore: []

  Control.PluginUpdateTestService { id: pluginUpdateService }
  Control.PluginUpdateTestService { id: replacementUpdateService }
  property var selectedUpdateService: pluginUpdateService
  property int updateRebindPhase: 0
  property var updateRebindPanel: null

  function fail(message) {
    console.error("control-center-smoke:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  function healthCheck(id, status, owner, label, value, detail) {
    return {
      id: id,
      group: "Runtime",
      label: label,
      status: status,
      value: value,
      detail: detail,
      component: "fixture component",
      owner: owner,
      issueEligible: owner === "shibumi" && status === "error",
      action: "Review the attributed component."
    }
  }

  function healthReport(overall, checks) {
    return {
      schemaVersion: 1,
      generatedEpoch: 1785570000,
      overall: overall,
      summary: "Projection fixture",
      checks: checks
    }
  }

  function quickBarStateError(panel, delegates, activeId, v2Detail) {
    const ids = ["v1", "v2", "omarchy"]
    const labels = ["V1", "V2", "Omarchy Bar"]
    const details = ["Shibumi split bar", v2Detail, "Stock Omarchy bar"]
    for (let index = 0; index < ids.length; index++) {
      const option = delegates[index]
      const active = ids[index] === activeId
      if (!option || String(option.modelData.id || "") !== ids[index]
          || String(option.modelData.label || "") !== labels[index]
          || String(option.modelData.detail || "") !== details[index]
          || option.modelData.active !== active
          || option.Accessible.role !== Accessible.RadioButton
          || option.Accessible.name !== labels[index]
          || option.Accessible.description !== details[index]
          || option.Accessible.checked !== active
          || !panel.findTextItem(option, labels[index])
          || !panel.findTextItem(option, details[index])
          || (panel.findTextItem(option, "ACTIVE") !== null) !== active)
        return ids[index]
    }
    return ""
  }

  QtObject {
    id: fakeShell

    property int writes: 0
    property var requestedStateOverride: null
    property string activeBarId: "hancore.shibumi.bar"
    property var barConfig: ({ id: "hancore.shibumi.bar" })
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

  // Omarchy's built-in bar gives a third-party widget this capability shape,
  // not the live Bar object. The selected barConfig can still name a custom
  // bar when its Loader failed and the built-in bar became the active host.
  QtObject {
    id: scopedStockBar

    property string pluginId: "hancore.shibumi.control-center"
    property string moduleName: "hancore.shibumi.control-center"
    readonly property var foreignPopoutMarker: ({ foreign: true })
    property var shell: fakeShell
    property var layoutConfig: ({})
    property bool vertical: false
    property int barSize: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#d75f5f"
    property var activePopout: null
    property var clickTargets: root.clickTargets

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

  Window {
    id: testWindow
    width: 800
    height: 600
    visible: root.phase === 8
    onVisibleChanged: if (visible) requestActivate()

    Loader {
      id: widgetLoader
      active: true
      sourceComponent: Component {
        Control.BarWidget {
          bar: fakeBar
          panelSource: Qt.resolvedUrl("fixtures/ControlCenterTestPanel.qml")
          pluginUpdateServiceOverride: root.selectedUpdateService
        }
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

        if (!root.requestedPreviewChecked) {
          const confirmed = JSON.parse(JSON.stringify(stateService.config))
          const requested = JSON.parse(JSON.stringify(confirmed))
          requested.workspace.mode = "active"
          requested.workspace.style = "rings"
          requested.launcher = ({ mode: "icon", text: "omarchy", icon: "rebel" })
          if (!requested.widgets) requested.widgets = ({})
          if (!requested.widgets.G4) requested.widgets.G4 = ({})
          requested.widgets.G4.enabledV1 = false
          fakeShell.requestedStateOverride = requested
          if (panel.workspaceConfig.mode !== "active"
              || panel.workspaceConfig.style !== "rings"
              || panel.launcherConfig.icon !== "rebel"
              || panel.groupEnabled("G4")
              || !widget.iconMode || widget.launcherConfig.icon !== "rebel"
              || stateService.config.workspace.mode === "active"
              || !stateService.groupEnabledForVariant("G4", "v1")
              || fakeShell.writes !== 0)
            return root.fail("requested presentation state did not preview independently")
          fakeShell.requestedStateOverride = null
          if (panel.workspaceConfig.mode === "active"
              || panel.launcherConfig.icon === "rebel"
              || !panel.groupEnabled("G4") || widget.iconMode
              || JSON.stringify(stateService.config) !== JSON.stringify(confirmed)
              || fakeShell.writes !== 0)
            return root.fail("requested presentation preview did not roll back")
          root.requestedPreviewChecked = true
        }

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
            || appearance.selectedWidgetModeOptions.length !== 2
            || appearance.selectedWidgetModeOptions[0].value !== "default"
            || appearance.selectedWidgetModeOptions[0].label !== "Default"
            || appearance.selectedWidgetModeOptions[1].value !== "full"
            || appearance.selectedWidgetModeOptions[1].label !== "Compact"
            || !appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== "full"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v2", "mediaStyle", "") !== "default")
          return root.fail("V1 Now Playing Default/Compact contract drifted")
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
            || appearance.selectedWidgetModeOptions.length !== 2
            || appearance.selectedWidgetModeOptions[0].value !== "default"
            || appearance.selectedWidgetModeOptions[0].label !== "Default"
            || appearance.selectedWidgetModeOptions[1].value !== "full"
            || appearance.selectedWidgetModeOptions[1].label !== "Compact"
            || !appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== "full"
            || stateService.groupAppearanceSettingForVariant(
              "G9", "v1", "mediaStyle", "") !== "default")
          return root.fail("V2 Now Playing Default/Compact contract drifted")
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
        const presentationRequestsBefore = panel.presentationPluginRequests
        panel.rejectNonPresentationWhilePending = true
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
            || !appearance.selectedWidgetActive
            || panel.presentationPluginRequests
              !== presentationRequestsBefore + 4)
          return root.fail("V2 Icons did not restore Storage through coalesced presentation requests")
        panel.rejectNonPresentationWhilePending = false
        panel.v2LayoutActive = false
        if (appearance.activeWidgetCount !== 12
            || appearance.inactiveWidgetCount !== 6
            || !appearance.widgetDetailOpen
            || appearance.selectedWidgetActive)
          return root.fail("Icons did not preserve inactive detail across V1/V2")
        pluginUpdateService.scopedHost = false
        if (!panel.showSettingsPage("plugins"))
          return root.fail("Plugins page rejected")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (!panel || panel.settingsPage !== "plugins"
            || !panel.settingsPageItem)
          return root.fail("Plugins page did not instantiate")
        const plugins = panel.settingsPageItem
        if ((!panel.settingsPageReady || !plugins.ready)
            && root.updateRebindPhase !== 2 && root.updateRebindPhase !== 3) {
          if (root.ticks < 20) return
          return root.fail("Plugins page did not become ready")
        }
        if (root.updateRebindPhase > 0 && panel !== root.updateRebindPanel)
          return root.fail("update provider change recreated the Plugins panel")
        if (root.updateRebindPhase === 0) {
          if (!plugins.ready || pluginUpdateService.catalogConsumerCount !== 0
              || plugins.catalogConsumerActive || plugins.catalogObservation !== null)
            return root.fail("legacy Plugins page acquired a native catalog lease or lost readiness")
          root.updateRebindPanel = panel
          pluginUpdateService.scopedHost = true
          root.updateRebindPhase++
          return
        }
        if (root.updateRebindPhase === 1) {
          if (pluginUpdateService.catalogConsumerCount !== 1
              || !plugins.catalogConsumerActive
              || plugins.catalogObservation === null)
            return root.fail("scoped Plugins page did not acquire the catalog observation")
          root.selectedUpdateService = null
          root.updateRebindPhase++
          return
        }
        if (root.updateRebindPhase === 2) {
          if (pluginUpdateService.consumerCount !== 0
              || pluginUpdateService.catalogConsumerCount !== 0
              || plugins.pluginUpdateConsumerActive
              || plugins.catalogConsumerActive)
            return root.fail("revoked update provider retained a page consumer")
          root.selectedUpdateService = replacementUpdateService
          root.updateRebindPhase++
          return
        }
        if (root.updateRebindPhase === 3) {
          if (replacementUpdateService.consumerCount !== 1
              || replacementUpdateService.catalogConsumerCount !== 1
              || pluginUpdateService.consumerCount !== 0
              || pluginUpdateService.catalogConsumerCount !== 0)
            return root.fail("late update provider did not acquire the open catalog")
          root.selectedUpdateService = pluginUpdateService
          root.updateRebindPhase++
          return
        }
        if (root.updateRebindPhase === 4) {
          if (replacementUpdateService.consumerCount !== 0
              || replacementUpdateService.catalogConsumerCount !== 0
              || pluginUpdateService.consumerCount !== 1
              || pluginUpdateService.catalogConsumerCount !== 1)
            return root.fail("update provider replacement leaked a page consumer")
          root.updateRebindPhase++
        }
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
        panel.asyncPluginTransitions = true
        const failedSettlements = [
          "state-refused", "revoked", "native-indeterminate", "state-timeout"
        ]
        for (let failureIndex = 0;
             failureIndex < failedSettlements.length; failureIndex++) {
          const result = failedSettlements[failureIndex]
          if (!plugins.togglePluginById("omarchy.audio")
              || !plugins.transitionPending
              || plugins.pendingPluginMutation === null
              || plugins.feedbackTitle.indexOf("Updating") !== 0
              || plugins.feedbackTitle.indexOf("activated") >= 0
              || plugins.undoMode !== ""
              || plugins.undoProviderSnapshot !== null
              || !panel.settlePluginTransition(result, false)
              || plugins.transitionPending
              || plugins.undoMode !== ""
              || plugins.undoProviderSnapshot !== null
              || plugins.feedbackDetail === ""
              || !panel.pluginEntries[0].installedInBar
              || panel.pluginEntries[1].installedInBar)
            return root.fail("failed async plugin settlement published success or Undo: "
              + result)
        }
        if (!plugins.togglePluginById("omarchy.audio")
            || !plugins.transitionPending
            || plugins.undoMode !== ""
            || !panel.settlePluginTransition("confirmed", true)
            || plugins.transitionPending
            || plugins.feedbackTitle !== "Omarchy Audio activated"
            || plugins.undoMode !== "provider-snapshot"
            || !plugins.undoProviderSnapshot
            || !panel.pluginEntries[1].installedInBar)
          return root.fail("confirmed async plugin settlement did not publish Undo")
        const retainedSnapshot = JSON.stringify(
          plugins.undoProviderSnapshot)
        if (!plugins.undoLastChange()
            || !plugins.transitionPending
            || !panel.providerSnapshotTransitionBusy
            || JSON.stringify(plugins.undoProviderSnapshot)
              !== retainedSnapshot
            || !panel.settleProviderSnapshotTransition(
              "state-refused", false)
            || plugins.transitionPending
            || plugins.undoMode !== "provider-snapshot"
            || JSON.stringify(plugins.undoProviderSnapshot)
              !== retainedSnapshot
            || plugins.feedbackTitle !== "Undo could not be completed"
            || !plugins.feedbackCountdownRunning
            || !panel.pluginEntries[1].installedInBar)
          return root.fail("failed async provider Undo discarded its snapshot: pending="
            + plugins.transitionPending + " mode=" + plugins.undoMode
            + " same=" + (JSON.stringify(plugins.undoProviderSnapshot)
              === retainedSnapshot)
            + " title=" + plugins.feedbackTitle
            + " countdown=" + plugins.feedbackCountdownRunning
            + " shibumi=" + panel.pluginEntries[0].installedInBar
            + " omarchy=" + panel.pluginEntries[1].installedInBar)
        if (!plugins.undoLastChange()
            || !plugins.transitionPending
            || !panel.settleProviderSnapshotTransition("unchanged", true)
            || plugins.transitionPending
            || plugins.feedbackVisible
            || plugins.undoMode !== ""
            || plugins.undoProviderSnapshot !== null
            || !panel.pluginEntries[0].installedInBar
            || panel.pluginEntries[1].installedInBar)
          return root.fail("confirmed async provider Undo did not clear its snapshot")
        panel.asyncPluginTransitions = false
        panel.asyncStateTransitions = true
        for (const stateFailure of ["state-timeout", "revoked"]) {
          if (!plugins.togglePluginById("hancore.shibumi.bluetooth")
              || !plugins.transitionPending
              || !panel.pluginStateTransitionBusy
              || plugins.undoMode !== ""
              || plugins.feedbackTitle.indexOf("Updating") !== 0
              || !panel.settlePluginStateTransition(stateFailure, false)
              || plugins.transitionPending || plugins.undoMode !== ""
              || !panel.pluginEntries[3].installedInBar)
            return root.fail("state-only plugin failure published success: "
              + stateFailure)
        }
        if (!plugins.togglePluginById("hancore.shibumi.bluetooth")
            || !plugins.transitionPending
            || !panel.pluginStateTransitionBusy
            || !panel.settlePluginStateTransition("confirmed", true)
            || plugins.transitionPending
            || plugins.feedbackTitle !== "Shibumi Bluetooth deactivated"
            || plugins.undoMode !== "plugin-value"
            || panel.pluginEntries[3].installedInBar)
          return root.fail("confirmed state-only plugin toggle lacked settlement")
        if (!plugins.undoLastChange() || !plugins.transitionPending
            || !panel.pluginStateTransitionBusy
            || !panel.settlePluginStateTransition("confirmed", true)
            || plugins.transitionPending || plugins.feedbackVisible
            || plugins.undoMode !== ""
            || !panel.pluginEntries[3].installedInBar)
          return root.fail("state-only plugin Undo lacked settlement")
        if (!plugins.togglePluginById("hancore.shibumi.bluetooth")
            || !plugins.transitionPending) {
          return root.fail("controller replacement state-only setup failed")
        }
        // Model the detached owner identity that an already accepted request
        // retains across controller replacement. A stale settlement must not
        // publish success or Undo into the current page.
        plugins.pendingPluginMutation.owner = fakeBar
        panel.settlePluginStateTransition("confirmed", false)
        if (plugins.transitionPending || plugins.undoMode !== ""
            || plugins.feedbackTitle.indexOf("Updating") !== 0)
          return root.fail("controller replacement published state-only success")
        plugins.feedbackVisible = false
        panel.asyncStateTransitions = false
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
        const beforeRemoval = JSON.stringify(panel.pluginEntries)
        panel.refusePluginRemoval = true
        if (!plugins.requestPluginRemovalById("acme.weather")
            || plugins.confirmPluginRemoval()
            || plugins.feedbackDetail !== panel.removalRefusalDetail
            || panel.pluginRemovalRunning
            || JSON.stringify(panel.pluginEntries) !== beforeRemoval)
          return root.fail("plugin removal feedback hid the return-to-extra workaround")
        panel.removalRefusalDetail = ""
        if (!plugins.requestPluginRemovalById("acme.weather")
            || plugins.confirmPluginRemoval()
            || plugins.feedbackDetail !== "The provider rejected the remove request."
            || JSON.stringify(panel.pluginEntries) !== beforeRemoval)
          return root.fail("plugin removal generic fallback retained stale feedback")
        panel.refusePluginRemoval = false
        if (!plugins.requestPluginRemovalById("acme.weather")
            || !plugins.removalConfirmationVisible
            || !plugins.confirmPluginRemoval()
            || plugins.entryById("acme.weather") !== null
            || plugins.feedbackTitle !== "Acme Weather removed")
          return root.fail("third-party plugin removal flow failed")
        panel.asyncPluginTransitions = true
        if (!plugins.togglePluginById("omarchy.audio")
            || !plugins.transitionPending
            || !panel.showSettingsPage("splits"))
          return root.fail("pending Plugins owner teardown setup failed")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (panel && panel.pluginLayoutTransitionBusy) {
          if (!panel.settlePluginTransition("revoked", false))
            return root.fail("destroyed Plugins owner settlement setup failed")
          root.ticks = 0
          return
        }
        if (pluginUpdateService.catalogConsumerCount !== 0
            || replacementUpdateService.catalogConsumerCount !== 0
            || pluginUpdateService.catalogReleaseCount < 2
            || pluginUpdateService.catalogWrongReleaseCount !== 0
            || replacementUpdateService.catalogWrongReleaseCount !== 0)
          return root.fail("leaving Plugins retained or misreleased its catalog lease")
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
            pluginId: "hancore.shibumi.example",
            sourcePath: "hancore.shibumi.example/Example.qml:42",
            owner: "shibumi",
            issueEligible: true,
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
              || panel.settingsPage !== "health" || !panel.settingsPageItem)
            return root.fail("Health page did not instantiate")
          const health = panel.settingsPageItem

          if (root.healthProjectionStep === 0) {
            if (panel.headerHealthErrorCount !== 1
                || health.attentionChecks.length !== 1)
              return root.fail(
                "Health page lost its initial Shibumi-owned runtime error")
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
            if (health.diagnosticIssueUrl({
                  id: "runtime-errors-omarchy", status: "error",
                  owner: "omarchy", issueEligible: true
                }) !== ""
                || health.diagnosticIssueUrl({
                  id: "runtime-errors", status: "warning",
                  owner: "shibumi", issueEligible: true
                }) !== "")
              return root.fail("Health filing gate accepted an external or warning finding")
            health.copyDiagnostic(error)
            if (health.copiedCheckId !== "runtime-errors")
              return root.fail("Health error report was not copied")

            root.stableHealthReport = panel.healthService.report
            panel.healthService.report = root.healthReport("error", [
              root.healthCheck("runtime-errors", "error", "omarchy",
                "External runtime-errors", "1 error", "External detail"),
              root.healthCheck("runtime-errors-omarchy", "warning", "omarchy",
                "External runtime-errors-omarchy", "1 warning", "External detail"),
              root.healthCheck("runtime-errors-third-party", "error",
                "third-party", "External runtime-errors-third-party", "1 error",
                "External detail"),
              root.healthCheck("runtime-errors-unknown", "warning", "unknown",
                "External runtime-errors-unknown", "1 warning", "External detail"),
              root.healthCheck("runtime-warnings", "error", "third-party",
                "External runtime-warnings", "1 error", "External detail"),
              root.healthCheck("runtime-warnings-omarchy", "warning", "omarchy",
                "External runtime-warnings-omarchy", "1 warning", "External detail"),
              root.healthCheck("runtime-warnings-third-party", "error",
                "third-party", "External runtime-warnings-third-party", "1 error",
                "External detail"),
              root.healthCheck("runtime-warnings-unknown", "warning", "unknown",
                "External runtime-warnings-unknown", "1 warning", "External detail"),
              root.healthCheck("runtime-errors", "error", "shibumi",
                "Shibumi runtime error", "1 error", "Shibumi detail"),
              root.healthCheck("runtime-errors", "warning", "unknown",
                "Recent runtime findings", "Log unavailable", "Unavailable detail"),
              root.healthCheck("runtime-errors-sensitive", "warning", "unknown",
                "Sensitive runtime findings", "Details redacted", "Redacted"),
              root.healthCheck("quickshell-process", "error", "unknown",
                "Quickshell process", "missing", "Process detail"),
              root.healthCheck("payload-integrity", "error", "unknown",
                "Payload integrity", "mismatch", "Payload detail"),
              root.healthCheck("audio-backend", "warning", "unknown",
                "Audio backend", "unavailable", "Backend detail")
            ])
            root.projectionReportJson = JSON.stringify(panel.healthService.report)
            root.healthProjectionStep = 1
            root.ticks = 0
            return
          }

          if (root.healthProjectionStep === 1) {
            const mixed = panel.healthService.report.checks
            if (health.primaryChecks.length !== 6
                || health.attentionChecks.length !== 6
                || panel.headerHealthErrorCount !== 3
                || panel.headerHealthWarningCount !== 3
                || health.primaryChecks[0] !== mixed[8]
                || health.primaryChecks[1] !== mixed[9]
                || health.primaryChecks[2] !== mixed[10]
                || health.primaryChecks[3] !== mixed[11]
                || health.primaryChecks[4] !== mixed[12]
                || health.primaryChecks[5] !== mixed[13]
                || JSON.stringify(panel.healthService.report)
                  !== root.projectionReportJson)
              return root.fail(
                "Health projection case 1 broke the exact-ID or owner boundary")
            panel.healthService.report = root.healthReport("error", [
              root.healthCheck("bar-runtime", "ok", "shibumi",
                "Active bar", "Running", "Primary detail"),
              root.healthCheck("quickshell-process", "ok", "unknown",
                "Quickshell process", "1 process", "Primary detail"),
              root.healthCheck("runtime-errors", "ok", "unknown",
                "Recent runtime errors", "None detected", "Primary detail"),
              root.healthCheck("runtime-errors-omarchy", "error", "omarchy",
                "Omarchy runtime error", "1 error", "External detail"),
              root.healthCheck("runtime-warnings-third-party", "warning",
                "third-party", "Third-party runtime warning", "1 warning",
                "External detail")
            ])
            root.projectionReportJson = JSON.stringify(panel.healthService.report)
            root.healthProjectionStep = 2
            root.ticks = 0
            return
          }

          if (root.healthProjectionStep === 2) {
            const realistic = panel.healthService.report.checks
            const oldGroupLabel = "2 runtime findings not attributed to Shibumi (Omarchy, Qt, third-party, unknown)"
            if (health.primaryChecks.length !== 3
                || health.attentionChecks.length !== 0
                || panel.headerHealthErrorCount !== 0
                || panel.headerHealthWarningCount !== 0
                || !panel.headerHealthPassed
                || health.overallLabel() !== "Healthy"
                || health.summaryLabel() !== "3 checks passed"
                || panel.healthReport.overall !== "error"
                || panel.healthReport.checks.length !== 5
                || health.primaryChecks[0] !== realistic[0]
                || health.primaryChecks[1] !== realistic[1]
                || health.primaryChecks[2] !== realistic[2]
                || panel.findTextItem(health, oldGroupLabel)
                || !panel.findTextItem(panel, "HEALTH  ·  PASS")
                || JSON.stringify(panel.healthService.report)
                  !== root.projectionReportJson)
              return root.fail(
                "Health projection case 2 exposed or counted external runtime findings"
                + " primary=" + health.primaryChecks.length
                + " attention=" + health.attentionChecks.length
                + " errors=" + panel.headerHealthErrorCount
                + " warnings=" + panel.headerHealthWarningCount
                + " passed=" + panel.headerHealthPassed
                + " label=" + health.overallLabel()
                + " summary=" + health.summaryLabel()
                + " overall=" + panel.healthReport.overall
                + " checks=" + panel.healthReport.checks.length
                + " oldGroup=" + !!panel.findTextItem(health, oldGroupLabel)
                + " chip=" + !!panel.findTextItem(panel, "HEALTH  ·  PASS")
                + " immutable=" + (JSON.stringify(panel.healthService.report)
                  === root.projectionReportJson))
            panel.healthService.report = root.healthReport("warning", [
              root.healthCheck("managed-plugins", "ok", "shibumi",
                "Managed plugins", "Complete", "Primary detail"),
              root.healthCheck("runtime-errors", "ok", "unknown",
                "Recent runtime errors", "None detected", "Primary detail"),
              root.healthCheck("runtime-warnings-unknown", "warning", "unknown",
                "Qt portal runtime warning", "1 warning", "External detail")
            ])
            root.projectionReportJson = JSON.stringify(panel.healthService.report)
            root.healthProjectionStep = 3
            root.ticks = 0
            return
          }

          if (root.healthProjectionStep === 3) {
            const oldGroupLabel = "1 runtime findings not attributed to Shibumi (Omarchy, Qt, third-party, unknown)"
            if (health.primaryChecks.length !== 2
                || health.attentionChecks.length !== 0
                || !panel.headerHealthPassed
                || health.overallLabel() !== "Healthy"
                || panel.healthReport.overall !== "warning"
                || panel.findTextItem(health, oldGroupLabel)
                || JSON.stringify(panel.healthService.report)
                  !== root.projectionReportJson)
              return root.fail(
                "Health projection case 3 trusted raw overall or rendered a warning")
            panel.healthService.report = root.healthReport("error", [
              root.healthCheck("runtime-errors", "warning", "unknown",
                "Recent runtime findings", "Log unavailable", "Unavailable detail"),
              root.healthCheck("runtime-warnings-omarchy", "warning", "omarchy",
                "Omarchy runtime warnings", "many warnings", "External detail"),
              root.healthCheck("runtime-errors-sensitive", "warning", "unknown",
                "Sensitive runtime findings", "Details redacted", "Redacted"),
              root.healthCheck("quickshell-process", "error", "unknown",
                "Quickshell process", "0 processes", "Process detail"),
              root.healthCheck("payload-integrity", "error", "unknown",
                "Payload integrity", "mismatch", "Payload detail"),
              root.healthCheck("audio-backend", "warning", "unknown",
                "Audio backend", "unavailable", "Backend detail")
            ])
            root.healthProjectionStep = 4
            root.ticks = 0
            return
          }

          if (root.healthProjectionStep === 4) {
            const unsafeMasking = panel.healthService.report.checks
            if (health.primaryChecks.length !== 5
                || health.attentionChecks.length !== 5
                || health.primaryChecks[0] !== unsafeMasking[0]
                || health.primaryChecks[1] !== unsafeMasking[2]
                || health.primaryChecks[2] !== unsafeMasking[3]
                || health.primaryChecks[3] !== unsafeMasking[4]
                || health.primaryChecks[4] !== unsafeMasking[5]
                || health.primaryChecks[0].value !== "Log unavailable"
                || health.primaryChecks[0].status !== "warning"
                || health.primaryChecks[1].status !== "warning"
                || health.primaryChecks[2].status !== "error"
                || health.primaryChecks[3].status !== "error"
                || health.primaryChecks[4].status !== "warning"
                || panel.headerHealthErrorCount !== 2
                || panel.headerHealthWarningCount !== 3
                || panel.headerHealthPassed
                || health.overallLabel() !== "Action needed"
                || panel.findTextItem(health, "Omarchy runtime warnings"))
              return root.fail(
                "Health projection case 4 masked Log unavailable or a primary failure")
            const unsafeReport = JSON.stringify({
              schemaVersion: 1,
              summary: "unsafe fixture",
              checks: [{
                id: "runtime-errors", status: "error",
                label: "Sensitive fixture", value: "1 error",
                detail: "password=\"secret value\"", owner: "shibumi",
                issueEligible: true
              }]
            })
            if (!panel.healthService.acceptReport(unsafeReport)
                || panel.healthService.report.checks[0].issueEligible
                || panel.healthService.report.checks[0].detail
                  .indexOf("secret value") >= 0)
              return root.fail("Health report sanitization or filing gate failed")
            panel.healthService.report = root.healthReport("healthy", [
              root.healthCheck("runtime-errors", "ok", "unknown",
                "Recent runtime errors", "None detected", "Clean sample")
            ])
            root.healthProjectionStep = 5
            root.ticks = 0
            return
          }

          if (root.healthProjectionStep === 5) {
            const healthyReport = panel.healthService.report
            if (panel.healthService.acceptReport("{broken")
                || panel.healthService.report !== healthyReport
                || panel.healthService.failure === ""
                || health.primaryChecks.length !== 1
                || panel.headerHealthErrorCount !== 1
                || panel.headerHealthPassed
                || health.overallLabel() !== "Action needed")
              return root.fail(
                "Health projection case 5 lost the schema-failure fallback")
            panel.healthService.failure = "Health check failed (exit 1)."
            root.healthProjectionStep = 6
            root.ticks = 0
            return
          }

          if (root.healthProjectionStep === 6) {
            if (panel.headerHealthErrorCount !== 1
                || panel.headerHealthPassed
                || health.overallLabel() !== "Action needed")
              return root.fail(
                "Health projection case 6 lost the fetch-failure fallback")
            panel.healthService.failure = ""
            panel.healthService.report = root.healthReport("loading", [])
            root.healthProjectionStep = 7
            root.ticks = 0
            return
          }

          if (health.primaryChecks.length !== 0
              || health.attentionChecks.length !== 0
              || panel.headerHealthErrorCount !== 0
              || panel.headerHealthWarningCount !== 0
              || panel.headerHealthPassed
              || health.overallLabel() !== "Not checked"
              || health.summaryLabel() !== "Not checked yet"
              || panel.findTextItem(panel, "HEALTH  ·  PASS"))
            return root.fail(
              "Health projection case 7 treated an empty report as checked")
          panel.healthService.report = root.stableHealthReport
          root.lifecycleHealthService = panel.healthService
          root.lifecycleReportEpoch = Number(
            root.stableHealthReport.generatedEpoch || 0)
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
        if (!panel) return root.fail("palette lifecycle panel disappeared")
        if (root.paletteLifecycleStep === 0) {
          if (panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== 0)
            return root.fail("closed widget palette retained production items")
          if (panel.settingsPage !== "plugins") {
            if (!panel.showSettingsPage("plugins"))
              return root.fail("widget palette host page did not open")
            root.ticks = 0
            return
          }
          const buildStarted = Date.now()
          if (!panel.openWidgetPicker())
            return root.fail("widget palette did not open")
          console.log("widget palette fixture initial open call ms:",
            Date.now() - buildStarted)
          root.paletteLifecycleStep = 1
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 1) {
          if (!panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== panel.availableWidgetCount
              || !panel.widgetPaletteInputFocused())
            return root.fail("open widget palette did not build and focus: loaded="
              + panel.widgetPaletteLoaded() + " tiles="
              + panel.widgetPaletteTileCount() + " expected="
              + panel.availableWidgetCount + " focus="
              + panel.widgetPaletteInputFocused())
          root.paletteInitialTileCount = panel.widgetPaletteTileCount()
          panel.setWidgetPaletteQuery("bluetooth")
          root.paletteLifecycleStep = 2
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 2) {
          if (panel.widgetPaletteTileCount() !== 1)
            return root.fail("widget palette search did not filter current catalog")
          if (!panel.dismissWidgetPaletteFromOutside())
            return root.fail("widget palette outside dismissal was unavailable")
          root.paletteLifecycleStep = 3
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 3) {
          if (panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== 0
              || panel.widgetPaletteInputFocused())
            return root.fail("outside dismissal did not unload widget palette")
          panel.appendWidgetPaletteProbe()
          const buildStarted = Date.now()
          if (!panel.openWidgetPicker())
            return root.fail("widget palette did not reopen")
          console.log("widget palette fixture reopen call ms:",
            Date.now() - buildStarted)
          root.paletteLifecycleStep = 4
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 4) {
          if (!panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== panel.availableWidgetCount
              || panel.widgetPaletteTileCount()
                !== root.paletteInitialTileCount + 1
              || !panel.widgetPaletteInputFocused())
            return root.fail("reopened widget palette retained stale catalog state")
          if (!panel.handleEscape())
            return root.fail("widget palette Escape dismissal failed")
          root.paletteLifecycleStep = 5
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 5) {
          if (panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== 0)
            return root.fail("Escape did not unload widget palette")
          if (!panel.openPluginInstaller())
            return root.fail("direct plugin installer did not open after unload")
          root.paletteLifecycleStep = 6
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 6) {
          if (!panel.pluginInstallerOpen || !panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== panel.availableWidgetCount
              || !panel.widgetPaletteInputFocused())
            return root.fail("reopened installer lost its production focus path")
          if (!panel.handleEscape())
            return root.fail("direct installer Escape dismissal failed")
          root.paletteLifecycleStep = 7
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 7) {
          if (panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== 0)
            return root.fail("installer close did not unload widget palette")
          if (!panel.openWidgetPicker())
            return root.fail("embedded installer picker did not open")
          root.paletteLifecycleStep = 8
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 8) {
          if (panel.widgetPaletteInstallMode() || !panel.widgetPaletteInputFocused()
              || !panel.openEmbeddedPluginInstaller())
            return root.fail("embedded installer production action was unavailable")
          root.paletteLifecycleStep = 9
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 9) {
          if (!panel.widgetPaletteInstallMode() || !panel.widgetPaletteInputFocused()
              || !panel.backFromEmbeddedPluginInstaller())
            return root.fail("embedded installer input did not receive focus")
          root.paletteLifecycleStep = 10
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 10) {
          if (panel.widgetPaletteInstallMode()
              || !panel.widgetPaletteInputFocused() || !panel.handleEscape())
            return root.fail("embedded installer Back did not refocus search")
          root.paletteLifecycleStep = 11
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 11) {
          if (panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== 0)
            return root.fail("embedded installer close did not unload palette")
          if (!panel.openWidgetPicker() || !panel.handleEscape())
            return root.fail("queued-focus teardown setup failed")
          root.paletteLifecycleStep = 12
          root.ticks = 0
          return
        }
        if (root.paletteLifecycleStep === 12) {
          if (panel.widgetPaletteLoaded()
              || panel.widgetPaletteTileCount() !== 0
              || panel.widgetPaletteInputFocused()
              || !panel.showSettingsPage("quick"))
            return root.fail("queued focus survived palette destruction")
          root.paletteLifecycleStep = 13
          root.ticks = 0
          return
        }
        if (panel.settingsPage !== "quick" || !quick || !quick.ready
            || quick.barOptionCount !== 3 || quick.actionCount !== 8
            || quick.barOptions[2].label !== "Omarchy Bar")
          return root.fail("compact Quick switch/action deck did not instantiate")
        const barDelegates = panel.quickBarOptionDelegates()
        const barPointers = panel.quickBarOptionPointerAreas()
        if (barDelegates.length !== 3 || barPointers.length !== 3
            || barDelegates.some(function(item) { return item === null })
            || barPointers.some(function(item) { return item === null }))
          return root.fail("Quick bar delegate identity fixture did not find three options")
        if (root.quickBarIdentityStep === 0) {
          panel.v2LayoutActive = true
          root.quickBarIdentityStep = 1
          root.ticks = 0
          return
        }
        if (root.quickBarIdentityStep === 1) {
          const stateError = root.quickBarStateError(
            panel, barDelegates, "v2", "Shibumi full bar")
          if (stateError !== "")
            return root.fail("Quick Full bar delegate data did not bind: "
              + stateError)
          if (!panel.setBarPresentation("shellStyle", "fit"))
            return root.fail("Quick Full/Fit delegate transition was rejected")
          root.quickBarIdentityStep = 2
          root.ticks = 0
          return
        }
        if (root.quickBarIdentityStep === 2) {
          const stateError = root.quickBarStateError(
            panel, barDelegates, "v2", "Shibumi fit bar")
          if (stateError !== "")
            return root.fail("Quick Fit bar delegate data did not rebound: "
              + stateError)
          root.quickBarDelegatesBefore = barDelegates
          root.quickBarPointersBefore = barPointers
          panel.v2LayoutActive = false
          root.quickBarIdentityStep = 3
          root.ticks = 0
          return
        }
        if (root.quickBarIdentityStep === 3) {
          for (let index = 0; index < 3; index++) {
            if (barDelegates[index] !== root.quickBarDelegatesBefore[index])
              return root.fail(
                "Quick bar delegate identity changed across V2 to V1")
            if (barPointers[index] !== root.quickBarPointersBefore[index])
              return root.fail(
                "Quick bar pointer identity changed across V2 to V1")
          }
          const stateError = root.quickBarStateError(
            panel, barDelegates, "v1", "Shibumi fit bar")
          if (stateError !== "")
            return root.fail("Quick V1 bar delegate data did not rebound: "
              + stateError)
          root.quickBarIdentityStep = 4
        }
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
            || !panel.pluginInstallerOpen || panel.settingsPage !== "plugins")
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
        fakeShell.activeBarId = ""
        fakeShell.barConfig = ({ id: "hancore.shibumi.bar" })
        widget.bar = scopedStockBar
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
        fakeShell.activeBarId = "hancore.shibumi.bar"
        fakeShell.barConfig = ({ id: "hancore.shibumi.bar" })
        widget.bar = fakeBar
        widget.close()
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 11) {
        if (!widget || root.ticks < 3) return
        if (widget.opened || widget.panelLoaded || fakeBar.activePopout !== null)
          return root.fail("panel did not release on close")
        fakeShell.activeBarId = ""
        fakeShell.barConfig = ({ position: "top" })
        widget.bar = scopedStockBar
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 12) {
        if (!widget || root.ticks < 2) return
        if (HostIdentity.shellName(scopedStockBar) !== "omarchy"
            || !widget.stockOmarchyHost || !widget.iconMode
            || widget.nativePillSurfaceVisible)
          return root.fail("scoped stock Omarchy return icon was not neutral")
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
