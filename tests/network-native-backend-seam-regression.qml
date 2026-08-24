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

  QtObject { id: savedSettingA }
  QtObject { id: savedSettingB }

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
      multiProfileNetwork, connectedMultiProfileNetwork
    ]
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
    property list<QtObject> devices: [sequenceDevice]
    property int pskCalls: 0
    property int disconnectCalls: 0
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
      return {
        ok: true,
        code: ["accepted"],
        message: "array code",
        generation: 0
      }
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

  Network.NetworkBackendAdapter {
    id: unavailableNativeAdapter
    active: true
    nativeServiceAvailable: true
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (root.ticks < 4) return
        if (!unavailableNativeAdapter.nativeGatewayLoaded) {
          if (root.ticks < 20) return
          return root.fail("active native gateway did not compile and load")
        }
        if (unavailableNativeAdapter.backendAvailable
            || unavailableNativeAdapter.deviceSnapshots.length !== 0)
          return root.fail("missing system bus did not stay unavailable")
        if (adapter.nativeGatewayLoaded || sequenceAdapter.nativeGatewayLoaded
            || inactiveNativeAdapter.nativeGatewayLoaded
            || unavailableAdapter.nativeGatewayLoaded
            || incompleteAdapter.nativeGatewayLoaded)
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
        if (!sequenceAdapter.backendAvailable
            || sequenceAdapter.deviceSnapshots.length !== 1
            || sequenceAdapter.networkSnapshots.length !== 2)
          return root.fail("QML list sequences were discarded")
        const multiProfileRow = root.rowFor(
          sequenceAdapter, multiProfileNetwork.ssid)
        const connectedMultiProfileRow = root.rowFor(
          sequenceAdapter, connectedMultiProfileNetwork.ssid)
        if (!multiProfileRow || !connectedMultiProfileRow
            || !multiProfileRow.ambiguous || multiProfileRow.profileCount !== 2
            || multiProfileRow.canConnect || multiProfileRow.canConnectWithPsk
            || multiProfileRow.canDisconnect || multiProfileRow.canForget
            || !connectedMultiProfileRow.ambiguous
            || connectedMultiProfileRow.profileCount !== 2
            || connectedMultiProfileRow.canConnect
            || connectedMultiProfileRow.canConnectWithPsk
            || connectedMultiProfileRow.canDisconnect
            || connectedMultiProfileRow.canForget)
          return root.fail("multi-profile SSID was published as actionable")
        const multiProfileResult = sequenceAdapter.connectNetworkWithPsk({
          entityId: multiProfileRow.id,
          generation: sequenceAdapter.generation
        }, "correct horse")
        const multiProfileDisconnect = sequenceAdapter.disconnectNetwork({
          entityId: connectedMultiProfileRow.id,
          generation: sequenceAdapter.generation
        })
        if (multiProfileResult.ok || multiProfileResult.code !== "ambiguous"
            || multiProfileDisconnect.ok
            || multiProfileDisconnect.code !== "ambiguous"
            || sequenceBackend.pskCalls !== 0
            || sequenceBackend.disconnectCalls !== 0)
          return root.fail("multi-profile action did not fail closed")

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
        if (!delimiterId.startsWith("shibumi-network-v1:")
            || delimiterId === delimiterNeighbor || nfcId === nfdId
            || spacedId === Model.networkId(
              normalizedDevice, "Office", "open")
            || Model.networkId(normalizedDevice, "", "open") !== "")
          return root.fail("collision-safe exact SSID identity contract")
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
          networks: adapter.networkSnapshots
        })
        if (!serialized || serialized.indexOf("correct horse") >= 0)
          return root.fail("primitive snapshots are not safely serializable")

        const personalRow = root.rowFor(adapter, personal.ssid)
        if (!personalRow || !personalRow.canConnectWithPsk
            || personalRow.canConnect || personalRow.canForget
            || personalRow.security !== "wpa2-psk")
          return root.fail("per-row PSK capability contract")
        root.personalId = personalRow.id
        root.signalGeneration = adapter.generation
        personal.signal = 74
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

        const invalidRequest = adapter.connectNetworkWithPsk({
          entityId: personalRow.id,
          generation: adapter.generation
        }, "short")
        if (invalidRequest.ok || invalidRequest.code !== "invalid")
          return root.fail("malformed PSK did not fail closed")
        const accepted = adapter.connectNetworkWithPsk({
          entityId: personalRow.id,
          generation: adapter.generation
        }, "correct horse")
        if (!accepted.ok || accepted.code !== "accepted"
            || fakeBackend.pskCalls !== 1
            || fakeBackend.lastTarget !== personal
            || fakeBackend.lastSecret !== "correct horse")
          return root.fail("PSK dispatch did not resolve the current object")
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
        if (malformedResultAdapter.connectivity !== "unknown"
            || malformedResult.ok || malformedResult.code !== "invalid"
            || malformedResult.generation
              !== malformedResultAdapter.generation
            || arrayCodeResult.ok || arrayCodeResult.code !== "invalid")
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
