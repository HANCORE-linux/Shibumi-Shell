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
  readonly property string securedId: "shibumi-network-v1:"
    + JSON.stringify(["network", root.deviceId, "Private", "wpa2-psk"])
  readonly property string profileId: "shibumi-network-v1:"
    + JSON.stringify(["profile", root.deviceId,
      "11111111-1111-4111-8111-111111111111"])
  property int phase: 0
  property var connectedForLayout: null

  function fail(message) {
    console.error("network-native-panel-smoke:", message)
    Qt.exit(1)
  }

  function findNamed(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    const children = item.children || []
    for (let index = 0; index < children.length; index++) {
      const found = findNamed(children[index], name)
      if (found) return found
    }
    return null
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
    property bool recoveryBlocked: false
    property string livenessPhase: "available"
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
    property int disconnectCalls: 0
    property int passphraseCalls: 0
    property int enterpriseCalls: 0
    property int speedCalls: 0
    property int qrGestureCalls: 0
    property int qrSecretCalls: 0
    property var qrOwner: null
    property string qrRequestToken: ""

    function refresh(_scan) { return true }
    function toggleWifi() { return { accepted: true } }
    function connect(entry) {
      if (entry.entityKind === "catalog") catalogConnectCalls++
      return { accepted: true }
    }
    function disconnect(_entry) {
      disconnectCalls++
      return { accepted: true }
    }
    function connectWithPassphrase(_entry, _password) {
      passphraseCalls++
      return { accepted: true }
    }
    function connectEnterprise(_entry, identity, password, domain) {
      enterpriseCalls++
      enterpriseIdentity = identity
      enterprisePassword = password
      enterpriseDomain = domain
      return { accepted: true }
    }
    function forget(_entry) { forgetCalls++; return { accepted: true } }
    function runSpeedTest(_owner) { speedCalls++; return true }
    function beginQrGesture(_owner, _entry) {
      qrGestureCalls++
      return { accepted: true, gestureToken: "gesture" }
    }
    function requestQrSecret(owner, _entry, gestureToken) {
      if (gestureToken !== "gesture")
        return { accepted: false, code: "unauthorized", requestToken: "" }
      qrSecretCalls++
      qrOwner = owner
      qrRequestToken = "request-token"
      return { accepted: true, code: "accepted",
        requestToken: qrRequestToken }
    }
    function cancelQrGesture(_owner, _token) { return true }
    function cancelQrSecret(_owner, _token) { return true }
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
    repeat: true
    onTriggered: {
      if (root.phase === 2) {
        const secure = service.networks[0]
        panel.expandedKey = secure.entryKey
        const qr = root.findNamed(panel,
          "networkQrAction:" + secure.entryKey)
        const keyCatcher = root.findNamed(
          panel, "shibumiNetworkPanelKeyCatcher")
        const qrCanvas = root.findNamed(panel, "shibumiNetworkQrCanvas")
        if (!qr || !keyCatcher || !qrCanvas)
          return root.fail("secured QR click fixture was not presented")
        keyCatcher.textKey("q")
        panel.showQrForConnected()
        if (service.qrGestureCalls !== 0 || service.qrSecretCalls !== 0
            || qrCanvas.visible)
          return root.fail("presentation route authorized a saved-secret read")
        if (!qr.activate() || service.qrGestureCalls !== 1
            || service.qrSecretCalls !== 1 || !service.qrOwner)
          return root.fail("explicit QR button did not authorize one secret read")
        const evidence = { requestToken: service.qrRequestToken }
        if (!service.qrOwner.stageSavedSecret(evidence, "correct horse")
            || qrCanvas.visible
            || !service.qrOwner.commitSavedSecret(service.qrRequestToken)
            || !qrCanvas.visible)
          return root.fail("explicit QR secret did not commit after clean result")
        console.log("network native panel smoke passed")
        Qt.exit(0)
        return
      }
      if (root.phase === 1) {
        const connected = root.connectedForLayout
        const primary = root.findNamed(panel,
          "networkPrimaryAction:" + connected.entryKey)
        const qr = root.findNamed(panel,
          "networkQrAction:" + connected.entryKey)
        if (!primary || !qr || qr.parent !== primary.parent
            || primary.parent.children.indexOf(primary)
              >= primary.parent.children.indexOf(qr)
            || qr.visible !== true || qr.label !== "QR Code")
          return root.fail("QR Code was not placed beside Disconnect"
            + " primary=" + !!primary + " qr=" + !!qr
            + " sibling=" + !!(primary && qr && qr.parent === primary.parent)
            + " ordered=" + !!(primary && qr
              && primary.parent.children.indexOf(primary)
                < primary.parent.children.indexOf(qr))
            + " visible=" + !!(qr && qr.visible)
            + " label=" + (qr ? qr.label : "missing"))
        const keyCatcher = root.findNamed(
          panel, "shibumiNetworkPanelKeyCatcher")
        if (!qr.activeFocusOnTab || !keyCatcher
            || !panel.focusQrAction(1))
          return root.fail("QR Code action lost keyboard reachability")
        keyCatcher.textKey("q")
        const qrCanvas = root.findNamed(panel, "shibumiNetworkQrCanvas")
        if (!qrCanvas || qrCanvas.visible || service.qrSecretCalls !== 0)
          return root.fail("QR shortcut read a secret without button activation")
        if (!qr.activate() || !qrCanvas.visible)
          return root.fail("explicit QR Code button did not open presentation")
        if (panel.openPassword(service.networks[1]) === false)
          return root.fail("credential cleanup setup was rejected")
        panel.passwordText = "clear-on-recovery"
        panel.identityText = "clear@example.test"
        panel.serverDomainText = "radius.example.test"
        panel.requestForget(service.networks[2])
        if (panel.passwordKey === "" || panel.pendingForgetKey === "")
          return root.fail("recovery cleanup fixtures were not active")
        const forgetBefore = service.forgetCalls
        const enterpriseBefore = service.enterpriseCalls
        service.recoveryBlocked = true
        service.livenessPhase = "recovery-blocked"
        if (panel.passwordKey !== "" || panel.passwordText !== ""
            || panel.identityText !== "" || panel.serverDomainText !== ""
            || panel.pendingForgetKey !== "" || qrCanvas.visible)
          return root.fail("recovery transition retained transient state")
        panel.runPrimary(connected)
        panel.requestForget(service.networks[2])
        panel.requestForget(service.networks[2])
        panel.passwordText = "blocked-secret"
        panel.identityText = "blocked@example.test"
        panel.serverDomainText = "radius.example.test"
        const submitted = panel.submitPassword(service.networks[1])
        const submittedPsk = panel.submitPassword(service.networks[3])
        const opened = panel.openPassword(service.networks[1])
        const shared = panel.showQr(connected)
        if (panel.statusText() !== "Restart the shell to restore NetworkManager"
            || panel.canRunPrimary(connected) || submitted || submittedPsk
            || opened || shared
            || service.disconnectCalls !== 0
            || service.forgetCalls !== forgetBefore
            || service.enterpriseCalls !== enterpriseBefore
            || panel.passwordKey !== "" || qrCanvas.visible)
          return root.fail("recovery block did not stop every panel mutation")
        service.recoveryBlocked = false
        service.livenessPhase = "available"
        if (!panel.showQrForConnected() || qrCanvas.visible
            || service.qrSecretCalls !== 0)
          return root.fail("presentation-only QR route read a secret")
        const rows = service.networks.slice()
        rows[0] = Object.assign({}, rows[0], {
          entryKey: "network:" + root.securedId,
          id: root.securedId,
          networkId: root.securedId,
          profileUuid: "33333333-3333-4333-8333-333333333333",
          ssid: "Private",
          security: "wpa2-psk",
          securityKind: "psk",
          securityLabel: "WPA2 Personal"
        })
        service.networks = rows
        root.phase = 2
        return
      }
      const available = panel.filteredNetworks()
      if (!panel.open || available.length !== 2 || panel.savedCount !== 2
          || typeof panel.dnsText !== "undefined")
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
      root.connectedForLayout = available[0]
      panel.toggleExpanded(root.connectedForLayout)
      root.phase = 1
    }
  }
}
