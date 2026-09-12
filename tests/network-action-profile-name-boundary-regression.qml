pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("network-action-profile-name-boundary-regression:", message)
    Qt.exit(1)
  }

  function profileRow() {
    const rows = adapter.profileSnapshots
    return rows.length === 1 ? rows[0] : null
  }

  function openRow() {
    const rows = adapter.networkSnapshots
    for (let index = 0; index < rows.length; index++) {
      if (rows[index].ssid === openNetwork.ssid) return rows[index]
    }
    return null
  }

  function dispatchUnrelated(label) {
    const row = root.openRow()
    if (!row || !row.canConnect)
      return root.fail(label + " removed unrelated action capability")
    const result = coordinator.connectNetwork({
      entityId: row.id,
      generation: adapter.generation
    })
    if (!result.accepted || !coordinator.busy)
      return root.fail(label + " blocked unrelated action dispatch")
    openNetwork.connected = true
    openNetwork.stateToken = "connected"
    wifiDevice.connected = true
    wifiDevice.stateToken = "connected"
  }

  QtObject {
    id: profileSetting
    property string uuid: "11111111-1111-4111-8111-111111111111"
    property string profileName: "é".repeat(128)
  }

  QtObject {
    id: savedNetwork
    property string ssid: "Saved"
    property string securityToken: "wpa2-psk"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 40
    property var nmSettings: [profileSetting]
  }

  QtObject {
    id: openNetwork
    property string ssid: "Guest"
    property string securityToken: "open"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 60
  }

  QtObject {
    id: wifiDevice
    property string typeToken: "wifi"
    property string name: "wlan-profile-name"
    property string address: "AA:BB:CC:DD:EE:42"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property var networks: [savedNetwork, openNetwork]
  }

  QtObject {
    id: fakeBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [wifiDevice]
    property int connectCalls: 0

    function connectNetwork(_network) {
      connectCalls++
      return true
    }
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: fakeBackend
  }

  Network.NetworkActionCoordinator {
    id: coordinator
    active: true
    networkAdapter: adapter
    actionTimeoutMs: 400
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("profile-name boundary regression timed out in phase "
          + root.phase)

      if (root.phase === 0) {
        if (!coordinator.authorized || !adapter.backendAvailable) return
        const row = root.profileRow()
        if (!row || row.name !== "é".repeat(128))
          return root.fail("exact 256-byte profile name was not projected")
        root.dispatchUnrelated("exact profile-name boundary")
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (coordinator.phase !== "succeeded") return
        coordinator.clearResult()
        openNetwork.connected = false
        openNetwork.stateToken = "disconnected"
        wifiDevice.connected = false
        wifiDevice.stateToken = "disconnected"
        profileSetting.profileName = "é".repeat(128) + "A"
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (coordinator.phase !== "idle" || root.openRow().connected) return
        const row = root.profileRow()
        if (!row || row.name !== "")
          return root.fail("overlong UTF-8 profile name was not sanitized")
        root.dispatchUnrelated("overlong profile name")
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (coordinator.phase !== "succeeded") return
        coordinator.clearResult()
        openNetwork.connected = false
        openNetwork.stateToken = "disconnected"
        wifiDevice.connected = false
        wifiDevice.stateToken = "disconnected"
        profileSetting.profileName = "\ud800"
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (coordinator.phase !== "idle" || root.openRow().connected) return
        const row = root.profileRow()
        if (!row || row.name !== "")
          return root.fail("malformed Unicode profile name was not sanitized")
        root.dispatchUnrelated("malformed profile name")
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (coordinator.phase !== "succeeded") return
        coordinator.clearResult()
        openNetwork.connected = false
        openNetwork.stateToken = "disconnected"
        wifiDevice.connected = false
        wifiDevice.stateToken = "disconnected"
        profileSetting.profileName = "bad\tname"
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (coordinator.phase !== "idle" || root.openRow().connected) return
        const row = root.profileRow()
        if (!row || row.name !== "")
          return root.fail("C0 profile name was not sanitized")
        root.dispatchUnrelated("C0 profile name")
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        if (coordinator.phase !== "succeeded") return
        coordinator.clearResult()
        openNetwork.connected = false
        openNetwork.stateToken = "disconnected"
        wifiDevice.connected = false
        wifiDevice.stateToken = "disconnected"
        profileSetting.profileName = "bad\u0085name"
        root.phase = 8
        return
      }

      if (root.phase === 8) {
        if (coordinator.phase !== "idle" || root.openRow().connected) return
        const row = root.profileRow()
        if (!row || row.name !== "")
          return root.fail("C1 profile name was not sanitized")
        root.dispatchUnrelated("C1 profile name")
        root.phase = 9
        return
      }

      if (root.phase === 9) {
        if (coordinator.phase !== "succeeded") return
        if (fakeBackend.connectCalls !== 5)
          return root.fail("profile-name cases did not reach unrelated delegate")
        console.log("network action profile name boundary regression passed")
        Qt.exit(0)
      }
    }
  }
}
