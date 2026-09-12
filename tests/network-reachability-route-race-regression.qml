pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-reachability-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string counterPath:
    Qt.resolvedUrl("fixtures/network-reachability-route-race-invocations")
      .toString().replace(/^file:\/\//, "")
  property var workerCommand: [
    "/usr/bin/python3", fixturePath, counterPath, "slow"
  ]

  function connection(uuid, interfaceName, hardware, gateway) {
    return {
      schemaVersion: 1, connected: true, connectionUuid: uuid,
      connectionName: "Wired", kind: "wired", interfaceName: interfaceName,
      hardwareAddress: hardware, metered: "no", addresses: [],
      gateways: [{ family: "ipv4", address: gateway }],
      dnsServers: [], dnsDomains: [], rxBytes: 0, txBytes: 0,
      sampleMonotonicMs: 1,
      activeConnections: [{ uuid: uuid, kind: "wired",
        interfaceName: interfaceName, hardwareAddress: hardware }],
      wifi: { ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0 },
      wired: { speedMbps: 1000, carrier: true },
      id: NetworkModel.connectionId(uuid),
      deviceId: NetworkModel.deviceId("wired", hardware, interfaceName)
    }
  }

  function fail(message) {
    console.error("network-reachability-route-race-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeTelemetry
    property bool available: true
    property var connectionSnapshot: root.connection(
      "11111111-1111-4111-8111-111111111111", "eth0",
      "02:00:00:00:00:01", "192.0.2.1")
  }

  Item { id: owner }

  Network.NetworkReachability {
    id: reachability
    active: true
    networkTelemetry: fakeTelemetry
    commandOverride: root.workerCommand
    pollIntervalMs: 100000
    refreshTimeoutMs: 5000
    drainTimeoutMs: 300
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 140)
        return root.fail("route race timed out in phase " + root.phase)
      if (root.phase === 0) {
        if (!reachability.authorized) return
        if (!reachability.acquire(owner))
          return root.fail("route-race owner could not acquire")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (!reachability.workerRunning
            || !reachability.workerOutputComplete) return
        root.workerCommand = [
          "/usr/bin/python3", root.fixturePath, root.counterPath
        ]
        fakeTelemetry.connectionSnapshot = root.connection(
          "22222222-2222-4222-8222-222222222222", "enp5s0",
          "02:00:00:00:00:02", "198.51.100.1")
        root.phase = 2
        root.ticks = 0
        return
      }
      const sample = reachability.reachabilitySnapshot
      if (!reachability.available || !sample
          || sample.sampleMonotonicMs !== 2000) return
      if (sample.interfaceName !== "enp5s0"
          || sample.gateway !== "198.51.100.1"
          || sample.routerSamples.length !== 1
          || sample.routerStatus !== "timeout"
          || sample.internetLatencyMs !== 30)
        return root.fail("late old-route output crossed the identity boundary")
      reachability.active = false
      console.log("network reachability route race regression passed")
      Qt.exit(0)
    }
  }
}
