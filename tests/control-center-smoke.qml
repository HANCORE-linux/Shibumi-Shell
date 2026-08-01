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
  property bool surfaceScrollRequested: false

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
    property bool restoreNeedsReplacement: false
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

    function scheduleWidgetRestore(pluginId, page, needsReplacement) {
      restoredWidgetId = String(pluginId || "")
      restoredPage = String(page || "")
      restoreNeedsReplacement = needsReplacement === true
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
            || fakeBar.restoreWrites !== 3
            || fakeBar.restoredWidgetId !== "hancore.shibumi.control-center"
            || fakeBar.restoredPage !== "functions"
            || !fakeBar.restoreNeedsReplacement
            || stateService.config.presentation.shellStyle !== "full"
            || fakeShell.writes !== 10)
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
        if (appearance.widgetDetailOpen
            || !appearance.openWidgetDetails("G4", "")
            || !appearance.widgetDetailOpen)
          return root.fail("Icons overview did not drill into one widget")
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
            || appearance.selectedWidgetActive)
          return root.fail("V1 Icons did not expose inactive Storage")
        const inactiveModeBeforeCycle = appearance.selectedWidgetMode
        const expectedInactiveModeAfterCycle = "full"
        if (!appearance.cycleSelectedWidgetMode()
            || appearance.selectedWidgetMode !== expectedInactiveModeAfterCycle
            || stateService.groupAppearanceSettingForVariant(
              "G:hancore.shibumi.storage", "v1", "displayMode", "")
                !== expectedInactiveModeAfterCycle)
          return root.fail("V1 exposed Compact for an unsupported widget")
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
        if (plugins.catalogSummary()
            !== "2 Shibumi plugins installed\n"
              + "2 available — 1 Omarchy + 1 third-party")
          return root.fail("plugin provider summary is ambiguous: "
            + plugins.catalogSummary())
        if (!plugins.togglePluginById("omarchy.audio")
            || !plugins.feedbackVisible
            || !plugins.feedbackCountdownRunning
            || plugins.feedbackProgress <= 0
            || plugins.feedbackTitle !== "Omarchy Audio activated"
            || plugins.feedbackDetail.indexOf("hidden") < 0
            || panel.pluginEntries[0].installedInBar
            || !panel.pluginEntries[0].replaced
            || !panel.pluginEntries[1].installedInBar
            || !panel.pluginEntries[1].replacementInEffect)
          return root.fail(
            "provider switch did not expose replacement feedback")
        if (!plugins.undoLastChange()
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
          return root.fail("Plugins page did not open layout")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        if (!panel || !panel.settingsPageReady
            || panel.settingsPage !== "splits")
          return root.fail("splits page did not instantiate")
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
        if (!panel || !panel.settingsPageReady
            || panel.settingsPage !== "bars"
            || !panel.settingsPageItem
            || panel.settingsPageItem.surfaceEffectOptionCount !== 2
            || panel.settingsPageItem.surfaceRadiusOptionCount !== 0)
          return root.fail("V2 exposed V1 Bar Surface settings"
            + " effects=" + (panel && panel.settingsPageItem
              ? panel.settingsPageItem.surfaceEffectOptionCount : "missing")
            + " radii=" + (panel && panel.settingsPageItem
              ? panel.settingsPageItem.surfaceRadiusOptionCount : "missing")
            + " active=" + (panel ? panel.v2LayoutActive : "missing")
            + " page-v2=" + (panel && panel.settingsPageItem
              ? panel.settingsPageItem.v2Active : "missing")
            + " shell=" + (panel ? panel.activeShell : "missing"))
        if (!root.surfaceScrollRequested) {
          if (panel.barsSurfaceActivationY < 0
              || panel.barsDetailScrollMaximum <= 0
              || panel.barsSurfaceActivationY
                >= panel.barsDetailScrollMaximum - 1
              || !panel.scrollToBarSurface())
            return root.fail("bar child route does not activate before scroll end"
              + " activation=" + panel.barsSurfaceActivationY
              + " maximum=" + panel.barsDetailScrollMaximum)
          root.surfaceScrollRequested = true
          root.ticks = 0
          return
        }
        if (root.ticks < 24) return
        if (!panel.barsSurfaceRouteActive)
          return root.fail("bar child route did not follow detail scrolling")
        panel.v2LayoutActive = false
        if (panel.settingsPageItem.surfaceEffectOptionCount !== 3
            || panel.settingsPageItem.surfaceRadiusOptionCount !== 2)
          return root.fail("V1 Bar Surface settings did not restore")
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
        if (!panel || !panel.settingsPageReady
            || panel.settingsPage !== "health"
            || !panel.settingsPageItem
            || panel.settingsPageItem.attentionChecks.length !== 1)
          return root.fail("Health page did not instantiate")
        const health = panel.settingsPageItem
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
        if (!panel.showSettingsPage("main"))
          return root.fail("Health page did not return to overview")
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
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
            || !panel.pluginInstallerOpen || !panel.handleEscape()
            || panel.pluginInstallerOpen || !panel.open || !widget.opened)
          return root.fail("direct plugin installer or staged Escape failed")
        if (!quick.activateAction("bars") || panel.settingsPage !== "bars"
            || !panel.showSettingsPage("quick"))
          return root.fail("Quick Bars tile did not open its existing editor")
        if (!quick.activateAction("pickers") || panel.settingsPage !== "pickers"
            || !panel.showSettingsPage("quick"))
          return root.fail("Quick Pickers tile did not open its existing page")
        if (!quick.activateAction("reboot") || quick.pendingAction !== "reboot"
            || panel.lastQuickSystemAction === "reboot")
          return root.fail("destructive Quick action skipped confirmation")
        quick.pendingAction = ""
        panel.activeShell = "omarchy"
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (!widget || root.ticks < 2) return
        const panel = widget.panelItem
        const quick = panel ? panel.settingsPageItem : null
        if (!panel || !panel.stockOmarchyHost || !quick || !quick.returnOnly
            || quick.actionCount !== 0 || panel.settingsPageOptions.length !== 0
            || panel.showSettingsPage("plugins")
            || panel.focusPredictiveSettingsSearch()
            || quick.activateAction("lock")
            || panel.lastQuickSystemAction !== "screensaver")
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

      if (root.phase === 10) {
        if (!widget || root.ticks < 3) return
        if (widget.opened || widget.panelLoaded || fakeBar.activePopout !== null)
          return root.fail("panel did not release on close")
        fakeShell.activeBarId = "omarchy.bar"
        root.phase++
        root.ticks = 0
        return
      }

      if (root.phase === 11) {
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
