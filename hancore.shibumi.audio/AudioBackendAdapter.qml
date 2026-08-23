pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "AudioModel.js" as Model

// Test-only/native preparation seam for Step 4A. It is not instantiated by
// production Service.qml until the native Audio activation commit. PipeWire
// objects stay inside the implementation object, callers receive primitive
// snapshots and typed action results, and every mutation resolves the current
// object by ID.
Item {
  id: root

  property bool active: false
  property int peakMonitoringClients: 0
  readonly property bool peakMonitoringEnabled: peakMonitoringClients > 0
  property var backendOverride: null
  property var mprisPlayersOverride: null
  property string volumeSinkName: ""
  property bool volumeSinkResolved: false
  property bool volumeSinkResolutionFailed: false
  property var sinkAvailability: ({})
  property bool sinkAvailabilityResolved: false
  property int sinkAvailabilityRequestGeneration: 0
  property int sinkAvailabilityProcessGeneration: 0
  property bool sinkAvailabilityProcessStarted: false
  property int volumeSinkRequestGeneration: 0
  property int volumeSinkProcessGeneration: 0
  property bool volumeSinkProcessStarted: false
  property bool volumeSinkProcessDiscarded: false
  // Keep the last primitive value while the asynchronous volume-sink
  // resolver is refreshing. Opening the panel acquires peak monitoring,
  // which can transiently invalidate link-derived sink state.
  property real lastKnownOutputVolume: 0
  property bool lastKnownOutputMuted: false
  property int generation: 0

  readonly property bool ready: implementation.ready()

  onActiveChanged: {
    if (root.backendOverride === null) {
      root.invalidateVolumeSink()
      root.invalidateSinkAvailability()
    }
  }
  onBackendOverrideChanged: {
    if (root.backendOverride === null) {
      root.invalidateVolumeSink()
      root.invalidateSinkAvailability()
    } else {
      root.volumeSinkResolved = true
      root.invalidateSinkAvailability()
    }
  }

  function invalidateSinkAvailability() {
    sinkAvailability = ({})
    sinkAvailabilityRequestGeneration++
    sinkAvailabilityResolved = backendOverride !== null
  }

  function invalidateVolumeSink() {
    volumeSinkName = ""
    volumeSinkRequestGeneration++
    volumeSinkResolutionFailed = false
    volumeSinkResolved = backendOverride !== null
  }
  readonly property real outputVolume: {
    // Keep the primitive binding reactive across the asynchronous volume-sink
    // resolver. The implementation method intentionally hides backend nodes,
    // so these dependencies must be explicit at the public seam.
    const active = root.active
    const resolved = root.volumeSinkResolved
    const failed = root.volumeSinkResolutionFailed
    const sinkName = root.volumeSinkName
    const requestGeneration = root.volumeSinkRequestGeneration
    const backendReady = root.backendOverride !== null
      ? root.backendOverride.ready !== false : Pipewire.ready === true
    void active
    void resolved
    void failed
    void sinkName
    void requestGeneration
    void backendReady
    if (!backendReady) return 0
    if (!resolved) {
      const sink = implementation.currentVolumeNode()
      if (sink && sink.audio && sink.audio.volume !== undefined)
        return Number(sink.audio.volume)
      return root.lastKnownOutputVolume
    }
    return implementation.outputVolume()
  }
  onOutputVolumeChanged: {
    if (root.volumeSinkResolved && root.ready)
      root.lastKnownOutputVolume = outputVolume
  }
  readonly property bool outputMuted: {
    const active = root.active
    const resolved = root.volumeSinkResolved
    const failed = root.volumeSinkResolutionFailed
    const sinkName = root.volumeSinkName
    const requestGeneration = root.volumeSinkRequestGeneration
    const backendReady = root.backendOverride !== null
      ? root.backendOverride.ready !== false : Pipewire.ready === true
    void active
    void resolved
    void failed
    void sinkName
    void requestGeneration
    void backendReady
    if (!backendReady) return false
    if (!resolved) {
      const sink = implementation.currentVolumeNode()
      if (sink && sink.audio && sink.audio.muted !== undefined)
        return sink.audio.muted === true
      return root.lastKnownOutputMuted
    }
    return implementation.outputMuted()
  }
  onOutputMutedChanged: {
    if (root.volumeSinkResolved && root.ready)
      root.lastKnownOutputMuted = outputMuted
  }
  readonly property real inputVolume: implementation.inputVolume()
  readonly property bool inputMuted: implementation.inputMuted()
  readonly property var audioSinks: implementation.audioSinks()
  readonly property var audioSources: implementation.audioSources()
  readonly property var audioStreams: implementation.audioStreams()
  readonly property var sinkSnapshot: implementation.sinkSnapshot()
  readonly property var volumeSinkSnapshot: implementation.volumeSinkSnapshot()
  readonly property var sourceSnapshot: implementation.sourceSnapshot()
  readonly property real inputPeak: implementation.inputPeak()

  // Public capability surface: primitive snapshots and typed action results.
  // Raw PipeWire nodes remain reachable only through the implementation id.
  function acquirePeakMonitoring() {
    peakMonitoringClients++
    return true
  }
  function releasePeakMonitoring() {
    peakMonitoringClients = Math.max(0, peakMonitoringClients - 1)
    return true
  }

  function setDefaultSink(id) { return implementation.setDefaultSink(id) }
  function setDefaultSource(id) { return implementation.setDefaultSource(id) }
  function setOutputVolume(value) { return implementation.setOutputVolume(value) }
  function toggleOutputMute() { return implementation.toggleOutputMute() }
  function setInputVolume(value) { return implementation.setInputVolume(value) }
  function toggleInputMute() { return implementation.toggleInputMute() }
  function setStreamVolume(id, value) {
    return implementation.setStreamVolume(id, value)
  }
  function toggleStreamMute(id) {
    return implementation.toggleStreamMute(id)
  }
  function nodeLabel(snapshot) {
    return snapshot && snapshot.label ? String(snapshot.label) : "Audio device"
  }
  function streamLabel(snapshot) {
    return snapshot && snapshot.label ? String(snapshot.label) : "Application"
  }
  function routeBluetoothDevice(request) {
    return implementation.routeBluetoothDevice(request)
  }

  QtObject {
    id: implementation

    function backendValue(name, fallback) {
      if (root.backendOverride !== null
          && root.backendOverride[name] !== undefined)
        return root.backendOverride[name]
      return fallback
    }

    function currentNodes() {
      if (!root.active) return []
      if (root.backendOverride !== null) return backendValue("nodes", [])
      return Pipewire.nodes ? Pipewire.nodes.values : []
    }

    function currentSink() {
      if (!root.active) return null
      return root.backendOverride !== null
        ? backendValue("defaultAudioSink", null)
        : Pipewire.defaultAudioSink
    }

    function currentSource() {
      if (!root.active) return null
      return root.backendOverride !== null
        ? backendValue("defaultAudioSource", null)
        : Pipewire.defaultAudioSource
    }

    function currentVolumeSink() {
      const sink = implementation.currentSink()
      if (!sink || sink.ready === false) return null
      // The default sink is already a stable native object while the helper
      // resolves the preferred volume sink. Keep live controls usable during
      // that short refresh window instead of returning an unavailable result.
      if (root.backendOverride === null && !root.volumeSinkResolved)
        return sink
      const configuredName = root.backendOverride !== null
        ? String(backendValue("volumeSinkName", ""))
        : String(root.volumeSinkName || "")
      if (!configuredName || String(sink.name || "") === configuredName)
        return sink
      const nodes = implementation.currentNodes()
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (node && node.isSink && !node.isStream
            && String(node.name || "") === configuredName
            && node.ready !== false && node.audio)
          return node
      }
      return null
    }

    function volumeSinkNameMapped() {
      const configuredName = String(root.volumeSinkName || "")
      if (!configuredName) return !root.volumeSinkResolutionFailed
      const sink = implementation.currentSink()
      if (!sink) return false
      if (String(sink.name || "") === configuredName) return true
      const nodes = implementation.currentNodes()
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (node && node.isSink && !node.isStream
            && String(node.name || "") === configuredName
            && node.ready !== false && node.audio) return true
      }
      return false
    }

    function currentVolumeNode() {
      const sink = implementation.currentVolumeSink()
      if (!sink) return null
      return implementation.resolveNode(Model.stableNodeId(sink, "sink"),
        implementation.allSinks(implementation.currentNodes()), "sink")
    }

    function currentInputNode() {
      const source = implementation.currentSource()
      if (!source) return null
      return implementation.resolveNode(Model.stableNodeId(source, "source"),
        implementation.allSources(implementation.currentNodes()), "source")
    }

    function monitorSource() {
      const source = implementation.currentInputNode()
      return source && source.ready !== false ? source : null
    }

    function ready() {
      return backendReady()
    }

    function outputVolume() {
      if (!backendReady()) return 0
      const sink = implementation.currentVolumeNode()
      return sink && sink.audio && sink.audio.volume !== undefined
        ? Number(sink.audio.volume) : 0
    }

    function outputMuted() {
      if (!backendReady()) return false
      const sink = implementation.currentVolumeNode()
      return sink && sink.audio && sink.audio.muted === true
    }

    function inputVolume() {
      if (!backendReady()) return 0
      const source = implementation.currentInputNode()
      if (!source || source.ready === false) return 0
      return source.audio && source.audio.volume !== undefined
        ? Number(source.audio.volume) : 0
    }

    function inputMuted() {
      if (!backendReady()) return false
      const source = implementation.currentInputNode()
      if (!source || source.ready === false) return false
      return source.audio && source.audio.muted === true
    }

    function inputPeak() {
      if (!backendReady() || !root.peakMonitoringEnabled
          || !monitorSource()) return 0
      if (root.backendOverride !== null
          && root.backendOverride.inputPeak !== undefined)
        return Number(root.backendOverride.inputPeak) || 0
      return Number(inputPeakMonitor.peak) || 0
    }

    function allSinks(nodes) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (node && node.isSink && !node.isStream) result.push(node)
      }
      return result
    }

    function allSources(nodes) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (node && String(node.name || "") !== "quickshell"
            && !node.isSink && !node.isStream
            && (node.ready === false || Model.isAudioSource(node)))
          result.push(node)
      }
      return result
    }

    function allStreams(nodes) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (node && String(node.name || "").indexOf("omarchy_speaker_tuning") !== 0
            && Model.isPlaybackStream(node)) result.push(node)
      }
      return result
    }

    function filterSinks(nodes) {
      const result = []
      const selected = currentSink()
      const selectedId = selected ? Model.stableNodeId(selected, "sink") : ""
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (!node || !node.isSink || node.isStream) continue
        const name = String(node.name || "")
        const nodeId = Model.stableNodeId(node, "sink")
        if (root.sinkAvailabilityResolved
            && root.sinkAvailability[name] === false
            && nodeId !== selectedId) continue
        result.push(node)
      }
      return result
    }

    function filterSources(nodes) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (node && node.ready !== false
            && String(node.name || "") !== "quickshell"
            && Model.isAudioSource(node)) result.push(node)
      }
      return result
    }

    function filterStreams(nodes) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (node && node.ready !== false
            && String(node.name || "").indexOf("omarchy_speaker_tuning") !== 0
            && Model.isPlaybackStream(node) && node.audio) result.push(node)
      }
      return result
    }

    function snapshotList(nodes, kind, selected) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const value = Model.snapshot(nodes[index], kind, nodes[index] === selected)
        if (value && value.id) result.push(value)
      }
      return result
    }

    function audioSinks() {
      const version = root.generation
      void version
      if (!backendReady()) return []
      const sinks = Model.groupedDeviceNodes(filterSinks(currentNodes()))
      return snapshotList(sinks, "sink", currentSink())
    }

    function audioSources() {
      const version = root.generation
      void version
      if (!backendReady()) return []
      return snapshotList(
        filterSources(currentNodes()), "source", currentSource())
    }

    function audioStreams() {
      const version = root.generation
      void version
      if (!backendReady()) return []
      const streams = filterStreams(currentNodes())
      const players = root.mprisPlayersOverride !== null
        ? root.mprisPlayersOverride
        : root.backendOverride !== null
        ? backendValue("mprisPlayers", [])
        : (Mpris.players ? Mpris.players.values : [])
      return snapshotList(streams, "stream", null,
        function(node) { return Model.streamLabel(node, players, streams) })
    }

    function sinkSnapshot() {
      const version = root.generation
      void version
      return backendReady() ? Model.snapshot(currentSink(), "sink", true) : null
    }

    function volumeSinkSnapshot() {
      const version = root.generation
      void version
      return backendReady()
        ? Model.snapshot(implementation.currentVolumeNode(), "sink", true) : null
    }

    function sourceSnapshot() {
      const version = root.generation
      void version
      return backendReady() ? Model.snapshot(currentSource(), "source", true) : null
    }

    function resolveNode(id, nodes, kind) {
      const key = String(id || "")
      if (!key) return null
      for (let index = 0; index < nodes.length; index++) {
        if (Model.stableNodeId(nodes[index], kind) === key) return nodes[index]
      }
      return null
    }

    function result(ok, code, message, entityId) {
      return Model.actionResult(
        ok, code, message, entityId, root.generation)
    }

    function delegatedResult(value, entityId) {
      if (value && typeof value === "object"
          && typeof value.ok === "boolean") {
        value.entityId = entityId
        if (value.code === undefined)
          value.code = value.ok ? "ok" : "unavailable"
        if (value.message === undefined) value.message = ""
        if (value.generation === undefined) value.generation = root.generation
        return value
      }
      if (value === false)
        return result(false, "unavailable", "Audio backend action failed", entityId)
      return null
    }

    function refreshedDelegatedSuccess(value, entityId) {
      return result(true, value.code || "ok", value.message || "", entityId)
    }

    function nativeBackendReady() {
      return Pipewire.ready === true
        && Pipewire.nodes !== null && Pipewire.nodes !== undefined
    }

    function backendReady() {
      if (!root.active) return false
      return root.backendOverride !== null
        ? backendValue("ready", true) !== false
        : nativeBackendReady()
    }

    function unresolvedId(id, label) {
      return result(
        false,
        backendReady() ? "stale-id" : "unavailable",
        label + " is unavailable",
        id)
    }

    function mutationError(node, kind, label) {
      const entityId = node ? Model.stableNodeId(node, kind) : ""
      if (!backendReady() || !node || node.ready === false)
        return result(false, "unavailable", label + " is unavailable", entityId)
      if (!entityId)
        return result(false, "stale-id", label + " is unavailable")
      return null
    }

    function setNodeDefault(node, kind, propertyName) {
      const failure = mutationError(node, kind, "Audio node")
      if (failure) return failure
      const entityId = Model.stableNodeId(node, kind)
      if (kind === "sink" && root.sinkAvailabilityResolved
          && root.sinkAvailability[String(node.name || "")] === false)
        return result(false, "unavailable", "Audio sink is unavailable", entityId)
      if (root.backendOverride !== null) {
        if (typeof root.backendOverride[propertyName] !== "function")
          return result(false, "unsupported", "Audio backend action is unavailable", entityId)
        const delegated = delegatedResult(
          root.backendOverride[propertyName](node), entityId)
        if (delegated) {
          if (!delegated.ok) return delegated
          root.generation++
          return refreshedDelegatedSuccess(delegated, entityId)
        }
      } else if (propertyName === "setDefaultSink") {
        Pipewire.preferredDefaultAudioSink = node
        if (node.id !== undefined && node.name) {
          Quickshell.execDetached([
            "omarchy-audio-output-set-default",
            String(node.id), String(node.name)
          ])
        }
      } else {
        Pipewire.preferredDefaultAudioSource = node
        if (node.id !== undefined && node.name) {
          Quickshell.execDetached([
            "omarchy-audio-input-set-default",
            String(node.id), String(node.name)
          ])
        }
      }
      root.generation++
      return result(true, "ok", "", entityId)
    }

    function setDefaultSink(id) {
      const node = resolveNode(id, allSinks(currentNodes()), "sink")
      if (!node) return unresolvedId(id, "Audio sink")
      return setNodeDefault(node, "sink", "setDefaultSink")
    }

    function setDefaultSource(id) {
      const node = resolveNode(id, allSources(currentNodes()), "source")
      if (!node) return unresolvedId(id, "Audio source")
      return setNodeDefault(node, "source", "setDefaultSource")
    }

    function setOutputVolume(value) {
      const sink = implementation.currentVolumeNode()
      if (!sink || sink.ready === false || !sink.audio)
        return result(false, "unavailable", "Output is unavailable", sink
          ? Model.stableNodeId(sink, "sink") : "")
      const failure = mutationError(sink, "sink", "Output")
      if (failure) return failure
      sink.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
      root.generation++
      return result(true, "ok", "", Model.stableNodeId(sink, "sink"))
    }

    function toggleOutputMute() {
      const sink = implementation.currentVolumeNode()
      const failure = mutationError(sink, "sink", "Output")
      if (failure) return failure
      if (!sink.audio)
        return result(false, "unavailable", "Output is unavailable",
          Model.stableNodeId(sink, "sink"))
      sink.audio.muted = !sink.audio.muted
      root.generation++
      return result(true, "ok", "", Model.stableNodeId(sink, "sink"))
    }

    function setInputVolume(value) {
      const source = implementation.currentInputNode()
      if (!source || source.ready === false || !source.audio)
        return result(false, "unavailable", "Input is unavailable",
          source ? Model.stableNodeId(source, "source") : "")
      const failure = mutationError(source, "source", "Input")
      if (failure) return failure
      source.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
      root.generation++
      return result(true, "ok", "", Model.stableNodeId(source, "source"))
    }

    function toggleInputMute() {
      const source = implementation.currentInputNode()
      const failure = mutationError(source, "source", "Input")
      if (failure) return failure
      if (!source.audio)
        return result(false, "unavailable", "Input is unavailable",
          Model.stableNodeId(source, "source"))
      source.audio.muted = !source.audio.muted
      root.generation++
      return result(true, "ok", "", Model.stableNodeId(source, "source"))
    }

    function setStreamVolume(id, value) {
      const node = resolveNode(id, allStreams(currentNodes()), "stream")
      if (!node) return unresolvedId(id, "Audio stream")
      const failure = mutationError(node, "stream", "Audio stream")
      if (failure) return failure
      if (!node.audio)
        return result(false, "unavailable", "Audio stream is unavailable", id)
      node.audio.volume = Math.max(0, Math.min(1.5, Number(value) || 0))
      root.generation++
      return result(true, "ok", "", id)
    }

    function toggleStreamMute(id) {
      const node = resolveNode(id, allStreams(currentNodes()), "stream")
      if (!node) return unresolvedId(id, "Audio stream")
      const failure = mutationError(node, "stream", "Audio stream")
      if (failure) return failure
      if (!node.audio)
        return result(false, "unavailable", "Audio stream is unavailable", id)
      node.audio.muted = !node.audio.muted
      root.generation++
      return result(true, "ok", "", id)
    }

    // This is the only cross-capability route method Bluetooth needs. The
    // request is primitive-only; the current PipeWire target is resolved here.
    function routeBluetoothDevice(request) {
      const sinks = allSinks(currentNodes())
      for (let index = 0; index < sinks.length; index++) {
        const node = sinks[index]
        if (!Model.bluetoothSinkMatchesRequest(node, request)) continue
        return setNodeDefault(node, "sink", "setDefaultSink")
      }
      return result(
        false,
        backendReady() ? "stale-id" : "unavailable",
        "Bluetooth audio sink is unavailable")
    }
  }

  PwObjectTracker {
    id: nativeObjectTracker
    objects: root.active && root.backendOverride === null
      ? (Pipewire.nodes ? Pipewire.nodes.values : []) : []
  }

  Process {
    id: sinkAvailabilityProcess
    command: ["omarchy-audio-sink-availability"]
    running: root.active && root.backendOverride === null
      && implementation.backendReady() && !root.sinkAvailabilityResolved
    onStarted: {
      root.sinkAvailabilityProcessStarted = true
      root.sinkAvailabilityProcessGeneration =
        root.sinkAvailabilityRequestGeneration
    }
    onRunningChanged: {
      if (running) {
        if (!root.sinkAvailabilityProcessStarted) {
          root.sinkAvailabilityProcessStarted = true
          root.sinkAvailabilityProcessGeneration =
            root.sinkAvailabilityRequestGeneration
        }
        return
      }
      if (!root.active || root.backendOverride !== null
          || !implementation.backendReady()
          || root.sinkAvailabilityResolved) {
        root.sinkAvailabilityProcessStarted = false
        return
      }
      root.sinkAvailability = ({})
      root.sinkAvailabilityResolved = true
      root.sinkAvailabilityProcessStarted = false
    }
    onExited: function(exitCode, _exitStatus) {
      if (root.sinkAvailabilityProcessGeneration
          !== root.sinkAvailabilityRequestGeneration
          || !root.active || root.backendOverride !== null
          || !implementation.backendReady()) {
        root.sinkAvailabilityProcessStarted = false
        root.sinkAvailabilityResolved = false
        return
      }
      if (exitCode !== 0) {
        root.sinkAvailability = ({})
        root.sinkAvailabilityResolved = true
      }
      root.sinkAvailabilityProcessStarted = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.sinkAvailabilityProcessGeneration
            !== root.sinkAvailabilityRequestGeneration) return
        root.sinkAvailability = Model.parseSinkAvailability(text)
        root.sinkAvailabilityResolved = true
      }
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.active && root.backendOverride === null
    onTriggered: {
      if (!implementation.backendReady()) return
      if (!sinkAvailabilityProcess.running)
        root.invalidateSinkAvailability()
      if (!volumeSinkProcess.running
          && (!root.volumeSinkResolved
            || root.volumeSinkResolutionFailed
            || !implementation.volumeSinkNameMapped()))
        root.invalidateVolumeSink()
    }
  }

  Process {
    id: volumeSinkProcess
    command: ["omarchy-audio-output-sink"]
    running: root.active && root.backendOverride === null
      && implementation.backendReady() && !root.volumeSinkResolved
    onStarted: {
      root.volumeSinkProcessStarted = true
      root.volumeSinkProcessGeneration = root.volumeSinkRequestGeneration
    }
    onRunningChanged: {
      if (running) {
        if (!root.volumeSinkProcessStarted) {
          root.volumeSinkProcessStarted = true
          root.volumeSinkProcessGeneration = root.volumeSinkRequestGeneration
        }
        return
      }
      if (root.volumeSinkProcessDiscarded) {
        root.volumeSinkProcessDiscarded = false
        root.volumeSinkProcessStarted = false
        root.volumeSinkResolved = false
        return
      }
      if (!root.active || root.backendOverride !== null
          || !implementation.backendReady()
          || root.volumeSinkResolved) {
        root.volumeSinkProcessStarted = false
        return
      }
      root.volumeSinkName = ""
      root.volumeSinkResolutionFailed = true
      root.volumeSinkResolved = true
      root.volumeSinkProcessStarted = false
    }
    onExited: function(exitCode, _exitStatus) {
      if (root.volumeSinkProcessGeneration
          !== root.volumeSinkRequestGeneration
          || !root.active || root.backendOverride !== null
          || !implementation.backendReady()) {
        root.volumeSinkProcessDiscarded = true
        root.volumeSinkProcessStarted = false
        root.volumeSinkResolved = false
        return
      }
      if (exitCode !== 0) {
        root.volumeSinkName = ""
        root.volumeSinkResolutionFailed = true
        root.volumeSinkResolved = true
      }
      root.volumeSinkProcessStarted = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.volumeSinkProcessGeneration
            !== root.volumeSinkRequestGeneration) {
          root.volumeSinkProcessDiscarded = true
          root.volumeSinkResolved = false
          return
        }
        root.volumeSinkName = String(text).trim()
        root.volumeSinkResolutionFailed = root.volumeSinkName === ""
        root.volumeSinkResolved = true
      }
    }
  }

  Connections {
    target: root.active && root.backendOverride === null ? Pipewire : null
    function onDefaultAudioSinkChanged() { root.invalidateVolumeSink() }
    function onReadyChanged() {
      if (Pipewire.ready) {
        root.invalidateVolumeSink()
        root.invalidateSinkAvailability()
      } else {
        root.volumeSinkResolved = false
        root.sinkAvailabilityResolved = false
      }
    }
  }

  Connections {
    target: root.active && root.backendOverride === null ? Pipewire.nodes : null
    function onValuesChanged() {
      if (Pipewire.ready) {
        root.invalidateVolumeSink()
        root.invalidateSinkAvailability()
      }
    }
  }

  Connections {
    target: root.active && root.backendOverride === null ? Pipewire.links : null
    function onValuesChanged() {
      if (Pipewire.ready) root.invalidateVolumeSink()
    }
  }

  Connections {
    target: root.active && root.backendOverride === null ? Pipewire.linkGroups : null
    function onValuesChanged() {
      if (Pipewire.ready) root.invalidateVolumeSink()
    }
  }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: root.backendOverride === null
      ? implementation.monitorSource() : null
    enabled: root.active && root.peakMonitoringEnabled
      && root.backendOverride === null && implementation.backendReady()
      && implementation.monitorSource() !== null
  }
}
