pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as Model

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property real signalGeneration: -1
  property real replacementGeneration: -1
  property string personalId: ""
  property string exactProfileId: ""
  property real profileReplacementGeneration: -1
  property var replacementRequest: null

  function fail(message) {
    console.error("network-native-backend-seam-regression:", message)
    Qt.exit(1)
  }

  function rowFor(adapter, ssid) {
    const rows = adapter.networkSnapshots
    for (let index = 0; index < rows.length; index++) {
      if (rows[index].ssid === ssid) return rows[index]
    }
    return null
  }

  function profileFor(adapter, deviceId, uuid) {
    const rows = adapter.profileSnapshots
    for (let index = 0; index < rows.length; index++) {
      if (rows[index].deviceId === deviceId && rows[index].uuid === uuid)
        return rows[index]
    }
    return null
  }

  function sparseProfiles(length, duplicate) {
    const rows = new Array(length)
    if (duplicate && length > 0) {
      rows[0] = duplicate
      rows[length - 1] = duplicate
    }
    return rows
  }

  QtObject {
    id: personal
    property string ssid: "Office:Personal [west]"
    property string securityToken: "wpa2-psk"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 41
  }

  QtObject {
    id: personalReplacement
    property string ssid: "Office:Personal [west]"
    property string securityToken: "wpa2-psk"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 77
  }

  QtObject {
    id: personalDuplicate
    property string ssid: "Office:Personal [west]"
    property string securityToken: "sae"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 52
  }

  QtObject {
    id: openNetwork
    property string ssid: "Guest"
    property string securityToken: "open"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 62
  }

  QtObject {
    id: unicodeNfc
    property string ssid: "Caf\u00e9"
    property string securityToken: "open"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 30
  }

  QtObject {
    id: unicodeNfd
    property string ssid: "Cafe\u0301"
    property string securityToken: "open"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 29
  }

  QtObject {
    id: spacedNetwork
    property string ssid: " Office "
    property string securityToken: "owe"
    property bool connected: false
    property bool known: false
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 20
  }

  QtObject {
    id: savedSettingA
    property string uuid: "11111111-1111-4111-8111-111111111111"
    property string profileId: "Shared personal A"
    property string profileName: profileId
    property int forgetCalls: 0
    property int readCalls: 0
    function read() {
      readCalls++
      return {
        "connection": { id: profileId, timestamp: 101 },
        "802-11-wireless": { ssid: "Shared profile SSID" },
        "802-11-wireless-security": {
          "key-mgmt": "wpa-psk", "auth-alg": "open"
        }
      }
    }
    function forget() { forgetCalls++ }
  }

  QtObject {
    id: savedSettingB
    property string uuid: "22222222-2222-4222-8222-222222222222"
    property string profileId: "Shared enterprise B"
    property string profileName: profileId
    property int forgetCalls: 0
    property int readCalls: 0
    function read() {
      readCalls++
      return {
        "connection": { id: profileId, timestamp: 102 },
        "802-11-wireless": { ssid: "Shared profile SSID" },
        "802-11-wireless-security": {
          "key-mgmt": "wpa-eap", "auth-alg": "open"
        },
        "802-1x": {
          identity: "must-not-leak@example.invalid",
          "ca-cert": "/private/certificate/path"
        }
      }
    }
    function forget() { forgetCalls++ }
  }

  QtObject {
    id: exactProfileSetting
    property string uuid: "33333333-3333-4333-8333-333333333333"
    property string profileId: "Exact profile"
    property string profileName: profileId
    property int readCalls: 0
    function read() {
      readCalls++
      return {
        "connection": { id: profileId, timestamp: 303 },
        "802-11-wireless": { ssid: "Exact saved network" },
        "802-11-wireless-security": { "key-mgmt": "sae" }
      }
    }
  }

  QtObject {
    id: mixedValidProfileSetting
    property string uuid: "55555555-5555-4555-8555-555555555555"
    property string profileId: "Mixed valid profile"
    property string profileName: profileId
    function read() {
      return {
        "connection": { id: profileId, timestamp: 505 },
        "802-11-wireless": { ssid: "Mixed profile network" },
        "802-11-wireless-security": { "key-mgmt": "wpa-psk" }
      }
    }
  }

  QtObject {
    id: malformedProfileSetting
    property string uuid: "{66666666-6666-4666-8666-666666666666}"
    property string profileId: "Malformed profile"
    property string profileName: profileId
    function read() {
      return {
        "connection": { id: profileId, timestamp: 606 },
        "802-11-wireless": { ssid: "Mixed profile network" },
        "802-11-wireless-security": { "key-mgmt": ["wpa-psk"] }
      }
    }
  }

  QtObject {
    id: replacementProfileSetting
    property string uuid: "44444444-4444-4444-8444-444444444444"
    property string profileId: "Replacement profile"
    property string profileName: profileId
    function read() {
      return {
        "connection": { id: profileId, timestamp: 404 },
        "802-11-wireless": { ssid: "Exact saved network" },
        "802-11-wireless-security": { "key-mgmt": "sae" }
      }
    }
  }

  QtObject {
    id: connectedExactProfileSetting
    property string uuid: "77777777-7777-4777-8777-777777777777"
    property string profileName: "Connected exact profile"
  }

  QtObject {
    id: secondaryProfileSetting
    property string uuid: "33333333-3333-4333-8333-333333333333"
    property string profileId: "Exact profile on second adapter"
    property string profileName: profileId
    function read() {
      return {
        "connection": { id: profileId, timestamp: 305 },
        "802-11-wireless": { ssid: "Exact saved network" },
        "802-11-wireless-security": { "key-mgmt": "sae" }
      }
    }
  }

  QtObject {
    id: multiProfileNetwork
    property string ssid: "Shared profile SSID"
    property string securityToken: "wpa2-psk"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 55
    property list<QtObject> nmSettings: [savedSettingA, savedSettingB]
  }

  QtObject {
    id: exactProfileNetwork
    property string ssid: "Exact saved network"
    property string securityToken: "sae"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 73
    property var nmSettings: [exactProfileSetting]
  }

  QtObject {
    id: mixedProfileNetwork
    property string ssid: "Mixed profile network"
    property string securityToken: "wpa2-psk"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 61
    property list<QtObject> nmSettings: [
      mixedValidProfileSetting, malformedProfileSetting
    ]
  }

  QtObject {
    id: connectedExactProfileNetwork
    property string ssid: "Connected exact network"
    property string securityToken: "wpa2-psk"
    property bool connected: true
    property bool known: true
    property string stateToken: "connected"
    property bool stateChanging: false
    property real signal: 80
    property list<QtObject> nmSettings: [connectedExactProfileSetting]
  }

  QtObject {
    id: connectedMultiProfileNetwork
    property string ssid: "Connected shared profile"
    property string securityToken: "wpa2-psk"
    property bool connected: true
    property bool known: true
    property string stateToken: "connected"
    property bool stateChanging: false
    property real signal: 68
    property list<QtObject> nmSettings: [savedSettingA, savedSettingB]
  }

  QtObject {
    id: secondaryProfileNetwork
    property string ssid: "Exact saved network"
    property string securityToken: "sae"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 49
    property var nmSettings: [secondaryProfileSetting]
  }

  QtObject {
    id: wifiDevice
    property string typeToken: "wifi"
    property string name: "wlan:test 0"
    property string address: "aa-bb-cc-dd-ee-01"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property var networks: [
      personal, openNetwork, unicodeNfc, unicodeNfd, spacedNetwork
    ]
  }

  QtObject {
    id: sequenceDevice
    property string typeToken: "wifi"
    property string name: "wlan-sequence"
    property string address: "AA:BB:CC:DD:EE:77"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property list<QtObject> networks: [
      multiProfileNetwork, connectedMultiProfileNetwork, exactProfileNetwork,
      mixedProfileNetwork, connectedExactProfileNetwork
    ]
  }

  QtObject {
    id: secondarySequenceDevice
    property string typeToken: "wifi"
    property string name: "wlan-sequence-secondary"
    property string address: "AA:BB:CC:DD:EE:88"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property list<QtObject> networks: [secondaryProfileNetwork]
  }

  QtObject {
    id: fakeBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [wifiDevice]
    property int radioCalls: 0
    property int connectCalls: 0
    property int pskCalls: 0
    property int disconnectCalls: 0
    property int forgetCalls: 0
    property var lastTarget: null
    property string lastSecret: ""

    function setWifiEnabled(enabled) {
      radioCalls++
      wifiEnabled = enabled
      return true
    }
    function connectNetwork(target) {
      connectCalls++
      lastTarget = target
      return true
    }
    function connectNetworkWithPsk(target, secret) {
      pskCalls++
      lastTarget = target
      lastSecret = secret
      return true
    }
    function disconnectNetwork(target) {
      disconnectCalls++
      lastTarget = target
      return true
    }
    function forgetNetwork(_target) {
      forgetCalls++
      return true
    }
  }

  QtObject {
    id: sequenceBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property list<QtObject> devices: [
      sequenceDevice, secondarySequenceDevice
    ]
    property int pskCalls: 0
    property int disconnectCalls: 0
    property int profileConnectCalls: 0
    property int profileForgetCalls: 0
    property var lastProfile: null
    property var lastProfileNetwork: null
    function setWifiEnabled(_enabled) { return true }
    function connectNetwork(_target) { return true }
    function connectNetworkWithPsk(_target, _secret) {
      pskCalls++
      return true
    }
    function disconnectNetwork(_target) {
      disconnectCalls++
      return true
    }
    function connectProfile(network, profile) {
      profileConnectCalls++
      lastProfileNetwork = network
      lastProfile = profile
      return {
        ok: true,
        code: "accepted",
        message: "fixture profile dispatch accepted"
      }
    }
    function forgetProfile(profile) {
      profileForgetCalls++
      lastProfile = profile
      return true
    }
  }

  QtObject {
    id: incompleteProfileBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property list<QtObject> devices: [sequenceDevice]
    function setWifiEnabled(_enabled) { return true }
    function connectNetwork(_target) { return true }
    function connectNetworkWithPsk(_target, _secret) { return true }
    function disconnectNetwork(_target) { return true }
  }

  QtObject {
    id: boundaryProfileSetting
    property string uuid: "88888888-8888-4888-8888-888888888888"
    property string profileName: "Boundary profile"
  }

  QtObject {
    id: boundary4095Network
    property string ssid: "Boundary 4095"
    property string securityToken: "open"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 1
    property var nmSettings: root.sparseProfiles(4095, null)
  }

  QtObject {
    id: boundary4096Network
    property string ssid: "Boundary 4096"
    property string securityToken: "open"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 1
    property var nmSettings: root.sparseProfiles(4096, null)
  }

  QtObject {
    id: overflowNetwork
    property string ssid: "Overflow 4097"
    property string securityToken: "open"
    property bool connected: false
    property bool known: true
    property string stateToken: "disconnected"
    property bool stateChanging: false
    property real signal: 1
    property var nmSettings: root.sparseProfiles(
      4097, boundaryProfileSetting)
  }

  QtObject {
    id: boundary4095Device
    property string typeToken: "wifi"
    property string name: "wlan-boundary-4095"
    property string address: "AA:BB:CC:DD:EE:95"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property list<QtObject> networks: [boundary4095Network]
  }

  QtObject {
    id: boundary4096Device
    property string typeToken: "wifi"
    property string name: "wlan-boundary-4096"
    property string address: "AA:BB:CC:DD:EE:96"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property list<QtObject> networks: [boundary4096Network]
  }

  QtObject {
    id: overflowDevice
    property string typeToken: "wifi"
    property string name: "wlan-overflow-4097"
    property string address: "AA:BB:CC:DD:EE:97"
    property bool connected: false
    property string stateToken: "disconnected"
    property bool managed: true
    property bool autoconnect: true
    property list<QtObject> networks: [overflowNetwork]
  }

  QtObject {
    id: boundary4095Backend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property list<QtObject> devices: [boundary4095Device]
  }

  QtObject {
    id: boundary4096Backend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property list<QtObject> devices: [boundary4096Device]
  }

  QtObject {
    id: overflowBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property list<QtObject> devices: [overflowDevice]
    property int radioCalls: 0
    function setWifiEnabled(_enabled) { radioCalls++; return true }
  }

  QtObject {
    id: unavailableBackend
    property bool backendAvailable: false
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [wifiDevice]
  }

  QtObject {
    id: availableEmptyBackend
    property bool backendAvailable: true
    property bool wifiEnabled: false
    property bool wifiHardwareEnabled: false
    property string connectivity: "none"
    property var devices: []
  }

  QtObject {
    id: incompleteBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [wifiDevice]
  }

  QtObject {
    id: failingBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [wifiDevice]
    function setWifiEnabled(_enabled) { return true }
    function connectNetwork(_target) {
      return {
        ok: false,
        code: "unavailable",
        message: "fixture dispatch failed",
        entityId: "ignored",
        generation: 17
      }
    }
    function connectNetworkWithPsk(_target, _secret) { return true }
    function disconnectNetwork(_target) { return true }
  }

  QtObject {
    id: malformedResultBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property var connectivity: ["full"]
    property var devices: [wifiDevice]
    property int resultMode: 0
    property int okReads: 0
    property int codeReads: 0
    property int messageReads: 0
    property int generationReads: 0
    function resetReads() {
      okReads = 0
      codeReads = 0
      messageReads = 0
      generationReads = 0
    }
    function accessorResult(throwImmediately) {
      resetReads()
      const value = {}
      Object.defineProperty(value, "ok", {
        enumerable: true,
        get: function() {
          malformedResultBackend.okReads++
          if (throwImmediately || malformedResultBackend.okReads > 1)
            throw new Error("fixture ok getter failure")
          return true
        }
      })
      Object.defineProperty(value, "code", {
        enumerable: true,
        get: function() {
          malformedResultBackend.codeReads++
          if (malformedResultBackend.codeReads > 1)
            throw new Error("fixture code getter failure")
          return "accepted"
        }
      })
      Object.defineProperty(value, "message", {
        enumerable: true,
        get: function() {
          malformedResultBackend.messageReads++
          if (malformedResultBackend.messageReads > 1)
            throw new Error("fixture message getter failure")
          return ""
        }
      })
      Object.defineProperty(value, "generation", {
        enumerable: true,
        get: function() {
          malformedResultBackend.generationReads++
          if (malformedResultBackend.generationReads > 1)
            throw new Error("fixture generation getter failure")
          return malformedResultAdapter.generation
        }
      })
      return value
    }
    function setWifiEnabled(_enabled) { return true }
    function connectNetwork(_target) {
      if (resultMode === 0) {
        return {
          ok: true,
          code: "unavailable",
          message: "contradictory",
          generation: -0.5
        }
      }
      if (resultMode === 1) return {
        ok: true,
        code: ["accepted"],
        message: "array code",
        generation: 0
      }
      return accessorResult(resultMode === 3)
    }
    function connectNetworkWithPsk(_target, _secret) { return true }
    function disconnectNetwork(_target) { return true }
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: fakeBackend
  }

  Network.NetworkBackendAdapter {
    id: sequenceAdapter
    active: true
    backendOverride: sequenceBackend
  }

  Network.NetworkBackendAdapter {
    id: incompleteProfileAdapter
    active: true
    backendOverride: incompleteProfileBackend
  }

  Network.NetworkBackendAdapter {
    id: boundary4095Adapter
    active: true
    backendOverride: boundary4095Backend
  }

  Network.NetworkBackendAdapter {
    id: boundary4096Adapter
    active: true
    backendOverride: boundary4096Backend
  }

  Network.NetworkBackendAdapter {
    id: overflowAdapter
    active: true
    backendOverride: overflowBackend
  }

  Network.NetworkBackendAdapter {
    id: unavailableAdapter
    active: true
    backendOverride: unavailableBackend
  }

  Network.NetworkBackendAdapter {
    id: availableEmptyAdapter
    active: true
    backendOverride: availableEmptyBackend
  }

  Network.NetworkBackendAdapter {
    id: incompleteAdapter
    active: true
    backendOverride: incompleteBackend
  }

  Network.NetworkBackendAdapter {
    id: failingAdapter
    active: true
    backendOverride: failingBackend
  }

  Network.NetworkBackendAdapter {
    id: malformedResultAdapter
    active: true
    backendOverride: malformedResultBackend
  }

  Network.NetworkBackendAdapter {
    id: inactiveNativeAdapter
    active: false
  }

  QtObject {
    id: admittedNativeLiveness
    property bool serviceUsable: true
    property real generation: 1
  }

  Network.NetworkBackendAdapter {
    id: admittedNativeAdapter
    active: true
    nativeLiveness: admittedNativeLiveness
  }

  Network.NetworkBackendAdapter {
    id: unmonitoredNativeAdapter
    active: true
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (root.ticks < 4) return
        if (!admittedNativeAdapter.nativeGatewayLoaded) {
          if (root.ticks < 20) return
          return root.fail("admitted native gateway did not compile and load")
        }
        if (unmonitoredNativeAdapter.nativeGatewayLoaded)
          return root.fail("native gateway loaded before liveness admission")
        if (admittedNativeAdapter.backendAvailable
            || admittedNativeAdapter.deviceSnapshots.length !== 0)
          return root.fail("missing system bus did not stay unavailable")
        if (adapter.nativeGatewayLoaded || sequenceAdapter.nativeGatewayLoaded
            || inactiveNativeAdapter.nativeGatewayLoaded
            || unavailableAdapter.nativeGatewayLoaded
            || incompleteAdapter.nativeGatewayLoaded
            || incompleteProfileAdapter.nativeGatewayLoaded
            || boundary4095Adapter.nativeGatewayLoaded
            || boundary4096Adapter.nativeGatewayLoaded
            || overflowAdapter.nativeGatewayLoaded)
          return root.fail("fake or inactive adapter loaded the native gateway")
        if (!adapter.backendAvailable
            || adapter.deviceSnapshots.length !== 1
            || adapter.networkSnapshots.length !== 5)
          return root.fail("primitive fake snapshots did not initialize")
        if (unavailableAdapter.backendAvailable
            || unavailableAdapter.deviceSnapshots.length !== 0
            || unavailableAdapter.networkSnapshots.length !== 0
            || !availableEmptyAdapter.backendAvailable
            || availableEmptyAdapter.deviceSnapshots.length !== 0)
          return root.fail("unavailable and available-empty were conflated")
        const overflowRadio = overflowAdapter.setWifiEnabled({
          entityId: overflowAdapter.radioSnapshot.id,
          generation: overflowAdapter.generation
        }, false)
        if (boundary4095Adapter.snapshotDegraded
            || boundary4096Adapter.snapshotDegraded
            || !overflowAdapter.snapshotDegraded
            || overflowAdapter.backendSnapshot.degraded !== true
            || overflowAdapter.networkSnapshots.length !== 0
            || overflowAdapter.profileSnapshots.length !== 0
            || overflowRadio.ok || overflowRadio.code !== "unavailable"
            || overflowBackend.radioCalls !== 0)
          return root.fail("oversized backend topology did not fail closed")
        if (!sequenceAdapter.backendAvailable
            || sequenceAdapter.deviceSnapshots.length !== 2
            || sequenceAdapter.networkSnapshots.length !== 6
            || sequenceAdapter.profileSnapshots.length !== 8
            || sequenceAdapter.snapshotDegraded)
          return root.fail("QML list sequences or profile rows were discarded")
        const multiProfileRow = root.rowFor(
          sequenceAdapter, multiProfileNetwork.ssid)
        const connectedMultiProfileRow = root.rowFor(
          sequenceAdapter, connectedMultiProfileNetwork.ssid)
        const mixedProfileRow = root.rowFor(
          sequenceAdapter, mixedProfileNetwork.ssid)
        if (!multiProfileRow || !connectedMultiProfileRow || !mixedProfileRow
            || multiProfileRow.ambiguous || multiProfileRow.profileCount !== 2
            || multiProfileRow.canConnect || multiProfileRow.canConnectWithPsk
            || multiProfileRow.canDisconnect || multiProfileRow.canForget
            || connectedMultiProfileRow.ambiguous
            || connectedMultiProfileRow.profileCount !== 2
            || connectedMultiProfileRow.canConnect
            || connectedMultiProfileRow.canConnectWithPsk
            || !connectedMultiProfileRow.canDisconnect
            || connectedMultiProfileRow.canForget
            || mixedProfileRow.ambiguous
            || mixedProfileRow.profileCount !== 2
            || mixedProfileRow.validProfileCount !== 1
            || mixedProfileRow.canConnect
            || mixedProfileRow.canConnectWithPsk
            || mixedProfileRow.canDisconnect || mixedProfileRow.canForget)
          return root.fail("profile ambiguity crossed an aggregate action")
        const multiProfileResult = sequenceAdapter.connectNetworkWithPsk({
          entityId: multiProfileRow.id,
          generation: sequenceAdapter.generation
        }, "correct horse")
        const multiProfileDisconnect = sequenceAdapter.disconnectNetwork({
          entityId: connectedMultiProfileRow.id,
          generation: sequenceAdapter.generation
        })
        if (multiProfileResult.ok || multiProfileResult.code !== "unsupported"
            || !multiProfileDisconnect.ok
            || multiProfileDisconnect.code !== "accepted"
            || sequenceBackend.pskCalls !== 0
            || sequenceBackend.disconnectCalls !== 1)
          return root.fail("multi-profile exact action policy was not enforced")

        const primaryDeviceId = Model.deviceId("wifi",
          sequenceDevice.address, sequenceDevice.name)
        const secondaryDeviceId = Model.deviceId("wifi",
          secondarySequenceDevice.address, secondarySequenceDevice.name)
        const exactProfile = root.profileFor(sequenceAdapter,
          primaryDeviceId, exactProfileSetting.uuid)
        const secondaryProfile = root.profileFor(sequenceAdapter,
          secondaryDeviceId, secondaryProfileSetting.uuid)
        const connectedExactProfile = root.profileFor(sequenceAdapter,
          primaryDeviceId, connectedExactProfileSetting.uuid)
        if (!exactProfile || !secondaryProfile || !connectedExactProfile
            || exactProfile.id === secondaryProfile.id
            || exactProfile.uuid !== secondaryProfile.uuid
            || !exactProfile.canConnect || !exactProfile.canForget
            || exactProfile.ambiguous || secondaryProfile.ambiguous
            || connectedExactProfile.canConnect
            || !connectedExactProfile.canForget)
          return root.fail("saved-profile identity is not device scoped")
        for (let profileIndex = 0;
            profileIndex < sequenceAdapter.profileSnapshots.length;
            profileIndex++) {
          const profileRow = sequenceAdapter.profileSnapshots[profileIndex]
          if (profileRow.deviceId === primaryDeviceId
              && (profileRow.uuid === savedSettingA.uuid
                || profileRow.uuid === savedSettingB.uuid)
              && (!profileRow.ambiguous || profileRow.canConnect
                || profileRow.canForget))
            return root.fail("duplicate exact profile was actionable")
        }
        const profileRequest = {
          entityId: exactProfile.id,
          generation: sequenceAdapter.generation
        }
        const profileConnect = sequenceAdapter.connectProfile(profileRequest)
        const profileForget = sequenceAdapter.forgetProfile(profileRequest)
        const connectedProfileConnect = sequenceAdapter.connectProfile({
          entityId: connectedExactProfile.id,
          generation: sequenceAdapter.generation
        })
        if (!profileConnect.ok || profileConnect.code !== "accepted"
            || profileConnect.message
              !== "fixture profile dispatch accepted"
            || !profileForget.ok || profileForget.code !== "accepted"
            || connectedProfileConnect.ok
            || connectedProfileConnect.code !== "unsupported"
            || sequenceBackend.profileConnectCalls !== 1
            || sequenceBackend.profileForgetCalls !== 1
            || sequenceBackend.lastProfile !== exactProfileSetting
            || sequenceBackend.lastProfileNetwork !== exactProfileNetwork
            || exactProfileSetting.readCalls !== 0
            || savedSettingA.readCalls !== 0 || savedSettingB.readCalls !== 0)
          return root.fail("exact saved-profile dispatch contract")
        root.exactProfileId = exactProfile.id
        root.profileReplacementGeneration = sequenceAdapter.generation

        const normalizedDevice = Model.deviceId(
          "wifi", "AA:BB:CC:DD:EE:01", "ignored")
        if (normalizedDevice === ""
            || normalizedDevice !== Model.deviceId(
              "wifi", "aa-bb-cc-dd-ee-01", "other")
            || Model.deviceId("wifi", "00:00:00:00:00:00", "wlan0") === ""
            || Model.deviceId("wifi", "invalid", "") !== ""
            || Model.deviceId("none", "AA:BB:CC:DD:EE:01", "wlan0") !== "")
          return root.fail("device identity normalization/fallback contract")
        const delimiterId = Model.networkId(
          normalizedDevice, "a:b,[c]", "open")
        const delimiterNeighbor = Model.networkId(
          normalizedDevice, "a:b", "open")
        const nfcId = Model.networkId(
          normalizedDevice, "Caf\u00e9", "open")
        const nfdId = Model.networkId(
          normalizedDevice, "Cafe\u0301", "open")
        const spacedId = Model.networkId(
          normalizedDevice, " Office ", "open")
        const canonicalProfileId = Model.profileId(normalizedDevice,
          "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")
        if (!delimiterId.startsWith("shibumi-network-v1:")
            || delimiterId === delimiterNeighbor || nfcId === nfdId
            || spacedId === Model.networkId(
              normalizedDevice, "Office", "open")
            || Model.networkId(normalizedDevice, "", "open") !== ""
            || Model.networkId(normalizedDevice,
              "123456789012345678901234567890123", "open") !== ""
            || canonicalProfileId !== Model.profileId(normalizedDevice,
              "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
            || Model.profileId(normalizedDevice,
              "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}") !== ""
            || Model.profileId(normalizedDevice,
              "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa\n") !== "")
          return root.fail("collision-safe exact identity contract")
        const expectedSecurity = [
          "wpa3-suite-b-192", "sae", "wpa2-eap", "wpa2-psk",
          "wpa-eap", "wpa-psk", "static-wep", "dynamic-wep",
          "leap", "owe", "open", "unknown"
        ]
        for (let index = 0; index < expectedSecurity.length; index++) {
          if (Model.securityToken(index) !== expectedSecurity[index])
            return root.fail("installed security enum mapping " + index)
        }
        const malformedEnums = [
          true, false, null, {}, [], "1", NaN, Infinity, -Infinity, 1.5
        ]
        for (let malformedIndex = 0;
            malformedIndex < malformedEnums.length; malformedIndex++) {
          const value = malformedEnums[malformedIndex]
          if (Model.securityToken(value) !== "unknown"
              || Model.connectionStateToken(value) !== "unknown"
              || Model.connectivityToken(value) !== "unknown"
              || Model.deviceTypeToken(value) !== "none")
            return root.fail("malformed enum crossed the fake boundary")
        }

        const serialized = JSON.stringify({
          backend: adapter.backendSnapshot,
          radio: adapter.radioSnapshot,
          devices: adapter.deviceSnapshots,
          networks: adapter.networkSnapshots,
          profiles: sequenceAdapter.profileSnapshots
        })
        if (!serialized || serialized.indexOf("correct horse") >= 0
            || serialized.indexOf("must-not-leak") >= 0
            || serialized.indexOf("/private/certificate") >= 0)
          return root.fail("primitive snapshots are not safely serializable")

        const personalRow = root.rowFor(adapter, personal.ssid)
        if (!personalRow || !personalRow.canConnectWithPsk
            || personalRow.canConnect || personalRow.canForget
            || personalRow.security !== "wpa2-psk")
          return root.fail("per-row PSK capability contract")
        root.personalId = personalRow.id
        root.signalGeneration = adapter.generation
        personal.signal = 74
        exactProfileNetwork.nmSettings = [replacementProfileSetting]
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (root.ticks < 3) return
        const personalRow = root.rowFor(adapter, personal.ssid)
        if (!personalRow || personalRow.signal !== 74
            || adapter.generation !== root.signalGeneration)
          return root.fail("signal update invalidated the action generation")
        const replacementProfile = root.profileFor(sequenceAdapter,
          Model.deviceId("wifi", sequenceDevice.address,
            sequenceDevice.name), replacementProfileSetting.uuid)
        const staleProfile = sequenceAdapter.connectProfile({
          entityId: root.exactProfileId,
          generation: root.profileReplacementGeneration
        })
        if (!replacementProfile
            || sequenceAdapter.generation
              <= root.profileReplacementGeneration
            || staleProfile.ok
            || staleProfile.code !== "stale-generation")
          return root.fail("profile replacement did not advance generation")
        const incompleteProfile = root.profileFor(incompleteProfileAdapter,
          Model.deviceId("wifi", sequenceDevice.address,
            sequenceDevice.name), replacementProfileSetting.uuid)
        if (!incompleteProfile)
          return root.fail("incomplete fake profile snapshot disappeared")
        const unsupportedProfile = incompleteProfileAdapter.connectProfile({
          entityId: incompleteProfile.id,
          generation: incompleteProfileAdapter.generation
        })
        if (incompleteProfile.canConnect || incompleteProfile.canForget
            || unsupportedProfile.ok
            || unsupportedProfile.code !== "unsupported")
          return root.fail("missing fake profile delegate fell through")

        const invalidRequest = adapter.connectNetworkWithPsk({
          entityId: personalRow.id,
          generation: adapter.generation
        }, "short")
        if (invalidRequest.ok || invalidRequest.code !== "invalid")
          return root.fail("malformed PSK did not fail closed")
        let throwingEntityReads = 0
        const throwingRequest = {}
        Object.defineProperty(throwingRequest, "entityId", {
          enumerable: true,
          get: function() {
            throwingEntityReads++
            throw new Error("fixture entity getter failure")
          }
        })
        Object.defineProperty(throwingRequest, "generation", {
          enumerable: true,
          get: function() { return adapter.generation }
        })
        const throwingResult = adapter.connectNetworkWithPsk(
          throwingRequest, "correct horse")
        const extraPropertyResult = adapter.connectNetworkWithPsk({
          entityId: personalRow.id,
          generation: adapter.generation,
          extra: true
        }, "correct horse")
        if (throwingResult.ok || throwingResult.code !== "invalid"
            || extraPropertyResult.ok || extraPropertyResult.code !== "invalid"
            || throwingEntityReads !== 1 || fakeBackend.pskCalls !== 0)
          return root.fail("untrusted direct adapter request did not fail closed")

        let entityReads = 0
        let generationReads = 0
        const statefulRequest = {}
        Object.defineProperty(statefulRequest, "entityId", {
          enumerable: true,
          get: function() {
            entityReads++
            if (entityReads > 1) return root.rowFor(adapter, openNetwork.ssid).id
            return personalRow.id
          }
        })
        Object.defineProperty(statefulRequest, "generation", {
          enumerable: true,
          get: function() {
            generationReads++
            if (generationReads > 1)
              throw new Error("second generation read")
            return adapter.generation
          }
        })
        const accepted = adapter.connectNetworkWithPsk(
          statefulRequest, "correct horse")
        if (!accepted.ok || accepted.code !== "accepted"
            || entityReads !== 1 || generationReads !== 1
            || fakeBackend.pskCalls !== 1
            || fakeBackend.lastTarget !== personal
            || fakeBackend.lastSecret !== "correct horse")
          return root.fail("PSK dispatch did not resolve one parsed identity: "
            + JSON.stringify({ accepted: accepted, entityReads: entityReads,
              generationReads: generationReads, calls: fakeBackend.pskCalls,
              targetPersonal: fakeBackend.lastTarget === personal,
              secret: fakeBackend.lastSecret }))
        const forgetResult = adapter.forgetNetwork({
          entityId: personalRow.id,
          generation: adapter.generation
        })
        if (forgetResult.ok || forgetResult.code !== "unsupported"
            || fakeBackend.forgetCalls !== 0)
          return root.fail("aggregate native forget was not blocked")

        const radioResult = adapter.setWifiEnabled({
          entityId: adapter.radioSnapshot.id,
          generation: adapter.generation
        }, false)
        if (!radioResult.ok || radioResult.code !== "accepted"
            || fakeBackend.radioCalls !== 1)
          return root.fail("global Wi-Fi radio dispatch contract")

        const incompleteRow = root.rowFor(incompleteAdapter, personal.ssid)
        const unsupported = incompleteAdapter.connectNetworkWithPsk({
          entityId: incompleteRow.id,
          generation: incompleteAdapter.generation
        }, "correct horse")
        if (unsupported.ok || unsupported.code !== "unsupported"
            || incompleteRow.canConnectWithPsk)
          return root.fail("missing fake delegate fell through")

        const failingRow = root.rowFor(failingAdapter, openNetwork.ssid)
        const typedFailure = failingAdapter.connectNetwork({
          entityId: failingRow.id,
          generation: failingAdapter.generation
        })
        if (typedFailure.ok || typedFailure.code !== "unavailable"
            || typedFailure.message !== "fixture dispatch failed"
            || typedFailure.entityId !== failingRow.id
            || typedFailure.generation !== 17)
          return root.fail("typed fake failure did not propagate")
        const malformedRow = root.rowFor(
          malformedResultAdapter, openNetwork.ssid)
        const malformedRequest = {
          entityId: malformedRow.id,
          generation: malformedResultAdapter.generation
        }
        const malformedResult = malformedResultAdapter.connectNetwork(
          malformedRequest)
        malformedResultBackend.resultMode = 1
        const arrayCodeResult = malformedResultAdapter.connectNetwork(
          malformedRequest)
        malformedResultBackend.resultMode = 2
        const accessorResult = malformedResultAdapter.connectNetwork(
          malformedRequest)
        const accessorReads = [
          malformedResultBackend.okReads,
          malformedResultBackend.codeReads,
          malformedResultBackend.messageReads,
          malformedResultBackend.generationReads
        ]
        malformedResultBackend.resultMode = 3
        const throwingAccessorResult = malformedResultAdapter.connectNetwork(
          malformedRequest)
        if (malformedResultAdapter.connectivity !== "unknown"
            || malformedResult.ok || malformedResult.code !== "invalid"
            || malformedResult.generation
              !== malformedResultAdapter.generation
            || arrayCodeResult.ok || arrayCodeResult.code !== "invalid"
            || !accessorResult.ok || accessorResult.code !== "accepted"
            || accessorReads.some(function(reads) { return reads !== 1 })
            || throwingAccessorResult.ok
            || throwingAccessorResult.code !== "invalid"
            || malformedResultBackend.okReads !== 1
            || malformedResultBackend.codeReads !== 0
            || malformedResultBackend.messageReads !== 0
            || malformedResultBackend.generationReads !== 0)
          return root.fail("malformed typed result did not fail closed")

        root.replacementRequest = {
          entityId: personalRow.id,
          generation: adapter.generation
        }
        root.replacementGeneration = adapter.generation
        wifiDevice.networks = [
          personalReplacement, openNetwork, unicodeNfc, unicodeNfd, spacedNetwork
        ]
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (root.ticks < 3) return
        const replacementResult = adapter.connectNetworkWithPsk(
          root.replacementRequest, "correct horse")
        if (!replacementResult.ok || fakeBackend.lastTarget !== personalReplacement
            || adapter.generation !== root.replacementGeneration)
          return root.fail("same-ID replacement used a cached raw object")
        personalReplacement.securityToken = "sae"
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (root.ticks < 3) return
        const changedRow = root.rowFor(adapter, personalReplacement.ssid)
        if (!changedRow || changedRow.id === root.personalId
            || adapter.generation <= root.replacementGeneration)
          return root.fail("security transition retained stale identity")
        const stale = adapter.connectNetworkWithPsk(
          root.replacementRequest, "correct horse")
        if (stale.ok || stale.code !== "stale-generation")
          return root.fail("security transition did not invalidate the request")
        personalDuplicate.securityToken = "sae"
        wifiDevice.networks = [personalReplacement, personalDuplicate]
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (root.ticks < 3) return
        const rows = adapter.networkSnapshots
        if (rows.length !== 2 || !rows[0].ambiguous || !rows[1].ambiguous)
          return root.fail("duplicate identity was not published as ambiguous")
        const ambiguous = adapter.connectNetworkWithPsk({
          entityId: rows[0].id,
          generation: adapter.generation
        }, "correct horse")
        if (ambiguous.ok || ambiguous.code !== "ambiguous")
          return root.fail("duplicate identity did not fail closed")
        const removedId = rows[0].id
        wifiDevice.networks = []
        root.personalId = removedId
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (root.ticks < 3) return
        const staleId = adapter.connectNetworkWithPsk({
          entityId: root.personalId,
          generation: adapter.generation
        }, "correct horse")
        if (staleId.ok || staleId.code !== "stale-id")
          return root.fail("removed identity did not return stale-id")
        console.log("network native backend seam regression passed")
        Qt.exit(0)
      }
    }
  }
}
