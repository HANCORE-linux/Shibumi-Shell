pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("network-profile-action-lease-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: telemetry
    property var owners: []
    property int acquireCalls: 0
    property int releaseCalls: 0
    property bool failAcquire: false
    function acquire(owner) {
      acquireCalls++
      if (failAcquire) return false
      if (owners.indexOf(owner) < 0) owners = owners.concat([owner])
      return true
    }
    function release(owner) {
      if (owners.indexOf(owner) < 0) return false
      owners = owners.filter(candidate => candidate !== owner)
      releaseCalls++
      return true
    }
  }

  QtObject {
    id: catalog
    property var owners: []
    property int acquireCalls: 0
    property int releaseCalls: 0
    property bool failAcquire: false
    function acquire(owner) {
      acquireCalls++
      if (failAcquire) return false
      if (owners.indexOf(owner) < 0) owners = owners.concat([owner])
      return true
    }
    function release(owner) {
      if (owners.indexOf(owner) < 0) return false
      owners = owners.filter(candidate => candidate !== owner)
      releaseCalls++
      return true
    }
  }

  QtObject {
    id: coordinator
    property string phase: "idle"
    property string kind: ""
    property var actionSnapshot: ({
      phase: phase, kind: kind, actionId: phase === "pending" ? "a" : ""
    })
  }

  Loader {
    id: leaseLoader
    sourceComponent: Component {
      Network.NetworkProfileActionLease {
        active: true
        networkTelemetry: telemetry
        savedProfileCatalog: catalog
        actionCoordinator: coordinator
      }
    }
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("timed out in phase " + root.phase)
      const lease = leaseLoader.item
      if (root.phase < 3 && !lease) return
      if (root.phase === 0) {
        catalog.failAcquire = true
        if (lease.acquire() || telemetry.owners.length !== 0
            || catalog.owners.length !== 0 || lease.held)
          return root.fail("partial profile evidence lease was retained")
        catalog.failAcquire = false
        if (!lease.acquire() || !lease.held
            || telemetry.owners.length !== 1 || catalog.owners.length !== 1)
          return root.fail("profile evidence leases were not acquired")
        coordinator.kind = "connect-profile"
        coordinator.phase = "pending"
        if (!lease.retainIfPending("connect-profile"))
          return root.fail("pending profile connect lost evidence leases")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (root.ticks < 4) return
        if (!lease.held || telemetry.owners.length !== 1
            || catalog.owners.length !== 1)
          return root.fail("panel-independent profile leases ended early")
        coordinator.phase = "succeeded"
        root.phase = 2
        root.ticks = 0
        return
      }
      if (root.phase === 2) {
        if (lease.held || telemetry.owners.length !== 0
            || catalog.owners.length !== 0
            || telemetry.releaseCalls !== 2
            || catalog.releaseCalls !== 1)
          return root.fail("terminal profile action retained evidence leases")
        coordinator.kind = "forget-profile"
        coordinator.phase = "pending"
        if (!lease.acquire() || !lease.retainIfPending("forget-profile"))
          return root.fail("pending profile forget lost evidence leases")
        leaseLoader.active = false
        root.phase = 3
        root.ticks = 0
        return
      }
      if (root.phase === 3) {
        if (root.ticks < 3) return
        if (leaseLoader.item !== null || telemetry.owners.length !== 0
            || catalog.owners.length !== 0)
          return root.fail("destroyed profile lease retained worker clients")
        console.log("network profile action lease regression passed")
        Qt.exit(0)
      }
    }
  }
}
