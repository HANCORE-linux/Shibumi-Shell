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
    Qt.resolvedUrl("fixtures/network-telemetry-destruction-invocations")
      .toString().replace(/^file:\/\//, "")
  readonly property var telemetry: telemetryLoader.item

  function fail(message) {
    console.error("network-telemetry-destruction-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeLiveness
    property bool serviceUsable: true
    property real generation: 1
  }

  Item { id: owner }

  Component {
    id: telemetryComponent
    Network.NetworkTelemetry {
      active: true
      nativeLiveness: fakeLiveness
      commandOverride: [
        "/usr/bin/python3", root.fixturePath, root.fixtureCounterPath,
        "delayed-exit"
      ]
      pollIntervalMs: 100000
      refreshTimeoutMs: 2000
    }
  }

  Loader { id: telemetryLoader; sourceComponent: telemetryComponent }

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
      if (root.ticks > 100)
        return root.fail("destruction authority test timed out")

      if (root.phase === 0) {
        if (!root.telemetry || !root.telemetry.authorized) return
        if (!root.telemetry.acquire(owner))
          return root.fail("destruction owner could not acquire")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!root.telemetry.workerRunning
            || !root.telemetry.workerOutputComplete) return
        telemetryLoader.active = false
        standbyTelemetry.active = true
        root.phase = 2
        root.ticks = 0
        return
      }

      if (standbyTelemetry.authorized || standbyTelemetry.workerRunning)
        return root.fail("destroyed live worker released authority fail-open")
      if (root.ticks < 35) return
      standbyTelemetry.active = false
      console.log("network telemetry destruction regression passed")
      Qt.exit(0)
    }
  }
}
