pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
  property var backendOverride: null
  property int generation: 0

  readonly property bool ready: implementation.ready()
  readonly property real outputVolume: implementation.outputVolume()
  readonly property bool outputMuted: implementation.outputMuted()
  readonly property real inputVolume: implementation.inputVolume()
  readonly property bool inputMuted: implementation.inputMuted()
  readonly property var audioSinks: implementation.audioSinks()
  readonly property var audioSources: implementation.audioSources()
  readonly property var audioStreams: implementation.audioStreams()
  readonly property var sinkSnapshot: implementation.sinkSnapshot()
  readonly property var sourceSnapshot: implementation.sourceSnapshot()

  // Public capability surface: primitive snapshots and typed action results.
  // Raw PipeWire nodes remain reachable only through the implementation id.
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

    function ready() {
      return backendReady()
    }

    function outputVolume() {
      const sink = currentSink()
      return sink && sink.audio && sink.audio.volume !== undefined
        ? Number(sink.audio.volume) : 0
    }

    function outputMuted() {
      const sink = currentSink()
      return sink && sink.audio && sink.audio.muted === true
    }

    function inputVolume() {
      const source = currentSource()
      return source && source.audio && source.audio.volume !== undefined
        ? Number(source.audio.volume) : 0
    }

    function inputMuted() {
      const source = currentSource()
      return source && source.audio && source.audio.muted === true
    }

    function filterSinks(nodes) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (node && node.isSink && !node.isStream) result.push(node)
      }
      return result
    }

    function filterSources(nodes) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (Model.isAudioSource(node)) result.push(node)
      }
      return result
    }

    function filterStreams(nodes) {
      const result = []
      for (let index = 0; index < nodes.length; index++) {
        const node = nodes[index]
        if (Model.isPlaybackStream(node) && node.audio) result.push(node)
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
      return snapshotList(filterSinks(currentNodes()), "sink", currentSink())
    }

    function audioSources() {
      return snapshotList(
        filterSources(currentNodes()), "source", currentSource())
    }

    function audioStreams() {
      return snapshotList(filterStreams(currentNodes()), "stream", null)
    }

    function sinkSnapshot() {
      return Model.snapshot(currentSink(), "sink", true)
    }

    function sourceSnapshot() {
      return Model.snapshot(currentSource(), "source", true)
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
      if (!backendReady() || !node || node.ready === false)
        return result(false, "unavailable", label + " is unavailable")
      const entityId = Model.stableNodeId(node, kind)
      if (!entityId)
        return result(false, "stale-id", label + " is unavailable")
      return null
    }

    function setNodeDefault(node, kind, propertyName) {
      const failure = mutationError(node, kind, "Audio node")
      if (failure) return failure
      const entityId = Model.stableNodeId(node, kind)
      if (root.backendOverride !== null) {
        if (typeof root.backendOverride[propertyName] !== "function")
          return result(false, "unsupported", "Audio backend action is unavailable", entityId)
        root.backendOverride[propertyName](node)
      } else if (propertyName === "setDefaultSink") {
        Pipewire.preferredDefaultAudioSink = node
      } else {
        Pipewire.preferredDefaultAudioSource = node
      }
      return result(true, "ok", "", entityId)
    }

    function setDefaultSink(id) {
      const node = resolveNode(id, filterSinks(currentNodes()), "sink")
      if (!node) return unresolvedId(id, "Audio sink")
      return setNodeDefault(node, "sink", "setDefaultSink")
    }

    function setDefaultSource(id) {
      const node = resolveNode(id, filterSources(currentNodes()), "source")
      if (!node) return unresolvedId(id, "Audio source")
      return setNodeDefault(node, "source", "setDefaultSource")
    }

    function setOutputVolume(value) {
      const sink = currentSink()
      if (!sink || !sink.audio)
        return result(false, "unavailable", "Output is unavailable")
      const failure = mutationError(sink, "sink", "Output")
      if (failure) return failure
      sink.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
      return result(true, "ok", "", Model.stableNodeId(sink, "sink"))
    }

    function toggleOutputMute() {
      const sink = currentSink()
      const failure = mutationError(sink, "sink", "Output")
      if (failure) return failure
      if (!sink.audio)
        return result(false, "unavailable", "Output is unavailable")
      sink.audio.muted = !sink.audio.muted
      return result(true, "ok", "", Model.stableNodeId(sink, "sink"))
    }

    function setInputVolume(value) {
      const source = currentSource()
      if (!source || !source.audio)
        return result(false, "unavailable", "Input is unavailable")
      const failure = mutationError(source, "source", "Input")
      if (failure) return failure
      source.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
      return result(true, "ok", "", Model.stableNodeId(source, "source"))
    }

    function toggleInputMute() {
      const source = currentSource()
      const failure = mutationError(source, "source", "Input")
      if (failure) return failure
      if (!source.audio)
        return result(false, "unavailable", "Input is unavailable")
      source.audio.muted = !source.audio.muted
      return result(true, "ok", "", Model.stableNodeId(source, "source"))
    }

    function setStreamVolume(id, value) {
      const node = resolveNode(id, filterStreams(currentNodes()), "stream")
      if (!node) return unresolvedId(id, "Audio stream")
      const failure = mutationError(node, "stream", "Audio stream")
      if (failure) return failure
      if (!node.audio)
        return result(false, "unavailable", "Audio stream is unavailable", id)
      node.audio.volume = Math.max(0, Math.min(1.5, Number(value) || 0))
      return result(true, "ok", "", id)
    }

    function toggleStreamMute(id) {
      const node = resolveNode(id, filterStreams(currentNodes()), "stream")
      if (!node) return unresolvedId(id, "Audio stream")
      const failure = mutationError(node, "stream", "Audio stream")
      if (failure) return failure
      if (!node.audio)
        return result(false, "unavailable", "Audio stream is unavailable", id)
      node.audio.muted = !node.audio.muted
      return result(true, "ok", "", id)
    }

    // This is the only cross-capability route method Bluetooth needs. The
    // request is primitive-only; the current PipeWire target is resolved here.
    function routeBluetoothDevice(request) {
      const sinks = filterSinks(currentNodes())
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
}
