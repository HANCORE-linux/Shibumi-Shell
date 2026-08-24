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
  property string oldCounterPath:
    Qt.resolvedUrl("fixtures/network-reachability-prestart-old")
      .toString().replace(/^file:\/\//, "")
  property string nextCounterPath:
    Qt.resolvedUrl("fixtures/network-reachability-prestart-next")
      .toString().replace(/^file:\/\//, "")

  function fail(message) {
    console.error("network-reachability-prestart-regression:", message)
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
    id: oldReachability
    active: true
    networkTelemetry: fakeTelemetry
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, root.oldCounterPath
    ]
    pollIntervalMs: 100000
    drainTimeoutMs: 300
  }

  Network.NetworkReachability {
    id: nextReachability
    active: false
    networkTelemetry: fakeTelemetry
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, root.nextCounterPath
    ]
    pollIntervalMs: 100000
    drainTimeoutMs: 300
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 120)
        return root.fail("pre-start cancellation timed out")
      if (root.phase === 0) {
        if (!oldReachability.authorized) return
        if (!oldReachability.acquire(owner))
          return root.fail("pre-start owner could not acquire")
        oldReachability.active = false
        nextReachability.active = true
        if (!oldReachability.draining
            || oldReachability.acquire(owner)
            || oldReachability.clientCount !== 0)
          return root.fail("draining pre-start owner accepted a lease")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.ticks < 2 && nextReachability.authorized)
        return root.fail("pre-start authority released before settlement")
      if (!nextReachability.authorized) return
      if (oldReachability.authorized || oldReachability.workerRunning)
        return root.fail("pre-start owner survived settlement")
      if (nextReachability.clientCount === 0
          && !nextReachability.acquire(owner))
        return root.fail("replacement pre-start owner could not acquire")
      if (!nextReachability.available
          || !nextReachability.reachabilitySnapshot) return
      oldReachability.active = false
      nextReachability.active = false
      console.log("network reachability prestart regression passed")
      Qt.exit(0)
    }
  }
}
