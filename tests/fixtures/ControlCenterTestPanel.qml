pragma ComponentBehavior: Bound

import QtQuick
import "../control" as Control

Item {
  id: root

  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var stateService

  readonly property bool open: ownerWidget.opened
  readonly property var stateConfig: stateService && stateService.config
    ? stateService.config : ({})
  readonly property var barPresentation: stateConfig.presentation || ({})
  readonly property var workspaceConfig: stateConfig.workspace || ({})
  readonly property var menuConfig: stateConfig.menu || ({})
  readonly property var launcherConfig: menuConfig.launcher
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
  readonly property bool stockOmarchyHost: false
  readonly property string activeShell: "shibumi"
  property bool v2LayoutActive: false
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
  readonly property var pluginEntries: []
  readonly property int availablePluginCount: 0
  readonly property int enabledPluginCount: 0
  readonly property int availableWidgetCount: 0
  readonly property int enabledWidgetCount: 0
  readonly property int registryShibumiPluginCount: 0
  readonly property int registryOmarchyPluginCount: 0
  readonly property int registryExternalPluginCount: 0
  readonly property bool settingsReady: settings.ready
  readonly property bool settingsFitsWidth: settings.fitsWidth
  readonly property bool settingsPageReady: settings.pageReady
  readonly property string settingsPage: settings.restorePage
  readonly property var settingsPageItem: settings.pageItem
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

  function groupSetting(groupId, key, fallback) {
    return stateService && typeof stateService.groupSetting === "function"
      ? stateService.groupSetting(groupId, key, fallback) : fallback
  }

  function setGroupSetting(groupId, key, value) {
    return stateService && typeof stateService.setGroupSetting === "function"
      ? stateService.setGroupSetting(groupId, key, value) : false
  }

  function resetGroupAppearance(groupId) {
    return stateService
      && typeof stateService.resetGroupAppearance === "function"
      ? stateService.resetGroupAppearance(groupId) : false
  }

  function setBarPresentation(name, value) {
    const preservePanel = String(name || "") === "shellStyle"
    const preservePage = settings.restorePage
    const restoreBar = bar
    if (preservePanel && restoreBar
        && typeof restoreBar.scheduleWidgetRestore === "function")
      restoreBar.scheduleWidgetRestore(
        "hancore.shibumi.control-center", preservePage)
    return stateService
      && typeof stateService.setPresentationSetting === "function"
      ? stateService.setPresentationSetting(name, value) : false
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
    if (!stateService || typeof stateService.setMenuConfig !== "function"
        || (nextMode !== "text" && nextMode !== "icon")) return false
    const next = JSON.parse(JSON.stringify(menuConfig))
    if (!next.launcher) next.launcher = {
      mode: "text", text: "shibumi", icon: "omarchy"
    }
    if (String(next.launcher.mode || "text") === nextMode) {
      if (nextMode === "text")
        next.launcher.text = nextLauncherValue(
          launcherTextOptions, next.launcher.text)
      else
        next.launcher.icon = nextLauncherValue(
          launcherIconOptions, next.launcher.icon)
    }
    next.launcher.mode = nextMode
    return stateService.setMenuConfig(next)
  }

  function reloadShell() { return true }
  function runSystemAction(action) {
    return ["lock", "suspend", "reboot", "shutdown"]
      .indexOf(String(action || "")) >= 0
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

  function editWidget(groupId, pluginId) {
    return settings.editWidget(groupId, pluginId)
  }

  function openWidgetPicker() {
    settings.setPage("plugins")
    return settings.openWidgetPicker()
  }

  function setPluginEnabled(_pluginId, _enabled) { return false }
  function rescanPlugins() { return true }
  function beginBarEditing() { return false }
  function quickWidgetAvailable(_pluginId) { return true }
  function quickWidgetVisible(_pluginId) { return true }
  function toggleQuickWidget(_pluginId) { return true }
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
