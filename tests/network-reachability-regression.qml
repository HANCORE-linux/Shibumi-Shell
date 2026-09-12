pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel
import "network/NetworkReachabilityModel.js" as ReachabilityModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-reachability-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string counterPath:
    Qt.resolvedUrl("fixtures/network-reachability-invocations")
      .toString().replace(/^file:\/\//, "")
  property var workerCommand:
    ["/usr/bin/python3", fixturePath, counterPath]

  function connection(uuid, name, interfaceName, hardwareAddress, gateway) {
    return {
      schemaVersion: 1,
      connected: true,
      connectionUuid: uuid,
      connectionName: name,
      kind: "wired",
      interfaceName: interfaceName,
      hardwareAddress: hardwareAddress,
      metered: "no",
      addresses: [{ family: "ipv4", address: "192.0.2.10", prefix: 24 }],
      gateways: gateway === "" ? []
        : [{ family: "ipv4", address: gateway }],
      dnsServers: [{ family: "ipv4", address: "1.1.1.1" }],
      dnsDomains: [],
      rxBytes: 100,
      txBytes: 200,
      sampleMonotonicMs: 100,
      activeConnections: [{ uuid: uuid, kind: "wired",
        interfaceName: interfaceName, hardwareAddress: hardwareAddress }],
      wifi: {
        ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0
      },
      wired: { speedMbps: 1000, carrier: true },
      id: NetworkModel.connectionId(uuid),
      deviceId: NetworkModel.deviceId(
        "wired", hardwareAddress, interfaceName),
      downloadBytesPerSecond: 0,
      uploadBytesPerSecond: 0,
      generation: 1
    }
  }

  function fail(message) {
    console.error("network-reachability-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeTelemetry
    property bool available: true
    property bool connected: true
    property real generation: 1
    property var connectionSnapshot: root.connection(
      "11111111-1111-4111-8111-111111111111", "Wired", "eth0",
      "02:00:00:00:00:01", "192.0.2.1")
    property var telemetrySnapshot: connectionSnapshot
  }

  QtObject {
    id: fakeDevice
    property string typeToken: "wired"
    property string name: "eth0"
    property string address: "02:00:00:00:00:01"
    property bool connected: true
    property string stateToken: "connected"
    property bool managed: true
    property bool autoconnect: true
  }

  QtObject {
    id: fakeBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [fakeDevice]
  }

  QtObject {
    id: forgedReachability
    property bool available: true
    property string phase: "live"
    property real generation: 1
    property var reachabilitySnapshot: ({
      connectionId: fakeTelemetry.connectionSnapshot.id,
      deviceId: fakeTelemetry.connectionSnapshot.deviceId,
      interfaceName: fakeTelemetry.connectionSnapshot.interfaceName,
      gateway: "203.0.113.1",
      internetTarget: "1.1.1.1",
      routerStatus: "reply",
      internetStatus: "reply",
      routerSamples: [1],
      internetSamples: [2],
      routerLatencyMs: 1,
      internetLatencyMs: 2,
      internetPacketLossPercent: 0,
      sampleMonotonicMs: 1,
      schemaVersion: 1,
      generation: 1
    })
  }

  Item { id: owner }

  Network.NetworkReachability {
    id: reachability
    active: true
    networkTelemetry: fakeTelemetry
    commandOverride: root.workerCommand
    pollIntervalMs: 100000
    refreshTimeoutMs: 2000
    drainTimeoutMs: 500
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: fakeBackend
    networkTelemetry: fakeTelemetry
    networkReachability: reachability
  }

  Network.NetworkBackendAdapter {
    id: forgedAdapter
    active: true
    backendOverride: fakeBackend
    networkTelemetry: fakeTelemetry
    networkReachability: forgedReachability
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 160)
        return root.fail("reachability lifecycle timed out in phase "
          + root.phase + " (worker=" + reachability.phase + ", error="
          + reachability.errorCode + ", route="
          + reachability.routeFingerprint + ")")

      if (root.phase === 0) {
        if (!reachability.authorized) return
        if (!reachability.acquire(owner))
          return root.fail("owner could not acquire reachability")
        root.phase = 1
        root.ticks = 0
        return
      }

      const sample = reachability.reachabilitySnapshot
      if (root.phase === 1) {
        if (!reachability.available || !sample
            || sample.sampleMonotonicMs !== 1000) return
        if (sample.routerLatencyMs !== 10
            || sample.internetLatencyMs !== 20
            || sample.internetPacketLossPercent !== 0
            || !adapter.networkReachabilityAvailable
            || adapter.networkReachabilityDegraded
            || !adapter.reachabilitySnapshot
            || !forgedAdapter.networkReachabilityDegraded
            || forgedAdapter.networkReachabilityAvailable)
          return root.fail("first reachability projection was wrong")
        reachability.requestRefresh()
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (!sample || sample.sampleMonotonicMs !== 2000) return
        if (sample.routerSamples.length !== 2
            || sample.routerSamples[1] !== null
            || sample.routerLatencyMs !== 10
            || sample.internetLatencyMs !== 25
            || sample.internetPacketLossPercent !== 0)
          return root.fail("timeout history was wrong")
        reachability.requestRefresh()
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (!sample || sample.sampleMonotonicMs !== 3000) return
        if (sample.routerLatencyMs !== 15
            || sample.internetLatencyMs !== 25
            || sample.internetPacketLossPercent !== 33)
          return root.fail("rolling ping aggregate was wrong")
        fakeDevice.name = "enp5s0"
        fakeDevice.address = "02:00:00:00:00:02"
        fakeTelemetry.connectionSnapshot = root.connection(
          "22222222-2222-4222-8222-222222222222", "Dock", "enp5s0",
          "02:00:00:00:00:02", "198.51.100.1")
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (!sample || sample.sampleMonotonicMs !== 4000) return
        if (sample.interfaceName !== "enp5s0"
            || sample.routerSamples.length !== 1
            || sample.routerLatencyMs !== 40
            || sample.internetLatencyMs !== 50)
          return root.fail("route change did not reset history")
        reachability.requestRefresh()
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (reachability.phase !== "error") return
        if (reachability.available || reachability.reachabilitySnapshot !== null
            || reachability.errorCode === ""
            || !adapter.networkReachabilityDegraded
            || adapter.networkReachabilityAvailable)
          return root.fail("malformed worker output did not fail closed")
        reachability.requestRefresh()
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (!sample || sample.sampleMonotonicMs !== 6000) return
        if (sample.routerSamples.length !== 1
            || sample.routerLatencyMs !== 60
            || sample.internetLatencyMs !== 70)
          return root.fail("recovery reused stale history")
        root.workerCommand = [
          "/usr/bin/python3", root.fixturePath, root.counterPath, "replay"
        ]
        reachability.requestRefresh()
        root.phase = 7
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (reachability.phase !== "error") return
        if (reachability.available || reachability.reachabilitySnapshot !== null
            || reachability.errorCode !== "invalid-probe")
          return root.fail("replayed timestamp did not fail closed")
        root.workerCommand = [
          "/usr/bin/python3", root.fixturePath, root.counterPath
        ]
        reachability.requestRefresh()
        root.phase = 8
        root.ticks = 0
        return
      }

      if (root.phase === 8) {
        if (!sample || sample.sampleMonotonicMs !== 8000) return
        if (sample.routerSamples.length !== 1
            || sample.internetPacketLossPercent !== 0)
          return root.fail("replay recovery retained stale history")
        fakeTelemetry.available = false
        root.phase = 9
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (reachability.available || reachability.reachabilitySnapshot !== null
            || reachability.phase !== "unavailable")
          return root.fail("telemetry loss did not clear reachability")
        fakeTelemetry.available = true
        root.phase = 10
        root.ticks = 0
        return
      }

      if (root.phase === 10) {
        if (!sample || sample.sampleMonotonicMs !== 9000) return
        if (sample.routerSamples.length !== 1
            || sample.internetPacketLossPercent !== 0)
          return root.fail("telemetry recovery retained stale history")
        if (!reachability.release(owner) || reachability.clientCount !== 0
            || reachability.available)
          return root.fail("final lease release failed")
        console.log("network reachability regression passed")
        Qt.exit(0)
      }
    }
  }
}
