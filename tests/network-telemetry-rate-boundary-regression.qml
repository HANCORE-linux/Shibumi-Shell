pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkTelemetryModel.js" as TelemetryModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-telemetry-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string fixtureCounterPath:
    Qt.resolvedUrl("fixtures/network-telemetry-rate-invocations")
      .toString().replace(/^file:\/\//, "")

  function fail(message) {
    console.error("network-telemetry-rate-boundary-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeLiveness
    property bool serviceUsable: true
    property real generation: 1
  }

  QtObject {
    id: fakeDevice
    property string typeToken: "wired"
    property string name: "eth0"
    property string address: "02:00:00:00:00:07"
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

  Item { id: owner }

  Network.NetworkTelemetry {
    id: telemetry
    active: true
    nativeLiveness: fakeLiveness
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, root.fixtureCounterPath,
      "rate-boundary"
    ]
    pollIntervalMs: 100000
    refreshTimeoutMs: 1000
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: fakeBackend
    nativeLiveness: fakeLiveness
    networkTelemetry: telemetry
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("throughput boundary test timed out")

      if (root.phase === 0) {
        if (!telemetry.authorized) return
        if (!telemetry.acquire(owner))
          return root.fail("rate-boundary owner could not acquire")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        const sample = telemetry.connectionSnapshot
        if (!sample || sample.sampleMonotonicMs !== 1000) return
        if (!telemetry.requestRefresh())
          return root.fail("safe maximum sample did not start")
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        const sample = telemetry.connectionSnapshot
        if (!sample || sample.sampleMonotonicMs !== 2000) return
        if (sample.downloadBytesPerSecond !== TelemetryModel.MaxSafeInteger
            || !adapter.networkTelemetryAvailable
            || adapter.throughputSnapshot.downloadBytesPerSecond
              !== TelemetryModel.MaxSafeInteger)
          return root.fail("safe maximum throughput was rejected")
        if (!telemetry.requestRefresh())
          return root.fail("counter reset sample did not start")
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        const sample = telemetry.connectionSnapshot
        if (!sample || sample.sampleMonotonicMs !== 3000) return
        if (sample.downloadBytesPerSecond !== 0)
          return root.fail("counter reset produced a negative rate")
        if (!telemetry.requestRefresh())
          return root.fail("oversized throughput sample did not start")
        root.phase = 4
        root.ticks = 0
        return
      }

      if (telemetry.workerRunning) return
      if (telemetry.phase !== "error"
          || telemetry.errorCode !== "invalid-identity"
          || telemetry.telemetrySnapshot !== null
          || adapter.networkTelemetryAvailable
          || adapter.throughputSnapshot !== null)
        return root.fail("oversized throughput crossed a public boundary")
      telemetry.active = false
      console.log("network telemetry rate boundary regression passed")
      Qt.exit(0)
    }
  }
}
