pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  readonly property string deviceId:
    'shibumi-network-v1:["device","wifi","mac","AA:BB:CC:DD:EE:01"]'
  readonly property string openId: "shibumi-network-v1:" + JSON.stringify([
    "network", root.deviceId, "Guest", "open"
  ])
  readonly property string enterpriseId: "shibumi-network-v1:"
    + JSON.stringify(["network", root.deviceId, "Corp", "wpa2-eap"])
  readonly property string profileId: "shibumi-network-v1:"
    + JSON.stringify(["profile", root.deviceId,
      "11111111-1111-4111-8111-111111111111"])

  function fail(message) {
    console.error("network-native-panel-smoke:", message)
    Qt.exit(1)
  }

  Item {
    id: fakeBar
    property color foreground: "#eeeeee"
    property color urgent: "#d75f5f"
    property string fontFamily: "monospace"
    property var activePopout: null
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function run(_command) {}
  }

  Item {
    id: owner
    property bool opened: true
    function close() { opened = false }
    function switchPanel(_direction) { return false }
  }

  QtObject {
    id: service
    property bool ready: true
    property bool backendAvailable: true
    property bool processRestartRequired: false
    property bool wifiAvailable: true
    property bool wifiEnabled: true
    property bool scanning: false
    property bool busy: false
    property string kind: "wifi"
    property string label: "Guest"
    property int signalStrength: 72
    property real internetPingLatency: 8.5
    property real downloadRate: 2048
    property real uploadRate: 1024
    property bool speedTestReady: true
    property bool speedTestRunning: false
    property string speedTestPhase: ""
    property string speedTestDownloadMbps: ""
    property string speedTestUploadMbps: ""
    property string speedTestError: ""
    property string actionSsid: ""
    property string actionKind: ""
    property string failureSsid: ""
    property string failureReason: ""
    property string profileError: ""
    property bool profilesLoaded: true
    property var info: ({
      iface: "wlan0", ip: "192.0.2.10", prefix: 24,
      gateway: "192.0.2.1", freq: 5180, bitrate: "866 Mbit/s", speed: 0
    })
    property var dnsServers: [
      { family: "ipv4", address: "1.1.1.1" },
      { family: "ipv6", address: "2606:4700:4700::1111" }
    ]
    property var networks: [
      {
        entryKey: "network:open", entityKind: "network", id: root.openId,
        networkId: root.openId, profileId: "", profileUuid: "",
        profileName: "", deviceId: root.deviceId, generation: 7,
        connected: true, known: false, ssid: "Guest", signal: 72,
        security: "open", securityKind: "open", securityLabel: "Open",
        hidden: false, state: "connected", stateChanging: false,
        ambiguous: false, visible: true, listKind: "available",
        canConnect: false, canConnectWithPsk: false, canDisconnect: true,
        canForget: false, canShare: true
      },
      {
        entryKey: "network:enterprise", entityKind: "network",
        id: root.enterpriseId, networkId: root.enterpriseId,
        profileId: "", profileUuid: "", profileName: "",
        deviceId: root.deviceId, generation: 7, connected: false,
        known: false, ssid: "Corp", signal: 65, security: "wpa2-eap",
        securityKind: "enterprise",
        securityLabel: "WPA2 Enterprise · PEAP/MSCHAPv2",
        hidden: false, state: "disconnected", stateChanging: false,
        ambiguous: false, visible: true, listKind: "available",
        canConnect: false, canConnectWithPsk: false, canDisconnect: false,
        canForget: false, canShare: false
      },
      {
        entryKey: "profile:saved", entityKind: "profile",
        id: root.profileId, networkId: root.enterpriseId,
        profileId: root.profileId,
        profileUuid: "11111111-1111-4111-8111-111111111111",
        profileName: "Corporate saved", deviceId: root.deviceId,
        generation: 7, connected: false, known: true, ssid: "Corp",
        signal: 65, security: "wpa2-eap", securityKind: "enterprise",
        securityLabel: "WPA2 Enterprise · PEAP/MSCHAPv2", hidden: false,
        state: "disconnected", stateChanging: false, ambiguous: false,
        visible: true, listKind: "saved", canConnect: true,
        canConnectWithPsk: false, canDisconnect: false, canForget: true,
        canShare: false
      },
      {
        entryKey: "catalog:hidden", entityKind: "catalog",
        id: "shibumi-network-v1:[\"saved-profile\",\"catalog\"]",
        networkId: "", profileId: "",
        profileUuid: "22222222-2222-4222-8222-222222222222",
        profileName: "Hidden saved", deviceId: root.deviceId,
        generation: 7, connected: false, known: true, ssid: "Hidden",
        signal: 0, security: "wpa2-psk", securityKind: "psk",
        securityLabel: "WPA2 Personal", hidden: true,
        state: "disconnected", stateChanging: false, ambiguous: false,
        visible: false, listKind: "saved", canConnect: true,
        canConnectWithPsk: false, canDisconnect: false, canForget: true,
        canShare: false
      }
    ]
    property string enterpriseIdentity: ""
    property string enterprisePassword: ""
    property string enterpriseDomain: ""
    property int forgetCalls: 0
    property int catalogConnectCalls: 0

    function refresh(_scan) { return true }
    function toggleWifi() { return { accepted: true } }
    function connect(entry) {
      if (entry.entityKind === "catalog") catalogConnectCalls++
      return { accepted: true }
    }
    function disconnect(_entry) { return { accepted: true } }
    function connectWithPassphrase(_entry, _password) {
      return { accepted: true }
    }
    function connectEnterprise(_entry, identity, password, domain) {
      enterpriseIdentity = identity
      enterprisePassword = password
      enterpriseDomain = domain
      return { accepted: true }
    }
    function forget(_entry) { forgetCalls++; return { accepted: true } }
    function runSpeedTest(_owner) { return true }
    function formatRate(value) { return String(value) }
    function formatPing(value) { return String(value) }
    function formatSpeed(value) { return String(value) }
  }

  Network.NetworkPanel {
    id: panel
    anchorItem: owner
    bar: fakeBar
    ownerWidget: owner
    networkService: service
  }

  Timer {
    interval: 100
    running: true
    onTriggered: {
      const available = panel.filteredNetworks()
      if (!panel.open || available.length !== 2 || panel.savedCount !== 2
          || panel.dnsText() !== "1.1.1.1 · 2606:4700:4700::1111")
        return root.fail("native primitive panel projection failed")
      const enterprise = available[1]
      panel.openPassword(enterprise)
      panel.identityText = "user@example.test"
      panel.passwordText = "not-published"
      panel.serverDomainText = "radius.example.test"
      if (!panel.submitPassword(enterprise)
          || service.enterpriseIdentity !== "user@example.test"
          || service.enterprisePassword !== "not-published"
          || service.enterpriseDomain !== "radius.example.test")
        return root.fail("Enterprise domain credentials were not typed")
      panel.clearPassword()
      panel.savedOnly = true
      const saved = panel.filteredNetworks()
      if (saved.length !== 2 || !panel.canForget(saved[0])
          || !panel.canForget(saved[1]))
        return root.fail("exact saved profiles were not presented")
      const catalogOnly = saved[0].entityKind === "catalog" ? saved[0] : saved[1]
      const nativeProfile = saved[0].entityKind === "profile" ? saved[0] : saved[1]
      panel.runPrimary(catalogOnly)
      if (service.catalogConnectCalls !== 1)
        return root.fail("catalog-only Connect was not routed")
      panel.requestForget(nativeProfile)
      panel.requestForget(nativeProfile)
      panel.requestForget(catalogOnly)
      panel.requestForget(catalogOnly)
      if (service.forgetCalls !== 2)
        return root.fail("exact saved profile confirmation was not routed")
      panel.savedOnly = false
      if (!panel.showQrForConnected())
        return root.fail("connected native open network did not open QR")
      console.log("network native panel smoke passed")
      Qt.exit(0)
    }
  }
}
