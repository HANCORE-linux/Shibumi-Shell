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

  readonly property var nodes: nodesOverride !== null
    ? nodesOverride
    : (Pipewire.nodes ? Pipewire.nodes.values : [])

  function audioSinks() {
    const sinks = []
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

  function setDefaultSink(sink) {
    if (!sink || sink.ready === false) return false
    if (outputOverride !== null
        && typeof outputOverride.setDefaultSink === "function") {
      outputOverride.setDefaultSink(sink)
      return true
    }
    Pipewire.preferredDefaultAudioSink = sink
    if (sink.id === undefined || !sink.name) return true
    Quickshell.execDetached([
      "omarchy-audio-output-set-default",
      String(sink.id),
      String(sink.name)
    ])
    return true
  }

  // Narrow cross-capability method. The request contains only stable device
  // identity and labels; PipeWire objects never cross back into Bluetooth.
  function routeBluetoothDevice(request) {
    const sink = sinkForDevice(request)
    return sink ? setDefaultSink(sink) : false
  }
}
