pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("network-action-lifecycle-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: network
    property string ssid: "Guest"
    property string securityToken: "open"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 50
  }

  QtObject {
    id: device
    property string typeToken: "wifi"
    property string name: "wlan-action-life"
    property string address: "AA:BB:CC:DD:EE:20"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property var networks: [network]
  }

  QtObject {
    id: backend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [device]
    property int connectCalls: 0
    function setWifiEnabled(_enabled) { return true }
    function connectNetwork(_target) { connectCalls++; return true }
    function connectNetworkWithPsk(_target, _secret) { return true }
    function disconnectNetwork(_target) { return true }
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: backend
  }

  Network.NetworkActionCoordinator {
    id: firstCoordinator
    active: true
    networkAdapter: adapter
    actionTimeoutMs: 400
  }

  Network.NetworkActionCoordinator {
    id: replacementCoordinator
    active: false
    networkAdapter: adapter
    actionTimeoutMs: 400
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("action authority handoff timed out")
      if (root.phase === 0) {
        if (!firstCoordinator.authorized) return
        if (replacementCoordinator.authorized)
          return root.fail("two action coordinators held authority")
        const row = adapter.networkSnapshots[0]
        if (!row) return
        const result = firstCoordinator.connectNetwork({
          entityId: row.id, generation: adapter.generation
        })
        if (!result.accepted || !firstCoordinator.busy)
          return root.fail("pending action was not established")
        firstCoordinator.active = false
        replacementCoordinator.active = true
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.ticks < 10 && replacementCoordinator.authorized)
        return root.fail("action authority released before timeout settlement")
      if (!replacementCoordinator.authorized) return
      if (firstCoordinator.authorized || firstCoordinator.busy
          || firstCoordinator.phase !== "failed"
          || firstCoordinator.failureCode !== "timeout")
        return root.fail("old action authority did not settle fail-closed")
      if (backend.connectCalls !== 1)
        return root.fail("authority handoff duplicated the dispatch")
      firstCoordinator.active = false
      replacementCoordinator.active = false
      console.log("network action lifecycle regression passed")
      Qt.exit(0)
    }
  }
}
