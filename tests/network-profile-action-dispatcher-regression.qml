pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  readonly property string uuid:
    "11111111-2222-4333-8444-555555555555"
  readonly property string profileId: "shibumi-network-v1:"
    + JSON.stringify(["saved-profile", uuid])
  readonly property string deviceId: "shibumi-network-v1:"
    + JSON.stringify(["device", "wifi", "mac", "02:00:00:00:00:01"])
  property string activeUuid: ""
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-profile-action-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string slowPidPath:
    Qt.resolvedUrl("fixtures/network-profile-action-slow.pid")
      .toString().replace(/^file:\/\//, "")

  function fail(message) {
    console.error("network-profile-action-dispatcher-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: catalog
    property bool available: true
    property real generation: 1
    property int refreshCalls: 0
    property var owners: []
    property var profileSnapshots: [{
      schemaVersion: 1, id: root.profileId, uuid: root.uuid,
      name: "Hidden fixture", profileType: "wifi", ssid: "Hidden",
      ssidHex: "48696464656E", security: "wpa2-psk",
      enterprise: false, hidden: true, autoconnect: true, timestamp: 1
    }]
    function acquire(owner) {
      if (owners.indexOf(owner) < 0) owners = owners.concat([owner])
      return true
    }
    function release(owner) {
      owners = owners.filter(candidate => candidate !== owner)
      return true
    }
    function requestRefresh() { refreshCalls++; return true }
  }

  QtObject {
    id: telemetry
    property var owners: []
    function acquire(owner) {
      if (owners.indexOf(owner) < 0) owners = owners.concat([owner])
      return true
    }
    function release(owner) {
      owners = owners.filter(candidate => candidate !== owner)
      return true
    }
  }

  QtObject {
    id: adapter
    property bool backendAvailable: true
    property var backendOverride: ({ fake: true })
    property real generation: 7
    property bool savedProfileCatalogAvailable: catalog.available
    property var savedProfileSnapshots: catalog.profileSnapshots.map(row =>
      Object.assign({}, row, { generation: generation }))
    property var deviceSnapshots: [{
      schemaVersion: 1, id: root.deviceId, type: "wifi", name: "wlan0",
      address: "02:00:00:00:00:01", connected: false,
      state: "disconnected", managed: true, autoconnect: true,
      ambiguous: false, generation: generation
    }]
    function activeConnectionUuidForDevice(device) {
      return device === root.deviceId ? root.activeUuid : ""
    }
  }

  Network.NetworkProfileActionDispatcher {
    id: dispatcher
    active: true
    networkAdapter: adapter
    savedProfileCatalog: catalog
    networkTelemetry: telemetry
    commandOverride: ["/usr/bin/python3", root.fixturePath]
    workerTimeoutMs: 3000
    evidenceTimeoutMs: 1000
    drainTimeoutMs: 100
  }

  Network.NetworkProfileActionDispatcher {
    id: replacementDispatcher
    active: false
    networkAdapter: adapter
    savedProfileCatalog: catalog
    networkTelemetry: telemetry
    commandOverride: ["/usr/bin/python3", root.fixturePath]
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 160)
        return root.fail("timed out in phase " + root.phase + ": "
          + JSON.stringify(dispatcher.actionSnapshot))
      if (root.phase === 0) {
        if (!dispatcher.authorized) return
        const result = dispatcher.connectProfile({
          entityId: root.profileId, generation: adapter.generation
        }, root.deviceId)
        if (!result.accepted || !dispatcher.busy
            || telemetry.owners.length !== 1 || catalog.owners.length !== 1)
          return root.fail("catalog profile connect was not admitted")
        root.phase = 1
        return
      }
      if (root.phase === 1) {
        if (dispatcher.workerRunning) return
        if (dispatcher.phase !== "pending")
          return root.fail("helper completion bypassed native evidence")
        root.activeUuid = root.uuid
        adapter.deviceSnapshots[0].connected = true
        adapter.generation++
        root.phase = 2
        return
      }
      if (root.phase === 2) {
        if (dispatcher.phase !== "succeeded") return
        if (telemetry.owners.length !== 0 || catalog.owners.length !== 0)
          return root.fail("connect evidence leases were retained")
        root.activeUuid = ""
        const result = dispatcher.forgetProfile({
          entityId: root.profileId, generation: adapter.generation
        })
        if (!result.accepted) return root.fail("catalog Forget was rejected")
        root.phase = 3
        return
      }
      if (root.phase === 3) {
        if (dispatcher.workerRunning) return
        if (dispatcher.phase !== "pending" || catalog.refreshCalls !== 1)
          return root.fail("Forget did not wait for refreshed catalog")
        catalog.profileSnapshots = []
        catalog.generation++
        root.phase = 4
        return
      }
      if (root.phase === 4) {
        if (dispatcher.phase !== "succeeded") return
        if (telemetry.owners.length !== 0 || catalog.owners.length !== 0)
          return root.fail("Forget evidence leases were retained")
        catalog.profileSnapshots = [{
          schemaVersion: 1, id: root.profileId, uuid: root.uuid,
          name: "Hidden fixture", profileType: "wifi", ssid: "Hidden",
          ssidHex: "48696464656E", security: "wpa2-psk",
          enterprise: false, hidden: true, autoconnect: true, timestamp: 1
        }]
        catalog.generation++
        adapter.generation++
        dispatcher.commandOverride = [
          "/usr/bin/python3", root.fixturePath, "fail"
        ]
        const failed = dispatcher.connectProfile({
          entityId: root.profileId, generation: adapter.generation
        }, root.deviceId)
        if (!failed.accepted) return root.fail("uncertain action was rejected")
        root.phase = 40
        root.ticks = 0
        return
      }
      if (root.phase === 40) {
        if (dispatcher.phase === "pending") return
        if (dispatcher.phase !== "failed"
            || telemetry.owners.length !== 0 || catalog.owners.length !== 0)
          return root.fail("uncertain helper exit did not settle boundedly")
        dispatcher.commandOverride = [
          "/usr/bin/python3", root.fixturePath, "slow", root.slowPidPath
        ]
        const result = dispatcher.connectProfile({
          entityId: root.profileId, generation: adapter.generation
        }, root.deviceId)
        if (!result.accepted) return root.fail("post-failure action was rejected")
        root.phase = 5
        root.ticks = 0
        return
      }
      if (root.phase === 5) {
        if (!dispatcher.workerRunning || !dispatcher.workerStarted) return
        replacementDispatcher.active = true
        dispatcher.active = false
        root.phase = 6
        root.ticks = 0
        return
      }
      if (root.phase === 6) {
        if (dispatcher.workerRunning && replacementDispatcher.authorized)
          return root.fail("replacement authorized before old worker drained")
        if (!replacementDispatcher.authorized) return
        if (dispatcher.workerRunning)
          return root.fail("replacement overlapped old profile worker")
        console.log("network profile action dispatcher regression passed")
        Qt.exit(0)
      }
    }
  }
}
