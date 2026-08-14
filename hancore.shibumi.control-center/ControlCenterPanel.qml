pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui as Ui
import "HostIdentity.js" as HostIdentity

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var stateService
  required property var healthService
  required property var switchService
  property var pluginUpdateService: null
  // Compatibility aliases for the Control Center views. Their provenance is
  // the active host's VisualTokens, which ultimately follow colors.toml.
  readonly property color marketBackground: shibumiTokens
    ? shibumiTokens.panelBackground : Commons.Color.popups.background
  readonly property color marketPanel: marketBackground
  readonly property color marketPanelRaised: shibumiTokens
    && shibumiTokens.fillHover !== undefined
    ? shibumiTokens.fillHover : Commons.Util.alpha(marketAccent, 0.10)
  readonly property color marketLine: shibumiTokens
    && shibumiTokens.separator !== undefined
    ? shibumiTokens.separator : Commons.Color.popups.border
  readonly property color marketLineStrong: shibumiTokens
    ? shibumiTokens.panelBorder : Commons.Color.popups.border
  readonly property color marketText: shibumiTokens
    ? shibumiTokens.ink : Commons.Color.popups.text
  readonly property color marketMuted: shibumiTokens
    && shibumiTokens.sumiHi !== undefined
    ? shibumiTokens.sumiHi : Commons.Color.muted
  readonly property color marketFaint: shibumiTokens
    && shibumiTokens.sumi !== undefined
    ? shibumiTokens.sumi : Commons.Color.muted
  readonly property color marketAccent: shibumiTokens
    ? shibumiTokens.seal : stateService
      ? stateService.selectedColor : Commons.Color.accent
  readonly property color buttonFillColor: controlFillColor
  readonly property color buttonHoverFillColor: controlHoverFillColor
  readonly property color buttonHoverBorderColor: controlHoverBorderColor
  readonly property string marketFont: shibumiTokens
    ? shibumiTokens.fontFamily : Commons.Style.font.family

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
      || "omarchy") : "omarchy"
  readonly property string mediaPickerStyle: stateConfig.picker
    ? String(stateConfig.picker.mediaStyle || stateConfig.picker.style
      || "carousel") : "carousel"
  readonly property int reactorMode: stateConfig.reactor
    ? Number(stateConfig.reactor.mode || 0) : 0
  readonly property var pluginRegistry: bar && "pluginRegistry" in bar
    && bar.pluginRegistry ? bar.pluginRegistry
    : bar && bar.shell && "pluginRegistry" in bar.shell
      ? bar.shell.pluginRegistry : null
  readonly property int pluginRevision: pluginRegistry
    ? Number(pluginRegistry.registryRevision || 0) : 0
  readonly property bool pluginsScanning: pluginRegistry
    ? pluginRegistry.scanning === true : false
  readonly property var pluginEntries: buildPluginEntries()
  readonly property int availablePluginCount: pluginEntries.length
  readonly property int enabledPluginCount: pluginEntries.filter(
    function(entry) { return entry.enabled }).length
  readonly property int availableWidgetCount: pluginEntries.filter(
    function(entry) {
      return entry.userToggleable && entry.styleAvailable
    }).length
  readonly property int enabledWidgetCount: pluginEntries.filter(
    function(entry) {
      return entry.userToggleable && entry.styleAvailable
        && entry.installedInBar
    }).length
  readonly property int nativePluginCount: pluginEntries.filter(
    function(entry) { return entry.firstParty }).length
  readonly property int shibumiPluginCount: pluginEntries.filter(
    function(entry) { return entry.compatibility === "Native" }).length + 1
  readonly property int registryShibumiPluginCount: pluginEntries.filter(
    function(entry) { return entry.suiteManaged }).length
  readonly property int registryOmarchyPluginCount: pluginEntries.filter(
    function(entry) { return entry.firstParty }).length
  readonly property int registryExternalPluginCount: pluginEntries.filter(
    function(entry) {
      return !entry.suiteManaged && !entry.firstParty
    }).length
  readonly property int preservedExtraCount: pluginEntries.filter(
    function(entry) {
      return entry.compatibility !== "Native" && entry.enabled
    }).length
  readonly property bool pluginRemovalRunning: pluginRemoval.running
  readonly property bool pluginUpdateCheckRunning:
    effectivePluginUpdateService
      ? effectivePluginUpdateService.running === true : false
  readonly property int pluginUpdateCount: effectivePluginUpdateService
    ? Number(effectivePluginUpdateService.updateCount || 0) : 0
  readonly property int pluginUpdateFailedCount: effectivePluginUpdateService
    ? Number(effectivePluginUpdateService.failedCount || 0) : 0
  readonly property string pluginUpdateCheckError: effectivePluginUpdateService
    ? String(effectivePluginUpdateService.error || "") : ""
  readonly property string pluginUpdateShortStatusText:
    effectivePluginUpdateService
      ? String(effectivePluginUpdateService.shortStatusText || "") : ""
  readonly property string pluginUpdateStatusText: effectivePluginUpdateService
    ? String(effectivePluginUpdateService.statusText || "")
    : "Plugin update check unavailable"
  readonly property string pluginRemovalId: removalPluginId
  property string removalPluginId: ""
  property bool removalPluginWasInBar: false
  property var removalReplacementGroups: []
  property string pluginActionError: ""
  signal pluginRemovalFinished(
    string pluginId, bool success, string detail)
  readonly property string managerCommand: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/hancore.shibumi.control-center"
    + "/manager/shibumi-manager"
  readonly property var effectivePluginUpdateService: pluginUpdateService
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("hancore.shibumi.control-center") : null)
  readonly property string pluginUpdateCommand: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/hancore.shibumi.control-center"
    + "/manager/shibumi-plugin-updates"
  readonly property string activeShell: HostIdentity.shellName(bar)
  readonly property bool stockOmarchyHost: activeShell === "omarchy"
  readonly property bool v2LayoutActive: bar && bar.layoutController
    ? bar.layoutController.v2Mode === true : false
  readonly property var activeWidgetOrder: bar && bar.layoutController
    && bar.layoutController.order
    ? bar.layoutController.order : ({ left: [], center: [], right: [] })
  readonly property var v1LayoutSlots: bar && bar.layoutController
    ? bar.layoutController.v1Slots
    : ({ left: [], center: [], right: [] })
  readonly property var networkService: shellService(
    "hancore.shibumi.network")
  readonly property var bluetoothService: shellService(
    "hancore.shibumi.bluetooth")
  readonly property var audioService: shellService(
    "hancore.shibumi.audio")
  readonly property var brightnessService: shellService(
    "hancore.shibumi.brightness")
  readonly property var powerService: shellService(
    "hancore.shibumi.power-state")
  readonly property bool quickNetworkAvailable: networkService
    && networkService.wifiAvailable === true
  readonly property bool quickNetworkEnabled: networkService
    && networkService.wifiEnabled === true
  readonly property string quickNetworkLabel: networkService
    ? String(networkService.label || (quickNetworkEnabled ? "Wi-Fi" : "Off"))
    : "Unavailable"
  readonly property string quickNetworkDetail: !quickNetworkAvailable
    ? "no adapter" : quickNetworkEnabled
      ? String(networkService.kind || "") === "disconnected"
        ? "not connected" : "connected"
      : "off"
  readonly property bool quickBluetoothAvailable: bluetoothService
    && bluetoothService.adapterAvailable === true
  readonly property bool quickBluetoothEnabled: bluetoothService
    && bluetoothService.radioEnabled === true
  readonly property string quickBluetoothLabel: !quickBluetoothAvailable
    ? "Unavailable" : quickBluetoothEnabled
      ? (Number(bluetoothService.connectedCount || 0) > 0
        ? bluetoothService.deviceLabel(
          bluetoothService.connectedDevices[0]) : "On")
      : "Off"
  readonly property string quickBluetoothDetail: quickBluetoothAvailable
    ? Number(bluetoothService.connectedCount || 0) + " connected"
    : "no adapter"
  readonly property bool quickAudioAvailable: audioService
    && audioService.ready === true
  readonly property bool quickAudioMuted: audioService
    && audioService.outputMuted === true
  readonly property string quickAudioLabel: !quickAudioAvailable
    ? "Unavailable" : quickAudioMuted ? "Muted" : "On"
  readonly property bool quickBrightnessAvailable: brightnessService
    && brightnessService.brightnessAvailable === true
  readonly property string quickBrightnessLabel: quickBrightnessAvailable
    ? Math.round(Number(brightnessService.brightnessPercent || 0)) + "%"
    : "Unavailable"
  readonly property string quickBrightnessDetail: quickBrightnessAvailable
    ? String(brightnessService.internalMonitor || "display") : "no backlight"
  readonly property bool quickProfileAvailable: powerService
    && powerService.profileAvailable === true
  readonly property string quickProfileLabel: quickProfileAvailable
    ? String(powerService.activeProfileLabel || "Ready") : "Unavailable"
  readonly property string switchPhase: switchService
    ? String(switchService.phase || "idle") : "idle"
  readonly property string switchTarget: switchService
    ? String(switchService.target || "") : ""
  readonly property string switchDetail: switchService
    ? String(switchService.detail || "") : ""
  readonly property bool switchBusy: switchService
    ? switchService.busy === true : false
  readonly property real returnOnlyQuickPanelHeight:
    Commons.Style.space(28) + Commons.Style.spacing.sm * 2
      + Commons.Style.space(1) + Commons.Style.space(130)
      + Commons.Style.space(12)
      + (switchPhase === "error"
        ? Commons.Style.space(10) + Commons.Style.space(42) : 0)
  readonly property bool settingsReady: settings.ready
  readonly property bool settingsFitsWidth: settings.fitsWidth
  readonly property bool settingsPageReady: settings.pageReady
  readonly property string settingsPage: settings.restorePage
  readonly property var settingsPageItem: settings.pageItem
  readonly property int headerHealthErrorCount: settings.healthErrorCount
  readonly property var settingsPageOptions: settings.pageOptions
  readonly property var healthReport: healthService.report
  readonly property bool healthRunning: healthService.running
  readonly property bool healthFetching: healthService.fetching
  readonly property string healthFailure: healthService.failure

  owner: ownerWidget
  open: ownerWidget.opened && stateService && stateService.ready
  focusTarget: keyCatcher
  centerOnBar: false
  surfaceOverrideEnabled: false
  contentWidth: fittedContentWidth(Commons.Style.space(820),
    Commons.Style.space(900))
  contentHeight: settings.currentPage === "quick"
    ? settings.returnOnly
      ? fittedContentHeight(returnOnlyQuickPanelHeight,
          Commons.Style.space(260))
      : fittedContentHeight(Commons.Style.space(
          switchPhase === "error" ? 488 : 436), Commons.Style.space(495))
    : settings.compactConfigureLanding
      ? fittedContentHeight(settings.compactConfigureLandingPanelHeight,
          Commons.Style.space(680))
    : settings.compactBarsPage
      ? fittedContentHeight(settings.compactBarsPanelHeight,
          Commons.Style.space(680))
    : settings.compactIconsOverview
      ? fittedContentHeight(settings.compactIconsPanelHeight,
          Commons.Style.space(680))
    : settings.compactIconsSelection
      ? fittedContentHeight(settings.compactIconsSelectionPanelHeight,
          Commons.Style.space(680))
    : settings.compactHealthPage
      ? fittedContentHeight(settings.compactHealthPanelHeight,
          Commons.Style.space(680))
    : settings.compactPickersPage
      ? fittedContentHeight(settings.compactPickersPanelHeight,
          Commons.Style.space(680))
    : settings.compactWorkspacesPage
      ? fittedContentHeight(settings.compactWorkspacesPanelHeight,
          Commons.Style.space(680))
    : settings.compactLogoPage
      ? fittedContentHeight(settings.compactLogoPanelHeight,
          Commons.Style.space(680))
    : settings.compactPluginsPage
      ? fittedContentHeight(settings.compactPluginsPanelHeight,
          Commons.Style.space(680))
    : fittedContentHeight(Commons.Style.space(610),
        Commons.Style.space(680))

  function switchShell(target) {
    let requested = String(target || "")
    if (requested === "shibumi")
      requested = v2LayoutActive ? "v2" : "v1"
    if (["v1", "v2", "omarchy"].indexOf(requested) < 0
        || managerCommand === "" || switchBusy
        || !switchService.begin(requested)) return false
    console.info("Shibumi continuity request:", requested)
    Quickshell.execDetached([managerCommand, "request", requested])
    ownerWidget.close()
    return true
  }

  function shellService(pluginId) {
    return bar && bar.shell
      && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor(String(pluginId || "")) : null
  }

  function beginBarEditing() {
    if (!bar || typeof bar.setLayoutEditing !== "function"
        || stockOmarchyHost) return false
    const changed = bar.setLayoutEditing(true, "")
    if (changed) ownerWidget.close()
    return changed
  }

  function pluginGlyph(pluginId, kinds) {
    const id = String(pluginId || "").toLowerCase()
    const semanticGlyphs = [
      { terms: ["control-center", ".menu"], glyph: "tune" },
      { terms: ["active-window"], glyph: "web_asset" },
      { terms: [".clock"], glyph: "schedule" },
      { terms: [".monitor", "display", "brightness"], glyph: "monitor" },
      { terms: ["dropbox"], glyph: "cloud" },
      { terms: ["indicator", "status", "tray"], glyph: "toggle_on" },
      { terms: ["keyboard"], glyph: "keyboard" },
      { terms: ["media"], glyph: "music_note" },
      { terms: ["microphone"], glyph: "mic" },
      { terms: ["model-usage", ".ai"], glyph: "neurology" },
      { terms: ["network", "tailscale"], glyph: "wifi" },
      { terms: ["audio"], glyph: "volume_up" },
      { terms: ["bluetooth"], glyph: "bluetooth" },
      { terms: ["battery"], glyph: "battery_5_bar" },
      { terms: ["power-profile", ".power"], glyph: "speed" },
      { terms: ["memory"], glyph: "memory" },
      { terms: ["temperature", "thermal"], glyph: "device_thermostat" },
      { terms: [".gpu"], glyph: "memory_alt" },
      { terms: ["storage"], glyph: "hard_drive" },
      { terms: [".cpu"], glyph: "developer_board" },
      { terms: ["quick-access"], glyph: "bolt" },
      { terms: ["workspace"], glyph: "grid_view" },
      { terms: ["weather"], glyph: "partly_cloudy_day" },
      { terms: ["update"], glyph: "system_update_alt" }
    ]
    for (let index = 0; index < semanticGlyphs.length; index++) {
      const match = semanticGlyphs[index]
      for (let termIndex = 0; termIndex < match.terms.length; termIndex++) {
        if (id.indexOf(match.terms[termIndex]) >= 0) return match.glyph
      }
    }
    const values = Array.isArray(kinds) ? kinds : []
    if (values.indexOf("bar-widget") >= 0) return "widgets"
    if (values.indexOf("service") >= 0) return "settings_input_component"
    if (values.indexOf("panel") >= 0) return "dashboard"
    return "extension"
  }

  function pluginCompatibility(manifest) {
    const shibumi = manifest && manifest["x-shibumi"]
      ? manifest["x-shibumi"] : null
    if (shibumi && String(shibumi.suiteId || "") === "hancore.shibumi")
      return "Native"
    const kinds = manifest && Array.isArray(manifest.kinds)
      ? manifest.kinds : []
    return kinds.indexOf("bar-widget") >= 0 ? "Adaptive" : "Original"
  }

  function shibumiWidgetGroup(pluginId) {
    const groups = {
      "hancore.shibumi.control-center": "G1",
      "hancore.shibumi.workspaces": "G2",
      "hancore.shibumi.status": "G3",
      "hancore.shibumi.memory": "G4",
      "hancore.shibumi.cpu": "G5",
      "hancore.shibumi.audio": "G6",
      "hancore.shibumi.ai": "G7",
      "hancore.shibumi.center": "G8",
      "hancore.shibumi.media": "G9",
      "hancore.shibumi.quick-access": "G10",
      "hancore.shibumi.network": "G11",
      "hancore.shibumi.battery": "G12",
      "hancore.shibumi.brightness": "G13",
      "hancore.shibumi.power-profile": "G14",
      "hancore.shibumi.bluetooth": "G15",
      "hancore.shibumi.temperature": "G16",
      "hancore.shibumi.gpu": "G17",
      "hancore.shibumi.storage": "G18"
    }
    return String(groups[String(pluginId || "")] || "")
  }

  function widgetInstalled(pluginId) {
    const id = String(pluginId || "")
    const group = shibumiWidgetGroup(id)
    if (["G16", "G17", "G18"].indexOf(group) >= 0)
      return v2LayoutActive
        ? groupEnabled(group)
        : bar && typeof bar.layoutContains === "function"
          ? bar.layoutContains(id) : false
    if (group !== "") return groupEnabled(group)
    return bar && typeof bar.layoutContains === "function"
      ? bar.layoutContains(id) : false
  }

  function buildPluginEntries() {
    void(pluginRevision)
    void(v2LayoutActive)
    if (bar) void(bar.layoutConfig)
    void(stateConfig.widgets)
    const registry = pluginRegistry
    const installed = registry && registry.installedPlugins
      ? registry.installedPlugins : ({})
    const result = []
    const ids = Object.keys(installed).sort(function(left, right) {
      const leftName = String(installed[left].name || left).toLowerCase()
      const rightName = String(installed[right].name || right).toLowerCase()
      return leftName.localeCompare(rightName)
    })
    for (let index = 0; index < ids.length; index++) {
      const id = ids[index]
      const manifest = installed[id] || ({})
      const kinds = Array.isArray(manifest.kinds) ? manifest.kinds : []
      const shibumi = manifest["x-shibumi"] || ({})
      const suiteManaged = String(shibumi.suiteId || "")
        === "hancore.shibumi"
      const group = shibumiWidgetGroup(id)
      const replacementGroups = group === "" && bar
        && typeof bar.widgetReplacementGroups === "function"
        ? bar.widgetReplacementGroups(id)
        : group === "" && bar
          && typeof bar.widgetReplacementGroup === "function"
          ? [bar.widgetReplacementGroup(id)].filter(function(value) {
              return String(value || "") !== ""
            }) : []
      const replacementGroup = replacementGroups.length > 0
        ? String(replacementGroups[0] || "") : ""
      const replacementTargetId = group === "" && bar
        && typeof bar.widgetReplacementTarget === "function"
        ? bar.widgetReplacementTarget(id) : ""
      const replacementTargetStates = groupVariantStates(replacementGroups)
      const conflictingProviderIds = group === "" && bar
        && typeof bar.conflictingLayoutProviderIds === "function"
        ? bar.conflictingLayoutProviderIds(id).filter(function(candidateId) {
            return String(candidateId || "") !== id
          }) : []
      const conflictingProviderGroups = group === "" && bar
        && typeof bar.conflictingLayoutProviderGroups === "function"
        ? bar.conflictingLayoutProviderGroups(id) : []
      const conflictingProviderStates = groupVariantStates(
        replacementGroups.concat(conflictingProviderGroups))
      const replacementTargetManifest =
        installed[String(replacementTargetId || "")] || ({})
      const replacementTarget = replacementTargetId !== ""
        ? String(replacementTargetManifest.name || replacementTargetId) : ""
      const barWidget = kinds.indexOf("bar-widget") >= 0
      const barWidgetMeta = manifest.barWidget || ({})
      const category = String(barWidgetMeta.category || "")
      const searchTags = []
      const declaredTags = (Array.isArray(manifest.tags)
        ? manifest.tags : []).concat(
          Array.isArray(shibumi.capabilities) ? shibumi.capabilities : [])
        .concat(Array.isArray(barWidgetMeta.semanticCapabilities)
          ? barWidgetMeta.semanticCapabilities : [])
        .concat(kinds)
        .concat(category !== "" ? [category] : [])
      for (let tagIndex = 0; tagIndex < declaredTags.length; tagIndex++) {
        const tag = String(declaredTags[tagIndex] || "").trim()
        if (tag !== "" && searchTags.indexOf(tag) < 0) searchTags.push(tag)
      }
      const placement = manifest.barWidget
        && ["left", "center", "right"].indexOf(
          String(manifest.barWidget.defaultSection || "")) >= 0
        ? String(manifest.barWidget.defaultSection) : "center"
      // A full bar is a mutually exclusive shell host, not a widget/plugin
      // toggle. It must only be changed through a dedicated bar selector.
      if (kinds.indexOf("bar") >= 0) continue
      const enabled = registry
        && typeof registry.isEnabled === "function"
        ? registry.isEnabled(id) : false
      result.push({
        id: id,
        name: String(manifest.name || id),
        description: [
          String(manifest.description || ""),
          String(barWidgetMeta.description || "")
        ].filter(function(value) { return value !== "" }).join(" "),
        author: String(manifest.author || ""),
        category: category,
        searchTags: searchTags,
        version: String(manifest.version || ""),
        kinds: kinds,
        glyph: pluginGlyph(id, kinds),
        enabled: enabled,
        barWidget: barWidget,
        installedInBar: barWidget
          ? widgetInstalled(id) : enabled,
        styleAvailable: true,
        suiteManaged: suiteManaged,
        userToggleable: barWidget && (!suiteManaged || group !== ""),
        defaultSection: placement,
        compatibility: pluginCompatibility(manifest),
        firstParty: manifest.__isFirstParty === true,
        removable: manifest.__isFirstParty !== true && !suiteManaged,
        provider: pluginCompatibility(manifest) === "Native"
          ? "Shibumi" : manifest.__isFirstParty === true
            ? "Omarchy Quattro" : "Third-party",
        replacementLabel: group === "" && bar
          && typeof bar.widgetReplacementLabel === "function"
          ? bar.widgetReplacementLabel(id) : "",
        group: group,
        replacementGroup: replacementGroup,
        replacementGroups: replacementGroups,
        replacementTargetId: replacementTargetId,
        replacementTarget: replacementTarget,
        replacementTargetStates: replacementTargetStates,
        conflictingProviderIds: conflictingProviderIds,
        conflictingProviderStates: conflictingProviderStates,
        replacementTargetEnabled: replacementGroups.some(function(groupId) {
          const states = replacementTargetStates[groupId] || ({})
          return states.v1 === true || states.v2 === true
        }),
        replacementInEffect: false,
        replaced: false,
        replacedBy: "",
        replacedByIds: []
      })
    }

    const activeReplacements = {}
    for (let index = 0; index < result.length; index++) {
      const entry = result[index]
      const replacementGroups = Array.isArray(entry.replacementGroups)
        ? entry.replacementGroups : []
      if (replacementGroups.length === 0
          || entry.installedInBar !== true) continue
      for (let groupIndex = 0; groupIndex < replacementGroups.length;
           groupIndex++) {
        const replacementGroup = String(replacementGroups[groupIndex] || "")
        if (replacementGroup === "") continue
        if (!activeReplacements[replacementGroup])
          activeReplacements[replacementGroup] = []
        activeReplacements[replacementGroup].push(entry)
      }
    }
    for (let index = 0; index < result.length; index++) {
      const entry = result[index]
      const group = String(entry.group || "")
      const replacementGroups = Array.isArray(entry.replacementGroups)
        ? entry.replacementGroups : []
      if (replacementGroups.length > 0) {
        const targetStates = entry.replacementTargetStates || ({})
        entry.replacementInEffect = entry.installedInBar === true
          && replacementGroups.every(function(groupId) {
            const states = targetStates[groupId] || ({})
            return states.v1 === false && states.v2 === false
          })
        continue
      }
      const replacements = activeReplacements[group] || []
      if (group === "" || replacements.length === 0
          || entry.installedInBar === true) continue
      entry.replaced = true
      entry.replacedByIds = replacements.map(function(item) {
        return String(item.id || "")
      })
      entry.replacedBy = replacements.length === 1
        ? String(replacements[0].name || replacements[0].id || "")
        : replacements.length + " active alternatives"
    }
    return result
  }

  function setPluginEnabled(pluginId, enabled) {
    pluginActionError = ""
    if (!pluginRegistry
        || typeof pluginRegistry.setEnabled !== "function") {
      pluginActionError = "The plugin registry is not ready."
      return false
    }
    const id = String(pluginId || "")
    const manifest = pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[id] : null
    const kinds = manifest && Array.isArray(manifest.kinds)
      ? manifest.kinds : []
    if (kinds.indexOf("bar") >= 0) {
      console.warn("Control Center rejected full-bar toggle:", id)
      pluginActionError = "Full bars can only be changed from Bars."
      return false
    }
    const shibumi = manifest && manifest["x-shibumi"]
      ? manifest["x-shibumi"] : ({})
    const suiteManaged = String(shibumi.suiteId || "")
      === "hancore.shibumi"
    if (kinds.indexOf("bar-widget") >= 0) {
      const group = shibumiWidgetGroup(id)
      if (group !== "") {
        if (!v2LayoutActive
            && ["G16", "G17", "G18"].indexOf(group) >= 0) {
          const section = manifest.barWidget
            && ["left", "center", "right"].indexOf(
              String(manifest.barWidget.defaultSection || "")) >= 0
            ? String(manifest.barWidget.defaultSection) : "right"
          const changed = setPluginBarWidgetEnabled(
            id, enabled === true, section)
          if (!changed)
            pluginActionError = enabled === true
              ? "V1 has no free extension slot. Remove an active added plugin or free a V1 extension slot under Bars."
              : "The plugin could not be removed from the V1 layout."
          return changed
        }
        const alternativesInstalled = enabled === true && bar
          && typeof bar.widgetFamilyAlternativesInstalled === "function"
          && bar.widgetFamilyAlternativesInstalled(group)
        if (alternativesInstalled
            && typeof bar.restoreWidgetFamilyProviders === "function")
          return bar.restoreWidgetFamilyProviders([group])
        let removedAlternative = false
        if (enabled === true && bar
            && typeof bar.removeWidgetFamilyAlternatives === "function")
          removedAlternative = bar.removeWidgetFamilyAlternatives(group)
        if (removedAlternative && bar
            && typeof bar.setWidgetGroupsEnabledForAllVariants === "function")
          return bar.setWidgetGroupsEnabledForAllVariants([group], true)
        return setGroupEnabled(group, enabled === true)
      }
      if (suiteManaged) {
        console.warn(
          "Control Center rejected suite-internal plugin toggle:", id)
        pluginActionError = "This suite service cannot be placed in the bar."
        return false
      }
      const section = manifest.barWidget
        && ["left", "center", "right"].indexOf(
          String(manifest.barWidget.defaultSection || "")) >= 0
        ? String(manifest.barWidget.defaultSection) : "center"
      const changed = setPluginBarWidgetEnabled(id, enabled === true, section)
      if (!changed)
        pluginActionError = enabled === true
          ? "V1 has no free extension slot. Remove an active added plugin or free a V1 extension slot under Bars."
          : "The plugin could not be removed from the active bar."
      return changed
    }
    if (suiteManaged) {
      console.warn(
        "Control Center rejected suite-internal plugin toggle:", id)
      pluginActionError = "This suite service is managed by Shibumi."
      return false
    }
    return pluginRegistry.setEnabled(id, enabled === true)
  }

  function setPluginBarWidgetEnabled(pluginId, enabled, section) {
    return runWithControlCenterRestore(function() {
      return bar && typeof bar.setBarWidgetInstalled === "function"
        ? bar.setBarWidgetInstalled(
            String(pluginId || ""), enabled === true, String(section || ""))
        : false
    })
  }

  function restoreShibumiProviders(groupValues) {
    if (!Array.isArray(groupValues) || !bar
        || typeof bar.removeWidgetFamilyAlternatives !== "function")
      return false
    const groups = []
    for (let index = 0; index < groupValues.length; index++) {
      const group = String(groupValues[index] || "")
      if (group !== "" && groups.indexOf(group) < 0) groups.push(group)
    }
    if (groups.length === 0) return false
    if (typeof bar.restoreWidgetFamilyProviders === "function")
      return bar.restoreWidgetFamilyProviders(groups)
    for (let index = 0; index < groups.length; index++)
      bar.removeWidgetFamilyAlternatives(groups[index])
    if (typeof bar.setWidgetGroupsEnabledForAllVariants === "function")
      return bar.setWidgetGroupsEnabledForAllVariants(groups, true)
    let restored = true
    for (let index = 0; index < groups.length; index++)
      restored = setGroupEnabled(groups[index], true) && restored
    return restored
  }

  function restoreShibumiProviderStates(stateValues) {
    if (!stateValues || typeof stateValues !== "object" || !bar
        || typeof bar.removeWidgetFamilyAlternatives !== "function")
      return false
    const groups = Object.keys(stateValues)
    if (groups.length === 0) return false
    for (let index = 0; index < groups.length; index++) {
      const states = stateValues[groups[index]]
      if (!states || typeof states.v1 !== "boolean"
          || typeof states.v2 !== "boolean") return false
    }
    if (typeof bar.restoreWidgetFamilyProviderStates === "function")
      return bar.restoreWidgetFamilyProviderStates(stateValues)
    for (let index = 0; index < groups.length; index++)
      bar.removeWidgetFamilyAlternatives(groups[index])
    if (typeof bar.setWidgetGroupVariantStates === "function")
      return bar.setWidgetGroupVariantStates(stateValues)
    return restoreShibumiProviders(groups)
  }

  function providerUndoSnapshot(pluginId) {
    const id = String(pluginId || "")
    if (id === "" || !bar
        || typeof bar.providerLayoutSnapshot !== "function") return null
    const groups = []
    const nativeGroup = shibumiWidgetGroup(id)
    if (nativeGroup !== "") {
      groups.push(nativeGroup)
      if (typeof bar.widgetFamilyAlternativeIds === "function"
          && typeof bar.widgetReplacementGroups === "function") {
        const alternatives = bar.widgetFamilyAlternativeIds([nativeGroup])
        for (let index = 0; index < alternatives.length; index++) {
          const alternativeId = alternatives[index]
          if (typeof bar.layoutContains === "function"
              && !bar.layoutContains(alternativeId)) continue
          const alternativeGroups = bar.widgetReplacementGroups(alternativeId)
          for (let groupIndex = 0;
               groupIndex < alternativeGroups.length; groupIndex++) {
            if (groups.indexOf(alternativeGroups[groupIndex]) < 0)
              groups.push(alternativeGroups[groupIndex])
          }
        }
      }
    } else {
      const replacementGroups = typeof bar.widgetReplacementGroups
        === "function" ? bar.widgetReplacementGroups(id) : []
      const conflictGroups = typeof bar.conflictingLayoutProviderGroups
        === "function" ? bar.conflictingLayoutProviderGroups(id) : []
      const affectedGroups = replacementGroups.concat(conflictGroups)
      for (let index = 0; index < affectedGroups.length; index++) {
        if (groups.indexOf(affectedGroups[index]) < 0)
          groups.push(affectedGroups[index])
      }
    }
    return groups.length > 0 ? bar.providerLayoutSnapshot(groups) : null
  }

  function restoreProviderUndoSnapshot(snapshotValue) {
    if (!snapshotValue || !bar
        || typeof bar.restoreProviderLayoutSnapshot !== "function")
      return false
    return runWithControlCenterRestore(function() {
      return bar.restoreProviderLayoutSnapshot(snapshotValue)
    })
  }

  function setProviderGroupStates(stateValues) {
    return stateValues && typeof stateValues === "object" && bar
      && typeof bar.setWidgetGroupVariantStates === "function"
      ? bar.setWidgetGroupVariantStates(stateValues) : false
  }

  function restoreShibumiProvider(groupId) {
    return restoreShibumiProviders([String(groupId || "")])
  }

  function removePlugin(pluginId) {
    const id = String(pluginId || "")
    if (id === "" || pluginRemoval.running) return false
    let entry = null
    for (let index = 0; index < pluginEntries.length; index++) {
      if (String(pluginEntries[index].id || "") === id) {
        entry = pluginEntries[index]
        break
      }
    }
    if (!entry || entry.removable !== true) {
      console.warn("Control Center rejected non-removable plugin:", id)
      return false
    }
    removalPluginId = id
    removalPluginWasInBar = entry.barWidget === true
      && entry.installedInBar === true
    removalReplacementGroups = removalPluginWasInBar
      && Array.isArray(entry.replacementGroups)
      ? entry.replacementGroups.slice() : []
    pluginRemoval.command = ["omarchy", "plugin", "remove", id, "--yes"]
    pluginRemoval.running = true
    return true
  }

  function rescanPlugins() {
    if (!pluginRegistry
        || typeof pluginRegistry.rescan !== "function") return false
    if (effectivePluginUpdateService)
      effectivePluginUpdateService.invalidate(false)
    pluginRegistry.rescan()
    return true
  }

  function groupSetting(groupId, key, fallback) {
    return stateService
      && typeof stateService.groupAppearanceSettingForVariant === "function"
      ? stateService.groupAppearanceSettingForVariant(groupId,
          v2LayoutActive ? "v2" : "v1", key, fallback)
      : stateService && typeof stateService.groupSetting === "function"
        ? stateService.groupSetting(groupId, key, fallback) : fallback
  }

  function groupEnabledForVariant(groupId, variantValue) {
    const variant = String(variantValue || "").toLowerCase()
    if (["v1", "v2"].indexOf(variant) < 0) return false
    return stateService && typeof stateService.groupEnabledForVariant
      === "function"
      ? stateService.groupEnabledForVariant(groupId, variant)
      : groupSetting(groupId, "enabled", true) !== false
  }

  function groupEnabled(groupId) {
    return groupEnabledForVariant(
      groupId, v2LayoutActive ? "v2" : "v1")
  }

  function groupVariantStates(groupValues) {
    const source = Array.isArray(groupValues) ? groupValues : []
    const states = ({})
    for (let index = 0; index < source.length; index++) {
      const group = String(source[index] || "")
      if (group === "" || Object.prototype.hasOwnProperty.call(states, group))
        continue
      states[group] = {
        v1: groupEnabledForVariant(group, "v1"),
        v2: groupEnabledForVariant(group, "v2")
      }
    }
    return states
  }

  function setGroupEnabled(groupId, enabled) {
    return runWithControlCenterRestore(function() {
      return stateService && typeof stateService.setGroupEnabledForVariant
        === "function"
        ? stateService.setGroupEnabledForVariant(groupId,
            v2LayoutActive ? "v2" : "v1", enabled === true)
        : stateService && typeof stateService.setGroupSetting === "function"
          ? stateService.setGroupSetting(groupId, "enabled", enabled === true)
          : false
    })
  }

  function setGroupSetting(groupId, key, value) {
    return runWithControlCenterRestore(function() {
      return stateService
        && typeof stateService.setGroupAppearanceSettingForVariant
          === "function"
        ? stateService.setGroupAppearanceSettingForVariant(groupId,
            v2LayoutActive ? "v2" : "v1", key, value)
        : stateService && typeof stateService.setGroupSetting === "function"
          ? stateService.setGroupSetting(groupId, key, value) : false
    })
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
    return runWithControlCenterRestore(function() {
      return stateService
        && typeof stateService.resetGroupAppearanceForVariant === "function"
        ? stateService.resetGroupAppearanceForVariant(groupId,
            v2LayoutActive ? "v2" : "v1")
        : stateService
            && typeof stateService.resetGroupAppearance === "function"
          ? stateService.resetGroupAppearance(groupId) : false
    })
  }

  function resetAllGroupAppearances(variantValue) {
    const variant = String(variantValue || "").toLowerCase()
    if (["v1", "v2"].indexOf(variant) < 0) return false
    return runWithControlCenterRestore(function() {
      return stateService
        && typeof stateService.resetAllGroupAppearancesForVariant
          === "function"
        ? stateService.resetAllGroupAppearancesForVariant(variant) : false
    })
  }

  function runWithControlCenterRestore(callback) {
    if (typeof callback !== "function") return false
    const restoreBar = bar
    const created = restoreBar
      && typeof restoreBar.scheduleOpenControlCenterRestores === "function"
      ? restoreBar.scheduleOpenControlCenterRestores(
          settings.restorePage, true, ownerWidget, popoutScreenName) : []
    const changed = callback()
    if (!changed && restoreBar
        && typeof restoreBar.cancelCreatedWidgetRestores === "function")
      restoreBar.cancelCreatedWidgetRestores(created)
    return changed
  }

  function setBarPresentation(name, value) {
    // This controller exists only while its owning Control Center is loaded.
    // A shell-style mutation may synchronously rebuild that owner, so enqueue
    // the restore before touching state instead of consulting a binding that
    // can disappear during the mutation.
    const presentationName = String(name || "")
    const preservePanel = [
      "accent", "border", "panelBorder", "frost", "shadow",
      "radius", "shellStyle"
    ].indexOf(presentationName) >= 0
    const restoreBar = bar
    const created = preservePanel && restoreBar
      && typeof restoreBar.scheduleOpenControlCenterRestores === "function"
      ? restoreBar.scheduleOpenControlCenterRestores(
          settings.restorePage, presentationName === "shellStyle",
          ownerWidget, popoutScreenName) : []
    const changed = stateService
      && typeof stateService.setPresentationSetting === "function"
      ? stateService.setPresentationSetting(name, value) : false
    if (!changed && restoreBar
        && typeof restoreBar.cancelCreatedWidgetRestores === "function")
      restoreBar.cancelCreatedWidgetRestores(created)
    return changed
  }

  function setLayoutProtection(variant, enabled) {
    const requested = String(variant || "").toLowerCase()
    if (["v1", "v2"].indexOf(requested) < 0
        || typeof enabled !== "boolean") return false
    const restoreBar = bar
    // A lock write republishes shell.json. Enroll every open output without
    // downgrading an already-running V1/V2 replacement-owner handoff.
    const created = restoreBar
      && typeof restoreBar.scheduleOpenControlCenterRestores === "function"
      ? restoreBar.scheduleOpenControlCenterRestores(
          settings.restorePage, false, ownerWidget, popoutScreenName) : []
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
    const restoreBar = bar
    const created = restoreBar
      && typeof restoreBar.scheduleOpenControlCenterRestores === "function"
      ? restoreBar.scheduleOpenControlCenterRestores(
          settings.restorePage, true, ownerWidget, popoutScreenName) : []
    const changed = stateService.setShellVariant(requested)
    if (!changed && restoreBar
        && typeof restoreBar.cancelCreatedWidgetRestores === "function")
      restoreBar.cancelCreatedWidgetRestores(created)
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
      ? bar.setBarPosition(value, ownerWidget, popoutScreenName) : false
  }

  function setAllSplits(value) {
    return bar && typeof bar.setAllSplits === "function"
      ? bar.setAllSplits(value) : false
  }

  function resetBarLayout() {
    return bar && typeof bar.resetBarLayout === "function"
      ? bar.resetBarLayout() : false
  }

  function addV1Slot(region) {
    return bar && typeof bar.addV1Slot === "function"
      ? bar.addV1Slot(region) : false
  }

  function removeV1Slot(region) {
    return bar && typeof bar.removeV1Slot === "function"
      ? bar.removeV1Slot(region) : false
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
    if (!stateService || typeof stateService.setLauncherConfig !== "function")
      return false

    const nextMode = String(mode || "")
    if (nextMode !== "text" && nextMode !== "icon") return false
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

  function reloadShell() {
    ownerWidget.close()
    Quickshell.reload(false)
    return true
  }

  function runQuickSystemAction(action) {
    if (stockOmarchyHost) return false
    const commands = {
      screensaver: ["omarchy-launch-screensaver", "force"],
      lock: ["omarchy-system-lock"],
      reboot: ["omarchy-system-reboot"],
      shutdown: ["omarchy-system-shutdown"]
    }
    const requested = String(action || "")
    if (!Object.prototype.hasOwnProperty.call(commands, requested))
      return false
    Quickshell.execDetached(commands[requested])
    ownerWidget.close()
    return true
  }

  function handleEscape() {
    if (settings.dismissEscapeState()) return true
    ownerWidget.close()
    return true
  }

  function runHealthChecks(fetchUpdates) {
    return healthService.runChecks(fetchUpdates === true)
  }

  function accentColor(value) {
    return stateService && typeof stateService.paletteColor === "function"
      ? stateService.paletteColor(value) : Commons.Color.urgent
  }

  function contrastColor(value) {
    return stateService
      && typeof stateService.paletteContrastColor === "function"
      ? stateService.paletteContrastColor(value) : Commons.Color.background
  }

  function showSettingsPage(value) {
    return settings.setPage(value)
  }

  function trackSettingsPage(value) {
    const page = String(value || "")
    if (page !== "functions" && bar
        && typeof bar.clearControlCenterWidgetDetail === "function")
      bar.clearControlCenterWidgetDetail()
    return bar && typeof bar.trackWidgetRestorePage === "function"
      ? bar.trackWidgetRestorePage(
          "hancore.shibumi.control-center", page,
          ownerWidget, popoutScreenName) : false
  }

  function trackWidgetDetails(groupId, pluginId) {
    return bar
        && typeof bar.trackControlCenterWidgetDetail === "function"
      ? bar.trackControlCenterWidgetDetail(groupId, pluginId) : false
  }

  function clearWidgetDetails() {
    return bar
        && typeof bar.clearControlCenterWidgetDetail === "function"
      ? bar.clearControlCenterWidgetDetail() : false
  }

  function restoreWidgetDetails(pageItem) {
    const group = bar
      ? String(bar.controlCenterWidgetDetailGroup || "") : ""
    const plugin = bar
      ? String(bar.controlCenterWidgetDetailPlugin || "") : ""
    return group !== "" && pageItem
        && typeof pageItem.openWidgetDetails === "function"
      ? pageItem.openWidgetDetails(group, plugin) : false
  }

  function openWidgetPicker() {
    settings.setPage("plugins")
    return settings.openWidgetPicker()
  }

  function openPluginInstaller() {
    settings.setPage("plugins")
    return settings.openPluginInstaller()
  }

  function checkPluginUpdates(force) {
    if (stockOmarchyHost || !effectivePluginUpdateService) return false
    return effectivePluginUpdateService.check(force === true)
  }

  function openPluginUpdater() {
    if (stockOmarchyHost || pluginUpdateCheckRunning) return false
    if (effectivePluginUpdateService)
      effectivePluginUpdateService.invalidate(false)
    Quickshell.execDetached([
      "omarchy-launch-floating-terminal-with-presentation",
      pluginUpdateCommand
    ])
    ownerWidget.close()
    return true
  }

  Item {
    width: 0
    height: 0
    visible: false

    Process {
      id: pluginRemoval
      running: false
      stdout: StdioCollector {
        id: removalStdout
        waitForEnd: true
      }
      stderr: StdioCollector {
        id: removalStderr
        waitForEnd: true
      }
      onExited: function(exitCode) {
        const id = panel.removalPluginId
        const output = String(
          removalStderr.text || removalStdout.text || "").trim()
        let detail = output === "" ? ""
          : output.split("\n").slice(-1)[0]
        let success = exitCode === 0
        if (success) {
          let cleanupSucceeded = true
          if (panel.removalPluginWasInBar && panel.bar) {
            if (panel.removalReplacementGroups.length > 0
                && typeof panel.bar.removeBarWidgetAndRestoreFamilies
                  === "function") {
              cleanupSucceeded = panel.bar.removeBarWidgetAndRestoreFamilies(
                id, panel.removalReplacementGroups)
            } else if (typeof panel.bar.setBarWidgetInstalled === "function") {
              cleanupSucceeded = panel.bar.setBarWidgetInstalled(id, false, "")
              if (cleanupSucceeded
                  && panel.removalReplacementGroups.length > 0)
                cleanupSucceeded = panel.restoreShibumiProviders(
                  panel.removalReplacementGroups)
            } else cleanupSucceeded = false
          }
          if (!cleanupSucceeded) {
            success = false
            detail = "Plugin removed, but bar provider cleanup failed."
              + (detail !== "" ? " " + detail : "")
          }
          panel.rescanPlugins()
        }
        panel.pluginRemovalFinished(id, success, detail)
        panel.removalPluginId = ""
        panel.removalPluginWasInBar = false
        panel.removalReplacementGroups = []
      }
    }
  }

  onOpenChanged: {
    if (!open) {
      settings.closeWidgetPicker()
      settings.setPage("quick")
    }
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.handleEscape()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }

    Column {
      anchors.fill: parent
      spacing: Commons.Style.spacing.sm

      Row {
        id: headerBand
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Commons.Style.space(20)
        anchors.rightMargin: Commons.Style.space(20)
        height: Commons.Style.space(28)
        spacing: Commons.Style.space(4)

        Text {
          width: parent.width - stateSync.width - closeAction.width
            - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          text: panel.stockOmarchyHost
            ? "SHIBUMI  /  RETURN TO SHIBUMI"
            : "SHIBUMI  /  CONTROL CENTER  /  "
            + (settings.restorePage === "quick" ? "QUICK"
              : settings.restorePage === "configure" ? "CONFIGURE"
              : settings.restorePage === "bars" ? "BARS"
              : settings.restorePage === "bars-motion" ? "BARS  /  GAP ANIMATIONS"
              : settings.restorePage === "plugins" ? "PLUGINS"
              : settings.restorePage === "workspaces" ? "WORKSPACES"
              : settings.restorePage === "pickers" ? "PICKERS"
              : settings.restorePage === "logo" ? "LOGO"
              : settings.restorePage === "functions" ? "ICONS"
              : settings.restorePage === "health" ? "HEALTH"
              : "OVERVIEW")
          color: panel.marketText
          font.family: panel.marketFont
          font.pixelSize: Commons.Style.font.bodySmall
          font.weight: Font.DemiBold
          font.letterSpacing: 1.1

          MouseArea {
            anchors.fill: parent
            enabled: false
          }
        }

        ActiveBarStatus {
          id: stateSync
          anchors.verticalCenter: parent.verticalCenter
          stockOmarchyHost: panel.stockOmarchyHost
          v2LayoutActive: panel.v2LayoutActive
          stateService: panel.stateService
          neutralColor: panel.marketText
          fontFamily: panel.bar
            ? panel.bar.fontFamily : Commons.Style.font.family
        }

        IconAction {
          id: closeAction
          anchors.verticalCenter: parent.verticalCenter
          icon: "close"
          tooltip: "Close"
          onClicked: panel.ownerWidget.close()
        }
      }

      Rectangle {
        id: headerDivider
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Commons.Style.space(20)
        anchors.rightMargin: Commons.Style.space(20)
        height: 1
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
          panel.bar.foreground.g, panel.bar.foreground.b, 0.18)
          : Commons.Color.popups.border
      }

      Item {
        id: settingsViewport
        width: parent.width
        height: Math.max(1, parent.height - y)
        clip: true

        Flickable {
          id: settingsFlick
          anchors.fill: parent
          contentWidth: width
          contentHeight: settings.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick

          ControlSettings {
            id: settings
            width: parent.width
            height: settingsViewport.height
            controller: panel
            foreground: panel.marketText
            accent: panel.marketAccent
          }
        }

        ThinScrollBar {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.topMargin: Commons.Style.space(4)
          anchors.bottomMargin: Commons.Style.space(4)
          anchors.rightMargin: Commons.Style.space(2)
          flickable: settingsFlick
          foreground: panel.marketText
          accent: panel.marketAccent
        }
      }
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.marketText
    accent: panel.marketAccent

    IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }

}
