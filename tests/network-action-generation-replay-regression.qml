pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  readonly property string radioId: 'shibumi-network-v1:["radio","wifi"]'
  readonly property string deviceId: 'shibumi-network-v1:["device","wifi","replay"]'
  readonly property string networkId: 'shibumi-network-v1:["network","replay"]'

  function fail(message) {
    console.error("network-action-generation-replay-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeAdapter
    property bool active: true
    property int schemaVersion: 1
    property int backendSchemaVersion: 1
    property real generation: 4
    property string connectivity: "full"
    property int dispatchCalls: 0
    property bool malformed: false
    property bool connected: false
    property var backendSnapshot: ({
      schemaVersion: backendSchemaVersion, available: true, degraded: false,
      connectivity: connectivity, generation: generation
    })
    property var radioSnapshot: ({
      schemaVersion: 1, id: root.radioId, available: true,
      hardwareEnabled: true, enabled: true, generation: generation
    })
    property var deviceSnapshots: [{
      schemaVersion: 1, id: root.deviceId, type: "wifi", name: "wlan-replay",
      address: "AA:BB:CC:DD:EE:60", connected: connected,
      state: connected ? "connected" : "disconnected", managed: true,
      autoconnect: true, ambiguous: false, generation: generation
    }]
    property var networkSnapshots: malformed ? [{ id: root.networkId }] : [{
      schemaVersion: 1, id: root.networkId, deviceId: root.deviceId,
      ssid: "Replay", security: "open", connected: connected,
      known: false, state: connected ? "connected" : "disconnected",
      stateChanging: false, signal: 50, profileCount: 0,
      validProfileCount: 0, canConnect: !connected,
      canConnectWithPsk: false, canDisconnect: connected,
      canForget: false, ambiguous: false, generation: generation
    }]
    property var profileSnapshots: []
    function connectNetwork(_request) {
      dispatchCalls++
      return { ok: true, code: "accepted", message: "",
        entityId: root.networkId, generation: generation }
    }
  }

  Network.NetworkActionCoordinator {
    id: coordinator
    active: true
    networkAdapter: fakeAdapter
    actionTimeoutMs: 300
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 80)
        return root.fail("generation replay regression timed out")
      if (root.phase === 0) {
        if (!coordinator.authorized) return
        fakeAdapter.backendSchemaVersion = 2
        let rejected = coordinator.connectNetwork({
          entityId: root.networkId, generation: fakeAdapter.generation
        })
        if (rejected.accepted || fakeAdapter.dispatchCalls !== 0)
          return root.fail("invalid backend schema reached dispatch")
        fakeAdapter.backendSchemaVersion = 1
        fakeAdapter.schemaVersion = 2
        rejected = coordinator.connectNetwork({
          entityId: root.networkId, generation: fakeAdapter.generation
        })
        if (rejected.accepted || fakeAdapter.dispatchCalls !== 0)
          return root.fail("invalid adapter schema reached dispatch")
        fakeAdapter.schemaVersion = 1
        fakeAdapter.connectivity = "forged"
        rejected = coordinator.connectNetwork({
          entityId: root.networkId, generation: fakeAdapter.generation
        })
        if (rejected.accepted || fakeAdapter.dispatchCalls !== 0)
          return root.fail("invalid connectivity reached dispatch")
        fakeAdapter.connectivity = "full"
        const result = coordinator.connectNetwork({
          entityId: root.networkId, generation: fakeAdapter.generation
        })
        if (!result.accepted || !coordinator.busy)
          return root.fail("replay action was not pending")
        fakeAdapter.malformed = true
        fakeAdapter.generation = 10
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (!coordinator.busy
            || coordinator.actionSnapshot.observedGeneration !== 10)
          return root.fail("malformed high-water generation was not retained")
        fakeAdapter.connected = true
        fakeAdapter.malformed = false
        fakeAdapter.generation = 6
        root.phase = 2
        root.ticks = 0
        return
      }
      if (coordinator.phase === "succeeded")
        return root.fail("replayed lower generation completed the action")
      if (coordinator.busy) {
        const parallel = coordinator.connectNetwork({
          entityId: root.networkId, generation: fakeAdapter.generation
        })
        if (parallel.accepted || parallel.code !== "busy")
          return root.fail("replayed topology released the pending barrier")
        return
      }
      if (coordinator.phase !== "failed"
          || coordinator.failureCode !== "timeout")
        return root.fail("replayed topology did not settle by timeout")
      coordinator.active = false
      console.log("network action generation replay regression passed")
      Qt.exit(0)
    }
  }
}
