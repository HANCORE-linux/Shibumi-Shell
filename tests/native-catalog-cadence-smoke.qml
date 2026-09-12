pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "catalog" as Catalog
Scope {
  id: root
  property int stage: 0
  property double settledAt: 0
  property double releasedAt: 0
  property int releasedCalls: 0
  QtObject { id: owner }
  QtObject {
    id: transport
    property bool busy: false
    property int calls: 0
    property int serial: 0
    signal completed(int serial, string output, bool ok)
    signal drained(int serial)
    function start(value) {
      if (busy) return false
      serial = value; calls++; busy = true
      if (calls === 1) slowRead.restart()
      return true
    }
    function cancel() { slowRead.stop(); busy = false; drained(serial) }
  }
  Catalog.NativeCatalog {
    id: catalog
    admitted: true
    sourceToken: owner
    shellDirectory: "/fixture/shell"
    backendOverride: transport
    demand: true
    onSettled: function(serial, result) {
      if (serial === 1) root.settledAt = Date.now()
    }
  }
  function assert(ok, message) {
    if (ok) return
    console.error("catalog-cadence:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  Timer {
    id: slowRead
    interval: 6100
    onTriggered: {
      transport.busy = false
      transport.completed(transport.serial, "", false)
      transport.drained(transport.serial)
    }
  }
  Timer {
    interval: 20; running: true; repeat: true
    onTriggered: {
      if (root.stage === 0) {
        if (!root.settledAt) return
        root.assert(transport.calls === 1, "slow failure bypassed reconcile cooldown")
        if (Date.now() - root.settledAt > 4500) root.stage = 1
      } else if (root.stage === 1) {
        if (transport.calls === 1) return
        root.assert(transport.calls === 2 && Date.now() - root.settledAt >= 4900,
          "reconcile started before post-drain interval")
        catalog.demand = false
        root.releasedCalls = transport.calls
        root.releasedAt = Date.now()
        root.stage = 2
      } else {
        root.assert(transport.calls === root.releasedCalls && !catalog.ready && !catalog.nativeConstructed,
          "released cadence restarted a worker")
        if (Date.now() - root.releasedAt > 5200) {
          root.assert(!catalog.refreshing, "released read did not drain")
          console.log("catalog post-drain cooldown and inactive silence passed")
          Qt.quit()
        }
      }
    }
  }
  Timer { interval: 22000; running: true; onTriggered: root.assert(false, "cadence deadline") }
}
