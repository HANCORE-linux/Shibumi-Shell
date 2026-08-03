pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Networking
import "../adapters" as Adapters

// One process-wide NetworkManager owner for every Shibumi output. Quattro's
// official network component remains authoritative for live status, details,
// scanning, DNS, speed tests, and visible-network actions. This service adds
// only the saved-profile view that the host networking API does not expose.
Item {
  id: root

  required property var bar
  readonly property url panelSource: bar
    ? bar.registeredWidgetSource("omarchy.network") : ""
  property Component panelComponent: String(panelSource) ? null
    : bar ? bar.registeredWidgetComponent("omarchy.network") : null
  readonly property var backend: bridge.panel
  readonly property bool ready: backend !== null
  readonly property bool backendAvailable: ready && bridge.backendAvailable
  readonly property string kind: bridge.kind
  readonly property string label: bridge.label
  readonly property int signalStrength: bridge.signalStrength
  readonly property bool scanning: bridge.scanning
  readonly property bool busy: bridge.busy || profileAction.running
  readonly property bool wifiEnabled: Networking.wifiEnabled
  readonly property bool wifiAvailable: backend
    ? backend.wifiStationAvailable === true : false
  readonly property var info: backend && backend.info ? backend.info : ({})
  readonly property real downloadRate: backend ? Number(backend.downloadRate || 0) : 0
  readonly property real uploadRate: backend ? Number(backend.uploadRate || 0) : 0
  readonly property real routerPingLatency: backend
    ? Number(backend.routerPingLatency === undefined ? -1 : backend.routerPingLatency) : -1
  readonly property real internetPingLatency: backend
    ? Number(backend.internetPingLatency === undefined ? -1 : backend.internetPingLatency) : -1
  readonly property int internetPingPacketLoss: backend
    ? Number(backend.internetPingPacketLoss || 0) : 0
  readonly property string dnsProvider: backend
    ? String(backend.dnsProvider || "DHCP") : "DHCP"
  readonly property var dnsProviders: backend && backend.dnsProviders
    ? backend.dnsProviders : ["DHCP", "Cloudflare", "Google", "Custom"]
  readonly property bool speedTestRunning: backend
    ? backend.speedTestRunning === true : false
  readonly property bool speedTestHasRun: speedTestDownloadMbps !== ""
    || speedTestUploadMbps !== ""
  readonly property string speedTestPhase: backend ? String(backend.speedTestPhase || "") : ""
  readonly property string speedTestDownloadMbps: backend
    ? String(backend.speedTestDownloadMbps || "") : ""
  readonly property string speedTestUploadMbps: backend
    ? String(backend.speedTestUploadMbps || "") : ""
  readonly property string speedTestError: backend ? String(backend.speedTestError || "") : ""
  readonly property string actionSsid: backend ? String(backend.actionSsid || "") : ""
  readonly property string actionKind: backend ? String(backend.actionKind || "") : ""
  readonly property string failureSsid: backend ? String(backend.failureSsid || "") : ""
  readonly property string failureReason: backend ? String(backend.failureReason || "") : ""
  readonly property var visibleNetworks: backend && backend.wifiNetworks
    ? backend.wifiNetworks : []
  property var savedProfiles: []
  property bool profilesLoaded: false
  property string profileError: ""
  property var sessionOwners: []
  readonly property int sessionCount: sessionOwners.length
  readonly property var networks: mergedNetworks(visibleNetworks, savedProfiles)

  visible: false
  width: 0
  height: 0

  onReadyChanged: {
    if (ready && backend && sessionCount === 0 && backend.wifiDevice)
      backend.wifiDevice.scannerEnabled = false
  }

  Connections {
    target: root.backend
    function onWifiDeviceChanged() {
      if (root.backend && root.sessionCount === 0 && root.backend.wifiDevice)
        root.backend.wifiDevice.scannerEnabled = false
    }
  }

  function officialSettings() {
    return bar && typeof bar.widgetSettings === "function"
      ? bar.widgetSettings("G11", "omarchy.network") : ({})
  }

  function beginSession(owner) {
    if (!owner || sessionOwners.indexOf(owner) >= 0) return
    const next = sessionOwners.slice()
    next.push(owner)
    sessionOwners = next
    if (sessionCount === 1) {
      refresh(true)
    }
  }

  function endSession(owner) {
    if (!owner) return
    sessionOwners = sessionOwners.filter(candidate => candidate !== owner)
    if (sessionCount !== 0) return
    if (speedTestRunning && backend
        && typeof backend.hideSpeedTest === "function")
      backend.hideSpeedTest()
    detailsPoll.stop()
    detailsProc.running = false
    profileList.running = false
    if (backend && backend.wifiDevice) backend.wifiDevice.scannerEnabled = false
  }

  function refresh(scanWifi) {
    if (!ready || typeof backend.refresh !== "function") return false
    const shouldScanWifi = scanWifi === true && wifiAvailable
    backend.refresh(shouldScanWifi)
    if (sessionCount > 0 && shouldScanWifi && !profileList.running)
      refreshProfiles()
    return true
  }

  function toggleWifi() {
    if (!backendAvailable || !wifiAvailable) return false
    Networking.wifiEnabled = !Networking.wifiEnabled
    if (Networking.wifiEnabled) Qt.callLater(function() { root.refresh(true) })
    return true
  }

  function securityKind(security) {
    switch (security) {
    case WifiSecurityType.Open: return "open"
    case WifiSecurityType.WpaPsk:
    case WifiSecurityType.Wpa2Psk:
    case WifiSecurityType.Sae: return "psk"
    case WifiSecurityType.Owe: return "owe"
    case WifiSecurityType.StaticWep:
    case WifiSecurityType.DynamicWep: return "wep"
    case WifiSecurityType.WpaEap:
    case WifiSecurityType.Wpa2Eap:
    case WifiSecurityType.Wpa3SuiteB192:
    case WifiSecurityType.Leap: return "enterprise"
    default: return "unknown"
    }
  }

  function securityLabel(security) {
    switch (security) {
    case WifiSecurityType.Open: return "Open"
    case WifiSecurityType.WpaPsk: return "WPA Personal"
    case WifiSecurityType.Wpa2Psk: return "WPA2 Personal"
    case WifiSecurityType.Sae: return "WPA3 Personal"
    case WifiSecurityType.Owe: return "Enhanced Open (OWE)"
    case WifiSecurityType.StaticWep:
    case WifiSecurityType.DynamicWep: return "WEP"
    case WifiSecurityType.WpaEap: return "WPA Enterprise"
    case WifiSecurityType.Wpa2Eap: return "WPA2 Enterprise"
    case WifiSecurityType.Wpa3SuiteB192: return "WPA3 Enterprise"
    case WifiSecurityType.Leap: return "LEAP"
    default: return "Unknown"
    }
  }

  function profileSecurityLabel(keyManagement) {
    switch (String(keyManagement || "").toLowerCase()) {
    case "wpa-psk": return "WPA Personal profile"
    case "sae": return "WPA3 Personal profile"
    case "owe": return "Enhanced Open profile"
    case "wpa-eap": return "WPA Enterprise profile"
    case "ieee8021x": return "802.1X profile"
    case "none": return "Open or WEP profile"
    default: return "Saved Wi-Fi profile"
    }
  }

  function mergedNetworks(visible, profiles) {
    const rows = []
    const visibleRows = Array.isArray(visible) ? visible : []
    const savedRows = Array.isArray(profiles) ? profiles : []

    for (let i = 0; i < visibleRows.length; i++) {
      const source = visibleRows[i]
      if (!source) continue
      let profile = null
      for (let p = 0; p < savedRows.length; p++) {
        if (savedRows[p] && savedRows[p].ssid === source.ssid) {
          profile = savedRows[p]
          break
        }
      }
      rows.push({
        network: source.network || null,
        connected: source.connected === true,
        known: source.known === true || profile !== null,
        ssid: String(source.ssid || ""),
        signal: Math.max(0, Math.min(100, Number(source.signal || 0))),
        security: source.security,
        securityKind: securityKind(source.security),
        securityLabel: securityLabel(source.security),
        visible: true,
        profileUuid: profile ? String(profile.uuid || "") : "",
        lastSuccessful: profile ? Number(profile.lastSuccessful || 0) : 0,
        entryKey: profile ? "profile:" + profile.uuid
          : "network:" + String(source.ssid || "") + ":" + securityKind(source.security)
      })
    }

    for (let p = 0; p < savedRows.length; p++) {
      const profile = savedRows[p]
      if (!profile) continue
      let represented = false
      for (let i = 0; i < rows.length; i++) {
        if (rows[i].ssid === profile.ssid) {
          represented = true
          break
        }
      }
      if (represented) continue
      rows.push({
        network: null,
        connected: false,
        known: true,
        ssid: String(profile.ssid || ""),
        signal: 0,
        security: null,
        securityKind: "saved",
        securityLabel: profileSecurityLabel(profile.keyManagement),
        visible: false,
        profileUuid: String(profile.uuid || ""),
        lastSuccessful: Number(profile.lastSuccessful || 0),
        entryKey: "profile:" + String(profile.uuid || "")
      })
    }

    rows.sort(function(left, right) {
      if (left.connected !== right.connected) return left.connected ? -1 : 1
      if (left.known !== right.known) return left.known ? -1 : 1
      if (left.visible !== right.visible) return left.visible ? -1 : 1
      return right.signal - left.signal
    })
    return rows
  }

  function connect(entry) {
    if (!entry || busy) return false
    profileError = ""
    if (!entry.network && entry.profileUuid)
      return runProfileAction("connect", entry.profileUuid)
    if (!entry.network || !ready) return false
    if (entry.connected) return disconnect(entry)
    if (entry.known || entry.securityKind === "open") {
      backend.connectKnown(entry.ssid)
      return true
    }
    return false
  }

  function connectWithPassphrase(entry, passphrase) {
    if (!entry || !entry.network || entry.securityKind !== "psk"
        || !String(passphrase || "") || !ready || busy) return false
    profileError = ""
    backend.connectWithPassphrase(entry.ssid, String(passphrase))
    return true
  }

  function connectEnterprise(entry, identity, passphrase) {
    if (!entry || !entry.network || entry.securityKind !== "enterprise"
        || !String(identity || "") || !String(passphrase || "")
        || !ready || busy) return false
    profileError = ""
    backend.connectEnterprise(entry.ssid, String(identity), String(passphrase))
    return true
  }

  function disconnect(entry) {
    if (!ready || busy) return false
    backend.disconnect(entry && entry.network ? entry.network : null)
    return true
  }

  function forget(entry) {
    if (!entry || !entry.known || busy) return false
    profileError = ""
    if (!entry.network && entry.profileUuid)
      return runProfileAction("forget", entry.profileUuid)
    if (!entry.network || !ready) return false
    backend.forget(entry)
    return true
  }

  function setDns(provider) {
    if (!ready || typeof backend.setDns !== "function") return false
    backend.setDns(provider)
    return true
  }

  function runSpeedTest() {
    if (!ready || typeof backend.runSpeedTest !== "function"
        || backend.speedTestRunning === true) return false
    backend.runSpeedTest()
    return true
  }

  function formatRate(value) {
    return ready && typeof backend.formatRate === "function"
      ? backend.formatRate(value) : "0 B/s"
  }

  function formatPing(value) {
    return ready && typeof backend.formatPingLatency === "function"
      ? backend.formatPingLatency(value) : "--"
  }

  function formatSpeed(value) {
    const speed = Number(value)
    if (!(speed > 0)) return "—"
    return (speed >= 100 ? speed.toFixed(0) : speed.toFixed(1)) + " Mbps"
  }

  function refreshProfiles() {
    if (sessionCount <= 0 || profileList.running) return false
    profilesLoaded = false
    profileList.running = true
    return true
  }

  function runProfileAction(action, uuid) {
    const id = String(uuid || "")
    if (!id || profileAction.running) return false
    profileAction.action = action
    profileAction.command = action === "connect"
      ? ["nmcli", "--wait", "20", "connection", "up", "uuid", id]
      : ["nmcli", "--wait", "20", "connection", "delete", "uuid", id]
    profileAction.running = true
    return true
  }

  Adapters.NetworkPanelBridge {
    id: bridge
    bar: root.bar
    ownerWidget: root.bar
    panelComponent: root.panelComponent
    panelSource: root.panelSource
    panelSettings: root.officialSettings()
  }

  Timer {
    id: detailsPoll
    interval: 1500
    repeat: true
    running: root.sessionCount > 0 && root.ready
    onTriggered: {
      if (!detailsProc.running) detailsProc.running = true
    }
  }

  Process {
    id: detailsProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.backend && typeof root.backend.updateDetails === "function")
          root.backend.updateDetails(text)
      }
    }
  }

  Process {
    id: profileList
    command: ["bash", "-c",
      "connections=$(nmcli -t -f UUID,TYPE connection show) || exit 1; "
      + "printf '__READY__\\n'; "
      + "while IFS=: read -r uuid type; do "
      + "case \"$type\" in 802-11-wireless|wifi) ;; *) continue ;; esac; "
      + "mapfile -t details < <(nmcli --escape no -g 802-11-wireless.ssid,connection.timestamp,802-11-wireless-security.key-mgmt connection show uuid \"$uuid\"); "
      + "ssid=${details[0]-}; timestamp=${details[1]:-0}; key_mgmt=${details[2]:-unknown}; "
      + "[ -n \"$ssid\" ] || continue; "
      + "case \"$timestamp\" in ''|*[!0-9]*) timestamp=0 ;; esac; "
      + "[ -n \"$key_mgmt\" ] || key_mgmt=unknown; "
      + "printf '%s\\t%s\\t%s\\t%s\\n' \"$uuid\" \"$ssid\" \"$timestamp\" \"$key_mgmt\"; "
      + "done <<< \"$connections\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const lines = String(text || "").trim().split("\n")
        const ready = lines.length > 0 && lines[0] === "__READY__"
        root.profilesLoaded = ready
        if (!ready) {
          root.profileError = "Saved networks unavailable"
          return
        }
        const profiles = []
        for (let i = 1; i < lines.length; i++) {
          if (!lines[i]) continue
          const fields = lines[i].split("\t")
          if (fields.length < 4) continue
          profiles.push({
            uuid: fields[0],
            ssid: fields.slice(1, fields.length - 2).join("\t"),
            lastSuccessful: parseInt(fields[fields.length - 2]) || 0,
            keyManagement: fields[fields.length - 1]
          })
        }
        root.profileError = ""
        root.savedProfiles = profiles
      }
    }
  }

  Process {
    id: profileAction
    property string action: ""
    stderr: StdioCollector {
      id: profileActionError
      waitForEnd: true
    }
    onExited: function(exitCode, _exitStatus) {
      root.profileError = exitCode === 0 ? ""
        : String(profileActionError.text || "Network action failed").trim()
      action = ""
      if (root.sessionCount > 0) {
        root.refresh(false)
        root.refreshProfiles()
      }
    }
  }

  Component.onDestruction: {
    sessionOwners = []
    detailsProc.running = false
    profileList.running = false
    if (backend && backend.wifiDevice) backend.wifiDevice.scannerEnabled = false
  }
}
