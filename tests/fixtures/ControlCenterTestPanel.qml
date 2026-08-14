pragma ComponentBehavior: Bound

import QtQuick
import "../control" as Control

Item {
  id: root

  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var stateService
  required property var healthService
  required property var switchService
  required property var pluginUpdateService

  readonly property bool open: ownerWidget.opened
  readonly property var healthReport: healthService.report
  readonly property bool healthRunning: healthService.running
  readonly property bool healthFetching: healthService.fetching
  readonly property string healthFailure: healthService.failure
  readonly property var stateConfig: stateService && stateService.config
    ? stateService.config : ({})
  readonly property var rawBarPresentation: stateConfig.presentation || ({})
  readonly property var barPresentation: {
    const source = rawBarPresentation
    const effective = {}
    for (const key in source) effective[key] = source[key]
    const profileBorder = v2LayoutActive ? source.v2Border : source.v1Border
    effective.border = profileBorder === undefined
      ? source.border !== false : profileBorder !== false
    if (!v2LayoutActive) effective.panelBorder = effective.border
    return effective
  }
  readonly property var workspaceConfig: stateConfig.workspace || ({})
  readonly property var layoutProtection: stateConfig.layoutProtection
    || ({ v1: false, v2: false })
  readonly property bool v1LayoutProtected: layoutProtection.v1 === true
  readonly property bool v2LayoutProtected: layoutProtection.v2 === true
  readonly property var pluginConfig: stateConfig.plugins || ({})
  readonly property var pluginFavorites: Array.isArray(pluginConfig.favorites)
    ? pluginConfig.favorites : []
  readonly property var launcherConfig: stateConfig.launcher
    || ({ mode: "text", text: "shibumi", icon: "omarchy" })
  readonly property var launcherTextOptions: [
    "shibumi", "omarchy", "hyprland", "arch", "omacom"
  ]
  readonly property var launcherIconOptions: [
    "shibumi", "omarchy", "hyprland", "arch", "grid", "spark", "power",
    "dragon", "mark", "nix", "branch", "rebel"
  ]
  readonly property string barPosition: bar
    ? String(bar.position || "top") : "top"
  readonly property string imagePickerStyle: stateConfig.picker
    ? String(stateConfig.picker.imageStyle || stateConfig.picker.style
      || "tanzaku") : "tanzaku"
  readonly property string mediaPickerStyle: stateConfig.picker
    ? String(stateConfig.picker.mediaStyle || stateConfig.picker.style
      || "tanzaku") : "tanzaku"
  readonly property int reactorMode: stateConfig.reactor
    ? Number(stateConfig.reactor.mode || 0) : 0
  property string activeShell: "shibumi"
  readonly property bool stockOmarchyHost: activeShell === "omarchy"
  readonly property string switchPhase: switchService
    ? String(switchService.phase || "idle") : "idle"
  readonly property string switchTarget: switchService
    ? String(switchService.target || "") : ""
  readonly property string switchDetail: switchService
    ? String(switchService.detail || "") : ""
  readonly property bool switchBusy: switchService
    ? switchService.busy === true : false
  property bool v2LayoutActive: false
  property string lastSwitchTarget: ""
  property string lastQuickSystemAction: ""
  property int reloadCalls: 0
  readonly property var activeWidgetOrder: v2LayoutActive
    ? {
        left: ["G1", "G2", "G3", "G5", "G6", "G4", "G7"],
        center: ["G8"],
        right: [
          "G9", "G10", "G11", "G14", "G12", "G13", "G16",
          "G18", "G17", "G15"
        ]
      }
    : {
        left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
        center: ["G8"],
        right: ["G9", "G10", "G11", "G12", "G13", "G14", "G15"]
      }
  readonly property bool quickNetworkAvailable: true
  readonly property bool quickNetworkEnabled: true
  readonly property string quickNetworkLabel: "Fixture Wi-Fi"
  readonly property string quickNetworkDetail: "connected"
  readonly property bool quickBluetoothAvailable: true
  readonly property bool quickBluetoothEnabled: true
  readonly property string quickBluetoothLabel: "Fixture Phone"
  readonly property string quickBluetoothDetail: "1 connected"
  readonly property bool quickAudioAvailable: true
  readonly property bool quickAudioMuted: false
  readonly property string quickAudioLabel: "On"
  readonly property bool quickBrightnessAvailable: true
  readonly property string quickBrightnessLabel: "75%"
  readonly property string quickBrightnessDetail: "eDP-1"
  readonly property bool quickProfileAvailable: true
  readonly property string quickProfileLabel: "Balanced"
  readonly property bool pluginsScanning: false
  property bool pluginRemovalRunning: false
  readonly property bool pluginUpdateCheckRunning:
    pluginUpdateService.running === true
  readonly property int pluginUpdateCount: pluginUpdateService.updateCount
  readonly property int pluginUpdateFailedCount: pluginUpdateService.failedCount
  readonly property string pluginUpdateCheckError: pluginUpdateService.error
  readonly property string pluginUpdateShortStatusText:
    pluginUpdateService.shortStatusText
  readonly property string pluginUpdateStatusText: pluginUpdateService.statusText
  readonly property var effectivePluginUpdateService: pluginUpdateService
  property bool rejectProviderRestore: false
  readonly property string pluginRemovalId: ""
  signal pluginRemovalFinished(
    string pluginId, bool success, string detail)
  property var pluginEntries: [
    {
      id: "hancore.shibumi.audio",
      name: "Shibumi Audio",
      description: "Volume, microphone, and PipeWire controls",
      author: "HANCORE",
      category: "Audio",
      searchTags: ["audio", "volume", "microphone", "pipewire"],
      kinds: ["bar-widget", "service"],
      glyph: "volume_up",
      provider: "Shibumi",
      removable: false,
      userToggleable: true,
      styleAvailable: true,
      installedInBar: true,
      group: "G6",
      replacementGroup: "",
      replacementTarget: "",
      replacementTargetEnabled: false,
      replacementInEffect: false,
      replacementLabel: "",
      replaced: false,
      replacedBy: "",
      replacedByIds: []
    },
    {
      id: "omarchy.audio",
      name: "Omarchy Audio",
      description: "Built-in Quattro volume widget",
      author: "Omarchy",
      category: "Audio",
      searchTags: ["audio", "volume", "pipewire"],
      kinds: ["bar-widget"],
      glyph: "volume_up",
      provider: "Omarchy Quattro",
      removable: false,
      userToggleable: true,
      styleAvailable: true,
      installedInBar: false,
      group: "",
      replacementGroup: "G6",
      replacementGroups: ["G6"],
      replacementTarget: "Shibumi Audio",
      replacementTargetStates: ({
        G6: { v1: true, v2: false }
      }),
      replacementTargetEnabled: true,
      replacementInEffect: false,
      replacementLabel: "Replaces Shibumi Audio",
      replaced: false,
      replacedBy: "",
      replacedByIds: []
    },
    {
      id: "acme.weather",
      name: "Acme Weather",
      description: "Forecast and temperature widget",
      author: "Acme Labs",
      category: "Weather",
      searchTags: ["weather", "forecast", "temperature"],
      kinds: ["bar-widget"],
      glyph: "cloud",
      provider: "Third-party",
      removable: true,
      userToggleable: true,
      styleAvailable: true,
      installedInBar: false,
      group: "",
      replacementGroup: "",
      replacementTarget: "",
      replacementTargetEnabled: false,
      replacementInEffect: false,
      replacementLabel: "",
      replaced: false,
      replacedBy: "",
      replacedByIds: []
    },
    {
      id: "hancore.shibumi.bluetooth",
      name: "Shibumi Bluetooth",
      description: "Shibumi Bluetooth presentation with a native BlueZ and audio backend",
      author: "HANCORE",
      category: "Connectivity",
      searchTags: ["bluetooth", "bluez", "devices"],
      kinds: ["bar-widget", "service"],
      glyph: "bluetooth",
      provider: "Shibumi",
      removable: false,
      userToggleable: true,
      styleAvailable: true,
      installedInBar: true,
      group: "G15",
      replacementGroup: "",
      replacementTarget: "",
      replacementTargetEnabled: false,
      replacementInEffect: false,
      replacementLabel: "",
      replaced: false,
      replacedBy: "",
      replacedByIds: []
    }
  ]
  readonly property int availablePluginCount: pluginEntries.length
  readonly property int enabledPluginCount: pluginEntries.filter(
    function(entry) { return entry.installedInBar === true }).length
  readonly property int availableWidgetCount: availablePluginCount
  readonly property int enabledWidgetCount: enabledPluginCount
  readonly property int registryShibumiPluginCount: 0
  readonly property int registryOmarchyPluginCount: 0
  readonly property int registryExternalPluginCount: 0
  readonly property bool settingsReady: settings.ready
  readonly property bool settingsFitsWidth: settings.fitsWidth
  readonly property bool settingsPageReady: settings.pageReady
  readonly property string settingsPage: settings.restorePage
  readonly property var settingsPageItem: settings.pageItem
  readonly property real configureDetailPanelChromeHeight:
    settings.configureDetailPanelChromeHeight
  readonly property bool compactBarsPage: settings.compactBarsPage
  readonly property real compactBarsPanelHeight:
    settings.compactBarsPanelHeight
  readonly property real compactIconsPanelHeight:
    settings.compactIconsPanelHeight
  readonly property bool compactIconsSelection:
    settings.compactIconsSelection
  readonly property real compactIconsSelectionPanelHeight:
    settings.compactIconsSelectionPanelHeight
  readonly property bool compactHealthPage: settings.compactHealthPage
  readonly property real compactHealthPanelHeight:
    settings.compactHealthPanelHeight
  readonly property bool compactWorkspacesPage: settings.compactWorkspacesPage
  readonly property real compactWorkspacesPanelHeight:
    settings.compactWorkspacesPanelHeight
  readonly property int headerHealthErrorCount: settings.healthErrorCount
  readonly property var settingsPageOptions: settings.pageOptions
  readonly property bool pluginInstallerOpen: settings.paletteOpen
    && settings.installMode && settings.installerDirect
  readonly property string pluginInstallUrl: settings.installUrl
  readonly property string normalizedPluginInstallUrl:
    settings.normalizedInstallUrl
  readonly property bool validPluginInstallUrl: settings.validInstallUrl
  readonly property bool pluginInstallInputWasCommand:
    settings.installInputWasCommand
  readonly property var settingsSearchSuggestions:
    settings.settingsSearchSuggestions
  readonly property var settingsSearchResults:
    settings.settingsSearchResults
  readonly property color marketBackground: "#08080a"
  readonly property color marketPanel: "#0b0b0d"
  readonly property color marketPanelRaised: "#101012"
  readonly property color marketLine: "#28282c"
  readonly property color marketLineStrong: "#3a3a3f"
  readonly property color marketText: "#d7d7d9"
  readonly property color marketMuted: "#aaaab0"
  readonly property color marketFaint: "#7d7d84"
  readonly property color marketAccent: "#ff5a36"
  readonly property string marketFont: "JetBrainsMono Nerd Font"
  readonly property color renderedSurfaceColor: "#202020"
  readonly property color controlFillColor: "#191919"
  readonly property color controlHoverFillColor: "#252525"
  readonly property color controlPrimaryHoverColor: "#e87070"
  readonly property color controlBorderColor: "#666666"
  readonly property color controlHoverBorderColor: "#888888"
  readonly property color buttonFillColor: "#191919"
  readonly property color buttonHoverFillColor: "#252525"
  readonly property color buttonHoverBorderColor: "#888888"
  readonly property real controlBorderWidth: 1
  readonly property real controlRadius:
    barPresentation.radius === "small" ? 4 : 10
  readonly property color dividerColor: "#555555"

  function syncPopout() {
    if (!bar) return
    if (open && typeof bar.requestPopout === "function")
      bar.requestPopout(ownerWidget)
    else if (!open && typeof bar.releasePopout === "function")
      bar.releasePopout(ownerWidget)
  }

  function focusPredictiveSettingsSearch() {
    return settings.focusPredictiveSettingsSearch()
  }

  function setPredictiveSettingsQuery(value) {
    return settings.setPredictiveSettingsQuery(value)
  }

  function acceptSettingsSearchSuggestion(index) {
    return settings.acceptSettingsSearchSuggestion(index)
  }

  function dismissSettingsSearch() {
    return settings.dismissSettingsSearch()
  }

  function blurPredictiveSettingsSearch() {
    return settings.blurPredictiveSettingsSearch()
  }

  function groupSetting(groupId, key, fallback) {
    return stateService
      && typeof stateService.groupAppearanceSettingForVariant === "function"
      ? stateService.groupAppearanceSettingForVariant(groupId,
          v2LayoutActive ? "v2" : "v1", key, fallback)
      : stateService && typeof stateService.groupSetting === "function"
        ? stateService.groupSetting(groupId, key, fallback) : fallback
  }

  function groupEnabled(groupId) {
    return stateService && typeof stateService.groupEnabledForVariant
      === "function"
      ? stateService.groupEnabledForVariant(groupId,
          v2LayoutActive ? "v2" : "v1")
      : groupSetting(groupId, "enabled", true) !== false
  }

  function setGroupEnabled(groupId, enabled) {
    return stateService && typeof stateService.setGroupEnabledForVariant
      === "function"
      ? stateService.setGroupEnabledForVariant(groupId,
          v2LayoutActive ? "v2" : "v1", enabled === true)
      : setGroupSetting(groupId, "enabled", enabled === true)
  }

  function setGroupSetting(groupId, key, value) {
    return stateService
      && typeof stateService.setGroupAppearanceSettingForVariant === "function"
      ? stateService.setGroupAppearanceSettingForVariant(groupId,
          v2LayoutActive ? "v2" : "v1", key, value)
      : stateService && typeof stateService.setGroupSetting === "function"
        ? stateService.setGroupSetting(groupId, key, value) : false
  }

  function pluginFavorite(pluginId) {
    return pluginFavorites.indexOf(String(pluginId || "")) >= 0
  }

  function setPluginFavorite(pluginId, favorite) {
    return stateService
      && typeof stateService.setPluginFavorite === "function"
      ? stateService.setPluginFavorite(pluginId, favorite) : false
  }

  function resetGroupAppearance(groupId) {
    return stateService
      && typeof stateService.resetGroupAppearanceForVariant === "function"
      ? stateService.resetGroupAppearanceForVariant(groupId,
          v2LayoutActive ? "v2" : "v1")
      : stateService && typeof stateService.resetGroupAppearance === "function"
        ? stateService.resetGroupAppearance(groupId) : false
  }

  function resetAllGroupAppearances(variantValue) {
    const variant = String(variantValue || "").toLowerCase()
    return ["v1", "v2"].indexOf(variant) >= 0
      && stateService
      && typeof stateService.resetAllGroupAppearancesForVariant === "function"
      ? stateService.resetAllGroupAppearancesForVariant(variant) : false
  }

  function setBarPresentation(name, value) {
    const presentationName = String(name || "")
    const preservePanel = [
      "accent", "border", "panelBorder", "frost", "shadow",
      "radius", "shellStyle"
    ].indexOf(presentationName) >= 0
    const preservePage = settings.restorePage
    const restoreBar = bar
    if (preservePanel && restoreBar
        && typeof restoreBar.scheduleWidgetRestore === "function")
      restoreBar.scheduleWidgetRestore(
        "hancore.shibumi.control-center", preservePage,
        presentationName === "shellStyle")
    const changed = stateService
      && typeof stateService.setPresentationSetting === "function"
      ? stateService.setPresentationSetting(name, value) : false
    if (!changed && preservePanel && restoreBar
        && typeof restoreBar.cancelWidgetRestore === "function")
      restoreBar.cancelWidgetRestore("hancore.shibumi.control-center")
    return changed
  }

  function setLayoutProtection(variant, enabled) {
    const requested = String(variant || "").toLowerCase()
    if (["v1", "v2"].indexOf(requested) < 0
        || typeof enabled !== "boolean") return false
    const restoreBar = bar
    const created = restoreBar
      && typeof restoreBar.scheduleOpenControlCenterRestores === "function"
      ? restoreBar.scheduleOpenControlCenterRestores(
          settings.restorePage, false, ownerWidget, "") : []
    const changed = stateService
      && typeof stateService.setLayoutProtection === "function"
      ? stateService.setLayoutProtection(requested, enabled) : false
    if (!changed && restoreBar
        && typeof restoreBar.cancelCreatedWidgetRestores === "function")
      restoreBar.cancelCreatedWidgetRestores(created)
    return changed
  }

  function setBarVariant(target) {
    const requested = String(target || "")
    if (requested !== "v1" && requested !== "v2"
        || !stateService
        || typeof stateService.setShellVariant !== "function") return false
    const preservePage = settings.restorePage
    const restoreBar = bar
    if (restoreBar
        && typeof restoreBar.scheduleWidgetRestore === "function")
      restoreBar.scheduleWidgetRestore(
        "hancore.shibumi.control-center", preservePage, true)
    const changed = stateService.setShellVariant(requested)
    if (!changed && restoreBar
        && typeof restoreBar.cancelWidgetRestore === "function")
      restoreBar.cancelWidgetRestore("hancore.shibumi.control-center")
    return changed
  }

  function setWorkspacePreference(name, value) {
    return stateService
      && typeof stateService.setWorkspacePreference === "function"
      ? stateService.setWorkspacePreference(name, value) : false
  }

  function setPickerStyle(value) {
    return stateService && typeof stateService.setPickerStyle === "function"
      ? stateService.setPickerStyle(value) : false
  }

  function setImagePickerStyle(value) {
    return stateService
      && typeof stateService.setImagePickerStyle === "function"
      ? stateService.setImagePickerStyle(value) : false
  }

  function setMediaPickerStyle(value) {
    return stateService
      && typeof stateService.setMediaPickerStyle === "function"
      ? stateService.setMediaPickerStyle(value) : false
  }

  function setReactorMode(value) {
    return stateService && typeof stateService.setReactorMode === "function"
      ? stateService.setReactorMode(value) : false
  }

  function setBarPosition(value) {
    return bar && typeof bar.setBarPosition === "function"
      ? bar.setBarPosition(value) : false
  }

  function setAllSplits(value) {
    return bar && typeof bar.setAllSplits === "function"
      ? bar.setAllSplits(value) : false
  }

  function resetBarLayout() {
    return bar && typeof bar.resetBarLayout === "function"
      ? bar.resetBarLayout() : false
  }

  function launcherLabel(value) {
    const id = String(value || "")
    if (id === "shibumi") return "Shibumi"
    if (id === "omacom") return "Omacom"
    if (id === "hyprland") return "Hyprland"
    if (id === "arch") return "Arch"
    if (id === "grid") return "Grid"
    if (id === "spark") return "Spark"
    if (id === "power") return "Power"
    if (id === "dragon") return "Dragon"
    if (id === "mark") return "Mark"
    if (id === "nix") return "Nix"
    if (id === "branch") return "Branch"
    if (id === "rebel") return "Rebel"
    return "Omarchy"
  }

  function launcherChoiceLabel(mode) {
    const selectedMode = String(mode || "text")
    const id = selectedMode === "icon"
      ? String(launcherConfig.icon || "omarchy")
      : String(launcherConfig.text || "shibumi")
    return launcherLabel(id)
  }

  function nextLauncherValue(options, current) {
    const index = options.indexOf(String(current || ""))
    return options[(index < 0 ? 0 : index + 1) % options.length]
  }

  function activateLauncherMode(mode) {
    const nextMode = String(mode || "")
    if (!stateService || typeof stateService.setLauncherConfig !== "function"
        || (nextMode !== "text" && nextMode !== "icon")) return false
    const next = JSON.parse(JSON.stringify(launcherConfig))
    if (String(next.mode || "text") === nextMode) {
      if (nextMode === "text")
        next.text = nextLauncherValue(launcherTextOptions, next.text)
      else
        next.icon = nextLauncherValue(launcherIconOptions, next.icon)
    }
    next.mode = nextMode
    return stateService.setLauncherConfig(next)
  }

  function setLauncherSelection(mode, value) {
    if (!stateService || typeof stateService.setLauncherConfig !== "function")
      return false
    const nextMode = String(mode || "")
    const nextValue = String(value || "")
    const options = nextMode === "text"
      ? launcherTextOptions : nextMode === "icon"
        ? launcherIconOptions : []
    if (options.indexOf(nextValue) < 0) return false
    const next = JSON.parse(JSON.stringify(launcherConfig))
    next.mode = nextMode
    next[nextMode] = nextValue
    return stateService.setLauncherConfig(next)
  }

  function switchShell(target) {
    const requested = String(target || "")
    if (["v1", "v2", "omarchy"].indexOf(requested) < 0
        || switchBusy || !switchService.begin(requested)) return false
    lastSwitchTarget = requested
    return true
  }

  function runQuickSystemAction(action) {
    const requested = String(action || "")
    if (stockOmarchyHost
        || ["screensaver", "lock", "reboot", "shutdown"]
          .indexOf(requested) < 0) return false
    lastQuickSystemAction = requested
    return true
  }

  function handleEscape() {
    if (settings.dismissEscapeState()) return true
    ownerWidget.close()
    return true
  }

  function reloadShell() {
    reloadCalls++
    return true
  }
  function runHealthChecks(fetchUpdates) {
    return healthService.runChecks(fetchUpdates === true)
  }

  function accentColor(value) {
    return stateService && typeof stateService.paletteColor === "function"
      ? stateService.paletteColor(value) : bar ? bar.urgent : "#d75f5f"
  }

  function contrastColor(value) {
    return stateService
      && typeof stateService.paletteContrastColor === "function"
      ? stateService.paletteContrastColor(value) : "#111111"
  }

  function showSettingsPage(value) {
    return settings.setPage(value)
  }

  function openWidgetPicker() {
    settings.setPage("plugins")
    return settings.openWidgetPicker()
  }

  function openPluginInstaller() {
    settings.setPage("plugins")
    return settings.openPluginInstaller()
  }

  function extractPluginInstallUrl(value) {
    return settings.extractInstallUrl(value)
  }

  function pluginInstallCommandFor(value) {
    return settings.pluginInstallCommand(value)
  }

  function setPluginInstallInput(value) {
    settings.installUrl = String(value || "")
    settings.installConfirmed = false
    settings.installStatus = ""
    return settings.normalizedInstallUrl
  }

  function normalizePluginInstallInput() {
    return settings.normalizeInstallInput()
  }

  property int pluginUpdaterOpenCount: 0

  function checkPluginUpdates(force) {
    return pluginUpdateService.check(force === true)
  }

  function openPluginUpdater() {
    pluginUpdaterOpenCount++
    return true
  }

  function setPluginEnabled(pluginId, enabled) {
    const id = String(pluginId || "")
    const next = JSON.parse(JSON.stringify(pluginEntries))
    const shibumi = next[0]
    const omarchy = next[1]
    if (id === "omarchy.audio") {
      omarchy.installedInBar = enabled === true
      omarchy.replacementInEffect = enabled === true
      if (enabled === true) {
        shibumi.installedInBar = false
        shibumi.replaced = true
        shibumi.replacedBy = "Omarchy Audio"
        shibumi.replacedByIds = ["omarchy.audio"]
      }
    } else if (id === "hancore.shibumi.audio") {
      shibumi.installedInBar = enabled === true
      if (enabled === true) {
        shibumi.replaced = false
        shibumi.replacedBy = ""
        shibumi.replacedByIds = []
        omarchy.installedInBar = false
        omarchy.replacementInEffect = false
      }
    } else if (id === "hancore.shibumi.memory") {
      return setGroupEnabled("G4", enabled === true)
    } else if (id === "hancore.shibumi.storage") {
      return setGroupEnabled("G18", enabled === true)
    } else {
      return false
    }
    omarchy.replacementTargetEnabled = shibumi.installedInBar === true
    pluginEntries = next
    return true
  }

  function restoreShibumiProviders(groupValues) {
    return !rejectProviderRestore
      && Array.isArray(groupValues)
      && groupValues.length === 1
      && String(groupValues[0] || "") === "G6"
      && setPluginEnabled("hancore.shibumi.audio", true)
  }

  function restoreShibumiProviderStates(stateValues) {
    return !rejectProviderRestore
      && stateValues && stateValues.G6
      && stateValues.G6.v1 === true
      && stateValues.G6.v2 === false
      && setPluginEnabled("hancore.shibumi.audio", true)
  }

  function providerUndoSnapshot(pluginId) {
    return String(pluginId || "") === "omarchy.audio"
      ? { token: "audio-provider-snapshot" } : null
  }

  function restoreProviderUndoSnapshot(snapshotValue) {
    const restoreBar = bar
    if (restoreBar
        && typeof restoreBar.scheduleWidgetRestore === "function")
      restoreBar.scheduleWidgetRestore(
        "hancore.shibumi.control-center", settings.restorePage, true)
    const restored = !rejectProviderRestore && snapshotValue
      && snapshotValue.token === "audio-provider-snapshot"
      && setPluginEnabled("hancore.shibumi.audio", true)
    if (!restored && restoreBar
        && typeof restoreBar.cancelWidgetRestore === "function")
      restoreBar.cancelWidgetRestore("hancore.shibumi.control-center")
    return restored
  }

  function setProviderGroupStates(stateValues) {
    return !rejectProviderRestore && stateValues
      && typeof stateValues === "object"
  }

  function restoreShibumiProvider(groupId) {
    return restoreShibumiProviders([String(groupId || "")])
  }

  function removePlugin(pluginId) {
    const id = String(pluginId || "")
    const remaining = pluginEntries.filter(function(entry) {
      return String(entry.id || "") !== id || entry.removable !== true
    })
    if (remaining.length === pluginEntries.length) return false
    pluginRemovalRunning = true
    pluginEntries = remaining
    pluginRemovalRunning = false
    pluginRemovalFinished(id, true, "Removed by fixture.")
    return true
  }
  function rescanPlugins() { return true }
  function beginBarEditing() { return false }
  function shibumiWidgetGroup(pluginId) {
    const groups = {
      "hancore.shibumi.storage": "G18"
    }
    return String(groups[String(pluginId || "")] || "")
  }

  onOpenChanged: syncPopout()
  Component.onCompleted: syncPopout()
  Component.onDestruction: {
    if (bar && typeof bar.releasePopout === "function")
      bar.releasePopout(ownerWidget)
  }

  Control.ControlSettings {
    id: settings
    width: 720
    height: 500
    controller: root
    foreground: root.bar ? root.bar.foreground : "#eeeeee"
    accent: root.bar ? root.bar.urgent : "#d75f5f"
  }
}
