pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("network-enterprise-adapter-regression:", message)
    Qt.exit(1)
  }

  function row(ssid) {
    const rows = adapter.networkSnapshots
    for (let index = 0; index < rows.length; index++) {
      if (rows[index].ssid === ssid) return rows[index]
    }
    return null
  }

  QtObject {
    id: enterpriseNetwork
    property string ssid: "Corp Café"
    property string securityToken: "wpa2-eap"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 75
    property var nmSettings: []
  }

  QtObject {
    id: suiteNetwork
    property string ssid: "Suite"
    property string securityToken: "wpa3-suite-b-192"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 70
    property var nmSettings: []
  }

  QtObject {
    id: device
    property string typeToken: "wifi"
    property string name: "wlan0"
    property string address: "02:00:00:00:00:01"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property var networks: [enterpriseNetwork, suiteNetwork]
  }

  QtObject {
    id: backend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [device]
    function setWifiEnabled(_value) { return true }
    function connectNetwork(_target) { return true }
    function connectNetworkWithPsk(_target, _secret) { return true }
    function disconnectNetwork(_target) { return true }
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: backend
  }

  Network.NetworkEnterpriseDispatcher {
    id: fakeDispatcher
    active: true
    networkAdapter: adapter
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("adapter descriptor timed out in phase " + root.phase)
      if (root.phase === 0) {
        const enterprise = root.row("Corp Café")
        const suite = root.row("Suite")
        if (!enterprise || !suite || !fakeDispatcher.authorized) return
        if (fakeDispatcher.helperPath.indexOf("/") !== 0
            || fakeDispatcher.helperPath.indexOf("file:") === 0)
          return root.fail("default Enterprise helper is not a filesystem path")
        const result = adapter.enterpriseConnectionDescriptor({
          entityId: enterprise.id, generation: adapter.generation
        })
        if (!result.ok || result.code !== "accepted" || !result.descriptor
            || result.descriptor.entityId !== enterprise.id
            || result.descriptor.deviceId !== enterprise.deviceId
            || result.descriptor.interfaceName !== "wlan0"
            || result.descriptor.hardwareAddress !== "02:00:00:00:00:01"
            || result.descriptor.security !== "wpa2-eap"
            || result.descriptor.ssidHex !== "436F727020436166C3A9"
            || "identity" in result.descriptor
            || "password" in result.descriptor)
          return root.fail("primitive Enterprise descriptor was wrong: "
            + JSON.stringify(result))
        const suiteResult = adapter.enterpriseConnectionDescriptor({
          entityId: suite.id, generation: adapter.generation
        })
        if (suiteResult.ok || suiteResult.code !== "unsupported")
          return root.fail("Suite-B crossed the PEAP boundary")
        const isolated = fakeDispatcher.connectNetworkEnterprise({
          entityId: enterprise.id, generation: adapter.generation
        }, {
          method: "peap-mschapv2", identity: "user@example.test",
          password: "must not reach host", serverDomain: "radius.example.test"
        })
        if (isolated.ok || isolated.code !== "unavailable"
            || fakeDispatcher.running || !fakeDispatcher.available)
          return root.fail("fake adapter could launch production helper")
        fakeDispatcher.commandOverride = []
        const emptyCommand = fakeDispatcher.connectNetworkEnterprise({
          entityId: enterprise.id, generation: adapter.generation
        }, {
          method: "peap-mschapv2", identity: "user@example.test",
          password: "must not be retained", serverDomain: "radius.example.test"
        })
        if (emptyCommand.ok || emptyCommand.code !== "unavailable"
            || fakeDispatcher.running || !fakeDispatcher.available)
          return root.fail("empty Enterprise command retained dispatcher state")
        const staleGeneration = adapter.generation
        enterpriseNetwork.known = true
        root.phase = 1
        root.ticks = 0
        root.staleGeneration = staleGeneration
        return
      }
      if (root.phase === 1) {
        const enterprise = root.row("Corp Café")
        if (!enterprise || adapter.generation === root.staleGeneration) return
        const stale = adapter.enterpriseConnectionDescriptor({
          entityId: enterprise.id, generation: root.staleGeneration
        })
        const known = adapter.enterpriseConnectionDescriptor({
          entityId: enterprise.id, generation: adapter.generation
        })
        if (stale.ok || stale.code !== "stale-generation"
            || known.ok || known.code !== "unsupported")
          return root.fail("saved/stale Enterprise identity was admitted")
        console.log("network enterprise adapter regression passed")
        Qt.exit(0)
      }
    }
  }

  property real staleGeneration: -1
}
