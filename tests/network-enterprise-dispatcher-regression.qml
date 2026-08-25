pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property bool connected: false
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-enterprise-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string capturePath:
    Qt.resolvedUrl("fixtures/network-enterprise-capture.json")
      .toString().replace(/^file:\/\//, "")
  property var fixtureCommand: [
    "/usr/bin/python3", fixturePath, capturePath, "no-completion"
  ]
  property var successCommand: ["/usr/bin/python3", fixturePath, capturePath]
  readonly property string deviceId: NetworkModel.deviceId(
    "wifi", "02:00:00:00:00:01", "wlan0")
  readonly property string networkId: NetworkModel.networkId(
    deviceId, "Corp", "wpa2-eap")

  function fail(message) {
    console.error("network-enterprise-dispatcher-regression:", message)
    Qt.exit(1)
  }

  function credentials(changes) {
    return Object.assign({
      method: "peap-mschapv2",
      identity: "user@example.test",
      password: "transient enterprise secret",
      serverDomain: "radius.example.test"
    }, changes || {})
  }

  function request() {
    return { entityId: root.networkId, generation: adapter.generation }
  }

  QtObject {
    id: adapter
    property bool active: true
    property int schemaVersion: 1
    property real generation: 1
    property var backendSnapshot: ({
      schemaVersion: 1, available: true, degraded: false,
      connectivity: root.connected ? "full" : "none", generation: generation
    })
    property var radioSnapshot: ({
      schemaVersion: 1, id: NetworkModel.radioId(), available: true,
      hardwareEnabled: true, enabled: true, generation: generation
    })
    property var deviceSnapshots: [{
      schemaVersion: 1, id: root.deviceId, type: "wifi", name: "wlan0",
      address: "02:00:00:00:00:01", connected: root.connected,
      state: root.connected ? "connected" : "disconnected",
      managed: true, autoconnect: true, ambiguous: false,
      generation: generation
    }]
    property var networkSnapshots: [{
      schemaVersion: 1, id: root.networkId, deviceId: root.deviceId,
      ssid: "Corp", security: "wpa2-eap", connected: root.connected,
      known: false, state: root.connected ? "connected" : "disconnected",
      stateChanging: false, signal: 80, profileCount: 0,
      validProfileCount: 0, canConnect: false, canConnectWithPsk: false,
      canDisconnect: root.connected, canForget: false, ambiguous: false,
      generation: generation
    }]
    property var profileSnapshots: []
    // A wired primary must not control Enterprise action completion.
    property var connectionDetailsSnapshot: ({
      schemaVersion: 1, id: "wired-primary", uuid: "", name: "Ethernet",
      deviceId: "wired-primary", kind: "wired", interfaceName: "eth0",
      hardwareAddress: "02:00:00:00:00:02", metered: "no",
      addresses: [], gateways: [],
      wifi: { ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0 },
      wired: { speedMbps: 1000, carrier: true }, generation: generation
    })

    function enterpriseConnectionDescriptor(action) {
      if (action.entityId !== root.networkId
          || action.generation !== generation) return {
        ok: false, code: "stale-generation", message: "",
        entityId: action.entityId, generation: generation, descriptor: null
      }
      return {
        ok: true, code: "accepted", message: "",
        entityId: action.entityId, generation: generation,
        descriptor: {
          deviceId: root.deviceId,
          entityId: root.networkId,
          generation: generation,
          hardwareAddress: "02:00:00:00:00:01",
          interfaceName: "wlan0",
          security: "wpa2-eap",
          ssidHex: "436F7270"
        }
      }
    }
  }

  Network.NetworkEnterpriseDispatcher {
    id: dispatcher
    active: true
    networkAdapter: adapter
    commandOverride: root.fixtureCommand
    workerTimeoutMs: 2000
    drainTimeoutMs: 200
  }

  Network.NetworkActionCoordinator {
    id: coordinator
    active: true
    networkAdapter: adapter
    enterpriseDispatcher: dispatcher
    actionTimeoutMs: 800
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 240)
        return root.fail("Enterprise lifecycle timed out in phase " + root.phase
          + " (coordinator=" + coordinator.phase + ", dispatcher="
          + dispatcher.phase + ")")

      if (root.phase === 0) {
        if (!dispatcher.authorized || !coordinator.authorized
            || !dispatcher.available) return
        const invalid = coordinator.connectNetworkEnterprise(
          root.request(), root.credentials({ serverDomain: "example" }))
        if (invalid.accepted || invalid.code !== "invalid"
            || dispatcher.running)
          return root.fail("invalid Enterprise credentials reached dispatcher")
        const result = coordinator.connectNetworkEnterprise(
          root.request(), root.credentials())
        const busy = coordinator.connectNetworkEnterprise(
          root.request(), root.credentials())
        if (!result.accepted || result.code !== "accepted"
            || "identity" in result || "password" in result
            || busy.accepted || busy.code !== "busy"
            || coordinator.phase !== "pending")
          return root.fail("Enterprise action admission was wrong: result="
            + JSON.stringify(result) + " busy=" + JSON.stringify(busy)
            + " coordinator=" + coordinator.phase
            + " dispatcher=" + dispatcher.phase)
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (dispatcher.running) return
        root.connected = true
        adapter.generation++
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (coordinator.phase === "succeeded")
          return root.fail("aggregate or wired-primary state completed action")
        if (coordinator.phase === "pending") return
        if (coordinator.phase !== "failed" || coordinator.failureCode !== "timeout")
          return root.fail("completion-free action did not time out safely")
        if (!coordinator.clearResult())
          return root.fail("completion-free timeout did not clear")
        root.connected = false
        adapter.generation++
        dispatcher.commandOverride = root.successCommand
        const result = coordinator.connectNetworkEnterprise(
          root.request(), root.credentials())
        if (!result.accepted) return root.fail("exact-completion run was rejected")
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (dispatcher.running) return
        if (!dispatcher.completionSnapshot)
          return root.fail("valid helper completion was not published")
        adapter.generation++
        root.phase = 30
        root.ticks = 0
        return
      }

      if (root.phase === 30) {
        if (coordinator.phase !== "pending")
          return root.fail("unrelated generation completed disconnected target")
        root.connected = true
        adapter.generation++
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (coordinator.phase !== "succeeded") return
        if (!coordinator.actionSnapshot
            || coordinator.actionSnapshot.kind !== "connect-enterprise"
            || coordinator.actionSnapshot.code !== "completed"
            || dispatcher.completionSnapshot !== null)
          return root.fail("exact Enterprise completion was wrong")
        if (!coordinator.clearResult())
          return root.fail("completed Enterprise action did not clear")
        root.connected = false
        adapter.generation++
        dispatcher.commandOverride = ["/shibumi/missing-enterprise-helper"]
        const result = coordinator.connectNetworkEnterprise(
          root.request(), root.credentials())
        if (!result.accepted) return root.fail("start-failure run was rejected")
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (coordinator.phase !== "failed") return
        if (coordinator.failureCode !== "unavailable")
          return root.fail("pre-start failure remained uncertain")
        console.log("network enterprise dispatcher regression passed")
        Qt.exit(0)
      }
    }
  }
}
