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
  property string slowCounterPath:
    Qt.resolvedUrl("fixtures/network-reachability-slow-invocations")
      .toString().replace(/^file:\/\//, "")
  property string nextCounterPath:
    Qt.resolvedUrl("fixtures/network-reachability-next-invocations")
      .toString().replace(/^file:\/\//, "")
  readonly property var owner: ownerLoader.item

  function fail(message) {
    console.error("network-reachability-lifecycle-regression:", message)
    Qt.exit(1)
  }

  function connection() {
    const uuid = "11111111-1111-4111-8111-111111111111"
    const hardware = "02:00:00:00:00:01"
    return {
      schemaVersion: 1, connected: true, connectionUuid: uuid,
      connectionName: "Wired", kind: "wired", interfaceName: "eth0",
      hardwareAddress: hardware, metered: "no",
      addresses: [{ family: "ipv4", address: "192.0.2.10", prefix: 24 }],
      gateways: [{ family: "ipv4", address: "192.0.2.1" }],
      dnsServers: [], dnsDomains: [], rxBytes: 0, txBytes: 0,
      sampleMonotonicMs: 1,
      activeConnections: [{ uuid: uuid, kind: "wired",
        interfaceName: "eth0", hardwareAddress: hardware }],
      wifi: { ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0 },
      wired: { speedMbps: 1000, carrier: true },
      id: NetworkModel.connectionId(uuid),
      deviceId: NetworkModel.deviceId("wired", hardware, "eth0")
    }
  }

  QtObject {
    id: fakeTelemetry
    property bool available: true
    property var connectionSnapshot: root.connection()
  }

  Component { id: ownerComponent; Item {} }
  Loader { id: ownerLoader; sourceComponent: ownerComponent }

  Network.NetworkReachability {
    id: slowReachability
    active: true
    networkTelemetry: fakeTelemetry
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, root.slowCounterPath, "slow"
    ]
    pollIntervalMs: 100000
    refreshTimeoutMs: 5000
    drainTimeoutMs: 500
  }

  Network.NetworkReachability {
    id: nextReachability
    active: false
    networkTelemetry: fakeTelemetry
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, root.nextCounterPath
    ]
    pollIntervalMs: 100000
    refreshTimeoutMs: 2000
    drainTimeoutMs: 500
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 120)
        return root.fail("reachability cleanup timed out in phase " + root.phase)

      if (root.phase === 0) {
        if (!slowReachability.authorized || !root.owner) return
        if (!slowReachability.acquire(root.owner))
          return root.fail("slow owner could not acquire")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!slowReachability.workerRunning
            || !slowReachability.workerOutputComplete) return
        slowReachability.active = false
        nextReachability.active = true
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (root.ticks < 8 && nextReachability.authorized)
          return root.fail("authority released before resistant worker drained")
        if (!nextReachability.authorized) return
        if (slowReachability.authorized || slowReachability.workerRunning
            || slowReachability.clientCount !== 0)
          return root.fail("old reachability owner survived handoff")
        if (!nextReachability.acquire(root.owner))
          return root.fail("replacement owner could not acquire")
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (!nextReachability.available
            || !nextReachability.reachabilitySnapshot) return
        ownerLoader.active = false
        root.phase = 4
        root.ticks = 0
        return
      }

      if (nextReachability.clientCount !== 0
          || nextReachability.workerRunning
          || nextReachability.available
          || nextReachability.reachabilitySnapshot !== null)
        return root.fail("destroyed lease owner retained reachability resources")
      slowReachability.active = false
      nextReachability.active = false
      console.log("network reachability lifecycle regression passed")
      Qt.exit(0)
    }
  }
}
