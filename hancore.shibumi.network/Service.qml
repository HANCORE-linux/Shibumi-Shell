pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/runtime" as SuiteRuntime
import "NetworkModel.js" as NetworkModel
import "NetworkQrSecretModel.js" as QrSecretModel

// One process-wide native Network owner. Raw Quickshell Networking objects are
// confined to NetworkBackendAdapter/NetworkScannerLease; this facade publishes
// primitive snapshots and typed mutations to every output-local bar/panel.
Item {
  id: root

  property var shell: null
  property var manifest: null
  SuiteRuntime.Provider {
    pluginId: "hancore.shibumi.network"
    implementationVersion: "0.1.1-beta.14"
    owner: root
    host: root.shell
    manifest: root.manifest
  }
  property var bar: shell ? shell.bar : null
  property bool active: true

  readonly property bool ready: root.active
    && liveness.monitorEstablished
  readonly property bool backendAvailable: adapter.backendAvailable
  readonly property bool processRestartRequired:
    liveness.processRestartRequired
  readonly property bool recoveryBlocked: liveness.recoveryBlocked
  readonly property string livenessPhase: liveness.phase
  readonly property bool mutationBlocked: root.processRestartRequired
    || root.recoveryBlocked || root.livenessPhase === "recovery-blocked"
  readonly property bool busy: actions.busy || profileActions.busy
    || qrSecrets.busy
  readonly property bool qrSecretBusy: qrSecrets.busy
  readonly property string qrSecretError: qrSecrets.errorCode
  readonly property bool wifiEnabled: adapter.radioSnapshot.enabled
  readonly property bool wifiAvailable: adapter.radioSnapshot.available
  readonly property bool scanning: scanner.scanning || scanner.scannerEnabled
  readonly property var radioSnapshot: adapter.radioSnapshot
  readonly property var deviceSnapshots: adapter.deviceSnapshots
  readonly property var visibleNetworkSnapshots: adapter.networkSnapshots
  readonly property var profileSnapshots: adapter.profileSnapshots
  readonly property var savedProfileSnapshots: adapter.savedProfileSnapshots
  readonly property var connectionSnapshot: adapter.connectionDetailsSnapshot
  readonly property var dnsSnapshot: adapter.dnsSnapshot
  readonly property var throughputSnapshot: adapter.throughputSnapshot
  readonly property var reachabilitySnapshot: adapter.reachabilitySnapshot
  readonly property var actionSnapshot: actions.phase === "pending"
    ? actions.actionSnapshot
    : profileActions.phase === "pending" || profileActions.phase === "failed"
      ? profileActions.actionSnapshot : actions.actionSnapshot
  readonly property var networks: implementation.networkRows()
  readonly property int sessionCount: implementation.sessionCount()
  readonly property int trafficConsumerCount:
    implementation.trafficConsumerCount()

  readonly property string kind: implementation.connectionKind()
  readonly property string label: implementation.connectionLabel()
  readonly property int signalStrength: implementation.connectionSignal()
  readonly property var info: implementation.connectionInfo()
  readonly property real downloadRate: adapter.throughputSnapshot
    ? adapter.throughputSnapshot.downloadBytesPerSecond : 0
  readonly property real uploadRate: adapter.throughputSnapshot
    ? adapter.throughputSnapshot.uploadBytesPerSecond : 0
  readonly property real routerPingLatency: adapter.reachabilitySnapshot
    ? adapter.reachabilitySnapshot.routerLatencyMs : -1
  readonly property real internetPingLatency: adapter.reachabilitySnapshot
    ? adapter.reachabilitySnapshot.internetLatencyMs : -1
  readonly property int internetPingPacketLoss: adapter.reachabilitySnapshot
    ? adapter.reachabilitySnapshot.internetPacketLossPercent : 0
  readonly property var dnsServers: adapter.dnsSnapshot
    ? adapter.dnsSnapshot.servers : []
  readonly property var dnsDomains: adapter.dnsSnapshot
    ? adapter.dnsSnapshot.domains : []
  readonly property string actionKind: profileActions.phase === "pending"
    ? profileActions.actionKind : actions.phase === "pending"
      ? actions.actionKind : ""
  readonly property string actionSsid:
    implementation.actionSsid(root.actionSnapshot)
  readonly property string failureSsid: profileActions.phase === "failed"
    || actions.phase === "failed"
      ? implementation.actionSsid(root.actionSnapshot) : ""
  readonly property string failureReason: profileActions.phase === "failed"
    ? profileActions.failureMessage : actions.failureMessage
  readonly property string profileError: catalog.errorCode === ""
    ? "" : implementation.catalogError(catalog.errorCode)
  readonly property bool profilesLoaded: catalog.available
  readonly property var savedProfiles: adapter.savedProfileSnapshots

  readonly property bool speedTestReady: speedTest.available
    && speedTest.testInput !== null
  readonly property bool speedTestRunning: speedTest.running
  readonly property bool speedTestHasRun: speedTest.speedTestResult !== null
  readonly property string speedTestPhase: speedTest.phase === "down"
    || speedTest.phase === "up" ? speedTest.phase : ""
  readonly property string speedTestDownloadMbps:
    speedTest.downloadMbps >= 0 ? String(speedTest.downloadMbps) : ""
  readonly property string speedTestUploadMbps:
    speedTest.uploadMbps >= 0 ? String(speedTest.uploadMbps) : ""
  readonly property string speedTestError: speedTest.errorCode === ""
    ? "" : implementation.speedError(speedTest.errorCode)

  visible: false
  width: 0
  height: 0

  function beginSession(owner) { return implementation.beginSession(owner) }
  function endSession(owner) { return implementation.endSession(owner) }
  function beginTrafficConsumer(owner) {
    return implementation.beginTrafficConsumer(owner)
  }
  function endTrafficConsumer(owner) {
    return implementation.endTrafficConsumer(owner)
  }
  function refresh(scanWifi) {
    return root.mutationBlocked && scanWifi === true
      ? false : implementation.refresh(scanWifi)
  }
  function refreshProfiles() { return catalog.requestRefresh() }

  function toggleWifi() {
    if (root.mutationBlocked)
      return implementation.invalidAction("restart-required")
    if (root.busy) return implementation.invalidAction("busy")
    implementation.prepareAction()
    return actions.setWifiEnabled({
      entityId: adapter.radioSnapshot.id,
      generation: adapter.generation
    }, !adapter.radioSnapshot.enabled)
  }

  function connect(entry) {
    if (root.mutationBlocked)
      return implementation.invalidAction("restart-required")
    const row = implementation.entryData(entry)
    if (!row || root.busy)
      return implementation.invalidAction(!row ? "invalid" : "busy")
    implementation.prepareAction()
    if (row.connected) return disconnect(row)
    if (row.entityKind === "profile")
      return implementation.dispatchProfileAction(
        "connect-profile", row.profileId, row.generation)
    if (row.entityKind === "catalog")
      return profileActions.connectProfile({
        entityId: row.id, generation: row.generation
      }, row.deviceId)
    if (row.entityKind !== "network")
      return implementation.invalidAction("unsupported")
    return actions.connectNetwork({
      entityId: row.networkId, generation: row.generation
    })
  }

  function connectWithPassphrase(entry, passphrase) {
    if (root.mutationBlocked)
      return implementation.invalidAction("restart-required")
    const row = implementation.entryData(entry)
    if (!row || row.entityKind !== "network" || root.busy)
      return implementation.invalidAction(root.busy ? "busy" : "invalid")
    implementation.prepareAction()
    return actions.connectNetworkWithPsk({
      entityId: row.networkId, generation: row.generation
    }, passphrase)
  }

  function connectEnterprise(entry, identity, passphrase, serverDomain) {
    if (root.mutationBlocked)
      return implementation.invalidAction("restart-required")
    const row = implementation.entryData(entry)
    if (!row || row.entityKind !== "network" || root.busy
        || row.security !== "wpa2-eap")
      return implementation.invalidAction(root.busy ? "busy" : "unsupported")
    implementation.prepareAction()
    return actions.connectNetworkEnterprise({
      entityId: row.networkId, generation: row.generation
    }, {
      method: "peap-mschapv2",
      identity: identity,
      password: passphrase,
      serverDomain: serverDomain
    })
  }

  function disconnect(entry) {
    if (root.mutationBlocked)
      return implementation.invalidAction("restart-required")
    const row = implementation.entryData(entry)
    if (!row || !row.networkId || root.busy)
      return implementation.invalidAction(root.busy ? "busy" : "invalid")
    implementation.prepareAction()
    return actions.disconnectNetwork({
      entityId: row.networkId, generation: row.generation
    })
  }

  function forget(entry) {
    if (root.mutationBlocked)
      return implementation.invalidAction("restart-required")
    const row = implementation.entryData(entry)
    if (!row || root.busy)
      return implementation.invalidAction(!row ? "invalid" : "busy")
    implementation.prepareAction()
    if (row.entityKind === "catalog")
      return profileActions.forgetProfile({
        entityId: row.id, generation: row.generation
      })
    if (row.entityKind !== "profile" || !row.profileId)
      return implementation.invalidAction("unsupported")
    return implementation.dispatchProfileAction(
      "forget-profile", row.profileId, row.generation)
  }

  function runSpeedTest(owner) {
    if (root.mutationBlocked) return false
    const target = owner || implementation.firstSessionOwner()
    return target ? speedTest.requestRun(target) : false
  }

  function stopSpeedTest(owner) {
    const target = owner || implementation.firstSessionOwner()
    return target ? speedTest.cancel(target) : false
  }

  function beginQrGesture(owner, entry) {
    return implementation.beginQrGesture(owner, entry)
  }

  function cancelQrGesture(owner, gestureToken) {
    return implementation.cancelQrGesture(owner, gestureToken)
  }

  function requestQrSecret(owner, entry, gestureToken) {
    if (root.mutationBlocked) return {
      accepted: false, code: "restart-required", requestToken: ""
    }
    const row = implementation.entryData(entry)
    const descriptor = implementation.qrSecretDescriptor(row)
    if (!descriptor) return {
      accepted: false, code: "descriptor-stale", requestToken: ""
    }
    if (!implementation.consumeQrGesture(
        owner, descriptor, gestureToken)) return {
      accepted: false, code: "gesture-expired", requestToken: ""
    }
    return qrSecrets.request(owner, descriptor)
  }

  function cancelQrSecret(owner, requestToken) {
    return qrSecrets.cancel(owner, requestToken)
  }

  function qrSecretRequestCurrent(descriptor) {
    return implementation.qrSecretRequestCurrent(descriptor)
  }

  function formatRate(value) {
    const bytes = Math.max(0, Number(value) || 0)
    if (bytes >= 1024 * 1024 * 1024)
      return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GiB/s"
    if (bytes >= 1024 * 1024)
      return (bytes / (1024 * 1024)).toFixed(1) + " MiB/s"
    if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KiB/s"
    return Math.round(bytes) + " B/s"
  }

  function formatPing(value) {
    const latency = Number(value)
    return isFinite(latency) && latency >= 0
      ? (latency < 10 ? latency.toFixed(1) : latency.toFixed(0)) + " ms"
      : "--"
  }

  function formatSpeed(value) {
    const measured = Number(value)
    if (!isFinite(measured) || measured < 0) return "—"
    return (measured >= 100 ? measured.toFixed(0) : measured.toFixed(1))
      + " Mbps"
  }

  Timer {
    id: qrGestureTimeout
    interval: 750
    onTriggered: implementation.clearQrGesture()
  }

  NetworkLivenessContinuity { id: continuity }

  NetworkManagerLiveness {
    id: liveness
    objectName: "shibumiNetworkManagerLiveness"
    active: root.active
    continuityState: continuity
  }

  NetworkProfileCatalog {
    id: catalog
    active: root.active
    nativeLiveness: liveness
  }

  NetworkTelemetry {
    id: telemetry
    active: root.active
    nativeLiveness: liveness
  }

  NetworkReachability {
    id: reachability
    active: root.active
    networkTelemetry: telemetry
  }

  NetworkBackendAdapter {
    id: adapter
    active: root.active
    nativeLiveness: liveness
    savedProfileCatalog: catalog
    networkTelemetry: telemetry
    networkReachability: reachability
  }

  NetworkScannerLease {
    id: scanner
    active: root.active
    nativeLiveness: liveness
  }

  NetworkEnterpriseDispatcher {
    id: enterprise
    active: root.active
    networkAdapter: adapter
  }

  NetworkActionCoordinator {
    id: actions
    active: root.active
    networkAdapter: adapter
    enterpriseDispatcher: enterprise
  }

  NetworkSpeedTest {
    id: speedTest
    active: root.active
    networkTelemetry: telemetry
  }

  NetworkProfileActionDispatcher {
    id: profileActions
    active: root.active
    networkAdapter: adapter
    savedProfileCatalog: catalog
    networkTelemetry: telemetry
  }

  NetworkQrSecretDispatcher {
    id: qrSecrets
    active: root.active
    networkService: root
    nativeLiveness: liveness
  }

  NetworkProfileActionLease {
    id: profileActionLease
    active: root.active
    networkTelemetry: telemetry
    savedProfileCatalog: catalog
    actionCoordinator: actions
  }

  NetworkPanelBridge {
    id: bridge
    bar: root.bar
    networkService: root
  }

  QtObject {
    id: implementation

    property var ownerRecords: []
    property string catalogRefreshActionId: ""
    property int qrGestureSequence: 1
    property string qrGestureToken: ""
    property var qrGestureOwner: null
    property var qrGestureDescriptor: null

    function sessionCount() {
      let count = 0
      for (let index = 0; index < ownerRecords.length; index++)
        if (ownerRecords[index].session) count++
      return count
    }

    function trafficConsumerCount() {
      let count = 0
      for (let index = 0; index < ownerRecords.length; index++)
        if (ownerRecords[index].traffic) count++
      return count
    }

    function recordIndex(owner) {
      for (let index = 0; index < ownerRecords.length; index++)
        if (ownerRecords[index].owner === owner) return index
      return -1
    }

    function replaceRecord(index, record) {
      const next = ownerRecords.slice()
      if (record.session || record.traffic) next[index] = record
      else next.splice(index, 1)
      ownerRecords = next
    }

    function beginSession(owner) {
      if (!owner || !root.active) return false
      let index = recordIndex(owner)
      let record = index >= 0 ? ownerRecords[index]
        : { owner: owner, session: false, traffic: false }
      if (record.session) return true
      if (!record.traffic && !telemetry.acquire(owner)) return false
      if (!catalog.acquire(owner)) {
        if (!record.traffic) telemetry.release(owner)
        return false
      }
      if (!reachability.acquire(owner)) {
        catalog.release(owner)
        if (!record.traffic) telemetry.release(owner)
        return false
      }
      if (!scanner.acquire(owner)) {
        reachability.release(owner)
        catalog.release(owner)
        if (!record.traffic) telemetry.release(owner)
        return false
      }
      record = { owner: owner, session: true, traffic: record.traffic }
      if (index < 0) {
        const next = ownerRecords.slice()
        next.push(record)
        ownerRecords = next
      } else replaceRecord(index, record)
      refresh(true)
      return true
    }

    function endSession(owner) {
      const index = recordIndex(owner)
      if (index < 0 || !ownerRecords[index].session) return false
      const record = ownerRecords[index]
      speedTest.cancel(owner)
      scanner.release(owner)
      reachability.release(owner)
      catalog.release(owner)
      if (!record.traffic) telemetry.release(owner)
      replaceRecord(index, {
        owner: owner, session: false, traffic: record.traffic
      })
      return true
    }

    function beginTrafficConsumer(owner) {
      if (!owner || !root.active) return false
      let index = recordIndex(owner)
      let record = index >= 0 ? ownerRecords[index]
        : { owner: owner, session: false, traffic: false }
      if (record.traffic) return true
      if (!record.session && !telemetry.acquire(owner)) return false
      record = { owner: owner, session: record.session, traffic: true }
      if (index < 0) {
        const next = ownerRecords.slice()
        next.push(record)
        ownerRecords = next
      } else replaceRecord(index, record)
      return true
    }

    function endTrafficConsumer(owner) {
      const index = recordIndex(owner)
      if (index < 0 || !ownerRecords[index].traffic) return false
      const record = ownerRecords[index]
      if (!record.session) telemetry.release(owner)
      replaceRecord(index, {
        owner: owner, session: record.session, traffic: false
      })
      return true
    }

    function firstSessionOwner() {
      for (let index = 0; index < ownerRecords.length; index++)
        if (ownerRecords[index].session) return ownerRecords[index].owner
      return null
    }

    function refresh(scanWifi) {
      if (!root.active) return false
      telemetry.requestRefresh()
      catalog.requestRefresh()
      reachability.requestRefresh()
      if (scanWifi === true) return scanner.requestScan()
      return true
    }

    function cloneEntry(source) {
      if (!source || typeof source !== "object") return null
      const row = ({})
      for (const key in source) row[key] = source[key]
      return row
    }

    function entryData(source) {
      const row = cloneEntry(source)
      if (!row || typeof row.generation !== "number"
          || !isFinite(row.generation) || row.generation < 0
          || Math.floor(row.generation) !== row.generation
          || ["network", "profile", "catalog"].indexOf(row.entityKind) < 0)
        return null
      return row
    }

    function clearQrGesture() {
      qrGestureTimeout.stop()
      qrGestureToken = ""
      qrGestureOwner = null
      qrGestureDescriptor = null
    }

    function beginQrGesture(owner, entry) {
      clearQrGesture()
      if (!owner || root.mutationBlocked) return {
        accepted: false, gestureToken: ""
      }
      const row = entryData(entry)
      const descriptor = qrSecretDescriptor(row)
      if (!descriptor) return { accepted: false, gestureToken: "" }
      const token = "shibumi-qr-gesture-v1:" + JSON.stringify([
        qrGestureSequence
      ])
      qrGestureSequence++
      if (qrGestureSequence > 2147483646) qrGestureSequence = 1
      qrGestureToken = token
      qrGestureOwner = owner
      qrGestureDescriptor = descriptor
      qrGestureTimeout.restart()
      return { accepted: true, gestureToken: token }
    }

    function cancelQrGesture(owner, token) {
      if (owner !== qrGestureOwner || token !== qrGestureToken) return false
      clearQrGesture()
      return true
    }

    function consumeQrGesture(owner, descriptor, token) {
      const accepted = owner === qrGestureOwner && token === qrGestureToken
        && QrSecretModel.sameDescriptor(descriptor, qrGestureDescriptor)
      clearQrGesture()
      return accepted
    }

    function qrSecretDescriptor(source) {
      if (!source || source.entityKind !== "network"
          || source.connected !== true || source.state !== "connected"
          || source.stateChanging === true || source.ambiguous === true
          || !NetworkModel.pskKind(source.security)
          || typeof source.profileUuid !== "string"
          || source.profileUuid === ""
          || source.generation !== adapter.generation
          || activeUuid(source.deviceId) !== source.profileUuid
          || adapter.savedProfileCatalogAvailable !== true) return null
      const nativeProfiles = adapter.profileSnapshots
      let nativeProfileCount = 0
      for (let index = 0; index < nativeProfiles.length; index++) {
        const profile = nativeProfiles[index]
        if (profile && profile.networkId === source.networkId
            && profile.uuid === source.profileUuid
            && profile.ambiguous !== true) nativeProfileCount++
      }
      const catalogRows = adapter.savedProfileSnapshots
      let catalogProfile = null
      let catalogCount = 0
      for (let index = 0; index < catalogRows.length; index++) {
        if (catalogRows[index]
            && catalogRows[index].uuid === source.profileUuid) {
          catalogProfile = catalogRows[index]
          catalogCount++
        }
      }
      if (catalogCount !== 1 || !NetworkModel.qrShareEligible(
          source.connected, source.ambiguous, source.security, source.ssid,
          source.profileUuid, nativeProfileCount, catalogProfile)) return null
      const rows = networkRows()
      let current = null
      let currentCount = 0
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (row && row.entityKind === "network"
            && row.networkId === source.networkId) {
          current = row
          currentCount++
        }
      }
      if (currentCount !== 1 || !current || current.connected !== true
          || current.canShare !== true
          || current.profileUuid !== source.profileUuid
          || current.deviceId !== source.deviceId
          || current.ssid !== source.ssid
          || current.security !== source.security
          || current.generation !== source.generation) return null
      const devices = adapter.deviceSnapshots
      let device = null
      let deviceCount = 0
      for (let index = 0; index < devices.length; index++) {
        if (devices[index] && devices[index].id === source.deviceId) {
          device = devices[index]
          deviceCount++
        }
      }
      if (deviceCount !== 1 || !device || device.type !== "wifi"
          || device.managed !== true || device.ambiguous === true
          || device.connected !== true) return null
      return QrSecretModel.descriptor({
        networkId: source.networkId,
        profileUuid: source.profileUuid,
        deviceId: source.deviceId,
        interfaceName: device.name,
        hardwareAddress: device.address,
        ssid: source.ssid,
        ssidHex: NetworkModel.ssidHex(source.ssid),
        security: source.security,
        generation: source.generation
      })
    }

    function qrSecretRequestCurrent(descriptor) {
      const safe = QrSecretModel.descriptor(descriptor)
      if (!safe || root.mutationBlocked) return false
      const rows = networkRows()
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (!row || row.entityKind !== "network"
            || row.networkId !== safe.networkId) continue
        const current = qrSecretDescriptor(row)
        return QrSecretModel.sameDescriptor(current, safe)
      }
      return false
    }

    function prepareAction() {
      if (root.busy) return false
      actions.clearResult()
      profileActions.clearResult()
      return true
    }

    function dispatchProfileAction(kind, entityId, generation) {
      if (!profileActionLease.acquire()) return invalidAction("unavailable")
      const request = { entityId: entityId, generation: generation }
      const result = kind === "connect-profile"
        ? actions.connectProfile(request) : actions.forgetProfile(request)
      profileActionLease.retainIfPending(kind)
      return result
    }

    function invalidAction(code) {
      return {
        accepted: false,
        code: String(code || "invalid"),
        message: code === "unsupported"
          ? "This exact network action is unsupported."
          : code === "restart-required"
            ? "Restart the shell to restore NetworkManager."
          : code === "unavailable"
            ? "Network action completion evidence is unavailable."
            : code === "busy"
              ? "Another network action is still pending."
              : "Network action request is invalid.",
        actionId: "",
        entityId: "",
        generation: adapter.generation
      }
    }

    function securityKind(token) {
      if (token === "open") return "open"
      if (token === "wpa-psk" || token === "wpa2-psk" || token === "sae")
        return "psk"
      if (token === "wpa2-eap") return "enterprise"
      if (token === "owe") return "owe"
      return "unsupported"
    }

    function securityLabel(token) {
      switch (token) {
      case "open": return "Open"
      case "wpa-psk": return "WPA Personal"
      case "wpa2-psk": return "WPA2 Personal"
      case "sae": return "WPA3 Personal"
      case "owe": return "Enhanced Open (OWE)"
      case "static-wep": return "WEP"
      case "dynamic-wep": return "Dynamic WEP"
      case "wpa-eap": return "WPA Enterprise"
      case "wpa2-eap": return "WPA2 Enterprise · PEAP/MSCHAPv2"
      case "wpa3-suite-b-192": return "WPA3 Enterprise"
      case "leap": return "LEAP"
      default: return "Unknown security"
      }
    }

    function catalogByUuid() {
      const result = ({})
      const rows = adapter.savedProfileSnapshots
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (row && row.uuid) result[row.uuid] = row
      }
      return result
    }

    function networkById() {
      const result = ({})
      const rows = adapter.networkSnapshots
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (row && row.id) result[row.id] = row
      }
      return result
    }

    function profilesByNetwork() {
      const result = ({})
      const rows = adapter.profileSnapshots
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (!row || !row.networkId) continue
        if (!result[row.networkId]) result[row.networkId] = []
        result[row.networkId].push(row)
      }
      return result
    }

    function activeUuid(deviceId) {
      return adapter.activeConnectionUuidForDevice(String(deviceId || ""))
    }

    function networkVisible(row) {
      return row && (row.connected === true || row.known !== true
        || Number(row.signal || 0) > 0)
    }

    function hiddenForNetwork(network, profiles, catalogRows) {
      const uuid = activeUuid(network.deviceId)
      if (uuid !== "") {
        for (let index = 0; index < profiles.length; index++) {
          if (profiles[index].uuid === uuid && catalogRows[uuid])
            return catalogRows[uuid].hidden === true
        }
      }
      return profiles.length === 1 && catalogRows[profiles[0].uuid]
        ? catalogRows[profiles[0].uuid].hidden === true : false
    }

    function networkRows() {
      const result = []
      const networks = adapter.networkSnapshots
      const profiles = adapter.profileSnapshots
      const catalogs = catalogByUuid()
      const grouped = profilesByNetwork()
      const representedCatalogs = ({})

      for (let index = 0; index < networks.length; index++) {
        const network = networks[index]
        if (!network) continue
        const related = grouped[network.id] || []
        const connectedUuid = network.connected === true
          ? activeUuid(network.deviceId) : ""
        let activeProfile = null
        let activeProfileCount = 0
        for (let profileIndex = 0; profileIndex < related.length;
            profileIndex++) {
          if (related[profileIndex].uuid !== connectedUuid) continue
          activeProfile = related[profileIndex]
          activeProfileCount++
        }
        const oneProfile = activeProfileCount === 1 ? activeProfile
          : related.length === 1 ? related[0] : null
        const qrActiveProfileCount = activeProfileCount === 1
            && activeProfile && activeProfile.ambiguous !== true
          ? 1 : 0
        const visible = networkVisible(network)
        result.push({
          entryKey: "network:" + network.id,
          entityKind: "network",
          id: network.id,
          networkId: network.id,
          profileId: oneProfile ? oneProfile.id : "",
          profileUuid: oneProfile ? oneProfile.uuid : "",
          profileName: oneProfile && catalogs[oneProfile.uuid]
            ? catalogs[oneProfile.uuid].name : "",
          deviceId: network.deviceId,
          generation: network.generation,
          connected: network.connected,
          known: network.known,
          ssid: network.ssid,
          signal: network.signal,
          security: network.security,
          securityKind: securityKind(network.security),
          securityLabel: securityLabel(network.security),
          hidden: hiddenForNetwork(network, related, catalogs),
          state: network.state,
          stateChanging: network.stateChanging,
          ambiguous: network.ambiguous,
          visible: visible,
          listKind: "available",
          canConnect: network.canConnect,
          canConnectWithPsk: network.canConnectWithPsk,
          canDisconnect: network.canDisconnect,
          canForget: false,
          canShare: NetworkModel.qrShareEligible(
            network.connected, network.ambiguous, network.security,
            network.ssid, connectedUuid, qrActiveProfileCount,
            catalogs[connectedUuid] || null)
        })
      }

      const networkMap = networkById()
      for (let index = 0; index < profiles.length; index++) {
        const profile = profiles[index]
        if (!profile) continue
        const network = networkMap[profile.networkId]
        if (!network) continue
        const catalogRow = catalogs[profile.uuid] || null
        representedCatalogs[profile.uuid] = true
        result.push({
          entryKey: "profile:" + profile.id,
          entityKind: "profile",
          id: profile.id,
          networkId: profile.networkId,
          profileId: profile.id,
          profileUuid: profile.uuid,
          profileName: catalogRow ? catalogRow.name : profile.name,
          deviceId: profile.deviceId,
          generation: profile.generation,
          connected: network.connected === true
            && activeUuid(profile.deviceId) === profile.uuid,
          known: true,
          ssid: profile.ssid,
          signal: network.signal,
          security: catalogRow ? catalogRow.security : "unknown",
          securityKind: securityKind(
            catalogRow ? catalogRow.security : "unknown"),
          securityLabel: securityLabel(
            catalogRow ? catalogRow.security : "unknown"),
          hidden: catalogRow ? catalogRow.hidden === true : false,
          state: network.state,
          stateChanging: network.stateChanging,
          ambiguous: profile.ambiguous,
          visible: networkVisible(network),
          listKind: "saved",
          canConnect: profile.canConnect,
          canConnectWithPsk: false,
          canDisconnect: network.canDisconnect,
          canForget: profile.canForget,
          canShare: false
        })
      }

      const catalogRows = adapter.savedProfileSnapshots
      const catalogDevice = uniqueWifiDevice()
      for (let index = 0; index < catalogRows.length; index++) {
        const profile = catalogRows[index]
        if (!profile || profile.profileType !== "wifi"
            || representedCatalogs[profile.uuid]) continue
        result.push({
          entryKey: "catalog:" + profile.id,
          entityKind: "catalog",
          id: profile.id,
          networkId: "",
          profileId: "",
          profileUuid: profile.uuid,
          profileName: profile.name,
          deviceId: catalogDevice ? catalogDevice.id : "",
          generation: profile.generation,
          connected: false,
          known: true,
          ssid: profile.ssid || profile.name,
          signal: 0,
          security: profile.security,
          securityKind: securityKind(profile.security),
          securityLabel: securityLabel(profile.security),
          hidden: profile.hidden,
          state: "disconnected",
          stateChanging: false,
          ambiguous: false,
          visible: false,
          listKind: "saved",
          canConnect: catalogDevice !== null,
          canConnectWithPsk: false,
          canDisconnect: false,
          canForget: true,
          canShare: false
        })
      }

      result.sort(function(left, right) {
        if (left.listKind !== right.listKind)
          return left.listKind === "available" ? -1 : 1
        if (left.connected !== right.connected) return left.connected ? -1 : 1
        if (left.visible !== right.visible) return left.visible ? -1 : 1
        if (left.signal !== right.signal) return right.signal - left.signal
        return String(left.ssid).localeCompare(String(right.ssid))
      })
      return result
    }

    function uniqueWifiDevice() {
      const rows = adapter.deviceSnapshots
      let result = null
      let count = 0
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (row && row.type === "wifi" && row.managed === true
            && row.ambiguous === false
            && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$/.test(row.name)
            && /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(row.address)) {
          result = row
          count++
        }
      }
      return count === 1 ? result : null
    }

    function connectedDevice(type) {
      const rows = adapter.deviceSnapshots
      let result = null
      let count = 0
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (row && row.type === type && row.connected === true
            && row.ambiguous === false) {
          result = row
          count++
        }
      }
      return count === 1 ? result : null
    }

    function connectedNetwork() {
      const rows = adapter.networkSnapshots
      let result = null
      let count = 0
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (row && row.connected === true && row.ambiguous === false) {
          result = row
          count++
        }
      }
      return count === 1 ? result : null
    }

    function connectionKind() {
      const details = adapter.connectionDetailsSnapshot
      if (details && (details.kind === "wifi" || details.kind === "wired"))
        return details.kind === "wired" ? "ethernet" : "wifi"
      if (connectedNetwork()) return "wifi"
      if (connectedDevice("wired")) return "ethernet"
      return "disconnected"
    }

    function connectionLabel() {
      if (connectionKind() === "wifi") {
        const network = connectedNetwork()
        return network ? network.ssid : ""
      }
      if (connectionKind() === "ethernet") {
        const details = adapter.connectionDetailsSnapshot
        if (details && details.interfaceName) return details.interfaceName
        const device = connectedDevice("wired")
        return device ? device.name : ""
      }
      return ""
    }

    function connectionSignal() {
      const network = connectedNetwork()
      return network ? network.signal : 0
    }

    function firstAddress(details) {
      if (!details || !Array.isArray(details.addresses)
          || details.addresses.length < 1) return null
      for (let index = 0; index < details.addresses.length; index++)
        if (details.addresses[index].family === "ipv4")
          return details.addresses[index]
      return details.addresses[0]
    }

    function firstGateway(details) {
      if (!details || !Array.isArray(details.gateways)) return ""
      for (let index = 0; index < details.gateways.length; index++)
        if (details.gateways[index].family === "ipv4")
          return details.gateways[index].address
      return details.gateways.length > 0 ? details.gateways[0].address : ""
    }

    function connectionInfo() {
      const details = adapter.connectionDetailsSnapshot
      const address = firstAddress(details)
      return {
        iface: details ? details.interfaceName : "",
        ip: address ? address.address : "",
        prefix: address ? address.prefix : 0,
        gateway: firstGateway(details),
        freq: details && details.wifi ? details.wifi.frequencyMhz : 0,
        bitrate: details && details.wifi && details.wifi.bitrateKbps > 0
          ? (details.wifi.bitrateKbps / 1000).toFixed(0) + " Mbit/s" : "",
        speed: details && details.wired ? details.wired.speedMbps : 0,
        metered: details ? details.metered : "unknown"
      }
    }

    function actionSsid(snapshot) {
      if (!snapshot || !snapshot.entityId) return ""
      const rows = networkRows()
      for (let index = 0; index < rows.length; index++) {
        const row = rows[index]
        if (row.id === snapshot.entityId
            || row.networkId === snapshot.entityId
            || row.profileId === snapshot.entityId)
          return row.ssid
      }
      return ""
    }

    function refreshForgottenProfile() {
      const snapshot = actions.actionSnapshot
      if (!snapshot || snapshot.phase !== "pending"
          || snapshot.kind !== "forget-profile") {
        catalogRefreshActionId = ""
        return false
      }
      if (catalogRefreshActionId === snapshot.actionId) return true
      const rows = adapter.profileSnapshots
      for (let index = 0; index < rows.length; index++)
        if (rows[index] && rows[index].id === snapshot.entityId) return false
      catalogRefreshActionId = snapshot.actionId
      return catalog.requestRefresh()
    }

    function catalogError(code) {
      if (code === "timeout") return "Saved networks timed out."
      if (code === "start-failed") return "Saved networks are unavailable."
      return "Saved network catalog is unavailable."
    }

    function speedError(code) {
      switch (code) {
      case "route-changed": return "Network route changed during the speed test."
      case "timeout": return "Network speed test timed out."
      case "cancelled": return "Network speed test was cancelled."
      default: return "Network speed test failed."
      }
    }

    function shutdownOwners() {
      const records = ownerRecords.slice()
      for (let index = 0; index < records.length; index++) {
        const record = records[index]
        if (record.session) endSession(record.owner)
        if (record.traffic) endTrafficConsumer(record.owner)
      }
      ownerRecords = []
    }
  }

  Connections {
    target: adapter
    function onGenerationChanged() {
      implementation.refreshForgottenProfile()
    }
  }

  Connections {
    target: actions
    function onPhaseChanged() {
      if (actions.phase !== "pending")
        implementation.catalogRefreshActionId = ""
    }
  }

  Component.onDestruction: {
    implementation.shutdownOwners()
    profileActionLease.active = false
    profileActions.active = false
    actions.active = false
    enterprise.active = false
    speedTest.active = false
    scanner.active = false
    reachability.active = false
    catalog.active = false
    telemetry.active = false
    adapter.active = false
    liveness.active = false
  }
}
