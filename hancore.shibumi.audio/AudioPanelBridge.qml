pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "AudioModel.js" as Model

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
  property var backendReadyOverride: null
  property real peakValue: 0
  property var peakAcquire: null
  property var peakRelease: null
  property var peakService: null
  property bool nativeBackendAccessEnabled: false
  property var nativeAudioService: null

  readonly property bool backendReady: backendReadyOverride !== null
    ? backendReadyOverride === true
    : nativeAudioService !== null
    ? nativeAudioService.nativeBackendReady === true
    : nativeBackendAccessEnabled ? Pipewire.ready === true : true
  readonly property bool ready: nativeAudioService !== null
    ? nativeAudioService.nativeBackendReady === true
    : panel.item !== null && backendReady
  readonly property var sinkSnapshot: {
    const version = generation
    void version
    if (!ready) return null
    if (nativeAudioService !== null) return nativeAudioService.nativeSinkSnapshot
    return panel.sink !== undefined
      ? Model.snapshot(panel.sink, "sink", true) : null
  }
  readonly property var sourceSnapshot: {
    const version = generation
    void version
    if (!ready) return null
    if (nativeAudioService !== null) return nativeAudioService.nativeSourceSnapshot
    return panel.source !== undefined
      ? Model.snapshot(panel.source, "source", true) : null
  }
  readonly property var volumeSinkSnapshot: {
    const version = generation
    void version
    if (!ready) return null
    if (nativeAudioService !== null)
      return nativeAudioService.nativeVolumeSinkSnapshot
    return panel.volumeSink !== undefined
      ? Model.snapshot(panel.volumeSink, "sink", true) : null
  }
  readonly property var audioSinks: {
    const version = generation
    void version
    if (!ready) return []
    if (nativeAudioService !== null)
      return nativeAudioService.nativeAudioSinks || []
    return panel.audioSinks !== undefined
      ? Model.snapshotList(Model.groupedDeviceNodes(panel.audioSinks), "sink", panel.sink)
      : []
  }
  readonly property var audioSources: {
    const version = generation
    void version
    if (!ready) return []
    if (nativeAudioService !== null)
      return nativeAudioService.nativeAudioSources || []
    return panel.audioSources !== undefined
      ? Model.snapshotList(panel.audioSources, "source", panel.source) : []
  }
  readonly property var audioStreams: {
    const version = generation
    void version
    if (!ready) return []
    if (nativeAudioService !== null)
      return nativeAudioService.nativeAudioStreams || []
    if (panel.audioStreams === undefined) return []
    const streams = panel.audioStreams
    const players = root.nativeBackendAccessEnabled
      ? (Mpris.players ? Mpris.players.values : []) : []
    return Model.snapshotList(streams, "stream", null,
      function(node) { return Model.streamLabel(node, players, streams) })
  }
  readonly property real outputVolume: {
    if (!ready) return 0
    if (nativeAudioService !== null)
      return Number(nativeAudioService.nativeOutputVolume || 0)
    return panel.outputVolume !== undefined ? Number(panel.outputVolume) : 0
  }
  readonly property bool outputMuted: {
    if (!ready) return false
    if (nativeAudioService !== null)
      return nativeAudioService.nativeOutputMuted === true
    return panel.outputMuted !== undefined && panel.outputMuted === true
  }
  readonly property real inputVolume: {
    if (!ready) return 0
    if (nativeAudioService !== null)
      return Number(nativeAudioService.nativeInputVolume || 0)
    return panel.inputVolume !== undefined ? Number(panel.inputVolume) : 0
  }
  readonly property bool inputMuted: {
    if (!ready) return false
    if (nativeAudioService !== null)
      return nativeAudioService.nativeInputMuted === true
    return panel.inputMuted !== undefined && panel.inputMuted === true
  }
  readonly property real inputPeak: {
    if (!ready) return 0
    if (nativeAudioService !== null)
      return Number(nativeAudioService.inputPeak || 0)
    return Number(peakValue || 0)
  }
  property int generation: 0

  // Internal-only facade around the loaded official component. It is a child
  // id, not a root property, so callers cannot obtain the raw panel object.
  QtObject {
    id: panel

    readonly property var item: panelLoader.item
    readonly property var sink: item && item.sink !== undefined ? item.sink : null
    readonly property var volumeSink: item && item.volumeSink !== undefined
      ? item.volumeSink : sink
    readonly property var source: item && item.source !== undefined ? item.source : null
    readonly property var audioSinks: item && item.audioSinks !== undefined
      ? item.audioSinks : []
    readonly property var audioSources: item && item.audioSources !== undefined
      ? item.audioSources : []
    readonly property var audioStreams: item && item.audioStreams !== undefined
      ? item.audioStreams : []
    readonly property var nodes: item && item.nodes !== undefined
      ? item.nodes : []
    readonly property var candidateSinks: item && item.candidateSinks !== undefined
      ? item.candidateSinks : null
    readonly property var candidateSources: item && item.candidateSources !== undefined
      ? item.candidateSources : null
    readonly property var candidateStreams: item && item.candidateStreams !== undefined
      ? item.candidateStreams : null
    readonly property var sinkAvailability: item && item.sinkAvailability !== undefined
      ? item.sinkAvailability : ({})
    readonly property bool sinkAvailabilityLoaded:
      item && item.sinkAvailabilityLoaded === true
    readonly property var outputVolume: item && item.outputVolume !== undefined
      ? item.outputVolume : 0
    readonly property bool outputMuted: item && item.outputMuted === true
    readonly property var inputVolume: item && item.inputVolume !== undefined
      ? item.inputVolume : 0
    readonly property bool inputMuted: item && item.inputMuted === true
    readonly property var inputPeak: item && item.inputPeak !== undefined
      ? item.inputPeak : undefined
    readonly property bool opened: item && item.opened === true

    function unsupported() {
      return {
        ok: false,
        code: "unsupported",
        message: "Audio backend action is unavailable",
        entityId: "",
        generation: root.generation
      }
    }
    function toggleOutputMute() {
      if (!item || typeof item.toggleOutputMute !== "function") return unsupported()
      return item.toggleOutputMute()
    }
    function setOutputVolume(value) {
      if (!item || typeof item.setOutputVolume !== "function") return unsupported()
      return item.setOutputVolume(value)
    }
    function toggleInputMute() {
      if (!item || typeof item.toggleInputMute !== "function") return unsupported()
      return item.toggleInputMute()
    }
    function setInputVolume(value) {
      if (!item || typeof item.setInputVolume !== "function") return unsupported()
      return item.setInputVolume(value)
    }
    function setDefaultSink(node) {
      if (!item || typeof item.setDefaultSink !== "function") return unsupported()
      return item.setDefaultSink(node)
    }
    function setDefaultSource(node) {
      if (!item || typeof item.setDefaultSource !== "function") return unsupported()
      return item.setDefaultSource(node)
    }
    function setStreamVolume(node, value) {
      if (!item || !node || !node.audio) return unsupported()
      node.audio.volume = Math.max(0, Math.min(1.5, Number(value) || 0))
      return true
    }
    function toggleStreamMute(node) {
      if (!item || !node || !node.audio) return unsupported()
      node.audio.muted = !node.audio.muted
      return true
    }
    function streamLabel(node) {
      return item && typeof item.streamLabel === "function"
        ? item.streamLabel(node) : ""
    }
    function close() {
      if (item && typeof item.close === "function") item.close()
    }
    function suppressKeyboardPanel() {
      if (!item || !item.data || item.data.length === undefined) return false
      let suppressed = false
      for (let index = 0; index < item.data.length; index++) {
        const candidate = item.data[index]
        if (!candidate || typeof candidate.beginFocusPrime !== "function"
            || !("anchorItem" in candidate) || !("open" in candidate)
            || !("visible" in candidate) || !("owner" in candidate)
            || candidate.owner !== item) continue
        candidate.open = false
        candidate.visible = false
        suppressed = true
      }
      return suppressed
    }
    function inject(host, settings) {
      if (!item) return
      suppressKeyboardPanel()
      if ("bar" in item) item.bar = host
      if ("moduleName" in item) item.moduleName = "omarchy.audio"
      if ("settings" in item) item.settings = settings
      if ("manageIpc" in item) item.manageIpc = false
      if (item.opened === true && typeof item.close === "function") item.close()
      item.opacity = 0
    }
  }

  property int peakClients: 0
  property var leasedPeakOwner: null
  property var leasedPeakRelease: null
  readonly property bool peakLeaseHeld: leasedPeakOwner !== null
    || leasedPeakRelease !== null

  function clearPeakLease() {
    const owner = leasedPeakOwner
    const release = leasedPeakRelease
    leasedPeakOwner = null
    leasedPeakRelease = null
    if (owner && typeof owner.releasePeakMonitoring === "function")
      owner.releasePeakMonitoring()
    else if (typeof release === "function") release()
  }

  function syncPeakLease() {
    const owner = ready && peakClients > 0 ? (nativeAudioService || peakService) : null
    const release = ready && peakClients > 0 && !owner ? peakRelease : null
    if (peakLeaseHeld && owner === leasedPeakOwner
        && release === leasedPeakRelease) return
    clearPeakLease()
    if (!ready || peakClients <= 0) return
    if (owner) {
      if (typeof owner.acquirePeakMonitoring === "function"
          && typeof owner.releasePeakMonitoring === "function"
          && owner.acquirePeakMonitoring() === true)
        leasedPeakOwner = owner
    } else if (typeof peakAcquire === "function" && typeof release === "function"
        && peakAcquire() === true) {
      leasedPeakRelease = release
    }
  }

  function acquirePeakMonitoring() {
    if (!ready) return false
    peakClients++
    syncPeakLease()
    if (peakLeaseHeld) return true
    peakClients--
    return false
  }

  function releasePeakMonitoring() {
    if (peakClients <= 0) return false
    peakClients--
    syncPeakLease()
    return true
  }

  onNativeAudioServiceChanged: syncPeakLease()
  onPeakServiceChanged: syncPeakLease()
  onReadyChanged: syncPeakLease()
  onPeakAcquireChanged: syncPeakLease()
  onPeakReleaseChanged: syncPeakLease()

  function actionResult(ok, code, message, entityId) {
    return Model.actionResult(ok, code, message, entityId, generation)
  }

  function delegatedResult(value, entityId) {
    if (value && typeof value === "object"
        && typeof value.ok === "boolean") {
      value.entityId = entityId
      if (value.code === undefined)
        value.code = value.ok ? "ok" : "unavailable"
      if (value.message === undefined) value.message = ""
      if (value.generation === undefined) value.generation = generation
      return value
    }
    if (value === false)
      return actionResult(false, "unavailable", "Audio backend action failed", entityId)
    return null
  }

  function refreshedDelegatedSuccess(value, entityId) {
    return actionResult(true, value.code || "ok", value.message || "", entityId)
  }

  function nativeAction(method, args, entityId) {
    if (!nativeAudioService || typeof nativeAudioService[method] !== "function")
      return actionResult(false, "unsupported",
        "Audio backend action is unavailable", entityId)
    const value = nativeAudioService[method].apply(nativeAudioService, args || [])
    const delegated = delegatedResult(value, entityId)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, entityId)
      : actionResult(true, "ok", "", entityId)
  }

  function advanceGeneration() {
    generation++
  }

  function entityId(entity, kind) {
    return entity && entity.id !== undefined
      ? String(entity.id) : String(entity || "")
  }

  function liveNode(entity, kind) {
    const id = entityId(entity, kind)
    const nodes = kind === "sink" ? panel.candidateSinks
      : kind === "source" ? panel.candidateSources : panel.candidateStreams
    if (!nodes) return null
    for (let index = 0; index < nodes.length; index++) {
      const node = nodes[index]
      if (!node || Model.stableNodeId(node, kind) !== id) continue
      return node
    }
    return null
  }

  function toggleOutputMute() {
    const id = volumeSinkSnapshot ? volumeSinkSnapshot.id
      : sinkSnapshot ? sinkSnapshot.id : ""
    if (nativeAudioService !== null)
      return nativeAction("nativeToggleOutputMute", [], id)
    if (!ready || !panel.volumeSink || panel.volumeSink.ready === false
        || !panel.volumeSink.audio)
      return actionResult(false, "unavailable", "Output is unavailable", id)
    if (typeof panel.toggleOutputMute !== "function")
      return actionResult(false, "unsupported", "Audio backend action is unavailable", id)
    const delegated = delegatedResult(panel.toggleOutputMute(), id)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, id)
      : actionResult(true, "ok", "", id)
  }

  function setOutputVolume(value) {
    const id = volumeSinkSnapshot ? volumeSinkSnapshot.id
      : sinkSnapshot ? sinkSnapshot.id : ""
    if (nativeAudioService !== null)
      return nativeAction("nativeSetOutputVolume",
        [Math.max(0, Math.min(1, Number(value) || 0))], id)
    if (!ready || !panel.volumeSink || panel.volumeSink.ready === false
        || !panel.volumeSink.audio)
      return actionResult(false, "unavailable", "Output is unavailable", id)
    if (typeof panel.setOutputVolume !== "function")
      return actionResult(false, "unsupported", "Audio backend action is unavailable", id)
    const delegated = delegatedResult(
      panel.setOutputVolume(Math.max(0, Math.min(1, Number(value) || 0))), id)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, id)
      : actionResult(true, "ok", "", id)
  }

  function toggleInputMute() {
    const id = sourceSnapshot ? sourceSnapshot.id : ""
    if (nativeAudioService !== null)
      return nativeAction("nativeToggleInputMute", [], id)
    if (!ready || !panel.source || panel.source.ready === false
        || !panel.source.audio)
      return actionResult(false, "unavailable", "Input is unavailable", id)
    if (typeof panel.toggleInputMute !== "function")
      return actionResult(false, "unsupported", "Audio backend action is unavailable", id)
    const delegated = delegatedResult(panel.toggleInputMute(), id)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, id)
      : actionResult(true, "ok", "", id)
  }

  function setInputVolume(value) {
    const id = sourceSnapshot ? sourceSnapshot.id : ""
    if (nativeAudioService !== null)
      return nativeAction("nativeSetInputVolume",
        [Math.max(0, Math.min(1, Number(value) || 0))], id)
    if (!ready || !panel.source || panel.source.ready === false
        || !panel.source.audio)
      return actionResult(false, "unavailable", "Input is unavailable", id)
    if (typeof panel.setInputVolume !== "function")
      return actionResult(false, "unsupported", "Audio backend action is unavailable", id)
    const delegated = delegatedResult(
      panel.setInputVolume(Math.max(0, Math.min(1, Number(value) || 0))), id)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, id)
      : actionResult(true, "ok", "", id)
  }

  function setDefaultSink(entity) {
    const id = entityId(entity, "sink")
    if (nativeAudioService !== null)
      return nativeAction("nativeSetDefaultSink", [id], id)
    const node = ready ? liveNode(entity, "sink") : null
    if (!ready) return actionResult(false, "unavailable", "Audio sink is unavailable", id)
    if (!node)
      return actionResult(false, "stale-id", "Audio sink is unavailable", id)
    if (node.ready === false)
      return actionResult(false, "unavailable", "Audio sink is unavailable", id)
    if (panel.sinkAvailabilityLoaded
        && panel.sinkAvailability[String(node.name || "")] === false)
      return actionResult(false, "unavailable", "Audio sink is unavailable", id)
    if (typeof panel.setDefaultSink !== "function")
      return actionResult(false, "unsupported", "Audio backend action is unavailable", id)
    const delegated = delegatedResult(panel.setDefaultSink(node), id)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, id)
      : actionResult(true, "ok", "", id)
  }

  function setDefaultSource(entity) {
    const id = entityId(entity, "source")
    if (nativeAudioService !== null)
      return nativeAction("nativeSetDefaultSource", [id], id)
    const node = ready ? liveNode(entity, "source") : null
    if (!ready) return actionResult(false, "unavailable", "Audio source is unavailable", id)
    if (!node)
      return actionResult(false, "stale-id", "Audio source is unavailable", id)
    if (node.ready === false)
      return actionResult(false, "unavailable", "Audio source is unavailable", id)
    if (typeof panel.setDefaultSource !== "function")
      return actionResult(false, "unsupported", "Audio backend action is unavailable", id)
    const delegated = delegatedResult(panel.setDefaultSource(node), id)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, id)
      : actionResult(true, "ok", "", id)
  }

  function setStreamVolume(entity, value) {
    const id = entityId(entity, "stream")
    if (nativeAudioService !== null)
      return nativeAction("nativeSetStreamVolume",
        [id, Math.max(0, Math.min(1.5, Number(value) || 0))], id)
    const node = ready ? liveNode(entity, "stream") : null
    if (!ready) return actionResult(false, "unavailable", "Audio stream is unavailable", id)
    if (!node)
      return actionResult(false, "stale-id", "Audio stream is unavailable", id)
    if (node.ready === false)
      return actionResult(false, "unavailable", "Audio stream is unavailable", id)
    if (!node.audio)
      return actionResult(false, "unavailable", "Audio stream is unavailable", id)
    const delegated = delegatedResult(panel.setStreamVolume(node, value), id)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, id)
      : actionResult(true, "ok", "", id)
  }

  function toggleStreamMute(entity) {
    const id = entityId(entity, "stream")
    if (nativeAudioService !== null)
      return nativeAction("nativeToggleStreamMute", [id], id)
    const node = ready ? liveNode(entity, "stream") : null
    if (!ready) return actionResult(false, "unavailable", "Audio stream is unavailable", id)
    if (!node)
      return actionResult(false, "stale-id", "Audio stream is unavailable", id)
    if (node.ready === false)
      return actionResult(false, "unavailable", "Audio stream is unavailable", id)
    if (!node.audio)
      return actionResult(false, "unavailable", "Audio stream is unavailable", id)
    const delegated = delegatedResult(panel.toggleStreamMute(node), id)
    if (delegated && !delegated.ok) return delegated
    advanceGeneration()
    return delegated ? refreshedDelegatedSuccess(delegated, id)
      : actionResult(true, "ok", "", id)
  }

  function nodeLabel(snapshot) {
    return snapshot && snapshot.label ? String(snapshot.label) : "Audio device"
  }

  function streamLabel(snapshot) {
    return snapshot && snapshot.label ? String(snapshot.label) : "Application"
  }


  function officialKeyboardState() {
    const item = panel.item
    if (!item || !item.data || item.data.length === undefined)
      return ({ open: false, visible: false })
    for (let index = 0; index < item.data.length; index++) {
      const candidate = item.data[index]
      if (!candidate || typeof candidate.beginFocusPrime !== "function"
          || !("anchorItem" in candidate) || !("open" in candidate)
          || !("visible" in candidate) || !("owner" in candidate)
          || candidate.owner !== item) continue
      return ({ open: candidate.open === true, visible: candidate.visible === true })
    }
    return ({ open: false, visible: false })
  }

  function officialPanelState() {
    const item = panel.item
    if (!item) return ({ present: false })
    const keyboard = officialKeyboardState()
    const firstStream = item.audioStreams && item.audioStreams.length > 0
      ? item.audioStreams[0] : null
    return {
      present: true,
      opacity: Number(item.opacity || 0),
      settings: item.settings || ({}),
      manageIpc: item.manageIpc === true,
      opened: item.opened === true,
      openCount: Number(item.openCount || 0),
      backendKeyboardPanelOpen: keyboard.open,
      backendKeyboardPanelVisible: keyboard.visible,
      clickTargetRegistered: !!(item.internalButton
        && item.internalButton.registeredBar !== undefined
        && item.internalButton.registeredBar === root.bar),
      defaultSinkChanges: Number(item.defaultSinkChanges || 0),
      sinkId: item.sink && item.sink.id !== undefined ? Number(item.sink.id) : -1,
      defaultSourceChanges: Number(item.defaultSourceChanges || 0),
      sourceId: item.source && item.source.id !== undefined ? Number(item.source.id) : -1,
      outputVolumeChanges: Number(item.outputVolumeChanges || 0),
      outputVolume: Number(item.outputVolume || 0),
      inputVolumeChanges: Number(item.inputVolumeChanges || 0),
      inputVolume: Number(item.inputVolume || 0),
      inputMuted: item.inputMuted === true,
      streamVolume: firstStream && firstStream.audio
        ? Number(firstStream.audio.volume || 0) : 0,
      streamMuted: !!(firstStream && firstStream.audio && firstStream.audio.muted)
    }
  }

  function openOfficialPanel() {
    if (!panel.item || typeof panel.item.open !== "function") return false
    panel.item.open()
    return true
  }

  function closeOfficialPanel() {
    panel.close()
    return true
  }

  function injectPanel() {
    if (!panel.item) return
    // The official button and popup remain instantiated for their backend
    // state, but Shibumi owns the only visible presentation and click target.
    panel.inject(hostProxy, panelSettings)
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
    peakClients = 0
    clearPeakLease()
    panel.close()
    // Destroy the official panel while its host facade is still valid.
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
