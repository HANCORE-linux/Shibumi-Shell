pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-telemetry-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string fixtureCounterPath:
    Qt.resolvedUrl("fixtures/network-telemetry-start-failure-invocations")
      .toString().replace(/^file:\/\//, "")
  property var telemetryCommand:
    ["/definitely/missing/shibumi-network-telemetry"]

  function fail(message) {
    console.error("network-telemetry-start-failure-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeLiveness
    property bool serviceUsable: true
    property real generation: 1
  }

  Item { id: owner }

  Network.NetworkTelemetry {
    id: failingTelemetry
    active: true
    nativeLiveness: fakeLiveness
    commandOverride: root.telemetryCommand
    pollIntervalMs: 100000
    refreshTimeoutMs: 1000
    drainTimeoutMs: 500
  }

  Network.NetworkTelemetry {
    id: standbyTelemetry
    active: false
    nativeLiveness: fakeLiveness
    commandOverride: ["/usr/bin/false"]
    pollIntervalMs: 100000
    refreshTimeoutMs: 1000
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 120)
        return root.fail("failed-start reactivation timed out")

      if (root.phase === 0) {
        if (!failingTelemetry.authorized) return
        if (!failingTelemetry.acquire(owner))
          return root.fail("failed-start owner could not acquire")
        failingTelemetry.active = false
        root.telemetryCommand = [
          "/usr/bin/python3", root.fixturePath, root.fixtureCounterPath
        ]
        failingTelemetry.active = true
        standbyTelemetry.active = true
        if (!failingTelemetry.draining
            || failingTelemetry.acquire(owner)
            || failingTelemetry.clientCount !== 0)
          return root.fail("draining telemetry accepted a new lease")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (standbyTelemetry.authorized || standbyTelemetry.workerRunning)
        return root.fail("reactivation exposed a second telemetry authority")
      if (!failingTelemetry.authorized) return
      if (failingTelemetry.clientCount === 0) {
        if (!failingTelemetry.acquire(owner)) return
      }
      if (!failingTelemetry.available
          || !failingTelemetry.connectionSnapshot) return
      if (failingTelemetry.connectionSnapshot.sampleMonotonicMs !== 1000)
        return root.fail("reactivated owner published the wrong sample")
      failingTelemetry.active = false
      standbyTelemetry.active = false
      console.log("network telemetry start failure regression passed")
      Qt.exit(0)
    }
  }
}
