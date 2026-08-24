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
    Qt.resolvedUrl("fixtures/network-reachability-stream-invocations")
      .toString().replace(/^file:\/\//, "")
  property var workerCommand: [
    "/usr/bin/python3", fixturePath, counterPath, "flood-stdout"
  ]

  function fail(message) {
    console.error("network-reachability-stream-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeTelemetry
    property bool available: true
    property var connectionSnapshot: {
      const uuid = "11111111-1111-4111-8111-111111111111"
      const hardware = "02:00:00:00:00:01"
      return {
        schemaVersion: 1, connected: true, connectionUuid: uuid,
        connectionName: "Wired", kind: "wired", interfaceName: "eth0",
        hardwareAddress: hardware, metered: "no", addresses: [],
        gateways: [{ family: "ipv4", address: "192.0.2.1" }],
        dnsServers: [], dnsDomains: [], rxBytes: 0, txBytes: 0,
        sampleMonotonicMs: 1,
        wifi: { ssid: "", ssidHex: "", signal: 0,
          frequencyMhz: 0, bitrateKbps: 0 },
        wired: { speedMbps: 1000, carrier: true },
        id: NetworkModel.connectionId(uuid),
        deviceId: NetworkModel.deviceId("wired", hardware, "eth0")
      }
    }
  }

  Item { id: owner }

  Network.NetworkReachability {
    id: reachability
    active: true
    networkTelemetry: fakeTelemetry
    commandOverride: root.workerCommand
    pollIntervalMs: 100000
    refreshTimeoutMs: 3000
    drainTimeoutMs: 300
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 120)
        return root.fail("bounded stream test timed out in phase " + root.phase)
      if (root.phase === 0) {
        if (!reachability.authorized) return
        if (!reachability.acquire(owner))
          return root.fail("stream owner could not acquire")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (reachability.workerRunning) return
        if (reachability.phase !== "error"
            || reachability.errorCode !== "invalid-line"
            || reachability.available)
          return root.fail("newline-free stdout flood did not fail bounded")
        root.workerCommand = [
          "/usr/bin/python3", root.fixturePath, root.counterPath,
          "malformed-slow"
        ]
        reachability.requestRefresh()
        root.phase = 2
        root.ticks = 0
        return
      }
      if (root.phase === 2) {
        if (reachability.phase !== "error"
            || !reachability.workerRunning) return
        if (reachability.available || reachability.reachabilitySnapshot !== null)
          return root.fail("malformed draining worker published state")
        root.workerCommand = [
          "/usr/bin/python3", root.fixturePath, root.counterPath,
          "flood-stderr"
        ]
        if (!reachability.requestRefresh())
          return root.fail("refresh was not queued during failed drain")
        root.phase = 3
        root.ticks = 0
        return
      }
      if (!reachability.available
          || !reachability.reachabilitySnapshot) return
      if (reachability.reachabilitySnapshot.sampleMonotonicMs !== 3000
          || reachability.reachabilitySnapshot.routerLatencyMs !== 3
          || reachability.reachabilitySnapshot.internetLatencyMs !== 4)
        return root.fail("queued drain recovery changed the valid snapshot")
      reachability.active = false
      console.log("network reachability stream regression passed")
      Qt.exit(0)
    }
  }
}
