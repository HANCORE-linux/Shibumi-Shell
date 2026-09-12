pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("network-action-shutdown-completion-regression:", message)
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
    property string name: "wlan-action-shutdown"
    property string address: "AA:BB:CC:DD:EE:50"
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
    function setWifiEnabled(_enabled) { return true }
    function connectNetwork(_target) { return true }
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
    actionTimeoutMs: 1000
  }

  Network.NetworkActionCoordinator {
    id: replacementCoordinator
    active: false
    networkAdapter: adapter
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("successful shutdown settlement timed out")
      if (root.phase === 0) {
        if (!firstCoordinator.authorized) return
        const row = adapter.networkSnapshots[0]
        if (!row) return
        const result = firstCoordinator.connectNetwork({
          entityId: row.id, generation: adapter.generation
        })
        if (!result.accepted) return root.fail("shutdown action was rejected")
        firstCoordinator.active = false
        replacementCoordinator.active = true
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (replacementCoordinator.authorized)
          return root.fail("replacement claimed before successful settlement")
        if (root.ticks < 5) return
        network.connected = true
        network.stateToken = "connected"
        device.connected = true
        device.stateToken = "connected"
        root.phase = 2
        return
      }
      if (!replacementCoordinator.authorized) return
      if (firstCoordinator.authorized || firstCoordinator.busy
          || firstCoordinator.phase !== "succeeded"
          || firstCoordinator.actionSnapshot.code !== "completed")
        return root.fail("successful shutdown did not release authority")
      firstCoordinator.active = false
      replacementCoordinator.active = false
      console.log("network action shutdown completion regression passed")
      Qt.exit(0)
    }
  }
}
