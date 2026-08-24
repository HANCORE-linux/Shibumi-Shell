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
  property string oldCounterPath:
    Qt.resolvedUrl("fixtures/network-telemetry-deferred-old-invocations")
      .toString().replace(/^file:\/\//, "")
  property string nextCounterPath:
    Qt.resolvedUrl("fixtures/network-telemetry-deferred-next-invocations")
      .toString().replace(/^file:\/\//, "")
  property var deferredCommand: []
  readonly property var deferredTelemetry: deferredLoader.item

  function fail(message) {
    console.error("network-telemetry-deferred-launch-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeLiveness
    property bool serviceUsable: true
    property real generation: 1
  }

  Item { id: oldOwner }
  Item { id: nextOwner }

  Component {
    id: deferredComponent
    Network.NetworkTelemetry {
      active: true
      nativeLiveness: fakeLiveness
      commandOverride: root.deferredCommand
      pollIntervalMs: 100000
      refreshTimeoutMs: 1000
    }
  }

  Loader { id: deferredLoader; sourceComponent: deferredComponent }

  Network.NetworkTelemetry {
    id: nextTelemetry
    active: false
    nativeLiveness: fakeLiveness
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, root.nextCounterPath
    ]
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
        return root.fail("deferred launch cancellation timed out")

      if (root.phase === 0) {
        if (!root.deferredTelemetry
            || !root.deferredTelemetry.authorized) return
        if (!root.deferredTelemetry.acquire(oldOwner))
          return root.fail("deferred owner could not acquire")
        if (root.deferredTelemetry.workerRunning)
          return root.fail("empty command unexpectedly started")
        if (!root.deferredTelemetry.release(oldOwner)
            || root.deferredTelemetry.phase !== "idle"
            || root.deferredTelemetry.clientCount !== 0)
          return root.fail("deferred release did not settle without a worker")
        root.deferredCommand = [
          "/usr/bin/python3", root.fixturePath, root.oldCounterPath
        ]
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!root.deferredTelemetry.acquire(oldOwner))
          return root.fail("deferred owner could not reacquire")
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (!root.deferredTelemetry.available
            || !root.deferredTelemetry.connectionSnapshot) return
        if (!root.deferredTelemetry.release(oldOwner))
          return root.fail("recovered deferred owner could not release")
        root.deferredCommand = []
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (!root.deferredTelemetry.acquire(oldOwner)
            || root.deferredTelemetry.workerRunning)
          return root.fail("second deferred launch was not established")
        deferredLoader.active = false
        nextTelemetry.active = true
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.deferredTelemetry !== null)
        return root.fail("deferred Loader survived destruction")
      if (!nextTelemetry.authorized) return
      if (nextTelemetry.clientCount === 0
          && !nextTelemetry.acquire(nextOwner))
        return root.fail("replacement deferred owner could not acquire")
      if (!nextTelemetry.available || !nextTelemetry.connectionSnapshot) return
      if (root.ticks < 20) return
      nextTelemetry.active = false
      console.log("network telemetry deferred launch regression passed")
      Qt.exit(0)
    }
  }
}
