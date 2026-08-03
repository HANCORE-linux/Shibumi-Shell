pragma ComponentBehavior: Bound

import QtQuick

// Hosts Quattro's monitor component as the single process-wide state/action
// owner. Shibumi owns only screen-local presentation and forwards mutations.
Item {
  id: root

  required property var bar
  required property Item ownerWidget
  property Component panelComponent: null
  property url panelSource: ""
  property var panelSettings: ({})

  readonly property var panel: panelLoader.item
  readonly property bool ready: panel !== null
  readonly property bool opened: ready && panel.opened === true
  readonly property bool brightnessAvailable: ready
    && panel.brightnessAvailable !== undefined
    ? panel.brightnessAvailable === true : false
  readonly property int brightnessPercent: ready
    && panel.brightnessPercent !== undefined
    ? Math.max(0, Math.min(100, Number(panel.brightnessPercent) || 0)) : 0
  readonly property int displayCount: ready && panel.displays !== undefined
    && Array.isArray(panel.displays) ? panel.displays.length : 0
  readonly property string internalMonitor: ready
    && panel.internalMonitor !== undefined ? String(panel.internalMonitor || "") : ""
  readonly property string externalMonitor: ready
    && panel.externalMonitor !== undefined ? String(panel.externalMonitor || "") : ""
  readonly property string focusedMonitor: ready
    && panel.focusedMonitor !== undefined ? String(panel.focusedMonitor || "") : ""
  readonly property bool internalEnabled: ready
    && panel.internalEnabled !== undefined ? panel.internalEnabled === true : false
  readonly property bool mirrorEnabled: ready
    && panel.mirrorEnabled !== undefined ? panel.mirrorEnabled === true : false
  readonly property string monitorScale: ready
    && panel.monitorScale !== undefined ? String(panel.monitorScale || "") : ""
  readonly property var displays: ready && panel.displays !== undefined
    && Array.isArray(panel.displays) ? panel.displays : []
  readonly property int enabledDisplayCount: ready
    && panel.enabledDisplayCount !== undefined
    ? Math.max(0, Number(panel.enabledDisplayCount) || 0) : 0
  readonly property bool textSizeAvailable: ready
    && Array.isArray(panel.textSizeStops) && panel.textSizeStops.length > 0
    && typeof panel.currentTextIndex === "function"
    && typeof panel.displayedTextPx === "function"
    && typeof panel.setTextSize === "function"
  readonly property var textSizeStops: textSizeAvailable
    ? panel.textSizeStops : []
  readonly property int textSizeIndex: textSizeAvailable
    ? Math.max(0, Math.min(textSizeStops.length - 1,
      Number(panel.currentTextIndex()) || 0)) : 0
  readonly property real textSizePx: textSizeAvailable
    ? Number(panel.displayedTextPx()) || textSizeStops[textSizeIndex] : 0

  function refresh() {
    if (!ready || typeof panel.refresh !== "function") return false
    panel.refresh()
    return true
  }

  function setBrightness(value) {
    if (!ready || !brightnessAvailable
        || typeof panel.setBrightness !== "function") return false
    panel.setBrightness(Math.max(1, Math.min(100, Number(value) || 1)))
    return true
  }

  function previewBrightness(value) {
    if (!ready || !brightnessAvailable) return false
    if (typeof panel.previewBrightness === "function")
      panel.previewBrightness(Math.max(1, Math.min(100, Number(value) || 1)))
    else return setBrightness(value)
    return true
  }

  function setScale(value) {
    if (!ready || typeof panel.setScale !== "function") return false
    panel.setScale(String(value || ""))
    return true
  }

  function setTextSize(value) {
    if (!textSizeAvailable) return false
    const px = Math.round(Number(value) || 0)
    if (textSizeStops.indexOf(px) < 0) return false
    panel.setTextSize(px)
    return true
  }

  function adjustTextSize(delta) {
    if (!textSizeAvailable) return false
    const next = Math.max(0, Math.min(textSizeStops.length - 1,
      textSizeIndex + Math.sign(Number(delta) || 0)))
    return setTextSize(textSizeStops[next])
  }

  function toggleDisplay(name, enabled) {
    if (!ready || !String(name || "")
        || typeof panel.toggleDisplay !== "function") return false
    panel.toggleDisplay(String(name), enabled === true)
    return true
  }

  function normalizeScale(value) {
    if (ready && typeof panel.normalizeScale === "function")
      return String(panel.normalizeScale(value) || "")
    const number = parseFloat(String(value || ""))
    return isFinite(number) ? String(Math.round(number * 100) / 100) : ""
  }

  function brightnessName(value) {
    if (ready && typeof panel.brightnessName === "function")
      return String(panel.brightnessName(value) || "")
    const percent = Math.round(Number(value) || 0)
    if (percent >= 80) return "Bright"
    if (percent >= 45) return "Balanced"
    if (percent >= 20) return "Dim"
    return "Low light"
  }

  function injectPanel() {
    if (!panel) return
    if ("bar" in panel) panel.bar = hostProxy
    if ("moduleName" in panel) panel.moduleName = "omarchy.monitor"
    if ("settings" in panel) panel.settings = panelSettings
    if ("manageIpc" in panel) panel.manageIpc = false
    if (panel.opened === true && typeof panel.close === "function") panel.close()
    panel.opacity = 0
  }

  function syncPanelSource() {
    panelLoader.sourceComponent = null
    panelLoader.source = ""
    if (panelComponent !== null) {
      panelLoader.sourceComponent = panelComponent
    } else if (String(panelSource)) {
      panelLoader.setSource(panelSource, {
        bar: hostProxy,
        moduleName: "omarchy.monitor",
        manageIpc: false,
        settings: panelSettings
      })
    }
  }

  onPanelSettingsChanged: injectPanel()
  onBarChanged: injectPanel()
  onPanelComponentChanged: Qt.callLater(syncPanelSource)
  onPanelSourceChanged: Qt.callLater(syncPanelSource)
  Component.onCompleted: Qt.callLater(syncPanelSource)
  Component.onDestruction: {
    if (!panel || !bar) return
    if (panel.opened === true && typeof panel.close === "function") panel.close()
  }

  // The official component owns the legacy IPC target. Redirect an IPC open
  // to Shibumi's screen-local presentation and never leave the stock popup
  // mapped behind it.
  Connections {
    target: root.panel
    function onOpenedChanged() {
      if (!root.panel || root.panel.opened !== true) return
      if (root.bar && typeof root.bar.summonBarWidget === "function")
        root.bar.summonBarWidget("omarchy.monitor")
      Qt.callLater(function() {
        if (root.panel && root.panel.opened === true
            && typeof root.panel.close === "function") root.panel.close()
      })
    }
  }

  QtObject {
    id: hostProxy

    readonly property var realBar: root.bar
    readonly property bool vertical: realBar ? realBar.vertical === true : false
    readonly property int barSize: realBar ? Number(realBar.barSize) : 35
    readonly property int sizeHorizontal: realBar && realBar.sizeHorizontal !== undefined
      ? Number(realBar.sizeHorizontal) : barSize
    readonly property string position: realBar ? String(realBar.position || "top") : "top"
    readonly property string fontFamily: realBar ? String(realBar.fontFamily || "monospace") : "monospace"
    readonly property color background: realBar && realBar.background !== undefined
      ? realBar.background : "#111111"
    readonly property color barBackground: background
    readonly property color foreground: realBar ? realBar.foreground : "#ffffff"
    readonly property color barForeground: foreground
    readonly property color urgent: realBar ? realBar.urgent : foreground
    readonly property bool foregroundAnimationEnabled: realBar
      ? realBar.foregroundAnimationEnabled !== false : false
    readonly property var shell: realBar ? realBar.shell : null
    readonly property var activePopout: realBar ? realBar.activePopout : null
    readonly property var clickTargets: realBar ? realBar.clickTargets : []

    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(_owner) {}
    function releasePopout(_owner) {}
    function switchPanelFrom(_owner, direction) {
      return realBar && typeof realBar.switchPanelFrom === "function"
        ? realBar.switchPanelFrom(root.ownerWidget, direction) : false
    }
    function targetBelongsToWindow(target, window) {
      return realBar && typeof realBar.targetBelongsToWindow === "function"
        ? realBar.targetBelongsToWindow(target, window) : false
    }
  }

  Loader {
    id: panelLoader
    anchors.fill: parent
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
