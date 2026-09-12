pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  readonly property string radioId: 'shibumi-network-v1:["radio","wifi"]'
  readonly property string deviceId: 'shibumi-network-v1:["device","wifi","throw"]'
  readonly property string networkId: 'shibumi-network-v1:["network","throw"]'

  function fail(message) {
    console.error("network-action-throwing-result-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeAdapter
    property bool active: true
    property int schemaVersion: 1
    property real generation: 4
    property int dispatchCalls: 0
    property var backendSnapshot: ({ schemaVersion: 1, available: true,
      degraded: false, connectivity: "full", generation: generation })
    property var radioSnapshot: ({ schemaVersion: 1, id: root.radioId,
      available: true, hardwareEnabled: true, enabled: true,
      generation: generation })
    property var deviceSnapshots: [{ schemaVersion: 1, id: root.deviceId,
      type: "wifi", name: "wlan-throw", address: "AA:BB:CC:DD:EE:70",
      connected: false, state: "disconnected", managed: true,
      autoconnect: true, ambiguous: false, generation: generation }]
    property var networkSnapshots: [{ schemaVersion: 1, id: root.networkId,
      deviceId: root.deviceId, ssid: "Throw", security: "open",
      connected: false, known: false, state: "disconnected",
      stateChanging: false, signal: 50, profileCount: 0,
      validProfileCount: 0, canConnect: true, canConnectWithPsk: false,
      canDisconnect: false, canForget: false, ambiguous: false,
      generation: generation }]
    property var profileSnapshots: []
    function connectNetwork(_request) {
      dispatchCalls++
      const result = {
        code: "accepted", message: "", entityId: root.networkId,
        generation: generation
      }
      Object.defineProperty(result, "ok", {
        enumerable: true,
        get: function() { throw new Error("throwing result getter") }
      })
      return result
    }
  }

  Network.NetworkActionCoordinator {
    id: coordinator
    active: true
    networkAdapter: fakeAdapter
    actionTimeoutMs: 250
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 80)
        return root.fail("throwing result regression timed out")
      if (root.phase === 0) {
        if (!coordinator.authorized) return
        let generationReads = 0
        const request = { entityId: root.networkId }
        Object.defineProperty(request, "generation", {
          enumerable: true,
          get: function() {
            generationReads++
            if (generationReads > 1) throw new Error("second generation read")
            return fakeAdapter.generation
          }
        })
        const result = coordinator.connectNetwork(request)
        if (result.accepted || result.code !== "uncertain"
            || !coordinator.busy || fakeAdapter.dispatchCalls !== 1
            || generationReads !== 1)
          return root.fail("throwing result bypassed uncertain barrier: "
            + JSON.stringify({ result: result, busy: coordinator.busy,
              calls: fakeAdapter.dispatchCalls, reads: generationReads }))
        const parallel = coordinator.connectNetwork({
          entityId: root.networkId, generation: fakeAdapter.generation
        })
        if (parallel.accepted || parallel.code !== "busy"
            || fakeAdapter.dispatchCalls !== 1)
          return root.fail("throwing result allowed a second dispatch")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (coordinator.busy) return
      if (coordinator.phase !== "failed"
          || coordinator.failureCode !== "timeout")
        return root.fail("throwing result did not settle by timeout")
      coordinator.active = false
      console.log("network action throwing result regression passed")
      Qt.exit(0)
    }
  }
}
