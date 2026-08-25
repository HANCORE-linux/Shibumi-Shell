pragma ComponentBehavior: Bound

import QtQuick
import "NetworkModel.js" as Model
import "NetworkProfileCatalogModel.js" as CatalogModel
import "NetworkTelemetryModel.js" as TelemetryModel
import "NetworkReachabilityModel.js" as ReachabilityModel

// Source-only Step 5A capability seam. Production Service.qml does not load
// this adapter yet. Native access is isolated behind an inactive Loader, raw
// backend objects stay private, and the public surface contains primitives and
// typed dispatch results only.
Item {
  id: root

  property bool active: false
  property var backendOverride: null
  // One process-wide NetworkManagerLiveness instance is supplied by the final
  // owning Service. Fake backends never derive readiness from this host seam.
  property var nativeLiveness: null
  property var savedProfileCatalog: null
  property var networkTelemetry: null
  property var networkReachability: null
  readonly property bool nativeServiceAvailable:
    root.nativeLiveness !== null
      && root.nativeLiveness.serviceUsable === true
  readonly property real nativeServiceEpoch:
    root.nativeLiveness !== null
      && typeof root.nativeLiveness.generation === "number"
      && isFinite(root.nativeLiveness.generation)
      && root.nativeLiveness.generation >= 0
      && Math.floor(root.nativeLiveness.generation)
        === root.nativeLiveness.generation
      ? root.nativeLiveness.generation : 0
  // `real` avoids a 32-bit wrapping counter. This is an action-precondition
  // generation, not a signal-strength or presentation revision.
  property real generation: 0

  readonly property int schemaVersion: Model.SchemaVersion
  readonly property bool nativeGatewayLoaded: nativeGateway.item !== null
  readonly property bool backendAvailable: root.active
    && implementation.backendAvailable()
  readonly property string connectivity: root.backendAvailable
    ? Model.connectivityToken(
      implementation.backendValue("connectivity", "unknown")) : "unknown"
  readonly property var baseRadioSnapshot: implementation.radioSnapshot()
  readonly property var deviceProjection: implementation.deviceProjection()
  readonly property var networkProjection: implementation.networkProjection()
  readonly property var profileProjection: implementation.profileProjection()
  readonly property var baseDeviceSnapshots: root.deviceProjection.rows
  readonly property var baseNetworkSnapshots: root.networkProjection.rows
  readonly property var baseProfileSnapshots: root.profileProjection.rows
  readonly property bool snapshotDegraded: root.deviceProjection.overflow
    || root.networkProjection.overflow || root.profileProjection.overflow
  readonly property string topologyFingerprint: Model.topologyFingerprint(
    root.backendAvailable, root.snapshotDegraded, root.baseRadioSnapshot,
    root.baseDeviceSnapshots, root.baseNetworkSnapshots,
    root.baseProfileSnapshots)
  readonly property var backendSnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.backendAvailable,
    degraded: root.snapshotDegraded,
    connectivity: root.connectivity,
    generation: root.generation
  })
  readonly property var radioSnapshot: ({
    schemaVersion: root.schemaVersion,
    id: root.baseRadioSnapshot.id,
    available: root.baseRadioSnapshot.available,
    hardwareEnabled: root.baseRadioSnapshot.hardwareEnabled,
    enabled: root.baseRadioSnapshot.enabled,
    generation: root.generation
  })
  readonly property var deviceSnapshots: Model.cloneWithGeneration(
    root.baseDeviceSnapshots, root.generation)
  readonly property var networkSnapshots: Model.cloneWithGeneration(
    root.baseNetworkSnapshots, root.generation)
  readonly property var profileSnapshots: Model.cloneWithGeneration(
    root.baseProfileSnapshots, root.generation)
  readonly property var savedProfileProjection:
    implementation.savedProfileProjection()
  readonly property bool savedProfileCatalogAvailable:
    root.savedProfileCatalog !== null
      && root.savedProfileCatalog.available === true
      && root.backendAvailable && !root.savedProfileProjection.overflow
  readonly property bool savedProfileCatalogDegraded:
    root.savedProfileProjection.overflow
  readonly property var savedProfileSnapshots: Model.cloneWithGeneration(
    root.savedProfileCatalogAvailable ? root.savedProfileProjection.rows : [],
    root.generation)
  readonly property var savedProfileCatalogSnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.savedProfileCatalogAvailable,
    degraded: root.savedProfileCatalogDegraded,
    count: root.savedProfileSnapshots.length,
    generation: root.generation
  })
  readonly property var telemetryProjection: implementation.telemetryProjection()
  readonly property bool networkTelemetryAvailable:
    root.telemetryProjection.available
  readonly property bool networkTelemetryDegraded:
    root.telemetryProjection.degraded
  readonly property bool networkTelemetryConnected:
    root.networkTelemetryAvailable && root.telemetryProjection.connected
  readonly property var connectionDetailsSnapshot:
    root.networkTelemetryConnected
      ? implementation.telemetryDetails(root.telemetryProjection.row) : null
  readonly property var dnsSnapshot: root.networkTelemetryConnected ? ({
    schemaVersion: root.schemaVersion,
    deviceId: root.telemetryProjection.row.deviceId,
    servers: TelemetryModel.cloneRows(root.telemetryProjection.row.dnsServers),
    domains: root.telemetryProjection.row.dnsDomains.slice(),
    generation: root.generation
  }) : null
  readonly property var throughputSnapshot: root.networkTelemetryConnected ? ({
    schemaVersion: root.schemaVersion,
    deviceId: root.telemetryProjection.row.deviceId,
    rxBytes: root.telemetryProjection.row.rxBytes,
    txBytes: root.telemetryProjection.row.txBytes,
    downloadBytesPerSecond:
      root.telemetryProjection.row.downloadBytesPerSecond,
    uploadBytesPerSecond: root.telemetryProjection.row.uploadBytesPerSecond,
    sampleMonotonicMs: root.telemetryProjection.row.sampleMonotonicMs,
    generation: root.generation
  }) : null
  readonly property var networkTelemetrySnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.networkTelemetryAvailable,
    degraded: root.networkTelemetryDegraded,
    connected: root.networkTelemetryConnected,
    generation: root.generation
  })
  readonly property var reachabilityProjection:
    implementation.reachabilityProjection()
  readonly property bool networkReachabilityAvailable:
    root.reachabilityProjection.available
  readonly property bool networkReachabilityDegraded:
    root.reachabilityProjection.degraded
  readonly property var reachabilitySnapshot:
    root.networkReachabilityAvailable
      ? implementation.reachabilityPublic(root.reachabilityProjection.row)
      : null
  readonly property var networkReachabilitySnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.networkReachabilityAvailable,
    degraded: root.networkReachabilityDegraded,
    generation: root.generation
  })

  visible: false
  width: 0
  height: 0

  onActiveChanged: generation++
  onBackendOverrideChanged: generation++
  onNativeLivenessChanged: generation++
  onSavedProfileCatalogChanged: generation++
  onNetworkTelemetryChanged: generation++
  onNetworkReachabilityChanged: generation++
  onNativeServiceAvailableChanged: generation++
  onNativeServiceEpochChanged: generation++
  onTopologyFingerprintChanged: generation++

  function result(ok, code, message, entityId, resultGeneration) {
    return {
      ok: ok === true,
      code: String(code || "invalid"),
      message: String(message || ""),
      entityId: typeof entityId === "string" ? entityId : "",
      generation: typeof resultGeneration === "number"
        && isFinite(resultGeneration) && resultGeneration >= 0
        && Math.floor(resultGeneration) === resultGeneration
          ? resultGeneration : root.generation
    }
  }

  function setWifiEnabled(request, enabled) {
    const parsed = implementation.requestData(request)
    if (parsed.error) return parsed.error
    const safeRequest = parsed.request
    if (typeof enabled !== "boolean")
      return result(false, "invalid", "Wi-Fi state must be boolean.",
        safeRequest.entityId, root.generation)
    const error = implementation.validateRequest(safeRequest)
    if (error) return error
    if (safeRequest.entityId !== Model.radioId())
      return result(false, "stale-id", "Wi-Fi radio identity is stale.",
        safeRequest.entityId, root.generation)
    if (!root.radioSnapshot.available)
      return result(false, "unavailable", "Wi-Fi radio is unavailable.",
        safeRequest.entityId, root.generation)
    return implementation.dispatchRadio(enabled, safeRequest.entityId)
  }

  function connectNetwork(request) {
    const parsed = implementation.requestData(request)
    if (parsed.error) return parsed.error
    const safeRequest = parsed.request
    const context = implementation.networkActionContext(safeRequest)
    if (context.error) return context.error
    const row = context.row
    if (row.connected)
      return result(false, "invalid", "Network is already connected.",
        safeRequest.entityId, root.generation)
    if (!row.canConnect)
      return result(false, "unsupported",
        "This network cannot be connected without a dedicated credential path.",
        safeRequest.entityId, root.generation)
    return implementation.dispatchNetwork(
      "connect", context.target, "", safeRequest.entityId)
  }

  function connectNetworkWithPsk(request, passphrase) {
    const parsed = implementation.requestData(request)
    if (parsed.error) return parsed.error
    const safeRequest = parsed.request
    if (typeof passphrase !== "string" || passphrase.length > 64
        || /[\u0000\r\n]/.test(passphrase))
      return result(false, "invalid", "Passphrase is malformed.",
        safeRequest.entityId, root.generation)
    const context = implementation.networkActionContext(safeRequest)
    if (context.error) return context.error
    if (!Model.validPsk(passphrase, context.row.security))
      return result(false, "invalid", "Passphrase is invalid for this network.",
        safeRequest.entityId, root.generation)
    if (!context.row.canConnectWithPsk)
      return result(false, "unsupported",
        "This network does not support the native PSK action.",
        safeRequest.entityId, root.generation)
    return implementation.dispatchNetwork(
      "connectWithPsk", context.target, passphrase, safeRequest.entityId)
  }

  function enterpriseConnectionDescriptor(request) {
    const parsed = implementation.requestData(request)
    const safeRequest = parsed.request
    function response(ok, code, message, descriptor) {
      return {
        ok: ok === true,
        code: String(code || "invalid"),
        message: String(message || ""),
        entityId: safeRequest.entityId,
        generation: root.generation,
        descriptor: descriptor || null
      }
    }
    if (parsed.error)
      return response(false, parsed.error.code, parsed.error.message, null)
    const context = implementation.networkActionContext(safeRequest)
    if (context.error)
      return response(false, context.error.code, context.error.message, null)
    const row = context.row
    if (row.security !== "wpa2-eap" || row.connected === true
        || row.state !== "disconnected" || row.stateChanging === true
        || row.known === true || row.profileCount !== 0
        || row.validProfileCount !== 0)
      return response(false, "unsupported",
        "Enterprise credentials require one new visible network.", null)
    let device = null
    let deviceCount = 0
    const devices = root.deviceSnapshots
    for (let index = 0; index < devices.length; index++) {
      if (devices[index].id !== row.deviceId) continue
      device = devices[index]
      deviceCount++
    }
    const hex = Model.ssidHex(row.ssid)
    if (deviceCount !== 1 || !device || device.type !== "wifi"
        || device.ambiguous === true || device.managed !== true
        || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$/.test(device.name)
        || !/^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(device.address)
        || device.address === "00:00:00:00:00:00"
        || device.address === "FF:FF:FF:FF:FF:FF" || hex === "")
      return response(false, "unavailable",
        "Enterprise network device identity is unavailable.", null)
    return response(true, "accepted", "", {
      deviceId: row.deviceId,
      entityId: row.id,
      generation: root.generation,
      hardwareAddress: device.address,
      interfaceName: device.name,
      security: row.security,
      ssidHex: hex
    })
  }

  function disconnectNetwork(request) {
    const parsed = implementation.requestData(request)
    if (parsed.error) return parsed.error
    const safeRequest = parsed.request
    const context = implementation.networkActionContext(safeRequest)
    if (context.error) return context.error
    if (!context.row.canDisconnect)
      return result(false, "unsupported", "Network is not disconnectable.",
        safeRequest.entityId, root.generation)
    return implementation.dispatchNetwork(
      "disconnect", context.target, "", safeRequest.entityId)
  }

  function forgetNetwork(request) {
    const parsed = implementation.requestData(request)
    if (parsed.error) return parsed.error
    const safeRequest = parsed.request
    const context = implementation.networkActionContext(safeRequest)
    if (context.error) return context.error
    // Quickshell 0.3.0 aggregates every saved setting for an SSID. Calling
    // WifiNetwork.forget() can therefore delete unrelated personal and
    // enterprise profiles. Only the exact profile path below may forget.
    return result(false, "unsupported",
      "Exact saved-profile identity is required before forgetting a network.",
      safeRequest.entityId, root.generation)
  }

  function connectProfile(request) {
    const parsed = implementation.requestData(request)
    if (parsed.error) return parsed.error
    const safeRequest = parsed.request
    const context = implementation.profileActionContext(safeRequest)
    if (context.error) return context.error
    if (!context.row.canConnect || context.network.connected === true
        || context.network.stateChanging === true)
      return result(false, "unsupported",
        "This saved profile is not connectable on its current device.",
        safeRequest.entityId, root.generation)
    return implementation.dispatchProfile("connect", context.network,
      context.profile, safeRequest.entityId)
  }

  function forgetProfile(request) {
    const parsed = implementation.requestData(request)
    if (parsed.error) return parsed.error
    const safeRequest = parsed.request
    const context = implementation.profileActionContext(safeRequest)
    if (context.error) return context.error
    if (!context.row.canForget)
      return result(false, "unsupported",
        "This saved profile cannot be forgotten.", safeRequest.entityId,
        root.generation)
    return implementation.dispatchProfile("forget", context.network,
      context.profile, safeRequest.entityId)
  }

  Connections {
    target: root.savedProfileCatalog
    ignoreUnknownSignals: true
    function onGenerationChanged() { root.generation++ }
  }

  Connections {
    target: root.networkTelemetry
    ignoreUnknownSignals: true
    function onIdentityGenerationChanged() { root.generation++ }
  }

  Loader {
    id: nativeGateway
    // Do not construct Quickshell's process-static Networking singleton until
    // the D-Bus owner monitor has published its first trusted present state.
    active: root.active && root.backendOverride === null
      && root.nativeServiceAvailable
    source: Qt.resolvedUrl("NetworkNativeGateway.qml")
  }

  QtObject {
    id: implementation

    function nativeBackend() {
      return root.backendOverride === null ? nativeGateway.item : null
    }

    function backendValue(name, fallback) {
      if (root.backendOverride !== null) {
        return name in root.backendOverride
          ? root.backendOverride[name] : fallback
      }
      const gateway = nativeBackend()
      return gateway && name in gateway ? gateway[name] : fallback
    }

    function backendAvailable() {
      if (!root.active) return false
      if (root.backendOverride !== null)
        return root.backendOverride.backendAvailable === true
      const gateway = nativeBackend()
      return root.nativeServiceAvailable && gateway
        ? gateway.backendInitialized === true : false
    }

    function sequenceInfo(value) {
      const result = []
      if (value === null || value === undefined)
        return { values: result, overflow: false }
      try {
        const length = value.length
        if (typeof length !== "number" || !isFinite(length) || length < 0
            || Math.floor(length) !== length
            || length > Model.MaxSnapshotRows)
          return { values: [], overflow: true }
        for (let index = 0; index < length; index++) result.push(value[index])
      } catch (error) {
        return { values: [], overflow: true }
      }
      return { values: result, overflow: false }
    }

    function savedProfileProjection() {
      if (!root.active || root.savedProfileCatalog === null
          || root.savedProfileCatalog.available !== true)
        return { rows: [], overflow: false }
      try {
        const info = sequenceInfo(root.savedProfileCatalog.profileSnapshots)
        if (info.overflow) return { rows: [], overflow: true }
        const rows = []
        let previousUuid = ""
        for (let index = 0; index < info.values.length; index++) {
          const source = info.values[index]
          if (!source || typeof source !== "object")
            return { rows: [], overflow: true }
          const keys = Object.keys(source)
          const expected = [
            "schemaVersion", "id", "uuid", "name", "profileType", "ssid",
            "ssidHex", "security", "enterprise", "hidden", "autoconnect",
            "timestamp"
          ]
          if (keys.length !== expected.length)
            return { rows: [], overflow: true }
          for (let field = 0; field < expected.length; field++) {
            if (!Object.prototype.hasOwnProperty.call(source, expected[field]))
              return { rows: [], overflow: true }
          }
          const profile = {
            schemaVersion: source.schemaVersion,
            uuid: source.uuid,
            name: source.name,
            profileType: source.profileType,
            ssid: source.ssid,
            ssidHex: source.ssidHex,
            security: source.security,
            enterprise: source.enterprise,
            hidden: source.hidden,
            autoconnect: source.autoconnect,
            timestamp: source.timestamp
          }
          if (!CatalogModel.validProfile(profile)
              || source.id !== Model.catalogProfileId(source.uuid)
              || previousUuid !== "" && previousUuid >= source.uuid)
            return { rows: [], overflow: true }
          previousUuid = source.uuid
          const row = { id: source.id }
          for (const key in profile) row[key] = profile[key]
          rows.push(row)
        }
        return { rows: rows, overflow: false }
      } catch (error) {
        return { rows: [], overflow: true }
      }
    }

    function telemetryProjection() {
      if (!root.active || root.networkTelemetry === null
          || root.networkTelemetry.available !== true)
        return { available: false, degraded: false, connected: false,
          row: null }
      if (!root.backendAvailable || root.snapshotDegraded)
        return { available: false, degraded: root.snapshotDegraded,
          connected: false, row: null }
      try {
        const source = root.networkTelemetry.telemetrySnapshot
        const expected = [
          "schemaVersion", "connected", "connectionUuid", "connectionName",
          "kind", "interfaceName", "hardwareAddress", "metered",
          "addresses", "gateways", "dnsServers", "dnsDomains", "rxBytes",
          "txBytes", "sampleMonotonicMs", "wifi", "wired", "id",
          "deviceId", "downloadBytesPerSecond", "uploadBytesPerSecond",
          "generation"
        ]
        if (!source || typeof source !== "object" || Array.isArray(source)
            || Object.keys(source).length !== expected.length)
          return { available: false, degraded: true, connected: false,
            row: null }
        for (let index = 0; index < expected.length; index++) {
          if (!Object.prototype.hasOwnProperty.call(source, expected[index]))
            return { available: false, degraded: true, connected: false,
              row: null }
        }
        const raw = {
          schemaVersion: source.schemaVersion,
          connected: source.connected,
          connectionUuid: source.connectionUuid,
          connectionName: source.connectionName,
          kind: source.kind,
          interfaceName: source.interfaceName,
          hardwareAddress: source.hardwareAddress,
          metered: source.metered,
          addresses: source.addresses,
          gateways: source.gateways,
          dnsServers: source.dnsServers,
          dnsDomains: source.dnsDomains,
          rxBytes: source.rxBytes,
          txBytes: source.txBytes,
          sampleMonotonicMs: source.sampleMonotonicMs,
          wifi: source.wifi,
          wired: source.wired
        }
        const validRate = function(value) {
          return typeof value === "number" && isFinite(value)
            && value >= 0 && value <= TelemetryModel.MaxSafeInteger
        }
        if (!TelemetryModel.validSnapshot(raw)
            || !validRate(source.downloadBytesPerSecond)
            || !validRate(source.uploadBytesPerSecond)
            || typeof source.generation !== "number"
            || !isFinite(source.generation) || source.generation < 0
            || Math.floor(source.generation) !== source.generation
            || source.generation !== root.networkTelemetry.generation
            || root.networkTelemetry.connected !== source.connected)
          return { available: false, degraded: true, connected: false,
            row: null }
        if (!source.connected) {
          if (source.id !== "" || source.deviceId !== ""
              || root.networkTelemetry.connectionSnapshot !== null)
            return { available: false, degraded: true, connected: false,
              row: null }
          for (let index = 0; index < root.baseDeviceSnapshots.length; index++) {
            if (root.baseDeviceSnapshots[index].connected === true)
              return { available: false, degraded: true, connected: false,
                row: null }
          }
          return { available: true, degraded: false, connected: false,
            row: null }
        }
        if (source.id !== Model.connectionId(source.connectionUuid)
            || source.deviceId !== Model.deviceId(source.kind,
              source.hardwareAddress, source.interfaceName)
            || root.networkTelemetry.connectionSnapshot === null)
          return { available: false, degraded: true, connected: false,
            row: null }
        let matches = 0
        for (let index = 0; index < root.baseDeviceSnapshots.length; index++) {
          const device = root.baseDeviceSnapshots[index]
          if (device.id !== source.deviceId) continue
          if (device.ambiguous || !device.connected
              || device.type !== source.kind
              || device.name !== source.interfaceName
              || device.address !== source.hardwareAddress)
            return { available: false, degraded: true, connected: false,
              row: null }
          matches++
        }
        if (matches !== 1)
          return { available: false, degraded: true, connected: false,
            row: null }
        const row = TelemetryModel.cloneSnapshot(raw)
        row.id = source.id
        row.deviceId = source.deviceId
        row.downloadBytesPerSecond = source.downloadBytesPerSecond
        row.uploadBytesPerSecond = source.uploadBytesPerSecond
        return { available: true, degraded: false, connected: true, row: row }
      } catch (error) {
        return { available: false, degraded: true, connected: false,
          row: null }
      }
    }

    function telemetryGateway(row) {
      if (!row || !Array.isArray(row.gateways)) return ""
      for (let index = 0; index < row.gateways.length; index++) {
        if (row.gateways[index].family === "ipv4")
          return row.gateways[index].address
      }
      return row.gateways.length > 0 ? row.gateways[0].address : ""
    }

    function reachabilityProjection() {
      if (!root.active || root.networkReachability === null)
        return { available: false, degraded: false, row: null }
      if (root.networkReachability.available !== true)
        return { available: false,
          degraded: root.networkReachability.phase === "error", row: null }
      if (!root.networkTelemetryConnected || root.telemetryProjection.row === null)
        return { available: false, degraded: true, row: null }
      try {
        const source = root.networkReachability.reachabilitySnapshot
        if (!ReachabilityModel.validPublicSnapshot(source)
            || source.generation !== root.networkReachability.generation)
          return { available: false, degraded: true, row: null }
        const telemetry = root.telemetryProjection.row
        if (source.connectionId !== telemetry.id
            || source.deviceId !== telemetry.deviceId
            || source.interfaceName !== telemetry.interfaceName
            || source.gateway !== telemetryGateway(telemetry))
          return { available: false, degraded: true, row: null }
        const row = ReachabilityModel.clonePublicSnapshot(source)
        return row ? { available: true, degraded: false, row: row }
          : { available: false, degraded: true, row: null }
      } catch (error) {
        return { available: false, degraded: true, row: null }
      }
    }

    function reachabilityPublic(row) {
      if (!row) return null
      const snapshot = ReachabilityModel.clonePublicSnapshot(row)
      if (!snapshot) return null
      snapshot.schemaVersion = root.schemaVersion
      snapshot.generation = root.generation
      return snapshot
    }

    function telemetryDetails(row) {
      if (!row) return null
      return {
        schemaVersion: root.schemaVersion,
        id: row.id,
        uuid: row.connectionUuid,
        name: row.connectionName,
        deviceId: row.deviceId,
        kind: row.kind,
        interfaceName: row.interfaceName,
        hardwareAddress: row.hardwareAddress,
        metered: row.metered,
        addresses: TelemetryModel.cloneRows(row.addresses),
        gateways: TelemetryModel.cloneRows(row.gateways),
        wifi: {
          ssid: row.wifi.ssid,
          ssidHex: row.wifi.ssidHex,
          signal: row.wifi.signal,
          frequencyMhz: row.wifi.frequencyMhz,
          bitrateKbps: row.wifi.bitrateKbps
        },
        wired: {
          speedMbps: row.wired.speedMbps,
          carrier: row.wired.carrier
        },
        generation: root.generation
      }
    }

    function deviceSequence() {
      if (!backendAvailable()) return { values: [], overflow: false }
      try {
        if (root.backendOverride !== null)
          return sequenceInfo(root.backendOverride.devices)
        const gateway = nativeBackend()
        return sequenceInfo(gateway ? gateway.deviceObjects : [])
      } catch (error) {
        return { values: [], overflow: true }
      }
    }

    function networkSequence(device) {
      if (!device) return { values: [], overflow: false }
      try {
        if (root.backendOverride !== null) return sequenceInfo(device.networks)
        const gateway = nativeBackend()
        return sequenceInfo(gateway ? gateway.networkObjects(device) : [])
      } catch (error) {
        return { values: [], overflow: true }
      }
    }

    function profileSequence(network) {
      if (!network) return { values: [], overflow: false }
      try {
        if (root.backendOverride !== null)
          return sequenceInfo(network.nmSettings)
        const gateway = nativeBackend()
        return sequenceInfo(gateway ? gateway.profileObjects(network) : [])
      } catch (error) {
        return { values: [], overflow: true }
      }
    }

    function profileUuid(profile) {
      if (!profile) return ""
      try {
        if (root.backendOverride !== null)
          return Model.canonicalUuid(profile.uuid)
        const gateway = nativeBackend()
        return gateway
          ? Model.canonicalUuid(gateway.profileUuid(profile)) : ""
      } catch (error) {
        return ""
      }
    }

    function profileName(profile) {
      if (!profile) return ""
      try {
        const value = root.backendOverride !== null
          ? profile.profileName : nativeBackend().profileName(profile)
        return Model.boundedDisplayName(value)
      } catch (error) {
        return ""
      }
    }

    function deviceType(device) {
      if (!device) return "none"
      if (root.backendOverride !== null)
        return Model.deviceTypeToken(device.typeToken)
      const gateway = nativeBackend()
      return gateway ? gateway.deviceTypeToken(device.type) : "none"
    }

    function deviceState(device) {
      if (!device) return "unknown"
      if (root.backendOverride !== null)
        return Model.connectionStateToken(device.stateToken)
      const gateway = nativeBackend()
      return gateway
        ? gateway.connectionStateToken(device.state) : "unknown"
    }

    function networkState(network) {
      if (!network) return "unknown"
      if (root.backendOverride !== null)
        return Model.connectionStateToken(network.stateToken)
      const gateway = nativeBackend()
      return gateway
        ? gateway.connectionStateToken(network.state) : "unknown"
    }

    function networkSecurity(network) {
      if (!network) return "unknown"
      if (root.backendOverride !== null)
        return Model.securityToken(network.securityToken)
      const gateway = nativeBackend()
      return gateway ? gateway.securityToken(network.security) : "unknown"
    }

    function deviceName(device) {
      return device && typeof device.name === "string" ? device.name : ""
    }

    function deviceAddress(device) {
      return device && typeof device.address === "string" ? device.address : ""
    }

    function networkSsid(network) {
      if (!network) return ""
      if (root.backendOverride !== null)
        return typeof network.ssid === "string" ? network.ssid : ""
      return typeof network.name === "string" ? network.name : ""
    }

    function deviceManaged(device) {
      if (!device) return false
      return root.backendOverride !== null
        ? device.managed !== false : device.nmManaged !== false
    }

    function signalPercent(network) {
      if (!network) return 0
      const raw = root.backendOverride !== null
        ? Number(network.signal || 0)
        : Number(network.signalStrength || 0) * 100
      return Math.max(0, Math.min(100, isFinite(raw) ? Math.round(raw) : 0))
    }

    function supportsNetworkAction(action, target) {
      if (!target) return false
      if (root.backendOverride !== null) {
        const delegateName = action === "connect" ? "connectNetwork"
          : action === "connectWithPsk" ? "connectNetworkWithPsk"
          : action === "disconnect" ? "disconnectNetwork" : ""
        return delegateName !== ""
          && typeof root.backendOverride[delegateName] === "function"
      }
      const gateway = nativeBackend()
      return gateway ? gateway.supportsNetworkAction(action, target) : false
    }

    function supportsProfileAction(action, network, profile) {
      if (!network || !profile) return false
      if (root.backendOverride !== null) {
        const delegateName = action === "connect" ? "connectProfile"
          : action === "forget" ? "forgetProfile" : ""
        return delegateName !== ""
          && typeof root.backendOverride[delegateName] === "function"
      }
      const gateway = nativeBackend()
      return gateway
        ? gateway.supportsProfileAction(action, network, profile) : false
    }

    function radioSnapshot() {
      return {
        schemaVersion: root.schemaVersion,
        id: Model.radioId(),
        available: backendAvailable()
          && backendValue("wifiHardwareEnabled", false) === true,
        hardwareEnabled: backendAvailable()
          && backendValue("wifiHardwareEnabled", false) === true,
        enabled: backendAvailable()
          && backendValue("wifiEnabled", false) === true
      }
    }

    function deviceProjection() {
      const rows = []
      const deviceInfo = deviceSequence()
      if (deviceInfo.overflow) return { rows: [], overflow: true }
      const devices = deviceInfo.values
      const idCounts = ({})
      if (devices.length > Model.MaxBackendObjects)
        return { rows: [], overflow: true }
      for (let index = 0; index < devices.length; index++) {
        const device = devices[index]
        if (!device) continue
        const type = deviceType(device)
        const rawName = deviceName(device)
        const name = Model.usableInterfaceName(rawName) ? rawName : ""
        const address = Model.normalizeHardwareAddress(deviceAddress(device))
        const id = Model.deviceId(type, deviceAddress(device), rawName)
        if (!id) continue
        idCounts[id] = Number(idCounts[id] || 0) + 1
        rows.push({
          schemaVersion: root.schemaVersion,
          id: id,
          type: type,
          name: name,
          address: address,
          connected: device.connected === true,
          state: deviceState(device),
          managed: deviceManaged(device),
          autoconnect: device.autoconnect !== false,
          ambiguous: false
        })
        if (rows.length > Model.MaxSnapshotRows)
          return { rows: [], overflow: true }
      }
      for (let rowIndex = 0; rowIndex < rows.length; rowIndex++)
        rows[rowIndex].ambiguous = idCounts[rows[rowIndex].id] !== 1
      return { rows: rows, overflow: false }
    }

    function profileDescriptor(deviceEntityId, network, profile) {
      const uuid = profileUuid(profile)
      const id = Model.profileId(deviceEntityId, uuid)
      const ssidValue = networkSsid(network)
      const ssid = Model.validSsid(ssidValue) ? ssidValue : ""
      const networkEntityId = Model.networkId(deviceEntityId, ssid,
        networkSecurity(network))
      return {
        valid: id !== "" && networkEntityId !== "" && ssid !== "",
        id: id,
        uuid: uuid,
        deviceId: deviceEntityId,
        networkId: networkEntityId,
        ssid: ssid,
        name: profileName(profile),
        security: "unknown",
        lastSuccessful: 0
      }
    }

    function networkProfileStats(deviceEntityId, network) {
      const profileInfo = profileSequence(network)
      if (profileInfo.overflow)
        return { count: 0, validCount: 0, overflow: true }
      const profiles = profileInfo.values
      let validCount = 0
      for (let index = 0; index < profiles.length; index++) {
        const descriptor = profileDescriptor(deviceEntityId, network,
          profiles[index])
        if (descriptor.valid) validCount++
      }
      return { count: profiles.length, validCount: validCount,
        overflow: false }
    }

    function networkProjection() {
      const rows = []
      const deviceInfo = deviceSequence()
      if (deviceInfo.overflow) return { rows: [], overflow: true }
      const devices = deviceInfo.values
      const idCounts = ({})
      let visited = devices.length
      if (visited > Model.MaxBackendObjects)
        return { rows: [], overflow: true }
      for (let deviceIndex = 0; deviceIndex < devices.length; deviceIndex++) {
        const device = devices[deviceIndex]
        if (!device || deviceType(device) !== "wifi") continue
        const deviceEntityId = Model.deviceId(
          deviceType(device), deviceAddress(device), deviceName(device))
        if (!deviceEntityId) continue
        const networkInfo = networkSequence(device)
        if (networkInfo.overflow) return { rows: [], overflow: true }
        const networks = networkInfo.values
        visited += networks.length
        if (visited > Model.MaxBackendObjects)
          return { rows: [], overflow: true }
        for (let networkIndex = 0; networkIndex < networks.length; networkIndex++) {
          const network = networks[networkIndex]
          if (!network) continue
          const ssid = networkSsid(network)
          const security = networkSecurity(network)
          const id = Model.networkId(deviceEntityId, ssid, security)
          if (!id) continue
          const connected = network.connected === true
          const known = network.known === true
          const stats = networkProfileStats(deviceEntityId, network)
          if (stats.overflow) return { rows: [], overflow: true }
          visited += stats.count
          if (visited > Model.MaxBackendObjects)
            return { rows: [], overflow: true }
          const profileAmbiguous = stats.count > 1
            || stats.validCount !== stats.count
          const canConnect = !connected && !profileAmbiguous
            && ((known && stats.count === 1)
              || (!known && Model.knownConnectKind(security)))
            && supportsNetworkAction("connect", network)
          const canConnectWithPsk = !connected && !profileAmbiguous
            && (!known || stats.count === 1) && Model.pskKind(security)
            && supportsNetworkAction("connectWithPsk", network)
          const canDisconnect = connected && !profileAmbiguous
            && supportsNetworkAction("disconnect", network)
          idCounts[id] = Number(idCounts[id] || 0) + 1
          rows.push({
            schemaVersion: root.schemaVersion,
            id: id,
            deviceId: deviceEntityId,
            ssid: ssid,
            security: security,
            connected: connected,
            known: known,
            state: networkState(network),
            stateChanging: network.stateChanging === true,
            signal: signalPercent(network),
            profileCount: stats.count,
            validProfileCount: stats.validCount,
            canConnect: canConnect,
            canConnectWithPsk: canConnectWithPsk,
            canDisconnect: canDisconnect,
            canForget: false,
            ambiguous: false
          })
          if (rows.length > Model.MaxSnapshotRows)
            return { rows: [], overflow: true }
        }
      }
      for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        const row = rows[rowIndex]
        row.ambiguous = idCounts[row.id] !== 1 || row.profileCount > 1
          || row.validProfileCount !== row.profileCount
        if (row.ambiguous) {
          row.canConnect = false
          row.canConnectWithPsk = false
          row.canDisconnect = false
          row.canForget = false
        }
      }
      return { rows: rows, overflow: false }
    }

    function profileProjection() {
      const rows = []
      const deviceInfo = deviceSequence()
      if (deviceInfo.overflow) return { rows: [], overflow: true }
      const devices = deviceInfo.values
      const idCounts = ({})
      let visited = devices.length
      if (visited > Model.MaxBackendObjects)
        return { rows: [], overflow: true }
      for (let deviceIndex = 0; deviceIndex < devices.length; deviceIndex++) {
        const device = devices[deviceIndex]
        if (!device || deviceType(device) !== "wifi") continue
        const deviceEntityId = Model.deviceId(
          deviceType(device), deviceAddress(device), deviceName(device))
        if (!deviceEntityId) continue
        const networkInfo = networkSequence(device)
        if (networkInfo.overflow) return { rows: [], overflow: true }
        const networks = networkInfo.values
        visited += networks.length
        if (visited > Model.MaxBackendObjects)
          return { rows: [], overflow: true }
        for (let networkIndex = 0; networkIndex < networks.length; networkIndex++) {
          const network = networks[networkIndex]
          if (!network) continue
          const profileInfo = profileSequence(network)
          if (profileInfo.overflow) return { rows: [], overflow: true }
          const profiles = profileInfo.values
          visited += profiles.length
          if (visited > Model.MaxBackendObjects)
            return { rows: [], overflow: true }
          for (let profileIndex = 0; profileIndex < profiles.length;
              profileIndex++) {
            const profile = profiles[profileIndex]
            const descriptor = profileDescriptor(deviceEntityId, network,
              profile)
            if (!descriptor.valid) continue
            idCounts[descriptor.id] = Number(idCounts[descriptor.id] || 0) + 1
            rows.push({
              schemaVersion: root.schemaVersion,
              id: descriptor.id,
              uuid: descriptor.uuid,
              deviceId: descriptor.deviceId,
              networkId: descriptor.networkId,
              ssid: descriptor.ssid,
              name: descriptor.name,
              security: descriptor.security,
              lastSuccessful: descriptor.lastSuccessful,
              canConnect: network.connected !== true
                && network.stateChanging !== true
                && supportsProfileAction("connect", network, profile),
              canForget: supportsProfileAction("forget", network, profile),
              ambiguous: false
            })
            if (rows.length > Model.MaxSnapshotRows)
              return { rows: [], overflow: true }
          }
        }
      }
      for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        const row = rows[rowIndex]
        row.ambiguous = idCounts[row.id] !== 1
        if (row.ambiguous) {
          row.canConnect = false
          row.canForget = false
        }
      }
      return { rows: rows, overflow: false }
    }

    function validGeneration(value) {
      return typeof value === "number" && isFinite(value)
        && value >= 0 && Math.floor(value) === value
    }

    function requestData(request) {
      let entityId = ""
      let generation = -1
      try {
        if (!request || typeof request !== "object" || Array.isArray(request))
          throw new Error("invalid request type")
        const keys = Reflect.ownKeys(request)
        if (keys.length !== 2 || keys.indexOf("entityId") < 0
            || keys.indexOf("generation") < 0)
          throw new Error("invalid request schema")
        const entityDescriptor = Object.getOwnPropertyDescriptor(
          request, "entityId")
        const generationDescriptor = Object.getOwnPropertyDescriptor(
          request, "generation")
        entityId = "value" in entityDescriptor
          ? entityDescriptor.value : entityDescriptor.get.call(request)
        generation = "value" in generationDescriptor
          ? generationDescriptor.value : generationDescriptor.get.call(request)
      } catch (error) {
        return { request: { entityId: "", generation: -1 },
          error: root.result(false, "invalid",
            "Action request is malformed.", "", root.generation) }
      }
      const size = typeof entityId === "string"
        && entityId.length <= 4096 ? Model.utf8Length(entityId) : -1
      if (entityId === "" || size < 1 || size > 4096
          || !validGeneration(generation))
        return { request: { entityId: "", generation: -1 },
          error: root.result(false, "invalid",
            "Action request is malformed.", "", root.generation) }
      return { request: { entityId: entityId, generation: generation },
        error: null }
    }

    function validateRequest(request) {
      const entityId = request.entityId
      if (entityId === "" || !validGeneration(request.generation))
        return root.result(false, "invalid", "Action request is malformed.",
          entityId, root.generation)
      if (!root.backendAvailable)
        return root.result(false, "unavailable",
          "NetworkManager backend is unavailable.", entityId, root.generation)
      if (root.snapshotDegraded)
        return root.result(false, "unavailable",
          "Network topology exceeds the safe snapshot budget.", entityId,
          root.generation)
      if (request.generation !== root.generation)
        return root.result(false, "stale-generation",
          "Network state changed before the action was dispatched.",
          entityId, root.generation)
      return null
    }

    function networkResolution(entityId) {
      let target = null
      let row = null
      let count = 0
      const deviceInfo = deviceSequence()
      if (deviceInfo.overflow)
        return { target: null, row: null, count: 0, overflow: true }
      const devices = deviceInfo.values
      let visited = devices.length
      if (visited > Model.MaxBackendObjects)
        return { target: null, row: null, count: 0, overflow: true }
      for (let deviceIndex = 0; deviceIndex < devices.length; deviceIndex++) {
        const device = devices[deviceIndex]
        if (!device || deviceType(device) !== "wifi") continue
        const deviceEntityId = Model.deviceId(
          deviceType(device), deviceAddress(device), deviceName(device))
        if (!deviceEntityId) continue
        const networkInfo = networkSequence(device)
        if (networkInfo.overflow)
          return { target: null, row: null, count: 0, overflow: true }
        const networks = networkInfo.values
        visited += networks.length
        if (visited > Model.MaxBackendObjects)
          return { target: null, row: null, count: 0, overflow: true }
        for (let networkIndex = 0; networkIndex < networks.length; networkIndex++) {
          const candidate = networks[networkIndex]
          if (!candidate) continue
          const candidateId = Model.networkId(deviceEntityId,
            networkSsid(candidate), networkSecurity(candidate))
          if (candidateId !== entityId) continue
          target = candidate
          count++
        }
      }
      if (count === 1) {
        const snapshots = root.baseNetworkSnapshots
        for (let index = 0; index < snapshots.length; index++) {
          if (snapshots[index].id === entityId) {
            row = snapshots[index]
            break
          }
        }
      }
      return { target: target, row: row, count: count, overflow: false }
    }

    function networkActionContext(request) {
      const requestError = validateRequest(request)
      if (requestError) return { error: requestError, target: null, row: null }
      const resolved = networkResolution(request.entityId)
      if (resolved.overflow)
        return { error: root.result(false, "unavailable",
          "Network topology exceeds the safe action budget.",
          request.entityId, root.generation), target: null, row: null }
      if (resolved.count === 0)
        return { error: root.result(false, "stale-id",
          "Network identity is no longer present.", request.entityId,
          root.generation), target: null, row: null }
      if (resolved.count > 1 || resolved.row && resolved.row.ambiguous)
        return { error: root.result(false, "ambiguous",
          "Network identity or saved-profile selection is ambiguous.",
          request.entityId, root.generation), target: null, row: null }
      if (!resolved.row)
        return { error: root.result(false, "stale-id",
          "Network snapshot changed before dispatch.", request.entityId,
          root.generation), target: null, row: null }
      return { error: null, target: resolved.target, row: resolved.row }
    }

    function profileResolution(entityId) {
      let network = null
      let profile = null
      let row = null
      let count = 0
      const deviceInfo = deviceSequence()
      if (deviceInfo.overflow)
        return { network: null, profile: null, row: null, count: 0,
          overflow: true }
      const devices = deviceInfo.values
      let visited = devices.length
      if (visited > Model.MaxBackendObjects)
        return { network: null, profile: null, row: null, count: 0,
          overflow: true }
      for (let deviceIndex = 0; deviceIndex < devices.length; deviceIndex++) {
        const device = devices[deviceIndex]
        if (!device || deviceType(device) !== "wifi") continue
        const deviceEntityId = Model.deviceId(deviceType(device),
          deviceAddress(device), deviceName(device))
        if (!deviceEntityId) continue
        const networkInfo = networkSequence(device)
        if (networkInfo.overflow)
          return { network: null, profile: null, row: null, count: 0,
            overflow: true }
        const networks = networkInfo.values
        visited += networks.length
        if (visited > Model.MaxBackendObjects)
          return { network: null, profile: null, row: null, count: 0,
            overflow: true }
        for (let networkIndex = 0; networkIndex < networks.length;
            networkIndex++) {
          const candidateNetwork = networks[networkIndex]
          if (!candidateNetwork) continue
          const profileInfo = profileSequence(candidateNetwork)
          if (profileInfo.overflow)
            return { network: null, profile: null, row: null, count: 0,
              overflow: true }
          const profiles = profileInfo.values
          visited += profiles.length
          if (visited > Model.MaxBackendObjects)
            return { network: null, profile: null, row: null, count: 0,
              overflow: true }
          for (let profileIndex = 0; profileIndex < profiles.length;
              profileIndex++) {
            const candidateProfile = profiles[profileIndex]
            const candidateId = Model.profileId(deviceEntityId,
              profileUuid(candidateProfile))
            if (candidateId !== entityId) continue
            network = candidateNetwork
            profile = candidateProfile
            count++
          }
        }
      }
      if (count === 1) {
        const snapshots = root.baseProfileSnapshots
        for (let index = 0; index < snapshots.length; index++) {
          if (snapshots[index].id === entityId) {
            row = snapshots[index]
            break
          }
        }
      }
      return { network: network, profile: profile, row: row, count: count,
        overflow: false }
    }

    function profileActionContext(request) {
      const requestError = validateRequest(request)
      if (requestError)
        return { error: requestError, network: null, profile: null, row: null }
      const resolved = profileResolution(request.entityId)
      if (resolved.overflow)
        return { error: root.result(false, "unavailable",
          "Network topology exceeds the safe action budget.",
          request.entityId, root.generation), network: null, profile: null,
          row: null }
      if (resolved.count === 0)
        return { error: root.result(false, "stale-id",
          "Saved profile identity is no longer present.", request.entityId,
          root.generation), network: null, profile: null, row: null }
      if (resolved.count > 1 || resolved.row && resolved.row.ambiguous)
        return { error: root.result(false, "ambiguous",
          "Saved profile identity is ambiguous on this device.",
          request.entityId, root.generation), network: null, profile: null,
          row: null }
      if (!resolved.row)
        return { error: root.result(false, "stale-id",
          "Saved profile snapshot changed before dispatch.",
          request.entityId, root.generation), network: null, profile: null,
          row: null }
      return { error: null, network: resolved.network,
        profile: resolved.profile, row: resolved.row }
    }

    function allowedResultCode(code) {
      return typeof code === "string" && [
        "accepted", "unavailable", "stale-generation", "stale-id",
        "ambiguous", "unsupported", "invalid"
      ].indexOf(code) >= 0
    }

    function delegateResult(value, entityId) {
      if (value === true)
        return root.result(true, "accepted", "", entityId, root.generation)
      if (value && typeof value === "object") {
        try {
          const ok = value.ok
          const code = value.code
          const message = value.message
          const generation = value.generation
          const messageValid = message === undefined
            || typeof message === "string"
          const statusConsistent = typeof ok === "boolean"
            && ok === (code === "accepted")
          const generationValid = generation === undefined
            || validGeneration(generation)
          if (allowedResultCode(code) && messageValid
              && statusConsistent && generationValid)
            return root.result(ok, code,
              message === undefined ? "" : message,
              entityId, generation === undefined
                ? root.generation : generation)
        } catch (error) {}
        return root.result(false, "invalid",
          "Backend returned a malformed action result.", entityId,
          root.generation)
      }
      return root.result(false, "unavailable",
        "Backend declined the network action.", entityId, root.generation)
    }

    function dispatchRadio(enabled, entityId) {
      try {
        if (root.backendOverride !== null) {
          if (typeof root.backendOverride.setWifiEnabled !== "function")
            return root.result(false, "unsupported",
              "Fake backend does not implement the Wi-Fi radio action.",
              entityId, root.generation)
          return delegateResult(root.backendOverride.setWifiEnabled(enabled),
            entityId)
        }
        const gateway = nativeBackend()
        if (!gateway || typeof gateway.setWifiEnabled !== "function")
          return root.result(false, "unsupported",
            "Native Wi-Fi radio action is unavailable.", entityId,
            root.generation)
        return delegateResult(gateway.setWifiEnabled(enabled), entityId)
      } catch (error) {
        return root.result(false, "unavailable",
          "Network backend rejected the Wi-Fi radio dispatch.", entityId,
          root.generation)
      }
    }

    function dispatchNetwork(action, target, secret, entityId) {
      try {
        let value = false
        if (root.backendOverride !== null) {
          const backend = root.backendOverride
          if (action === "connect"
              && typeof backend.connectNetwork === "function")
            value = backend.connectNetwork(target)
          else if (action === "connectWithPsk"
              && typeof backend.connectNetworkWithPsk === "function")
            value = backend.connectNetworkWithPsk(target, secret)
          else if (action === "disconnect"
              && typeof backend.disconnectNetwork === "function")
            value = backend.disconnectNetwork(target)
          else
            return root.result(false, "unsupported",
              "Fake backend does not implement this network action.",
              entityId, root.generation)
          return delegateResult(value, entityId)
        }

        const gateway = nativeBackend()
        if (!gateway)
          return root.result(false, "unavailable",
            "Native Network gateway is unavailable.", entityId,
            root.generation)
        if (action === "connect") value = gateway.connectNetwork(target)
        else if (action === "connectWithPsk")
          value = gateway.connectNetworkWithPsk(target, secret)
        else if (action === "disconnect")
          value = gateway.disconnectNetwork(target)
        else
          return root.result(false, "unsupported",
            "Native network action is unsupported.", entityId,
            root.generation)
        return delegateResult(value, entityId)
      } catch (error) {
        return root.result(false, "unavailable",
          "Network backend rejected the network dispatch.", entityId,
          root.generation)
      }
    }

    function dispatchProfile(action, network, profile, entityId) {
      try {
        let value = false
        if (root.backendOverride !== null) {
          const backend = root.backendOverride
          if (action === "connect"
              && typeof backend.connectProfile === "function")
            value = backend.connectProfile(network, profile)
          else if (action === "forget"
              && typeof backend.forgetProfile === "function")
            value = backend.forgetProfile(profile)
          else
            return root.result(false, "unsupported",
              "Fake backend does not implement this profile action.",
              entityId, root.generation)
          return delegateResult(value, entityId)
        }

        const gateway = nativeBackend()
        if (!gateway)
          return root.result(false, "unavailable",
            "Native Network gateway is unavailable.", entityId,
            root.generation)
        if (action === "connect")
          value = gateway.connectProfile(network, profile)
        else if (action === "forget")
          value = gateway.forgetProfile(profile)
        else
          return root.result(false, "unsupported",
            "Native saved-profile action is unsupported.", entityId,
            root.generation)
        return delegateResult(value, entityId)
      } catch (error) {
        return root.result(false, "unavailable",
          "Network backend rejected the saved-profile dispatch.", entityId,
          root.generation)
      }
    }
  }
}
