pragma ComponentBehavior: Bound

import QtQuick
import "NetworkModel.js" as Model

// Source-only Step 5A capability seam. Production Service.qml does not load
// this adapter yet. Native access is isolated behind an inactive Loader, raw
// backend objects stay private, and the public surface contains primitives and
// typed dispatch results only.
Item {
  id: root

  property bool active: false
  property var backendOverride: null
  // Quickshell 0.3.0 cannot detect NetworkManager loss after singleton
  // initialization. A later activation slice must drive this from a reactive
  // D-Bus service-owner watcher; false keeps native snapshots/actions closed.
  property bool nativeServiceAvailable: false
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
  readonly property var baseDeviceSnapshots: implementation.deviceSnapshots()
  readonly property var baseNetworkSnapshots: implementation.networkSnapshots()
  readonly property string topologyFingerprint: Model.topologyFingerprint(
    root.backendAvailable, root.baseRadioSnapshot,
    root.baseDeviceSnapshots, root.baseNetworkSnapshots)
  readonly property var backendSnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.backendAvailable,
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

  visible: false
  width: 0
  height: 0

  onActiveChanged: generation++
  onBackendOverrideChanged: generation++
  onNativeServiceAvailableChanged: generation++
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
    if (typeof enabled !== "boolean")
      return result(false, "invalid", "Wi-Fi state must be boolean.",
        request && request.entityId, root.generation)
    const error = implementation.validateRequest(request)
    if (error) return error
    if (request.entityId !== Model.radioId())
      return result(false, "stale-id", "Wi-Fi radio identity is stale.",
        request.entityId, root.generation)
    if (!root.radioSnapshot.available)
      return result(false, "unavailable", "Wi-Fi radio is unavailable.",
        request.entityId, root.generation)
    return implementation.dispatchRadio(enabled, request.entityId)
  }

  function connectNetwork(request) {
    const context = implementation.networkActionContext(request)
    if (context.error) return context.error
    const row = context.row
    if (row.connected)
      return result(false, "invalid", "Network is already connected.",
        request.entityId, root.generation)
    if (!row.canConnect)
      return result(false, "unsupported",
        "This network cannot be connected without a dedicated credential path.",
        request.entityId, root.generation)
    return implementation.dispatchNetwork(
      "connect", context.target, "", request.entityId)
  }

  function connectNetworkWithPsk(request, passphrase) {
    if (typeof passphrase !== "string" || passphrase.length > 64
        || /[\u0000\r\n]/.test(passphrase))
      return result(false, "invalid", "Passphrase is malformed.",
        request && request.entityId, root.generation)
    const context = implementation.networkActionContext(request)
    if (context.error) return context.error
    if (!Model.validPsk(passphrase, context.row.security))
      return result(false, "invalid", "Passphrase is invalid for this network.",
        request.entityId, root.generation)
    if (!context.row.canConnectWithPsk)
      return result(false, "unsupported",
        "This network does not support the native PSK action.",
        request.entityId, root.generation)
    return implementation.dispatchNetwork(
      "connectWithPsk", context.target, passphrase, request.entityId)
  }

  function disconnectNetwork(request) {
    const context = implementation.networkActionContext(request)
    if (context.error) return context.error
    if (!context.row.canDisconnect)
      return result(false, "unsupported", "Network is not disconnectable.",
        request.entityId, root.generation)
    return implementation.dispatchNetwork(
      "disconnect", context.target, "", request.entityId)
  }

  function forgetNetwork(request) {
    const context = implementation.networkActionContext(request)
    if (context.error) return context.error
    // Quickshell 0.3.0 aggregates every saved setting for an SSID. Calling
    // WifiNetwork.forget() can therefore delete unrelated personal and
    // enterprise profiles. Step 5 will forget only an exact profile UUID.
    return result(false, "unsupported",
      "Exact saved-profile identity is required before forgetting a network.",
      request.entityId, root.generation)
  }

  Loader {
    id: nativeGateway
    active: root.active && root.backendOverride === null
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

    function objectSequence(value) {
      const result = []
      if (!value || typeof value.length !== "number"
          || !isFinite(value.length) || value.length < 0) return result
      const length = Math.min(4096, Math.floor(value.length))
      for (let index = 0; index < length; index++) result.push(value[index])
      return result
    }

    function deviceObjects() {
      if (!backendAvailable()) return []
      if (root.backendOverride !== null)
        return objectSequence(root.backendOverride.devices)
      const gateway = nativeBackend()
      return gateway ? objectSequence(gateway.deviceObjects) : []
    }

    function networkObjects(device) {
      if (!device) return []
      if (root.backendOverride !== null)
        return objectSequence(device.networks)
      const gateway = nativeBackend()
      return gateway ? objectSequence(gateway.networkObjects(device)) : []
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

    function networkProfileCount(network) {
      if (!network) return 0
      return objectSequence(network.nmSettings).length
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

    function deviceSnapshots() {
      const rows = []
      const devices = deviceObjects()
      const idCounts = ({})
      for (let index = 0; index < devices.length; index++) {
        const device = devices[index]
        if (!device) continue
        const type = deviceType(device)
        const name = deviceName(device)
        const address = Model.normalizeHardwareAddress(deviceAddress(device))
        const id = Model.deviceId(type, deviceAddress(device), name)
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
      }
      for (let rowIndex = 0; rowIndex < rows.length; rowIndex++)
        rows[rowIndex].ambiguous = idCounts[rows[rowIndex].id] !== 1
      return rows
    }

    function networkSnapshots() {
      const rows = []
      const devices = deviceObjects()
      const idCounts = ({})
      for (let deviceIndex = 0; deviceIndex < devices.length; deviceIndex++) {
        const device = devices[deviceIndex]
        if (!device || deviceType(device) !== "wifi") continue
        const deviceEntityId = Model.deviceId(
          deviceType(device), deviceAddress(device), deviceName(device))
        if (!deviceEntityId) continue
        const networks = networkObjects(device)
        for (let networkIndex = 0; networkIndex < networks.length; networkIndex++) {
          const network = networks[networkIndex]
          if (!network) continue
          const ssid = networkSsid(network)
          const security = networkSecurity(network)
          const id = Model.networkId(deviceEntityId, ssid, security)
          if (!id) continue
          const connected = network.connected === true
          const known = network.known === true
          const profileCount = networkProfileCount(network)
          const profileAmbiguous = profileCount > 1
          const canConnect = !connected && !profileAmbiguous
            && ((known && profileCount === 1)
              || (!known && Model.knownConnectKind(security)))
            && supportsNetworkAction("connect", network)
          const canConnectWithPsk = !connected && !profileAmbiguous
            && (!known || profileCount === 1) && Model.pskKind(security)
            && supportsNetworkAction("connectWithPsk", network)
          const canDisconnect = connected
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
            profileCount: profileCount,
            canConnect: canConnect,
            canConnectWithPsk: canConnectWithPsk,
            canDisconnect: canDisconnect,
            canForget: false,
            ambiguous: false
          })
        }
      }
      for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        const row = rows[rowIndex]
        row.ambiguous = idCounts[row.id] !== 1 || row.profileCount > 1
        if (row.ambiguous) {
          row.canConnect = false
          row.canConnectWithPsk = false
          row.canDisconnect = false
          row.canForget = false
        }
      }
      return rows
    }

    function validGeneration(value) {
      return typeof value === "number" && isFinite(value)
        && value >= 0 && Math.floor(value) === value
    }

    function validateRequest(request) {
      const entityId = request && typeof request.entityId === "string"
        ? request.entityId : ""
      if (!request || typeof request !== "object" || Array.isArray(request)
          || entityId === "" || !validGeneration(request.generation))
        return root.result(false, "invalid", "Action request is malformed.",
          entityId, root.generation)
      if (!root.backendAvailable)
        return root.result(false, "unavailable",
          "NetworkManager backend is unavailable.", entityId, root.generation)
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
      const devices = deviceObjects()
      for (let deviceIndex = 0; deviceIndex < devices.length; deviceIndex++) {
        const device = devices[deviceIndex]
        if (!device || deviceType(device) !== "wifi") continue
        const deviceEntityId = Model.deviceId(
          deviceType(device), deviceAddress(device), deviceName(device))
        if (!deviceEntityId) continue
        const networks = networkObjects(device)
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
        const snapshots = networkSnapshots()
        for (let index = 0; index < snapshots.length; index++) {
          if (snapshots[index].id === entityId) {
            row = snapshots[index]
            break
          }
        }
      }
      return { target: target, row: row, count: count }
    }

    function networkActionContext(request) {
      const requestError = validateRequest(request)
      if (requestError) return { error: requestError, target: null, row: null }
      const resolved = networkResolution(request.entityId)
      if (resolved.count === 0)
        return { error: root.result(false, "stale-id",
          "Network identity is no longer present.", request.entityId,
          root.generation), target: null, row: null }
      if (resolved.count > 1 || resolved.row && resolved.row.ambiguous)
        return { error: root.result(false, "ambiguous",
          "Network identity or saved-profile selection is ambiguous.",
          request.entityId, root.generation), target: null, row: null }
      return { error: null, target: resolved.target, row: resolved.row }
    }

    function allowedResultCode(code) {
      return typeof code === "string" && [
        "accepted", "unavailable", "stale-generation", "stale-id",
        "ambiguous", "unsupported", "invalid"
      ].indexOf(code) >= 0
    }

    function delegateResult(value, entityId) {
      try {
        if (value && typeof value === "object"
            && typeof value.ok === "boolean"
            && allowedResultCode(value.code)) {
          const code = value.code
          const messageValid = value.message === undefined
            || typeof value.message === "string"
          const statusConsistent = value.ok === (code === "accepted")
          const generationValid = value.generation === undefined
            || validGeneration(value.generation)
          if (messageValid && statusConsistent && generationValid)
            return root.result(value.ok, code,
              value.message === undefined ? "" : value.message,
              entityId, value.generation === undefined
                ? root.generation : value.generation)
        }
      } catch (error) {}
      if (value === true)
        return root.result(true, "accepted", "", entityId, root.generation)
      if (value && typeof value === "object")
        return root.result(false, "invalid",
          "Backend returned a malformed action result.", entityId,
          root.generation)
      return root.result(false, "unavailable",
        "Backend declined the network action.", entityId, root.generation)
    }

    function dispatchRadio(enabled, entityId) {
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
    }

    function dispatchNetwork(action, target, secret, entityId) {
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
    }
  }
}
