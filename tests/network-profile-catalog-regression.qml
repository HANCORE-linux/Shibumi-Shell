pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel
import "network/NetworkProfileCatalogModel.js" as CatalogModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string mode: "normal"
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-profile-catalog-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string fixtureCounterPath:
    Qt.resolvedUrl("fixtures/network-profile-catalog-invocations")
      .toString().replace(/^file:\/\//, "")
  readonly property var catalog: catalogLoader.item
  readonly property var ownerOne: ownerOneLoader.item
  readonly property var ownerTwo: ownerTwoLoader.item

  function fail(message) {
    console.error("network-profile-catalog-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeLiveness
    property bool serviceUsable: true
    property real generation: 1
  }

  QtObject {
    id: fakeBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: []
  }

  QtObject {
    id: malformedCatalog
    property bool available: true
    property real generation: 1
    property var profileSnapshots: [{
      schemaVersion: 1,
      id: "forged-id",
      uuid: "44444444-4444-4444-8444-444444444444",
      name: "Forged fixture",
      profileType: "wifi",
      ssid: "Forged",
      ssidHex: "466F72676564",
      security: "open",
      enterprise: false,
      hidden: false,
      autoconnect: true,
      timestamp: 0
    }]
  }

  Component {
    id: ownerComponent
    Item {}
  }

  Loader {
    id: ownerOneLoader
    sourceComponent: ownerComponent
  }

  Loader {
    id: ownerTwoLoader
    active: false
    sourceComponent: ownerComponent
  }

  Component {
    id: catalogComponent
    Network.NetworkProfileCatalog {
      active: true
      nativeLiveness: fakeLiveness
      commandOverride: [
        "/usr/bin/python3", root.fixturePath, "sequence",
        root.fixtureCounterPath
      ]
      refreshTimeoutMs: 1000
    }
  }

  Loader {
    id: catalogLoader
    sourceComponent: catalogComponent
  }

  Network.NetworkProfileCatalog {
    id: standbyCatalog
    active: false
    nativeLiveness: fakeLiveness
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, "sequence",
      root.fixtureCounterPath
    ]
    refreshTimeoutMs: 1000
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: fakeBackend
    nativeLiveness: fakeLiveness
    savedProfileCatalog: root.catalog
  }

  Network.NetworkBackendAdapter {
    id: malformedAdapter
    active: true
    backendOverride: fakeBackend
    savedProfileCatalog: malformedCatalog
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 160)
        return root.fail("catalog lifecycle timed out: " + JSON.stringify({
          phase: root.phase,
          catalogPhase: root.catalog && root.catalog.phase,
          worker: root.catalog && root.catalog.workerRunning,
          clients: root.catalog && root.catalog.clientCount,
          rows: root.catalog && root.catalog.profileSnapshots.length,
          available: root.catalog && root.catalog.available,
          error: root.catalog && root.catalog.errorCode
        }))

      if (root.phase === 0) {
        if (!root.catalog || !root.catalog.authorized) return
        if (root.catalog.workerRunning || root.catalog.clientCount !== 0
            || root.catalog.profileSnapshots.length !== 0)
          return root.fail("closed catalog consumed host resources")
        if (CatalogModel.parseLine(
              '{"schemaVersion":1,"event":"begin","sequence":1,"count":4097}').ok
            || !CatalogModel.parseLine(
              '{"schemaVersion":1,"event":"begin","sequence":1,"count":4096}').ok
            || CatalogModel.parseLine(
              '{"schemaVersion":1,"event":"begin","event":"end","sequence":1,"count":0}').ok)
          return root.fail("catalog parser accepted malformed bounds or duplicates")
        if (!malformedAdapter.savedProfileCatalogDegraded
            || malformedAdapter.savedProfileSnapshots.length !== 0)
          return root.fail("forged catalog identity did not fail closed")
        if (!root.catalog.acquire(root.ownerOne))
          return root.fail("catalog owner could not acquire")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!root.catalog.available || root.catalog.profileSnapshots.length !== 2)
          return
        const rows = root.catalog.profileSnapshots
        if (rows[0].id !== NetworkModel.catalogProfileId(rows[0].uuid)
            || rows[1].id !== NetworkModel.catalogProfileId(rows[1].uuid)
            || rows[0].uuid >= rows[1].uuid
            || rows[0].timestamp !== 1 || rows[1].timestamp !== 1
            || rows[1].enterprise !== true
            || rows[1].name !== "Enterprise Café 🚀"
            || rows[1].ssid !== "Office🚀"
            || "identity" in rows[1] || "settings" in rows[1]
            || !adapter.savedProfileCatalogAvailable
            || adapter.savedProfileSnapshots.length !== 2
            || adapter.savedProfileSnapshots[0].generation !== adapter.generation)
          return root.fail("primitive saved-profile catalog projection changed")
        root.mode = "malformed"
        if (!root.catalog.requestRefresh())
          return root.fail("malformed refresh did not start")
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (root.catalog.workerRunning) return
        if (root.catalog.phase !== "error"
            || root.catalog.profileSnapshots.length !== 0
            || adapter.savedProfileCatalogAvailable
            || adapter.savedProfileSnapshots.length !== 0)
          return root.fail("malformed helper output did not clear atomically")
        root.mode = "normal"
        if (!root.catalog.requestRefresh())
          return root.fail("catalog could not recover from malformed output")
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (!root.catalog.available || root.catalog.profileSnapshots.length !== 2)
          return
        if (root.catalog.profileSnapshots[0].timestamp !== 3)
          return root.fail("malformed output retried without demand")
        root.mode = "slow"
        if (!root.catalog.requestRefresh())
          return root.fail("slow refresh did not start")
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (!root.catalog.workerRunning) return
        root.mode = "normal"
        if (!root.catalog.release(root.ownerOne)
            || !root.catalog.acquire(root.ownerOne))
          return root.fail("close/reopen race could not queue refresh")
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (!root.catalog.available || root.catalog.profileSnapshots.length !== 2)
          return
        if (root.catalog.profileSnapshots[0].timestamp !== 5)
          return root.fail("close/reopen queued duplicate refreshes: "
            + root.catalog.profileSnapshots[0].timestamp)
        root.mode = "slow"
        if (!root.catalog.requestRefresh())
          return root.fail("liveness-race refresh did not start")
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (!root.catalog.workerRunning) return
        root.mode = "normal"
        fakeLiveness.serviceUsable = false
        fakeLiveness.generation++
        fakeLiveness.serviceUsable = true
        fakeLiveness.generation++
        root.phase = 7
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (!root.catalog.available || root.catalog.profileSnapshots.length !== 2)
          return
        if (root.catalog.profileSnapshots[0].timestamp !== 7)
          return root.fail("liveness race queued duplicate refreshes")
        root.mode = "failed"
        if (!root.catalog.requestRefresh())
          return root.fail("failed-output fixture did not start")
        root.phase = 8
        root.ticks = 0
        return
      }

      if (root.phase === 8) {
        if (root.catalog.workerRunning || root.ticks < 5) return
        if (root.catalog.phase !== "error"
            || root.catalog.profileSnapshots.length !== 0)
          return root.fail("failed helper retained published state")
        root.mode = "normal"
        if (!root.catalog.requestRefresh())
          return root.fail("explicit recovery after failed helper did not start")
        root.phase = 9
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (!root.catalog.available || root.catalog.profileSnapshots.length !== 2)
          return
        if (root.catalog.profileSnapshots[0].timestamp !== 9)
          return root.fail("failed helper retried without explicit demand")
        ownerOneLoader.active = false
        root.phase = 10
        root.ticks = 0
        return
      }

      if (root.phase === 10) {
        if (root.ownerOne !== null || root.catalog.clientCount !== 0
            || root.catalog.workerRunning) return
        if (root.catalog.profileSnapshots.length !== 0
            || root.catalog.phase !== "idle")
          return root.fail("owner destruction retained saved-profile data")
        standbyCatalog.active = true
        if (standbyCatalog.authorized || standbyCatalog.workerRunning)
          return root.fail("standby catalog duplicated process worker")
        root.catalog.active = false
        root.phase = 11
        root.ticks = 0
        return
      }

      if (root.phase === 11) {
        if (!standbyCatalog.authorized) return
        ownerTwoLoader.active = true
        root.phase = 12
        root.ticks = 0
        return
      }

      if (!root.ownerTwo) return
      if (standbyCatalog.clientCount === 0
          && !standbyCatalog.acquire(root.ownerTwo))
        return root.fail("replacement catalog could not acquire")
      if (!standbyCatalog.available
          || standbyCatalog.profileSnapshots.length !== 2) return
      if (standbyCatalog.profileSnapshots[0].timestamp !== 10)
        return root.fail("authority handoff duplicated catalog refresh")
      standbyCatalog.active = false
      console.log("network profile catalog regression passed")
      Qt.exit(0)
    }
  }
}
