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
    Qt.resolvedUrl("fixtures/network-speed-test-failure-invocations")
      .toString().replace(/^file:\/\//, "")
  property var baseCommand: ["/usr/bin/python3", fixturePath, counterPath]

  function fail(message) {
    console.error("network-speed-test-failure-regression:", message)
    Qt.exit(1)
  }

  function connection() {
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
      addresses: [{ family: "ipv4", address: "192.0.2.10", prefix: 24 }],
      gateways: [{ family: "ipv4", address: "192.0.2.1" }],
      dnsServers: [], dnsDomains: [], rxBytes: 1, txBytes: 2,
      sampleMonotonicMs: 1,
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

  function command(mode) {
    return mode === "" ? baseCommand
      : ["/usr/bin/python3", fixturePath, counterPath, mode]
  }

  function start(mode) {
    speedTest.commandOverride = command(mode)
    if (!speedTest.requestRun(owner)) {
      fail("could not start mode " + mode)
      return false
    }
    ticks = 0
    return true
  }

  QtObject {
    id: telemetry
    property bool available: true
    property bool connected: true
    property var connectionSnapshot: root.connection()
  }

  Item { id: owner }

  Network.NetworkSpeedTest {
    id: speedTest
    active: true
    networkTelemetry: telemetry
    commandOverride: root.baseCommand
    phaseDurationMs: 1000
    phaseTimeoutMs: 1800
    drainTimeoutMs: 200
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 240)
        return root.fail("failure lifecycle timed out in phase " + root.phase
          + " (state=" + speedTest.phase + ", error="
          + speedTest.errorCode + ", worker=" + speedTest.workerRunning + ")")

      if (root.phase === 0) {
        if (!speedTest.authorized) return
        if (!root.start("malformed")) return
        root.phase = 1
        return
      }
      if (root.phase === 1) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.phase !== "error"
            || speedTest.errorCode !== "invalid-result")
          return root.fail("malformed output did not fail closed")
        if (!root.start("flood-stdout")) return
        root.phase = 2
        return
      }
      if (root.phase === 2) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.errorCode !== "invalid-line"
            || speedTest.speedTestResult !== null)
          return root.fail("oversized stdout was accepted")
        if (!root.start("empty")) return
        root.phase = 3
        return
      }
      if (root.phase === 3) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.errorCode !== "process-exited")
          return root.fail("empty output was accepted")
        if (!root.start("fail")) return
        root.phase = 4
        return
      }
      if (root.phase === 4) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.errorCode !== "process-exited")
          return root.fail("nonzero exit was accepted")
        if (!root.start("flood-stderr")) return
        root.phase = 5
        return
      }
      if (root.phase === 5) {
        if (speedTest.phase !== "succeeded") return
        if (!speedTest.speedTestResult
            || speedTest.speedTestResult.downloadMbps !== 100
            || speedTest.speedTestResult.uploadMbps !== 50)
          return root.fail("bounded stderr-discard path lost valid output")
        if (!root.start("replay-up")) return
        root.phase = 6
        return
      }
      if (root.phase === 6) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.errorCode !== "invalid-result"
            || speedTest.speedTestResult !== null)
          return root.fail("replayed upload timestamp was accepted")
        if (!root.start("changed-index-up")) return
        root.phase = 7
        return
      }
      if (root.phase === 7) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.errorCode !== "invalid-result")
          return root.fail("inter-phase interface replacement was accepted")
        if (!root.start("stale-token")) return
        root.phase = 8
        return
      }
      if (root.phase === 8) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.errorCode !== "invalid-result")
          return root.fail("stale full-run token was accepted")
        speedTest.commandOverride = ["/shibumi/definitely/missing-speed-worker"]
        if (!speedTest.requestRun(owner))
          return root.fail("missing-worker case was not admitted")
        root.phase = 9
        root.ticks = 0
        return
      }
      if (root.phase === 9) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.errorCode !== "start-failed")
          return root.fail("failed-to-start did not settle safely: "
            + speedTest.errorCode)
        if (!root.start("slow")) return
        root.phase = 10
        return
      }
      if (root.phase === 10) {
        if (!speedTest.workerRunning || root.ticks < 8) return
        if (!speedTest.cancel(owner))
          return root.fail("owner could not cancel resistant worker")
        root.phase = 11
        root.ticks = 0
        return
      }
      if (root.phase === 11) {
        if (speedTest.running || speedTest.workerRunning) return
        if (speedTest.phase !== "idle" || speedTest.errorCode !== "")
          return root.fail("explicit cancellation published a failure")
        if (!root.start("")) return
        root.phase = 12
        return
      }
      if (root.phase === 12) {
        if (speedTest.phase !== "succeeded") return
        if (!speedTest.speedTestResult)
          return root.fail("post-cancellation recovery did not publish")
        console.log("network speed-test failure regression passed")
        Qt.exit(0)
      }
    }
  }
}
