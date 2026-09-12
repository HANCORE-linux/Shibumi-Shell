pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "catalog" as Catalog

Scope {
  id: root
  property int stage: 0
  property int mode: 0
  property var owner: null
  property var oldToken: null
  property var replacement: null
  property var held: []
  property var tokens: []
  property Catalog.CatalogDemand doomed: null
  property bool destroyed: false
  Component { id: holderFactory; QtObject {} }
  Component { id: demandFactory; Catalog.CatalogDemand { Component.onDestruction: root.destroyed = true } }
  Catalog.CatalogDemand {
    id: demand
    onCountChanged: {
      if (count === 1 && root.mode === 1) {
        root.mode = 0
        root.oldToken = demand.acquire(root.owner)
        root.assert(demand.release(root.oldToken), "reentrant release refused")
        root.replacement = demand.acquire(root.owner)
      } else if (count === 1 && root.mode === 2) {
        root.mode = 0
        demand.release(demand.acquire(root.owner))
      } else if (count === 0 && root.mode === 3) {
        root.mode = 0
        root.replacement = demand.acquire(root.owner)
      }
    }
  }
  function assert(value, message) {
    if (value) return
    console.error("catalog-demand-smoke:", stage, message)
    Qt.exit(1)
    throw new Error(message)
  }
  Timer {
    interval: 10; running: true; repeat: true
    onTriggered: {
      switch (root.stage) {
      case 0:
        root.assert(!demand.acquire(null) && !demand.acquire({}) && !demand.has({})
          && !demand.release({}), "invalid holder or foreign token accepted")
        root.owner = holderFactory.createObject(root)
        root.mode = 1
        var token = demand.acquire(root.owner)
        root.assert(token === root.replacement && demand.has(token) && demand.count === 1,
          "reentrant acquire lost replacement token")
        root.assert(!demand.release(root.oldToken) && demand.has(token), "stale token released replacement")
        root.assert(demand.acquire(root.owner) === token && Object.isFrozen(token)
          && Object.keys(token).length === 0, "non-idempotent or nonopaque token")
        root.assert(demand.release(token) && demand.count === 0, "last release retained demand")
        root.mode = 2
        root.assert(demand.acquire(root.owner) === null && demand.count === 0, "release during acquire retained demand")
        token = demand.acquire(root.owner)
        root.mode = 3
        root.assert(demand.release(token) && demand.count === 1 && demand.has(root.replacement)
          && !demand.has(token), "release destroyed reentrant new lease")
        root.owner.destroy()
        root.stage = 1; break
      case 1:
        root.assert(demand.count === 0 && !demand.has(root.replacement), "destroyed holder retained demand")
        for (var i = 0; i < 65; i++) root.held.push(holderFactory.createObject(root))
        for (var j = 0; j < 64; j++) {
          root.tokens.push(demand.acquire(root.held[j]))
          root.assert(demand.has(root.tokens[j]) && demand.count === j + 1, "capacity refused early")
        }
        root.assert(demand.acquire(root.held[64]) === null && demand.count === 64, "65th holder admitted")
        root.assert(demand.acquire(root.held[0]) === root.tokens[0], "idempotent acquire refused at capacity")
        root.held[10].destroy()
        root.stage = 2; break
      case 2:
        root.assert(demand.count === 63 && !demand.has(root.tokens[10]), "capacity destruction retained lease")
        root.assert(demand.acquire(root.held[64]) !== null && demand.count === 64, "released capacity not reused")
        for (var i = 0; i < root.held.length; i++)
          if (Qt.isQtObject(root.held[i])) root.held[i].destroy()
        root.stage = 3; break
      case 3:
        root.assert(demand.count === 0, "bulk holder destruction leaked demand")
        root.owner = holderFactory.createObject(root)
        root.doomed = demandFactory.createObject(root)
        root.assert(root.doomed.acquire(root.owner) !== null, "temporary demand refused")
        root.doomed.destroy()
        root.stage = 4; break
      case 4:
        root.assert(root.destroyed && root.doomed === null && Qt.isQtObject(root.owner),
          "demand destruction leaked or destroyed consumer")
        root.owner.destroy()
        console.log("catalog demand ownership/reentry/capacity passed")
        Qt.quit()
      }
    }
  }
  Timer { interval: 3000; running: true; onTriggered: root.assert(false, "deadline") }
}
