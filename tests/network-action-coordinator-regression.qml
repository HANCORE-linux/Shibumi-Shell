pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string openId: ""
  property string pskId: ""
  property string profileNetworkId: ""
  property string profileId: ""
  property real uncertainDispatchGeneration: -1
  property real uncertainResultGeneration: -1
  readonly property string secretMarker: "SHIBUMI-TOP-SECRET-12345"

  function fail(message) {
    console.error("network-action-coordinator-regression:", message)
    Qt.exit(1)
  }

  function networkRow(ssid) {
    const rows = adapter.networkSnapshots
    for (let index = 0; index < rows.length; index++) {
      if (rows[index].ssid === ssid) return rows[index]
    }
    return null
  }

  function profileRow() {
    const rows = adapter.profileSnapshots
    for (let index = 0; index < rows.length; index++) {
      if (rows[index].uuid === profileSetting.uuid) return rows[index]
    }
    return null
  }

  function request(entityId) {
    return { entityId: entityId, generation: adapter.generation }
  }

  function assertNoSecret(label) {
    if (JSON.stringify(coordinator.actionSnapshot).indexOf(root.secretMarker) >= 0
        || coordinator.failureMessage.indexOf(root.secretMarker) >= 0)
      root.fail(label + " leaked a credential into action state")
  }

  QtObject {
    id: openNetwork
    property string ssid: "Guest"
    property string securityToken: "open"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 70
  }

  QtObject {
    id: pskNetwork
    property string ssid: "Private"
    property string securityToken: "wpa2-psk"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 60
  }

  QtObject {
    id: profileSetting
    property string uuid: "11111111-1111-4111-8111-111111111111"
    property string profileName: "Saved office"
  }

  QtObject {
    id: savedNetwork
    property string ssid: "Saved"
    property string securityToken: "wpa2-psk"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 50
    property var nmSettings: [profileSetting]
  }

  QtObject {
    id: wifiDevice
    property string typeToken: "wifi"
    property string name: "wlan-action"
    property string address: "AA:BB:CC:DD:EE:10"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property var networks: [openNetwork, pskNetwork, savedNetwork]
  }

  QtObject {
    id: fakeBackend
    signal connectionFailure(var deviceObject, var networkObject, string reason)
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property string activeConnectionUuid: ""
    property var devices: [wifiDevice]
    property int resultMode: 0
    property int radioCalls: 0
    property int connectCalls: 0
    property int pskCalls: 0
    property int disconnectCalls: 0
    property int profileConnectCalls: 0
    property int profileForgetCalls: 0
    property string lastSecret: ""
    property var nestedResult: null

    function activeConnectionUuidForDevice(deviceId) {
      return deviceId === adapter.deviceSnapshots[0].id
        ? activeConnectionUuid : ""
    }

    function result() {
      if (resultMode === 1) {
        root.uncertainDispatchGeneration = adapter.generation
        adapter.generation++
        root.uncertainResultGeneration = adapter.generation
        return {
          ok: false, code: "unsupported", message: root.secretMarker,
          generation: adapter.generation
        }
      }
      if (resultMode === 2) return {
        ok: true, code: "accepted", message: [root.secretMarker],
        generation: -1
      }
      if (resultMode === 3) {
        resultMode = 0
        nestedResult = coordinator.connectNetwork(root.request(root.pskId))
      }
      return true
    }
    function setWifiEnabled(_enabled) { radioCalls++; return result() }
    function connectNetwork(_network) { connectCalls++; return result() }
    function connectNetworkWithPsk(_network, secret) {
      pskCalls++
      lastSecret = secret
      return result()
    }
    function disconnectNetwork(_network) { disconnectCalls++; return result() }
    function connectProfile(_network, _profile) {
      profileConnectCalls++
      return result()
    }
    function forgetProfile(_profile) { profileForgetCalls++; return result() }
  }

  QtObject {
    id: fakeCatalog
    property bool available: true
    property real generation: 1
    property var profileSnapshots: [{
      schemaVersion: 1,
      id: "shibumi-network-v1:" + JSON.stringify([
        "saved-profile", profileSetting.uuid
      ]),
      uuid: profileSetting.uuid,
      name: "Saved office",
      profileType: "wifi",
      ssid: "Saved",
      ssidHex: "5361766564",
      security: "wpa2-psk",
      enterprise: false,
      hidden: false,
      autoconnect: true,
      timestamp: 1
    }]
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: fakeBackend
    savedProfileCatalog: fakeCatalog
  }

  Network.NetworkActionCoordinator {
    id: coordinator
    active: true
    networkAdapter: adapter
    actionTimeoutMs: 150
  }

  Network.NetworkActionCoordinator {
    id: standbyCoordinator
    active: true
    networkAdapter: adapter
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 160)
        return root.fail("action coordinator timed out in phase " + root.phase
          + ": " + JSON.stringify(coordinator.actionSnapshot))

      if (root.phase === 0) {
        const open = root.networkRow("Guest")
        const psk = root.networkRow("Private")
        const saved = root.networkRow("Saved")
        const profile = root.profileRow()
        if (!coordinator.authorized || standbyCoordinator.authorized
            || !adapter.backendAvailable || !open || !psk || !saved || !profile)
          return
        if ("authorityGuard" in coordinator)
          return root.fail("action authority guard escaped publicly")
        root.openId = open.id
        root.pskId = psk.id
        root.profileNetworkId = saved.id
        root.profileId = profile.id
        const stale = coordinator.connectNetwork({
          entityId: root.openId, generation: adapter.generation - 1
        })
        if (stale.accepted || fakeBackend.connectCalls !== 0)
          return root.fail("stale action reached the backend")
        const result = coordinator.connectNetwork(root.request(root.openId))
        if (!result.accepted || !coordinator.busy
            || coordinator.actionKind !== "connect")
          return root.fail("connect dispatch was not tracked")
        const busy = coordinator.setWifiEnabled(
          root.request(adapter.radioSnapshot.id), false)
        if (busy.accepted || busy.code !== "busy" || fakeBackend.radioCalls !== 0)
          return root.fail("parallel action was not rejected")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        openNetwork.stateChanging = true
        openNetwork.stateToken = "connecting"
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (!coordinator.busy) return root.fail("connect completed too early")
        openNetwork.connected = true
        openNetwork.stateChanging = false
        openNetwork.stateToken = "connected"
        wifiDevice.connected = true
        wifiDevice.stateToken = "connected"
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (coordinator.phase !== "succeeded"
            || coordinator.actionSnapshot.code !== "completed") return
        coordinator.clearResult()
        const result = coordinator.disconnectNetwork(root.request(root.openId))
        if (!result.accepted) return root.fail("disconnect was rejected")
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        openNetwork.connected = false
        openNetwork.stateChanging = false
        openNetwork.stateToken = "disconnected"
        wifiDevice.connected = false
        wifiDevice.stateToken = "disconnected"
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (coordinator.phase !== "succeeded") return
        coordinator.clearResult()
        const result = coordinator.connectNetworkWithPsk(
          root.request(root.pskId), root.secretMarker)
        if (!result.accepted || fakeBackend.lastSecret !== root.secretMarker)
          return root.fail("PSK dispatch did not reach the exact backend path")
        root.assertNoSecret("pending PSK action")
        pskNetwork.connected = true
        pskNetwork.stateToken = "connected"
        wifiDevice.connected = true
        wifiDevice.stateToken = "connected"
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (coordinator.phase !== "succeeded") return
        root.assertNoSecret("completed PSK action")
        coordinator.clearResult()
        pskNetwork.connected = false
        pskNetwork.stateToken = "disconnected"
        wifiDevice.connected = false
        wifiDevice.stateToken = "disconnected"
        const result = coordinator.connectProfile(root.request(root.profileId))
        if (!result.accepted) return root.fail("saved profile dispatch was rejected")
        fakeBackend.activeConnectionUuid = profileSetting.uuid
        savedNetwork.connected = true
        savedNetwork.stateToken = "connected"
        wifiDevice.connected = true
        wifiDevice.stateToken = "connected"
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        if (coordinator.phase !== "succeeded") return
        coordinator.clearResult()
        fakeBackend.activeConnectionUuid = ""
        savedNetwork.connected = false
        savedNetwork.stateToken = "disconnected"
        wifiDevice.connected = false
        wifiDevice.stateToken = "disconnected"
        const result = coordinator.forgetProfile(root.request(root.profileId))
        if (!result.accepted) return root.fail("forget profile was rejected")
        savedNetwork.nmSettings = []
        root.phase = 70
        root.ticks = 0
        return
      }

      if (root.phase === 70) {
        if (root.ticks < 3) return
        if (coordinator.phase !== "pending")
          return root.fail("native removal completed before catalog absence")
        fakeCatalog.profileSnapshots = []
        fakeCatalog.generation++
        root.phase = 8
        return
      }

      if (root.phase === 8) {
        if (coordinator.phase !== "succeeded") return
        coordinator.clearResult()
        const result = coordinator.setWifiEnabled(
          root.request(adapter.radioSnapshot.id), false)
        if (!result.accepted || fakeBackend.radioCalls !== 1)
          return root.fail("Wi-Fi disable was rejected")
        fakeBackend.wifiEnabled = false
        root.phase = 9
        return
      }

      if (root.phase === 9) {
        if (coordinator.phase !== "succeeded") return
        coordinator.clearResult()
        fakeBackend.wifiEnabled = true
        const result = coordinator.connectNetwork(root.request(root.openId))
        if (!result.accepted)
          return root.fail("adapter-replacement action was rejected")
        coordinator.networkAdapter = null
        root.phase = 10
        return
      }

      if (root.phase === 10) {
        if (coordinator.phase !== "failed") return
        if (coordinator.failureCode !== "adapter-replaced")
          return root.fail("adapter replacement did not fail pending action")
        coordinator.networkAdapter = adapter
        coordinator.clearResult()
        const result = coordinator.connectNetwork(root.request(root.openId))
        if (!result.accepted) return root.fail("timeout action was rejected")
        root.phase = 11
        root.ticks = 0
        return
      }

      if (root.phase === 11) {
        if (coordinator.phase !== "failed") return
        if (coordinator.failureCode !== "timeout")
          return root.fail("pending action did not time out")
        coordinator.clearResult()
        const result = coordinator.connectNetwork(root.request(root.openId))
        if (!result.accepted) return root.fail("liveness-loss action was rejected")
        fakeBackend.backendAvailable = false
        root.phase = 12
        return
      }

      if (root.phase === 12) {
        if (coordinator.phase !== "failed") return
        if (coordinator.failureCode !== "unavailable")
          return root.fail("backend loss did not fail pending action")
        fakeBackend.backendAvailable = true
        coordinator.clearResult()
        fakeBackend.resultMode = 1
        const result = coordinator.connectNetwork(root.request(root.openId))
        if (result.accepted || result.code !== "uncertain" || !coordinator.busy
            || root.uncertainResultGeneration
              <= root.uncertainDispatchGeneration
            || coordinator.actionSnapshot.observedGeneration
              !== root.uncertainResultGeneration)
          return root.fail("uncertain rejection released the action barrier")
        const blocked = coordinator.setWifiEnabled(
          root.request(adapter.radioSnapshot.id), false)
        if (blocked.accepted || blocked.code !== "busy")
          return root.fail("uncertain rejection allowed a second mutation")
        root.assertNoSecret("backend rejection")
        root.phase = 13
        root.ticks = 0
        return
      }

      if (root.phase === 13) {
        if (coordinator.phase !== "failed") return
        if (coordinator.failureCode !== "timeout")
          return root.fail("uncertain rejection did not retain timeout barrier")
        root.assertNoSecret("settled backend rejection")
        coordinator.clearResult()
        fakeBackend.resultMode = 2
        const result = coordinator.connectNetwork(root.request(root.openId))
        if (result.accepted || result.code !== "uncertain" || !coordinator.busy)
          return root.fail("malformed result released the action barrier")
        root.phase = 14
        root.ticks = 0
        return
      }

      if (root.phase === 14) {
        if (coordinator.phase !== "failed") return
        if (coordinator.failureCode !== "timeout")
          return root.fail("malformed result did not remain bounded")
        root.assertNoSecret("malformed backend result")
        coordinator.clearResult()
        fakeBackend.resultMode = 0
        const failed = coordinator.connectNetworkWithPsk(
          root.request(root.pskId), root.secretMarker)
        if (!failed.accepted) return root.fail("failure action was rejected")
        fakeBackend.connectionFailure(
          wifiDevice, pskNetwork, "no-secrets")
        root.phase = 140
        root.ticks = 0
        return
      }

      if (root.phase === 140) {
        if (coordinator.phase !== "failed") return
        if (coordinator.failureCode !== "connection-no-secrets"
            || coordinator.failureMessage !== "Network credentials were rejected.")
          return root.fail("native connection failure was not attributed")
        root.assertNoSecret("native connection failure")
        coordinator.clearResult()
        const symbolRequest = root.request(root.openId)
        symbolRequest[Symbol("extra")] = true
        const callsBeforeSymbol = fakeBackend.connectCalls
        const symbolResult = coordinator.connectNetwork(symbolRequest)
        if (symbolResult.accepted || symbolResult.code !== "invalid"
            || fakeBackend.connectCalls !== callsBeforeSymbol)
          return root.fail("symbol-key request crossed the coordinator boundary")
        fakeBackend.resultMode = 3
        const callsBeforeReentry = fakeBackend.connectCalls
        const result = coordinator.connectNetwork(root.request(root.openId))
        if (!result.accepted || !coordinator.busy
            || !fakeBackend.nestedResult
            || fakeBackend.nestedResult.accepted
            || fakeBackend.nestedResult.code !== "busy"
            || fakeBackend.connectCalls !== callsBeforeReentry + 1
            || coordinator.actionEntityId !== root.openId)
          return root.fail("delegate re-entry crossed the action barrier")
        openNetwork.connected = true
        openNetwork.stateToken = "connected"
        wifiDevice.connected = true
        wifiDevice.stateToken = "connected"
        root.phase = 15
        root.ticks = 0
        return
      }

      if (root.phase === 15) {
        if (coordinator.phase !== "succeeded") return
        if (coordinator.actionEntityId !== root.openId)
          return root.fail("re-entry replaced the tracked original action")
        coordinator.active = false
        standbyCoordinator.active = false
        console.log("network action coordinator regression passed")
        Qt.exit(0)
      }
    }
  }
}
