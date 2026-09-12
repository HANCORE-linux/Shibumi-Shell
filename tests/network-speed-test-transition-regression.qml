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
    Qt.resolvedUrl("fixtures/network-speed-test-transition-invocations")
      .toString().replace(/^file:\/\//, "")

  function fail(message) {
    console.error("network-speed-test-transition-regression:", message)
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

  function betweenPhases() {
    return speedTest.running && !speedTest.workerRunning
      && speedTest.phase === "down"
  }

  QtObject {
    id: telemetry
    property bool available: true
    property bool connected: true
    property var connectionSnapshot: root.connection()
  }

  Component { id: ownerComponent; Item {} }
  Loader { id: ownerLoader; active: true; sourceComponent: ownerComponent }

  Network.NetworkSpeedTest {
    id: speedTest
    active: true
    networkTelemetry: telemetry
    commandOverride: ["/usr/bin/python3", root.fixturePath, root.counterPath]
    phaseDurationMs: 1000
    phaseTimeoutMs: 2000
    drainTimeoutMs: 250
    interPhaseDelayMs: 200
  }

  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 500)
        return root.fail("transition lifecycle timed out in phase " + root.phase
          + " (state=" + speedTest.phase + ", run=" + speedTest.runId + ")")

      if (root.phase === 0) {
        if (!speedTest.authorized || !ownerLoader.item) return
        if (!speedTest.requestRun(ownerLoader.item))
          return root.fail("initial transition run was rejected")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (!root.betweenPhases()) return
        if (!speedTest.cancel(ownerLoader.item)
            || !speedTest.requestRun(ownerLoader.item))
          return root.fail("inter-phase cancel/immediate rerun failed")
        root.phase = 2
        root.ticks = 0
        return
      }
      if (root.phase === 2) {
        if (speedTest.phase !== "succeeded") return
        if (!speedTest.speedTestResult || speedTest.speedTestResult.runId !== 2)
          return root.fail("stale continuation corrupted immediate rerun")
        if (!speedTest.requestRun(ownerLoader.item))
          return root.fail("owner-destruction run was rejected")
        root.phase = 3
        root.ticks = 0
        return
      }
      if (root.phase === 3) {
        if (!root.betweenPhases()) return
        ownerLoader.active = false
        root.phase = 4
        root.ticks = 0
        return
      }
      if (root.phase === 4) {
        if (speedTest.running || speedTest.phase !== "idle") return
        ownerLoader.active = true
        root.phase = 5
        root.ticks = 0
        return
      }
      if (root.phase === 5) {
        if (!ownerLoader.item) return
        if (!speedTest.requestRun(ownerLoader.item))
          return root.fail("owner recreation run was rejected")
        root.phase = 6
        root.ticks = 0
        return
      }
      if (root.phase === 6) {
        if (speedTest.phase !== "succeeded") return
        if (!speedTest.speedTestResult || speedTest.speedTestResult.runId !== 4)
          return root.fail("owner destruction left a stale continuation")
        if (!speedTest.requestRun(ownerLoader.item))
          return root.fail("deactivation run was rejected")
        root.phase = 7
        root.ticks = 0
        return
      }
      if (root.phase === 7) {
        if (!root.betweenPhases()) return
        speedTest.active = false
        root.phase = 8
        root.ticks = 0
        return
      }
      if (root.phase === 8) {
        if (speedTest.authorized || speedTest.phase !== "inactive") return
        speedTest.active = true
        root.phase = 9
        root.ticks = 0
        return
      }
      if (root.phase === 9) {
        if (!speedTest.authorized) return
        if (!speedTest.requestRun(ownerLoader.item))
          return root.fail("reactivated run was rejected")
        root.phase = 10
        root.ticks = 0
        return
      }
      if (root.phase === 10) {
        if (speedTest.phase !== "succeeded") return
        if (!speedTest.speedTestResult || speedTest.speedTestResult.runId !== 6)
          return root.fail("deactivation retained a stale continuation")
        console.log("network speed-test transition regression passed")
        Qt.exit(0)
      }
    }
  }
}
