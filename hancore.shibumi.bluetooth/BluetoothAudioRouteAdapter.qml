pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "BluetoothModel.js" as Model

// Focused transitional seam for Bluetooth audio routing. The adapter owns
// PipeWire object access while Bluetooth passes only a primitive route request.
// Step 4A can replace this adapter with the Shibumi Audio service without
// changing Bluetooth discovery, device actions, or presentation.
Item {
  id: root

  // Tests inject a side-effect-free node list and route sink.
  property var nodesOverride: null
  property var outputOverride: null
  property var readyOverride: null

  readonly property bool ready: readyOverride !== null
    ? readyOverride === true
    : Pipewire.nodes !== null && Pipewire.nodes !== undefined
  readonly property var nodes: nodesOverride !== null
    ? nodesOverride
    : (Pipewire.nodes ? Pipewire.nodes.values : [])

  function audioSinks() {
    const sinks = []
    if (!ready) return sinks
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i]
      if (node && node.isSink && !node.isStream) sinks.push(node)
    }
    return sinks
  }

  function sinkForDevice(request) {
    const sinks = audioSinks()
    for (let i = 0; i < sinks.length; i++) {
      if (Model.bluetoothSinkMatchesDevice(sinks[i], request))
        return sinks[i]
    }
    return null
  }

  function actionResult(ok, code, message, entityId) {
    return {
      ok: ok === true,
      code: String(code || (ok ? "ok" : "unavailable")),
      message: String(message || ""),
      entityId: String(entityId || ""),
      generation: 0
    }
  }

  function setDefaultSink(sink) {
    if (!ready)
      return actionResult(false, "unavailable", "Bluetooth audio is unavailable")
    if (!sink || sink.ready === false)
      return actionResult(false, "unavailable", "Bluetooth audio sink is unavailable")
    const rawId = sink.id === undefined || sink.id === null
      ? "" : String(sink.id).trim()
    if (!/^[0-9]+$/.test(rawId))
      return actionResult(false, "stale-id", "Bluetooth audio sink is unavailable")
    const entityId = "sink:" + rawId
    if (outputOverride !== null) {
      if (typeof outputOverride.setDefaultSink !== "function")
        return actionResult(
          false, "unsupported", "Audio backend action is unavailable", entityId)
      const delegated = outputOverride.setDefaultSink(entityId)
      if (delegated && typeof delegated === "object"
          && typeof delegated.ok === "boolean")
        return delegated
      if (delegated === true)
        return actionResult(true, "ok", "", entityId)
      return actionResult(
        false, "unavailable", "Audio backend action failed", entityId)
    }
    Pipewire.preferredDefaultAudioSink = sink
    Quickshell.execDetached([
      "omarchy-audio-output-set-default",
      String(sink.id),
      String(sink.name || "")
    ])
    return actionResult(true, "ok", "", entityId)
  }

  // Narrow cross-capability method. The request contains only stable device
  // identity and labels; PipeWire objects never cross back into Bluetooth.
  function routeBluetoothDevice(request) {
    if (!ready)
      return actionResult(false, "unavailable", "Bluetooth audio is unavailable")
    const sink = sinkForDevice(request)
    return sink
      ? setDefaultSink(sink)
      : actionResult(false, "stale-id", "Bluetooth audio sink is unavailable")
  }
}
