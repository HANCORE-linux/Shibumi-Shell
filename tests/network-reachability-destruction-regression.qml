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
    Qt.resolvedUrl("fixtures/network-reachability-destruction-invocations")
      .toString().replace(/^file:\/\//, "")
  readonly property var reachability: reachabilityLoader.item

  function fail(message) {
    console.error("network-reachability-destruction-regression:", message)
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
        hardwareAddress: hardware, metered: "no",
        addresses: [],
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

  Component {
    id: reachabilityComponent
    Network.NetworkReachability {
      active: true
      networkTelemetry: fakeTelemetry
      commandOverride: [
        "/usr/bin/python3", root.fixturePath, root.counterPath, "slow"
      ]
      pollIntervalMs: 100000
      refreshTimeoutMs: 5000
      drainTimeoutMs: 500
    }
  }

  Loader { id: reachabilityLoader; sourceComponent: reachabilityComponent }

  Network.NetworkReachability {
    id: replacement
    active: false
    networkTelemetry: fakeTelemetry
    commandOverride: ["/usr/bin/false"]
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("destruction regression timed out")
      if (root.phase === 0) {
        if (!root.reachability || !root.reachability.authorized) return
        if (!root.reachability.acquire(owner))
          return root.fail("destruction owner could not acquire")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (!root.reachability.workerRunning
            || !root.reachability.workerOutputComplete) return
        reachabilityLoader.active = false
        replacement.active = true
        root.phase = 2
        root.ticks = 0
        return
      }
      if (root.reachability !== null)
        return root.fail("destroyed reachability Loader survived")
      if (replacement.authorized || replacement.workerRunning)
        return root.fail("uncertain destruction reopened process authority")
      if (root.ticks < 25) return
      replacement.active = false
      console.log("network reachability destruction regression passed")
      Qt.exit(0)
    }
  }
}
