pragma ComponentBehavior: Bound

import QtQuick

// Keeps Quattro's audio component as the single PipeWire/device/action owner.
// Shibumi renders its own bar and popup presentation, while this bridge exposes
// only state and commands from the hidden official instance.
Item {
  id: root

  required property var bar
  required property Item ownerWidget
  property Component panelComponent: null
  property url panelSource: ""
  property var panelSettings: ({})

  readonly property var panel: panelLoader.item
  readonly property bool ready: panel !== null
  readonly property var sink: ready && panel.sink !== undefined ? panel.sink : null
  readonly property var source: ready && panel.source !== undefined ? panel.source : null
  readonly property var audioSinks: ready && panel.audioSinks !== undefined
    ? panel.audioSinks : []
  readonly property var audioSources: ready && panel.audioSources !== undefined
    ? panel.audioSources : []
  readonly property var audioStreams: ready && panel.audioStreams !== undefined
    ? panel.audioStreams : []
  readonly property real outputVolume: ready
    && panel.outputVolume !== undefined ? Number(panel.outputVolume) : 0
  readonly property bool outputMuted: ready
    && panel.outputMuted !== undefined ? panel.outputMuted === true : false
  readonly property real inputVolume: ready
    && panel.inputVolume !== undefined ? Number(panel.inputVolume) : 0
  readonly property bool inputMuted: ready
    && panel.inputMuted !== undefined ? panel.inputMuted === true : false

  function toggleOutputMute() {
    if (!ready || typeof panel.toggleOutputMute !== "function") return false
    panel.toggleOutputMute()
    return true
  }

  function setOutputVolume(value) {
    if (!ready || typeof panel.setOutputVolume !== "function") return false
    panel.setOutputVolume(Math.max(0, Math.min(1, Number(value) || 0)))
    return true
  }

  function toggleInputMute() {
    if (!ready || typeof panel.toggleInputMute !== "function") return false
    panel.toggleInputMute()
    return true
  }

  function setInputVolume(value) {
    if (!ready || typeof panel.setInputVolume !== "function") return false
    panel.setInputVolume(Math.max(0, Math.min(1, Number(value) || 0)))
    return true
  }

  function setDefaultSink(node) {
    if (!ready || !node || typeof panel.setDefaultSink !== "function") return false
    panel.setDefaultSink(node)
    return true
  }

  function setDefaultSource(node) {
    if (!ready || !node || typeof panel.setDefaultSource !== "function") return false
    panel.setDefaultSource(node)
    return true
  }

  function setStreamVolume(node, value) {
    if (!node || !node.audio) return false
    node.audio.volume = Math.max(0, Math.min(1.5, Number(value) || 0))
    return true
  }

  function toggleStreamMute(node) {
    if (!node || !node.audio) return false
    node.audio.muted = !node.audio.muted
    return true
  }

  function callLabelHelper(name, node, fallback) {
    if (!ready || typeof panel[name] !== "function") return String(fallback || "")
    return String(panel[name](node) || fallback || "")
  }

  function nodeLabel(node) { return callLabelHelper("nodeLabel", node, "Audio device") }
  function sinkGlyph(node) { return callLabelHelper("sinkGlyph", node, "speaker") }
  function sourceGlyph(node) { return callLabelHelper("sourceGlyph", node, "mic") }
  function streamLabel(node) { return callLabelHelper("streamLabel", node, "Application") }

  function injectPanel() {
    if (!panel) return
    if ("bar" in panel) panel.bar = hostProxy
    if ("moduleName" in panel) panel.moduleName = "omarchy.audio"
    if ("settings" in panel) panel.settings = panelSettings
    if ("manageIpc" in panel) panel.manageIpc = false
    if (panel.opened === true && typeof panel.close === "function") panel.close()
    // The official button and popup remain instantiated for their backend
    // state, but Shibumi owns the only visible presentation and click target.
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
        moduleName: "omarchy.audio",
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
    const currentPanel = panel
    if (currentPanel && currentPanel.opened === true
        && typeof currentPanel.close === "function") currentPanel.close()
    // Destroy the official panel while its host facade is still valid. Setting
    // panel.bar to null first reevaluates unguarded upstream bindings.
    panelLoader.active = false
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

    // The hidden official button must not become a second click target.
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}

    function requestPopout(owner) {
      if (realBar && typeof realBar.requestPopout === "function")
        realBar.requestPopout(owner)
    }

    function releasePopout(owner) {
      if (realBar && typeof realBar.releasePopout === "function")
        realBar.releasePopout(owner)
    }

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
