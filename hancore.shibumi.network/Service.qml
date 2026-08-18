pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Networking

// One process-wide NetworkManager owner for every Shibumi output. Quattro's
// official network component remains authoritative for live status, details,
// DNS, and visible-network actions. Shibumi owns the session-scoped scanner
// lease required by its hidden backend, its inline speed-test process, and the
// saved-profile view missing from the host API.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var bar: shell ? shell.bar : null
  readonly property url panelSource: registeredSource("omarchy.network")
  property Component panelComponent: String(panelSource) ? null
    : registeredComponent("omarchy.network")
  readonly property var backend: bridge.panel
  readonly property url speedTestRunnerSource:
    Qt.resolvedUrl("InlineSpeedTestRunner.py")
  property string speedTestExecutable: "omarchy-network-speedtest"
  property int speedTestPhaseDuration: 5000
  readonly property bool speedTestReady: String(speedTestRunnerSource) !== ""
    && String(speedTestExecutable || "") !== ""
  property bool speedTestRunning: false
  readonly property bool speedTestHasRun: speedTestDownloadMbps !== ""
    || speedTestUploadMbps !== ""
  property string speedTestPhase: ""
  property string speedTestDownloadMbps: ""
  property string speedTestUploadMbps: ""
  property string speedTestError: ""
  property bool speedTestExpectedStop: false
  property bool speedTestPendingRun: false
  property bool speedTestProcessStarted: false
  property string speedTestStderr: ""
  readonly property bool ready: backend !== null
  readonly property bool backendAvailable: ready && bridge.backendAvailable
  readonly property string kind: bridge.kind
  readonly property string label: bridge.label !== ""
    ? bridge.label : connectedVisibleLabel(visibleNetworks)
  readonly property int signalStrength: bridge.signalStrength
  property bool scanPending: false
  property var scannerDevice: null
  readonly property bool scanning: bridge.scanning || scanPending
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

  function registeredSource(id) {
    if (bar && typeof bar.registeredWidgetSource === "function")
      return bar.registeredWidgetSource(id)
    const registry = shell && "pluginRegistry" in shell
      ? shell.pluginRegistry : null
    const pluginManifest = registry && registry.installedPlugins
      ? registry.installedPlugins[String(id || "")] : null
    return registry && typeof registry.entryPointUrl === "function"
      ? registry.entryPointUrl(pluginManifest, "barWidget") : ""
  }

  function registeredComponent(id) {
    if (bar && typeof bar.registeredWidgetComponent === "function")
      return bar.registeredWidgetComponent(id)
    const registry = bar && "barWidgetRegistry" in bar
      ? bar.barWidgetRegistry : null
    if (registry) void(registry.revision)
    const widgets = registry && registry.widgets ? registry.widgets : ({})
    const entry = widgets[String(id || "")]
    return entry && entry.component ? entry.component : null
  }

  function connectedVisibleLabel(rows) {
    const values = Array.isArray(rows) ? rows : []
    for (let i = 0; i < values.length; i++) {
      if (values[i] && values[i].connected === true
          && String(values[i].ssid || "") !== "")
        return String(values[i].ssid)
    }
    return ""
  }

  function activeWifiDevice() {
    return ready && backend && backend.wifiDevice
      ? backend.wifiDevice : null
  }

  function setSessionScannerEnabled(enabled) {
    const nextDevice = sessionCount > 0 ? activeWifiDevice() : null
    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false
    scannerDevice = nextDevice
    if (!scannerDevice) return false
    scannerDevice.scannerEnabled = enabled === true
    return true
  }

  function releaseWifiScanner() {
    scanRestart.stop()
    scanDone.stop()
    scanPending = false
    const currentDevice = activeWifiDevice()
    if (scannerDevice) scannerDevice.scannerEnabled = false
    if (currentDevice && currentDevice !== scannerDevice)
      currentDevice.scannerEnabled = false
    scannerDevice = null
  }

  function requestWifiScan() {
    scanRestart.stop()
    scanDone.stop()
    if (sessionCount <= 0 || !activeWifiDevice()) {
      releaseWifiScanner()
      return false
    }
    scanPending = true
    setSessionScannerEnabled(false)
    scanRestart.restart()
    return true
  }

  function completeWifiScan() {
    scanPending = false
    if (backend && typeof backend.syncWifiNetworks === "function")
      backend.syncWifiNetworks()
  }

  visible: false
  width: 0
  height: 0

  onReadyChanged: {
    if (!ready || sessionCount === 0) releaseWifiScanner()
    else requestWifiScan()
  }

  Connections {
    target: root.backend
    function onWifiDeviceChanged() {
      if (root.sessionCount > 0) root.requestWifiScan()
      else root.releaseWifiScanner()
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
    const nextOwners = sessionOwners.filter(candidate => candidate !== owner)
    if (nextOwners.length === 0) stopSpeedTest()
    sessionOwners = nextOwners
    if (sessionCount !== 0) return
    // Ethernet bar presentations consume the same central throughput sample as
    // the panel. Keep that one worker alive while a wired route is active.
    if (kind !== "ethernet") {
      detailsPoll.stop()
      detailsProc.running = false
    }
    profileList.running = false
    releaseWifiScanner()
  }

  function refresh(scanWifi) {
    if (!ready || typeof backend.refresh !== "function") return false
    const shouldScanWifi = scanWifi === true && activeWifiDevice() !== null
    // The hidden backend may gate its own scanner on `opened`, while older
    // hosts enable it synchronously even for refresh(false). A requested scan
    // therefore defers every backend refresh until our scanner lease starts.
    if (shouldScanWifi) {
      requestWifiScan()
      if (sessionCount > 0 && !profileList.running) refreshProfiles()
      return true
    }
    if (scanPending) return true
    backend.refresh(false)
    if (sessionCount > 0) setSessionScannerEnabled(true)
    else releaseWifiScanner()
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
    case WifiSecurityType.Wpa2Eap: return "enterprise"
    case WifiSecurityType.Wpa3SuiteB192:
    case WifiSecurityType.Leap: return "unsupported"
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

  function profileSecurityLabel(keyManagement, authAlgorithm) {
    switch (String(keyManagement || "").toLowerCase()) {
    case "wpa-psk": return "WPA Personal profile"
    case "sae": return "WPA3 Personal profile"
    case "owe": return "Enhanced Open profile"
    case "wpa-eap": return "WPA Enterprise profile"
    case "wpa-eap-suite-b-192": return "WPA3 Suite B profile"
    case "ieee8021x": return String(authAlgorithm || "").toLowerCase()
      === "leap" ? "LEAP profile" : "802.1X profile"
    case "open": return "Open profile"
    case "none": return "WEP profile"
    default: return "Saved Wi-Fi profile"
    }
  }

  function profileMatchesSecurity(profile, security) {
    const keyManagement = String(profile && profile.keyManagement || "")
      .toLowerCase()
    switch (keyManagement) {
    case "wpa-psk":
      return security === WifiSecurityType.WpaPsk
        || security === WifiSecurityType.Wpa2Psk
    case "sae": return security === WifiSecurityType.Sae
    case "owe": return security === WifiSecurityType.Owe
    case "wpa-eap":
      return security === WifiSecurityType.WpaEap
        || security === WifiSecurityType.Wpa2Eap
    case "wpa-eap-suite-b-192":
      return security === WifiSecurityType.Wpa3SuiteB192
    case "ieee8021x":
      return String(profile.authAlgorithm || "").toLowerCase() === "leap"
        ? security === WifiSecurityType.Leap
        : security === WifiSecurityType.DynamicWep
    case "open": return security === WifiSecurityType.Open
    case "none": return security === WifiSecurityType.StaticWep
    default: return false
    }
  }

  function profileVisibleMatchCount(profile, visible) {
    if (!profile || !Array.isArray(visible)) return 0
    let count = 0
    for (let i = 0; i < visible.length; i++) {
      const candidate = visible[i]
      if (candidate && candidate.ssid === profile.ssid
          && profileMatchesSecurity(profile, candidate.security)) count++
    }
    return count
  }

  function mergedNetworks(visible, profiles) {
    const rows = []
    const visibleRows = Array.isArray(visible) ? visible : []
    const savedRows = Array.isArray(profiles) ? profiles : []
    const representedProfileUuids = ({})

    for (let i = 0; i < visibleRows.length; i++) {
      const source = visibleRows[i]
      if (!source) continue
      const matchingProfiles = []
      for (let p = 0; p < savedRows.length; p++) {
        const candidate = savedRows[p]
        if (candidate && candidate.ssid === source.ssid
            && profileMatchesSecurity(candidate, source.security))
          matchingProfiles.push(candidate)
      }
      const profile = matchingProfiles.length === 1
        && profileVisibleMatchCount(matchingProfiles[0], visibleRows) === 1
        ? matchingProfiles[0] : null
      if (profile && String(profile.uuid || ""))
        representedProfileUuids[String(profile.uuid)] = true
      rows.push({
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
      if (!profile || representedProfileUuids[String(profile.uuid || "")])
        continue
      rows.push({
        network: null,
        connected: false,
        known: true,
        ssid: String(profile.ssid || ""),
        signal: 0,
        security: null,
        securityKind: "saved",
        securityLabel: profileSecurityLabel(profile.keyManagement,
          profile.authAlgorithm),
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

  function visibleIdentityMatchCount(entry) {
    if (!entry || entry.visible === false) return 0
    const ssid = String(entry.ssid || "")
    if (!ssid) return 0
    const expectedKind = String(entry.securityKind
      || securityKind(entry.security))
    const hasExactSecurity = entry.security !== undefined
      && entry.security !== null
    const rows = Array.isArray(visibleNetworks) ? visibleNetworks : []
    let count = 0
    for (let i = 0; i < rows.length; i++) {
      const candidate = rows[i]
      if (!candidate || String(candidate.ssid || "") !== ssid) continue
      if (hasExactSecurity && candidate.security !== entry.security) continue
      if (!hasExactSecurity
          && securityKind(candidate.security) !== expectedKind) continue
      count++
    }
    return count
  }

  function hasUniqueVisibleIdentity(entry) {
    return visibleIdentityMatchCount(entry) === 1
  }

  function currentVisibleEntry(entry) {
    if (!entry || entry.visible === false) return null
    const ssid = String(entry.ssid || "")
    const hasExactSecurity = entry.security !== undefined
      && entry.security !== null
    const expectedKind = String(entry.securityKind
      || securityKind(entry.security))
    const rows = mergedNetworks(visibleNetworks, savedProfiles)
    let result = null
    let count = 0
    for (let i = 0; i < rows.length; i++) {
      const candidate = rows[i]
      if (!candidate || candidate.visible === false
          || String(candidate.ssid || "") !== ssid) continue
      if (hasExactSecurity && candidate.security !== entry.security) continue
      if (!hasExactSecurity && candidate.securityKind !== expectedKind) continue
      result = candidate
      count++
    }
    return count === 1 ? result : null
  }

  function savedProfileMatchCount(entry) {
    if (!entry || !Array.isArray(savedProfiles)) return 0
    let count = 0
    for (let i = 0; i < savedProfiles.length; i++) {
      const profile = savedProfiles[i]
      if (profile && profile.ssid === entry.ssid
          && profileMatchesSecurity(profile, entry.security)) count++
    }
    return count
  }

  function visibleSsidMatchCount(entry) {
    const ssid = String(entry && entry.ssid || "")
    if (!ssid || !Array.isArray(visibleNetworks)) return 0
    let count = 0
    for (let i = 0; i < visibleNetworks.length; i++) {
      const candidate = visibleNetworks[i]
      if (candidate && String(candidate.ssid || "") === ssid) count++
    }
    return count
  }

  function hasUnambiguousVisibleSsid(entry) {
    return hasUniqueVisibleIdentity(entry)
      && visibleSsidMatchCount(entry) === 1
  }

  function connect(entry) {
    if (!entry || busy) return false
    profileError = ""
    if (entry.profileUuid && entry.visible === false)
      return runProfileAction("connect", entry.profileUuid)
    if (!ready || !hasUniqueVisibleIdentity(entry)) return false
    if (entry.connected) return disconnect(entry)
    if (entry.profileUuid)
      return runProfileAction("connect", entry.profileUuid)
    if (hasUnambiguousVisibleSsid(entry)
        && (entry.known || entry.securityKind === "open")
        && typeof backend.connectKnown === "function") {
      backend.connectKnown(String(entry.ssid || ""))
      return true
    }
    return false
  }

  function connectWithPassphrase(entry, passphrase) {
    const current = currentVisibleEntry(entry)
    if (!entry || entry.securityKind !== "psk"
        || !String(passphrase || "") || !ready || busy
        || !hasUnambiguousVisibleSsid(entry) || !current
        || current.connected === true || current.known === true
        || savedProfileMatchCount(entry) > 0
        || typeof backend.connectWithPassphrase !== "function") return false
    profileError = ""
    backend.connectWithPassphrase(String(entry.ssid || ""), String(passphrase))
    return true
  }

  function connectEnterprise(entry, identity, passphrase) {
    const current = currentVisibleEntry(entry)
    if (!entry || entry.securityKind !== "enterprise"
        || !String(identity || "") || !String(passphrase || "")
        || !ready || busy || !hasUnambiguousVisibleSsid(entry) || !current
        || current.connected === true || current.known === true
        || savedProfileMatchCount(entry) > 0
        || typeof backend.connectEnterprise !== "function") return false
    profileError = ""
    backend.connectEnterprise(String(entry.ssid || ""),
      String(identity), String(passphrase))
    return true
  }

  function disconnect(entry) {
    if (!entry || entry.connected !== true || !ready || busy
        || !hasUnambiguousVisibleSsid(entry)
        || typeof backend.disconnectRow !== "function") return false
    backend.disconnectRow(String(entry.ssid || ""))
    return true
  }

  function forget(entry) {
    if (!entry || !entry.known || busy) return false
    profileError = ""
    if (entry.profileUuid && entry.visible === false)
      return runProfileAction("forget", entry.profileUuid)
    if (!ready || !hasUniqueVisibleIdentity(entry)) return false
    if (entry.profileUuid)
      return runProfileAction("forget", entry.profileUuid)
    if (!hasUnambiguousVisibleSsid(entry)
        || typeof backend.forget !== "function") return false
    backend.forget(entry)
    return true
  }

  function setDns(provider) {
    if (!ready || typeof backend.setDns !== "function") return false
    backend.setDns(provider)
    return true
  }

  function speedTestCommandFor(phaseValue) {
    return [String(speedTestRunnerSource),
      String(speedTestExecutable || ""), String(phaseValue || "")]
  }

  function updateSpeedTestLine(line) {
    const raw = String(line || "").trim()
    if (!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw)) return
    const value = Number(raw)
    if (!isFinite(value) || value < 0) return
    const normalized = String(value)
    if (speedTestPhase === "down") speedTestDownloadMbps = normalized
    else if (speedTestPhase === "up") speedTestUploadMbps = normalized
  }

  function startSpeedTestPhase(phaseValue) {
    speedTestExpectedStop = false
    speedTestProcessStarted = false
    speedTestPhase = phaseValue
    speedTestStderr = ""
    speedTestProc.command = speedTestCommandFor(phaseValue)
    speedTestProc.running = true
    speedTestPhaseTimer.restart()
  }

  function speedTestPhaseHasSample() {
    return speedTestPhase === "down"
      ? speedTestDownloadMbps !== "" : speedTestUploadMbps !== ""
  }

  function failSpeedTest(message) {
    speedTestPhaseTimer.stop()
    speedTestError = String(message || "Speed test failed")
    speedTestPhase = ""
    speedTestRunning = false
    speedTestExpectedStop = false
    speedTestProcessStarted = false
  }

  function finishSpeedTestPhase() {
    if (!speedTestRunning) return
    if (speedTestPhase === "down") {
      startSpeedTestPhase("up")
      return
    }
    speedTestPhase = ""
    speedTestRunning = false
    speedTestExpectedStop = false
  }

  function stopSpeedTestPhase() {
    speedTestPhaseTimer.stop()
    if (!speedTestRunning) return
    if (speedTestProc.running) {
      speedTestExpectedStop = true
      speedTestProc.running = false
      return
    }
    finishSpeedTestPhase()
  }

  function handleSpeedTestExit(exitCode) {
    speedTestPhaseTimer.stop()
    const expected = speedTestExpectedStop
    speedTestExpectedStop = false
    speedTestProcessStarted = false
    if (speedTestPendingRun) {
      speedTestPendingRun = false
      speedTestRunning = false
      if (sessionCount > 0) Qt.callLater(function() {
        if (root.sessionCount > 0) root.runSpeedTest()
      })
      return
    }
    if (!speedTestRunning) return
    if (!expected && exitCode !== 0) {
      failSpeedTest(speedTestStderr || "Speed test failed")
      return
    }
    if (!speedTestPhaseHasSample()) {
      failSpeedTest(speedTestStderr || "Speed test produced no "
        + speedTestPhase + "load data")
      return
    }
    finishSpeedTestPhase()
  }

  function stopSpeedTest() {
    const active = speedTestRunning || speedTestProc.running
    speedTestPhaseTimer.stop()
    speedTestPendingRun = false
    speedTestPhase = ""
    speedTestRunning = false
    if (speedTestProc.running) {
      speedTestExpectedStop = true
      speedTestProc.running = false
    } else {
      speedTestExpectedStop = false
      speedTestProcessStarted = false
    }
    return active
  }

  function runSpeedTest() {
    if (!ready || !speedTestReady || speedTestRunning) return false
    speedTestError = ""
    speedTestDownloadMbps = ""
    speedTestUploadMbps = ""
    if (speedTestProc.running) {
      if (sessionCount <= 0) return false
      speedTestPendingRun = true
      speedTestRunning = true
      speedTestPhase = ""
      return true
    }
    speedTestPendingRun = false
    speedTestRunning = true
    startSpeedTestPhase("down")
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

  NetworkPanelBridge {
    id: bridge
    bar: root.bar
    ownerWidget: root.bar
    networkService: root
    panelComponent: root.panelComponent
    panelSource: root.panelSource
    panelSettings: root.officialSettings()
  }

  Timer {
    id: scanRestart
    interval: 100
    repeat: false
    onTriggered: {
      if (root.sessionCount > 0
          && root.setSessionScannerEnabled(true)) {
        if (root.backend && typeof root.backend.refresh === "function")
          root.backend.refresh(false)
        scanDone.restart()
      } else {
        root.scanPending = false
      }
    }
  }

  Timer {
    id: scanDone
    interval: 1500
    repeat: false
    onTriggered: root.completeWifiScan()
  }

  Timer {
    id: speedTestPhaseTimer
    interval: root.speedTestPhaseDuration
    repeat: false
    onTriggered: root.stopSpeedTestPhase()
  }

  Process {
    id: speedTestProc
    onStarted: root.speedTestProcessStarted = true
    onRunningChanged: {
      if (!running && root.speedTestRunning
          && !root.speedTestProcessStarted)
        root.failSpeedTest("Unable to start network speed test")
    }
    stdout: SplitParser {
      onRead: function(line) { root.updateSpeedTestLine(line) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.speedTestStderr = String(text || "").trim()
        if (root.speedTestError !== "" && root.speedTestStderr !== "")
          root.speedTestError = root.speedTestStderr
      }
    }
    onExited: function(exitCode, _exitStatus) {
      root.handleSpeedTestExit(exitCode)
    }
  }

  Timer {
    id: detailsPoll
    interval: 2000
    repeat: true
    running: root.ready
      && (root.sessionCount > 0 || root.kind === "ethernet")
    triggeredOnStart: true
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
      + "mapfile -t details < <(nmcli --escape no -g 802-11-wireless.ssid,connection.timestamp,802-11-wireless-security.key-mgmt,802-11-wireless-security.auth-alg connection show uuid \"$uuid\"); "
      + "ssid=${details[0]-}; timestamp=${details[1]:-0}; key_mgmt=${details[2]-}; auth_alg=${details[3]-}; "
      + "[ -n \"$ssid\" ] || continue; "
      + "case \"$timestamp\" in ''|*[!0-9]*) timestamp=0 ;; esac; "
      + "[ -n \"$key_mgmt\" ] || key_mgmt=open; [ -n \"$auth_alg\" ] || auth_alg=unknown; "
      + "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$uuid\" \"$ssid\" \"$timestamp\" \"$key_mgmt\" \"$auth_alg\"; "
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
          if (fields.length < 5) continue
          profiles.push({
            uuid: fields[0],
            ssid: fields.slice(1, fields.length - 3).join("\t"),
            lastSuccessful: parseInt(fields[fields.length - 3]) || 0,
            keyManagement: fields[fields.length - 2],
            authAlgorithm: fields[fields.length - 1]
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
    releaseWifiScanner()
    stopSpeedTest()
    detailsProc.running = false
    profileList.running = false
  }
}
