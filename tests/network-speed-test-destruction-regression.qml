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
    Qt.resolvedUrl("fixtures/network-speed-test-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string counterPath:
    Qt.resolvedUrl("fixtures/network-speed-test-destruction-invocations")
      .toString().replace(/^file:\/\//, "")

  function fail(message) {
    console.error("network-speed-test-destruction-regression:", message)
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
      dnsServers: [], dnsDomains: [], rxBytes: 1, txBytes: 2,
      sampleMonotonicMs: 1,
      activeConnections: [{ uuid: uuid, kind: "wired",
        interfaceName: "eth0", hardwareAddress: hardware }],
      wifi: {
        ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0
      },
      wired: { speedMbps: 1000, carrier: true },
      id: NetworkModel.connectionId(uuid),
      deviceId: NetworkModel.deviceId("wired", hardware, "eth0"),
      downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, generation: 1
    }
  }

  QtObject {
    id: telemetry
    property bool available: true
    property bool connected: true
    property var connectionSnapshot: root.connection()
  }

  Item { id: owner }

  Component {
    id: speedComponent
    Network.NetworkSpeedTest {
      active: true
      networkTelemetry: telemetry
      commandOverride: [
        "/usr/bin/python3", root.fixturePath, root.counterPath, "slow"
      ]
      phaseDurationMs: 1000
      phaseTimeoutMs: 5000
      drainTimeoutMs: 200
    }
  }

  Loader { id: primaryLoader; active: true; sourceComponent: speedComponent }
  Loader { id: replacementLoader; active: false; sourceComponent: speedComponent }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 160)
        return root.fail("destruction lifecycle timed out in phase " + root.phase)
      const primary = primaryLoader.item
      const replacement = replacementLoader.item
      if (root.phase === 0) {
        if (!primary || !primary.authorized) return
        if (!primary.requestRun(owner))
          return root.fail("could not start destruction worker")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (!primary || !primary.workerRunning || root.ticks < 8) return
        primaryLoader.active = false
        replacementLoader.active = true
        root.phase = 2
        root.ticks = 0
        return
      }
      if (root.phase === 2) {
        if (!replacement || root.ticks < 40) return
        if (replacement.authorized)
          return root.fail("destroyed active worker released authority")
        console.log("network speed-test destruction regression passed")
        Qt.exit(0)
      }
    }
  }
}
