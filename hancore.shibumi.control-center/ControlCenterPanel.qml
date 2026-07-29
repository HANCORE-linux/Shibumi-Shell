pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui
import "HostIdentity.js" as HostIdentity

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var stateService
  readonly property color marketBackground: "#08080a"
  readonly property color marketPanel: "#0b0b0d"
  readonly property color marketPanelRaised: "#101012"
  readonly property color marketLine: "#28282c"
  readonly property color marketLineStrong: "#3a3a3f"
  readonly property color marketText: "#d7d7d9"
  readonly property color marketMuted: "#aaaab0"
  readonly property color marketFaint: "#7d7d84"
  readonly property color marketAccent: stateService
    ? stateService.selectedColor : "#ff5a36"
  readonly property color marketButtonFill: stateService
    ? stateService.paletteColor("color08") : marketPanel
  readonly property color buttonFillColor: marketButtonFill
  readonly property color buttonHoverFillColor: marketButtonFill
  readonly property color buttonHoverBorderColor: marketMuted
  readonly property string marketFont: "JetBrainsMono Nerd Font"

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
    "omarchy", "hyprland", "arch", "grid", "spark", "power",
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
  readonly property var pluginRegistry: bar && bar.pluginRegistry
    ? bar.pluginRegistry : null
  readonly property int pluginRevision: pluginRegistry
    ? Number(pluginRegistry.registryRevision || 0) : 0
  readonly property bool pluginsScanning: pluginRegistry
    ? pluginRegistry.scanning === true : false
  readonly property var pluginEntries: buildPluginEntries()
  readonly property int availablePluginCount: pluginEntries.length
  readonly property int enabledPluginCount: pluginEntries.filter(
    function(entry) { return entry.enabled }).length
  readonly property int availableWidgetCount: pluginEntries.filter(
    function(entry) { return entry.userToggleable }).length
  readonly property int enabledWidgetCount: pluginEntries.filter(
    function(entry) {
      return entry.userToggleable && entry.installedInBar
    }).length
  readonly property int nativePluginCount: pluginEntries.filter(
    function(entry) { return entry.firstParty }).length
  readonly property int shibumiPluginCount: pluginEntries.filter(
    function(entry) { return entry.compatibility === "Native" }).length + 1
  readonly property int preservedExtraCount: pluginEntries.filter(
    function(entry) {
      return entry.compatibility !== "Native" && entry.enabled
    }).length
  readonly property string managerCommand: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/hancore.shibumi.control-center"
    + "/manager/shibumi-manager"
  readonly property string activeShell: HostIdentity.shellName(bar)
  readonly property bool v2LayoutActive: bar && bar.layoutController
    ? bar.layoutController.v2Mode === true : false
  readonly property var v2LayoutSlots: bar && bar.layoutController
    ? bar.layoutController.v2Slots
    : ({ left: [], center: [], right: [] })
  property string switchPhase: ""
  property string switchDetail: ""
  readonly property bool settingsReady: settings.ready
  readonly property bool settingsFitsWidth: settings.fitsWidth
  readonly property bool settingsPageReady: settings.pageReady
  readonly property string settingsPage: settings.currentPage
  readonly property var settingsPageItem: settings.pageItem

  owner: ownerWidget
  open: ownerWidget.opened && stateService && stateService.ready
  focusTarget: keyCatcher
  centerOnBar: false
  surfaceOverrideEnabled: true
  surfaceColorOverride: marketBackground
  surfaceBorderColorOverride: marketLineStrong
  surfaceBorderWidthOverride: 1
  surfaceRadiusOverride: 0
  controlRadiusOverride: 0
  controlForegroundOverride: marketText
  controlAccentOverride: marketAccent
  controlFillOverride: marketPanel
  controlHoverFillOverride: marketPanelRaised
  controlBorderOverride: marketLine
  controlHoverBorderOverride: marketMuted
  contentWidth: fittedContentWidth(Commons.Style.space(820),
    Commons.Style.space(900))
  contentHeight: fittedContentHeight(
    Commons.Style.space(520), Commons.Style.space(620))

  function switchShell(target) {
    const requested = String(target || "")
    if ((requested !== "shibumi" && requested !== "omarchy")
        || managerCommand === "" || switchPhase === "queued") return false
    switchPhase = "queued"
    switchDetail = ""
    console.info("Shibumi continuity request:", requested)
    Quickshell.execDetached([managerCommand, "request", requested])
    ownerWidget.close()
    return true
  }

  function beginBarEditing() {
    if (!bar || typeof bar.setLayoutEditing !== "function"
        || v2LayoutActive !== true) return false
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
        && groupSetting(group, "enabled", true) !== false
    if (group !== "") return groupSetting(group, "enabled", true) !== false
    return bar && typeof bar.layoutContains === "function"
      ? bar.layoutContains(id) : false
  }

  function buildPluginEntries() {
    void(pluginRevision)
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
      const barWidget = kinds.indexOf("bar-widget") >= 0
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
        version: String(manifest.version || ""),
        kinds: kinds,
        glyph: pluginGlyph(id, kinds),
        enabled: enabled,
        barWidget: barWidget,
        installedInBar: barWidget
          ? widgetInstalled(id) : enabled,
        suiteManaged: suiteManaged,
        userToggleable: barWidget && (!suiteManaged || group !== ""),
        defaultSection: placement,
        compatibility: pluginCompatibility(manifest),
        firstParty: manifest.__isFirstParty === true,
        provider: pluginCompatibility(manifest) === "Native"
          ? "Shibumi" : manifest.__isFirstParty === true
            ? "Omarchy Quattro" : "Third-party",
        replacementLabel: bar
          && typeof bar.widgetReplacementLabel === "function"
          ? bar.widgetReplacementLabel(id) : ""
      })
    }
    return result
  }

  function setPluginEnabled(pluginId, enabled) {
    if (!pluginRegistry
        || typeof pluginRegistry.setEnabled !== "function") return false
    const id = String(pluginId || "")
    const manifest = pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins[id] : null
    const kinds = manifest && Array.isArray(manifest.kinds)
      ? manifest.kinds : []
    if (kinds.indexOf("bar") >= 0) {
      console.warn("Control Center rejected full-bar toggle:", id)
      return false
    }
    const shibumi = manifest && manifest["x-shibumi"]
      ? manifest["x-shibumi"] : ({})
    const suiteManaged = String(shibumi.suiteId || "")
      === "hancore.shibumi"
    if (kinds.indexOf("bar-widget") >= 0) {
      const group = shibumiWidgetGroup(id)
      if (group !== "") {
        if (enabled === true && bar
            && typeof bar.removeWidgetFamilyAlternatives === "function")
          bar.removeWidgetFamilyAlternatives(group)
        return setGroupSetting(group, "enabled", enabled === true)
      }
      if (suiteManaged) {
        console.warn(
          "Control Center rejected suite-internal plugin toggle:", id)
        return false
      }
      const section = manifest.barWidget
        && ["left", "center", "right"].indexOf(
          String(manifest.barWidget.defaultSection || "")) >= 0
        ? String(manifest.barWidget.defaultSection) : "center"
      return bar && typeof bar.setBarWidgetInstalled === "function"
        ? bar.setBarWidgetInstalled(id, enabled === true, section) : false
    }
    if (suiteManaged) {
      console.warn(
        "Control Center rejected suite-internal plugin toggle:", id)
      return false
    }
    return pluginRegistry.setEnabled(id, enabled === true)
  }

  function rescanPlugins() {
    if (!pluginRegistry
        || typeof pluginRegistry.rescan !== "function") return false
    pluginRegistry.rescan()
    return true
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
    // This controller exists only while its owning Control Center is loaded.
    // A shell-style mutation may synchronously rebuild that owner, so enqueue
    // the restore before touching state instead of consulting a binding that
    // can disappear during the mutation.
    const preservePanel = String(name || "") === "shellStyle"
    const preservePage = settings.currentPage
    const restoreBar = bar
    if (preservePanel && restoreBar
        && typeof restoreBar.scheduleWidgetRestore === "function")
      restoreBar.scheduleWidgetRestore(
        "hancore.shibumi.control-center", preservePage)
    const changed = stateService
      && typeof stateService.setPresentationSetting === "function"
      ? stateService.setPresentationSetting(name, value) : false
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

  function addV2Slot(region) {
    return bar && typeof bar.addV2Slot === "function"
      ? bar.addV2Slot(region) : false
  }

  function removeV2Slot(region) {
    return bar && typeof bar.removeV2Slot === "function"
      ? bar.removeV2Slot(region) : false
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
    if (!stateService || typeof stateService.setMenuConfig !== "function")
      return false

    const nextMode = String(mode || "")
    if (nextMode !== "text" && nextMode !== "icon") return false
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

  function reloadShell() {
    ownerWidget.close()
    Quickshell.reload(false)
    return true
  }

  function runSystemAction(action) {
    const commands = {
      lock: ["omarchy-system-lock"],
      suspend: ["systemctl", "suspend"],
      reboot: ["omarchy-system-reboot"],
      shutdown: ["omarchy-system-shutdown"]
    }
    const command = commands[String(action || "")]
    if (!command) return false
    ownerWidget.close()
    Quickshell.execDetached(command)
    return true
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

  function openWidgetPicker() {
    settings.setPage("plugins")
    return settings.openWidgetPicker()
  }

  onOpenChanged: {
    if (!open) {
      settings.closeWidgetPicker()
      settings.setPage("bars")
    }
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }

    Column {
      anchors.fill: parent
      spacing: Commons.Style.spacing.sm

      Row {
        width: parent.width
        height: Commons.Style.space(28)
        spacing: Commons.Style.space(4)

        Text {
          width: parent.width - stateSync.width - closeAction.width
            - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          text: "SHIBUMI  /  CONTROL CENTER  /  "
            + (settings.currentPage === "bars" ? "BARS"
              : settings.currentPage === "plugins" ? "WIDGETS"
              : settings.currentPage === "functions" ? "APPEARANCE"
              : settings.currentPage === "splits" ? "LAYOUT"
              : settings.currentPage === "preferences" ? "ADVANCED"
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

        Text {
          id: stateSync
          anchors.verticalCenter: parent.verticalCenter
          text: "●  STATE SYNCED"
          color: panel.marketAccent
          font.family: panel.bar
            ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption
          font.letterSpacing: 1.1
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
        width: parent.width
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

        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: -Commons.Style.space(2)
          width: 1
          height: Math.max(Commons.Style.space(18),
            settingsViewport.height * settingsFlick.visibleArea.heightRatio)
          y: Math.max(0, Math.min(settingsViewport.height - height,
            settingsFlick.visibleArea.yPosition * settingsViewport.height))
          visible: settingsFlick.visibleArea.heightRatio < 0.999
          color: panel.dividerColor
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
    radius: 0
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
