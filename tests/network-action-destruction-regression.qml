pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  readonly property var coordinator: coordinatorLoader.item

  function fail(message) {
    console.error("network-action-destruction-regression:", message)
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
    property string name: "wlan-action-destroy"
    property string address: "AA:BB:CC:DD:EE:30"
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

  Component {
    id: coordinatorComponent
    Network.NetworkActionCoordinator {
      active: true
      networkAdapter: adapter
      actionTimeoutMs: 1000
    }
  }

  Loader { id: coordinatorLoader; sourceComponent: coordinatorComponent }

  Network.NetworkActionCoordinator {
    id: replacement
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
        return root.fail("action destruction regression timed out")
      if (root.phase === 0) {
        if (!root.coordinator || !root.coordinator.authorized) return
        const row = adapter.networkSnapshots[0]
        if (!row) return
        const result = root.coordinator.connectNetwork({
          entityId: row.id, generation: adapter.generation
        })
        if (!result.accepted || !root.coordinator.busy)
          return root.fail("destruction action was not pending")
        coordinatorLoader.active = false
        replacement.active = true
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.coordinator !== null)
        return root.fail("destroyed action coordinator survived")
      if (replacement.authorized || replacement.busy)
        return root.fail("uncertain action destruction reopened authority")
      if (backend.connectCalls !== 1)
        return root.fail("destruction duplicated the pending mutation")
      if (root.ticks < 25) return
      replacement.active = false
      console.log("network action destruction regression passed")
      Qt.exit(0)
    }
  }
}
