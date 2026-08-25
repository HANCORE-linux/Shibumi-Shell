pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string sourceAddress: "192.0.2.10"
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-speed-test-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string counterPath:
    Qt.resolvedUrl("fixtures/network-speed-test-invocations")
      .toString().replace(/^file:\/\//, "")
  property var defaultCommand:
    ["/usr/bin/python3", fixturePath, counterPath]
  property var workerCommand: defaultCommand

  function fail(message) {
    console.error("network-speed-test-regression:", message)
    Qt.exit(1)
  }

  function connection(address) {
    const uuid = "11111111-1111-4111-8111-111111111111"
    const hardware = "02:00:00:00:00:01"
    return {
      schemaVersion: 1,
      connected: true,
      connectionUuid: uuid,
      connectionName: "Wired",
      kind: "wired",
      interfaceName: "eth0",
      hardwareAddress: hardware,
      metered: "no",
      addresses: [{ family: "ipv4", address: address, prefix: 24 }],
      gateways: [{ family: "ipv4", address: "192.0.2.1" }],
      dnsServers: [],
      dnsDomains: [],
      rxBytes: 100,
      txBytes: 200,
      sampleMonotonicMs: 100,
      activeConnections: [{ uuid: uuid, kind: "wired",
        interfaceName: "eth0", hardwareAddress: hardware }],
      wifi: {
        ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0
      },
      wired: { speedMbps: 1000, carrier: true },
      id: NetworkModel.connectionId(uuid),
      deviceId: NetworkModel.deviceId("wired", hardware, "eth0"),
      downloadBytesPerSecond: 0,
      uploadBytesPerSecond: 0,
      generation: 1
    }
  }

  QtObject {
    id: fakeTelemetry
    property bool available: true
    property bool connected: true
    property var connectionSnapshot: root.connection(root.sourceAddress)
  }

  Item { id: owner }
  Item { id: wrongOwner }
  Item { id: standbyOwner }

  Network.NetworkSpeedTest {
    id: speedTest
    active: true
    networkTelemetry: fakeTelemetry
    commandOverride: root.workerCommand
    phaseDurationMs: 1000
    phaseTimeoutMs: 2500
    drainTimeoutMs: 300
  }

  Network.NetworkSpeedTest {
    id: standby
    active: true
    networkTelemetry: fakeTelemetry
    commandOverride: root.defaultCommand
    phaseDurationMs: 1000
    phaseTimeoutMs: 2500
    drainTimeoutMs: 300
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 240)
        return root.fail("speed-test lifecycle timed out in phase "
          + root.phase + " (state=" + speedTest.phase + ", error="
          + speedTest.errorCode + ", worker=" + speedTest.workerRunning + ")")

      if (root.phase === 0) {
        if (!speedTest.authorized) return
        if (standby.authorized || !speedTest.available
            || speedTest.running || speedTest.speedTestResult !== null)
          return root.fail("initial authority state was wrong")
        if (!speedTest.requestRun(owner)
            || speedTest.requestRun(owner)
            || speedTest.requestRun(wrongOwner)
            || !speedTest.running || speedTest.phase !== "down")
          return root.fail("run admission was not single-owner")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (speedTest.phase !== "succeeded") return
        const result = speedTest.speedTestResult
        if (!result || speedTest.running || result.runId !== 1
            || result.downloadMbps !== 100 || result.uploadMbps !== 50
            || result.sourceAddress !== "192.0.2.10"
            || speedTest.downloadMbps !== 100 || speedTest.uploadMbps !== 50
            || speedTest.errorCode !== "")
          return root.fail("successful two-phase result was wrong")
        if (speedTest.cancel(owner) || speedTest.cancel(wrongOwner))
          return root.fail("completed run retained an owner token")
        root.workerCommand = [
          "/usr/bin/python3", root.fixturePath, root.counterPath, "delayed"
        ]
        if (!speedTest.requestRun(owner))
          return root.fail("route-race run was rejected")
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (!speedTest.workerRunning) return
        root.sourceAddress = "192.0.2.11"
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.phase !== "error"
            || speedTest.errorCode !== "route-changed"
            || speedTest.speedTestResult !== null)
          return root.fail("route change did not fail closed")
        root.workerCommand = root.defaultCommand
        if (!speedTest.requestRun(owner))
          return root.fail("post-race recovery run was rejected")
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        const result = speedTest.speedTestResult
        if (!result || speedTest.phase !== "succeeded") return
        if (result.runId !== 3 || result.sourceAddress !== "192.0.2.11"
            || result.downloadMbps !== 100 || result.uploadMbps !== 50)
          return root.fail("post-race recovery result was wrong")
        fakeTelemetry.available = false
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (speedTest.available || speedTest.speedTestResult !== null)
          return root.fail("telemetry loss retained a public result")
        fakeTelemetry.available = true
        speedTest.active = false
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (speedTest.authorized) return
        if (!standby.authorized) return
        if (!standby.requestRun(standbyOwner))
          return root.fail("authority handoff could not start a run")
        root.phase = 7
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        const result = standby.speedTestResult
        if (!result || standby.phase !== "succeeded") return
        if (result.downloadMbps !== 100 || result.uploadMbps !== 50)
          return root.fail("handoff owner published a wrong result")
        console.log("network speed-test regression passed")
        Qt.exit(0)
      }
    }
  }
}
