pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "AudioModel.js" as Model

// Test-only/native preparation seam for Step 4A. It is not instantiated by
// production Service.qml until the native Audio activation commit. PipeWire
// objects stay private here; callers receive primitive snapshots and typed
// action results, and every mutation resolves the current object by ID.
Item {
  id: root

  property bool active: false
  property var backendOverride: null
  property int generation: 0

  readonly property bool ready: active && (backendOverride === null
    || backendValue("ready", true) !== false)
  readonly property real outputVolume: currentSink()
    && currentSink().audio && currentSink().audio.volume !== undefined
    ? Number(currentSink().audio.volume) : 0
  readonly property bool outputMuted: currentSink()
    && currentSink().audio && currentSink().audio.muted === true
  readonly property real inputVolume: currentSource()
    && currentSource().audio && currentSource().audio.volume !== undefined
    ? Number(currentSource().audio.volume) : 0
  readonly property bool inputMuted: currentSource()
    && currentSource().audio && currentSource().audio.muted === true

  readonly property var audioSinks: snapshotList(
    filterSinks(currentNodes()), "sink", currentSink())
  readonly property var audioSources: snapshotList(
    filterSources(currentNodes()), "source", currentSource())
  readonly property var audioStreams: snapshotList(
    filterStreams(currentNodes()), "stream", null)
  readonly property var sinkSnapshot: Model.snapshot(currentSink(), "sink", true)
  readonly property var sourceSnapshot: Model.snapshot(
    currentSource(), "source", true)

  function currentNodes() {
    if (!active) return []
    if (backendOverride !== null) return backendValue("nodes", [])
    return Pipewire.nodes ? Pipewire.nodes.values : []
  }

  function currentSink() {
    if (!active) return null
    return backendOverride !== null
      ? backendValue("defaultAudioSink", null)
      : Pipewire.defaultAudioSink
  }

  function currentSource() {
    if (!active) return null
    return backendOverride !== null
      ? backendValue("defaultAudioSource", null)
      : Pipewire.defaultAudioSource
  }

  function backendValue(name, fallback) {
    if (backendOverride !== null && backendOverride[name] !== undefined)
      return backendOverride[name]
    return fallback
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

  function resolveNode(id, nodes, kind) {
    const key = String(id || "")
    if (!key) return null
    for (let index = 0; index < nodes.length; index++) {
      if (Model.stableNodeId(nodes[index], kind) === key) return nodes[index]
    }
    return null
  }

  function result(ok, code, message, entityId) {
    return Model.actionResult(ok, code, message, entityId, generation)
  }

  function setNodeDefault(node, kind, propertyName) {
    const entityId = Model.stableNodeId(node, kind)
    if (!node || !entityId)
      return result(false, "stale-id", "Audio node is unavailable")
    if (backendOverride !== null
        && typeof backendOverride[propertyName] === "function") {
      backendOverride[propertyName](node)
    } else if (propertyName === "setDefaultSink") {
      Pipewire.preferredDefaultAudioSink = node
    } else {
      Pipewire.preferredDefaultAudioSource = node
    }
    return result(true, "ok", "", entityId)
  }

  function setDefaultSink(id) {
    const node = resolveNode(id, filterSinks(currentNodes()), "sink")
    return setNodeDefault(node, "sink", "setDefaultSink")
  }

  function setDefaultSource(id) {
    const node = resolveNode(id, filterSources(currentNodes()), "source")
    return setNodeDefault(node, "source", "setDefaultSource")
  }

  function setOutputVolume(value) {
    const sink = currentSink()
    if (!sink || !sink.audio) return result(false, "unavailable", "Output is unavailable")
    sink.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
    return result(true, "ok")
  }

  function toggleOutputMute() {
    const sink = currentSink()
    if (!sink || !sink.audio) return result(false, "unavailable", "Output is unavailable")
    sink.audio.muted = !sink.audio.muted
    return result(true, "ok")
  }

  function setInputVolume(value) {
    const source = currentSource()
    if (!source || !source.audio) return result(false, "unavailable", "Input is unavailable")
    source.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
    return result(true, "ok")
  }

  function toggleInputMute() {
    const source = currentSource()
    if (!source || !source.audio) return result(false, "unavailable", "Input is unavailable")
    source.audio.muted = !source.audio.muted
    return result(true, "ok")
  }

  function setStreamVolume(id, value) {
    const node = resolveNode(id, filterStreams(currentNodes()), "stream")
    if (!node || !node.audio)
      return result(false, "stale-id", "Audio stream is unavailable", id)
    node.audio.volume = Math.max(0, Math.min(1.5, Number(value) || 0))
    return result(true, "ok", "", id)
  }

  function toggleStreamMute(id) {
    const node = resolveNode(id, filterStreams(currentNodes()), "stream")
    if (!node || !node.audio)
      return result(false, "stale-id", "Audio stream is unavailable", id)
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
    return result(false, "stale-id", "Bluetooth audio sink is unavailable")
  }
}
