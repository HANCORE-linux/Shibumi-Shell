.pragma library

.import "NetworkModel.js" as NetworkModel

var SchemaVersion = 1
var MaxSafeInteger = 9007199254740991
var MaxRows = 4096
var MaxMessageBytes = 512
var Kinds = [
  "wifi-enable", "wifi-disable", "connect", "connect-with-psk",
  "connect-enterprise", "disconnect", "connect-profile", "forget-profile"
]
var DispatchCodes = [
  "accepted", "unavailable", "stale-generation", "stale-id",
  "ambiguous", "unsupported", "invalid"
]
var TerminalCodes = [
  "idle", "pending", "completed", "timeout", "unavailable",
  "device-removed", "cancelled", "adapter-replaced", "invalid"
]
var ConnectivityTokens = ["unknown", "none", "portal", "limited", "full"]

function own(value, key) {
  return value !== null && typeof value === "object"
    && Object.prototype.hasOwnProperty.call(value, key)
}

function exactKeys(value, expected) {
  if (value === null || typeof value !== "object" || Array.isArray(value))
    return false
  const prototype = Object.getPrototypeOf(value)
  if (prototype !== Object.prototype && prototype !== null) return false
  const keys = Object.keys(value)
  if (keys.length !== expected.length) return false
  for (let index = 0; index < expected.length; index++) {
    if (!own(value, expected[index])) return false
  }
  return true
}

function utf8Length(value, maximum) {
  if (typeof value !== "string" || value.length > maximum) return null
  try {
    const length = unescape(encodeURIComponent(value)).length
    return length <= maximum ? length : null
  } catch (error) {
    return null
  }
}

function validGeneration(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= MaxSafeInteger && Math.floor(value) === value
}

function validEntityId(value, allowEmpty) {
  const length = utf8Length(value, 1024)
  return length !== null && (allowEmpty && length === 0
      || length > 0 && value.indexOf("shibumi-network-v1:") === 0)
}

function validMessage(value) {
  const length = utf8Length(value, MaxMessageBytes)
  return length !== null
    && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/.test(value)
}

function actionId(claim, sequence) {
  if (!validGeneration(claim) || claim <= 0
      || !validGeneration(sequence) || sequence <= 0) return ""
  return "shibumi-network-action-v1:" + JSON.stringify([claim, sequence])
}

function validKind(value) {
  return typeof value === "string" && Kinds.indexOf(value) >= 0
}

function validDispatchResult(value, entityId) {
  return exactKeys(value, ["ok", "code", "message", "entityId", "generation"])
    && typeof value.ok === "boolean"
    && DispatchCodes.indexOf(value.code) >= 0
    && value.ok === (value.code === "accepted")
    && validMessage(value.message)
    && value.entityId === entityId
    && validGeneration(value.generation)
}

function fixedDispatchMessage(code) {
  switch (code) {
  case "stale-generation": return "Network state changed before dispatch."
  case "stale-id": return "Network identity is no longer present."
  case "ambiguous": return "Network identity is ambiguous."
  case "unsupported": return "Network action is unsupported."
  case "invalid": return "Network action request is invalid."
  default: return "Network backend is unavailable."
  }
}

function fixedTerminalMessage(code) {
  switch (code) {
  case "completed": return ""
  case "timeout": return "Network action timed out."
  case "device-removed": return "Network device was removed during the action."
  case "cancelled": return "Network action monitoring was cancelled."
  case "adapter-replaced": return "Network backend changed during the action."
  case "invalid": return "Network action state became invalid."
  default: return "Network backend became unavailable during the action."
  }
}

function rowResolution(rows, entityId) {
  if (!Array.isArray(rows) || rows.length > MaxRows)
    return { ok: false, row: null, count: 0 }
  let row = null
  let count = 0
  for (let index = 0; index < rows.length; index++) {
    const candidate = rows[index]
    if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)
        || typeof candidate.id !== "string")
      return { ok: false, row: null, count: 0 }
    if (candidate.id !== entityId) continue
    row = candidate
    count++
  }
  return { ok: true, row: row, count: count }
}

function validBoundedText(value, maximum, allowEmpty) {
  const length = utf8Length(value, maximum)
  return length !== null && (allowEmpty || length > 0)
    && !/[\u0000-\u001f\u007f-\u009f]/.test(value)
}

function validBoolean(value) {
  return typeof value === "boolean"
}

function validRadio(row, generation) {
  return exactKeys(row, [
      "schemaVersion", "id", "available", "hardwareEnabled", "enabled",
      "generation"
    ])
    && row.schemaVersion === SchemaVersion
    && validEntityId(row.id, false)
    && validBoolean(row.available) && validBoolean(row.hardwareEnabled)
    && validBoolean(row.enabled) && row.generation === generation
}

function validDevice(row, generation) {
  return exactKeys(row, [
      "schemaVersion", "id", "type", "name", "address", "connected",
      "state", "managed", "autoconnect", "ambiguous", "generation"
    ])
    && row.schemaVersion === SchemaVersion
    && validEntityId(row.id, false)
    && (row.type === "wifi" || row.type === "wired")
    && validBoundedText(row.name, 64, false)
    && validBoundedText(row.address, 32, true)
    && validBoolean(row.connected)
    && ["unknown", "connecting", "connected", "disconnecting",
      "disconnected"].indexOf(row.state) >= 0
    && validBoolean(row.managed) && validBoolean(row.autoconnect)
    && validBoolean(row.ambiguous) && row.generation === generation
}

function validNetwork(row, generation) {
  return exactKeys(row, [
      "schemaVersion", "id", "deviceId", "ssid", "security", "connected",
      "known", "state", "stateChanging", "signal", "profileCount",
      "validProfileCount", "canConnect", "canConnectWithPsk",
      "canDisconnect", "canForget", "ambiguous", "generation"
    ])
    && row.schemaVersion === SchemaVersion
    && validEntityId(row.id, false) && validEntityId(row.deviceId, false)
    && validBoundedText(row.ssid, 32, false)
    && NetworkModel.validSsid(row.ssid)
    && NetworkModel.SecurityTokens.indexOf(row.security) >= 0
    && validBoolean(row.connected) && validBoolean(row.known)
    && ["unknown", "connecting", "connected", "disconnecting",
      "disconnected"].indexOf(row.state) >= 0
    && validBoolean(row.stateChanging)
    && validGeneration(row.signal) && row.signal <= 100
    && validGeneration(row.profileCount) && row.profileCount <= MaxRows
    && validGeneration(row.validProfileCount)
    && row.validProfileCount <= row.profileCount
    && validBoolean(row.canConnect)
    && validBoolean(row.canConnectWithPsk)
    && validBoolean(row.canDisconnect) && validBoolean(row.canForget)
    && validBoolean(row.ambiguous) && row.generation === generation
}

function validProfile(row, generation) {
  return exactKeys(row, [
      "schemaVersion", "id", "uuid", "deviceId", "networkId", "ssid",
      "name", "security", "lastSuccessful", "canConnect", "canForget",
      "ambiguous", "generation"
    ])
    && row.schemaVersion === SchemaVersion
    && validEntityId(row.id, false) && validEntityId(row.deviceId, false)
    && validEntityId(row.networkId, false)
    && typeof row.uuid === "string" && row.uuid.length === 36
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(row.uuid)
    && validBoundedText(row.ssid, 32, false)
    && NetworkModel.validSsid(row.ssid)
    && validBoundedText(row.name, 256, true)
    && NetworkModel.SecurityTokens.indexOf(row.security) >= 0
    && validGeneration(row.lastSuccessful)
    && validBoolean(row.canConnect) && validBoolean(row.canForget)
    && validBoolean(row.ambiguous) && row.generation === generation
}

function validRows(rows, validator, generation) {
  if (!Array.isArray(rows) || rows.length > MaxRows) return false
  const seen = ({})
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index]
    if (!validator(row, generation) || own(seen, row.id)) return false
    seen[row.id] = true
  }
  return true
}

function validView(view) {
  if (!exactKeys(view, [
      "available", "degraded", "generation", "radio", "devices",
      "networks", "profiles"
    ]) || !validBoolean(view.available) || !validBoolean(view.degraded)
      || !validGeneration(view.generation)
      || !validRadio(view.radio, view.generation)
      || !validRows(view.devices, validDevice, view.generation)
      || !validRows(view.networks, validNetwork, view.generation)
      || !validRows(view.profiles, validProfile, view.generation)) return false
  const devices = ({})
  const networks = ({})
  for (let index = 0; index < view.devices.length; index++)
    devices[view.devices[index].id] = view.devices[index]
  for (let index = 0; index < view.networks.length; index++) {
    const network = view.networks[index]
    if (!own(devices, network.deviceId)) return false
    if (network.connected && devices[network.deviceId].connected !== true)
      return false
    networks[network.id] = network
  }
  for (let index = 0; index < view.profiles.length; index++) {
    const profile = view.profiles[index]
    if (!own(devices, profile.deviceId) || !own(networks, profile.networkId)
        || networks[profile.networkId].deviceId !== profile.deviceId
        || networks[profile.networkId].ssid !== profile.ssid)
      return false
  }
  return true
}

function actionContext(kind, entityId, radio, networks, profiles) {
  if (!validKind(kind) || !validEntityId(entityId, false)) return null
  if (kind === "wifi-enable" || kind === "wifi-disable") {
    if (!radio || typeof radio !== "object" || radio.id !== entityId
        || radio.available !== true || typeof radio.enabled !== "boolean")
      return null
    const targetEnabled = kind === "wifi-enable"
    if (radio.enabled === targetEnabled) return null
    return {
      deviceId: "", relatedEntityId: "", targetEnabled: targetEnabled
    }
  }
  if (kind === "connect" || kind === "connect-with-psk"
      || kind === "connect-enterprise" || kind === "disconnect") {
    const resolved = rowResolution(networks, entityId)
    if (!resolved.ok || resolved.count !== 1 || !resolved.row
        || resolved.row.ambiguous === true
        || !validEntityId(resolved.row.deviceId, false)
        || resolved.row.stateChanging === true) return null
    if (kind === "connect" && (resolved.row.connected === true
        || resolved.row.state !== "disconnected"
        || resolved.row.canConnect !== true)) return null
    if (kind === "connect-with-psk" && (resolved.row.connected === true
        || resolved.row.state !== "disconnected"
        || resolved.row.canConnectWithPsk !== true)) return null
    if (kind === "connect-enterprise" && (resolved.row.connected === true
        || resolved.row.state !== "disconnected"
        || resolved.row.known === true || resolved.row.profileCount !== 0
        || resolved.row.validProfileCount !== 0
        || resolved.row.security !== "wpa2-eap")) return null
    if (kind === "disconnect" && (resolved.row.connected !== true
        || resolved.row.state !== "connected"
        || resolved.row.canDisconnect !== true)) return null
    return {
      deviceId: resolved.row.deviceId,
      relatedEntityId: "",
      targetEnabled: null
    }
  }
  const resolved = rowResolution(profiles, entityId)
  if (!resolved.ok || resolved.count !== 1 || !resolved.row
      || resolved.row.ambiguous === true
      || !validEntityId(resolved.row.deviceId, false)
      || !validEntityId(resolved.row.networkId, false)) return null
  const network = rowResolution(networks, resolved.row.networkId)
  if (!network.ok || network.count !== 1 || !network.row
      || network.row.ambiguous === true
      || network.row.deviceId !== resolved.row.deviceId
      || network.row.stateChanging === true
      || kind === "connect-profile" && resolved.row.canConnect !== true
      || kind === "forget-profile" && resolved.row.canForget !== true)
    return null
  return {
    deviceId: resolved.row.deviceId,
    relatedEntityId: resolved.row.networkId,
    targetEnabled: null
  }
}

function enterpriseConnected(pending, view) {
  if (!pending || pending.kind !== "connect-enterprise" || !validView(view))
    return false
  const device = deviceUsable(view.devices, pending.deviceId)
  const network = rowResolution(view.networks, pending.entityId)
  return device.ok && device.row.connected === true
    && network.ok && network.count === 1 && network.row
    && network.row.ambiguous === false
    && network.row.deviceId === pending.deviceId
    && network.row.connected === true && network.row.state === "connected"
    && network.row.stateChanging === false
}

function deviceUsable(devices, entityId) {
  const resolved = rowResolution(devices, entityId)
  if (!resolved.ok || resolved.count !== 1 || !resolved.row
      || resolved.row.ambiguous === true)
    return { ok: false, removed: resolved.ok && resolved.count === 0,
      row: null }
  return { ok: true, removed: false, row: resolved.row }
}

function pendingResult() {
  return { terminal: false, success: false, code: "pending", message: "" }
}

function terminal(success, code) {
  return {
    terminal: true,
    success: success === true,
    code: code,
    message: fixedTerminalMessage(code)
  }
}

function reconcile(pending, view) {
  if (!pending || typeof pending !== "object" || !validKind(pending.kind)
      || !validEntityId(pending.entityId, false)
      || !validGeneration(pending.dispatchGeneration)
      || !validGeneration(pending.observedGeneration)
      || !validView(view) || view.available !== true
      || view.degraded === true)
    return terminal(false, "unavailable")
  if (view.generation < pending.dispatchGeneration
      || view.generation < pending.observedGeneration)
    return terminal(false, "invalid")
  const completionFresh = view.generation > pending.dispatchGeneration

  if (pending.kind === "wifi-enable" || pending.kind === "wifi-disable") {
    const radio = view.radio
    if (radio.id !== pending.entityId || radio.available !== true)
      return terminal(false, "unavailable")
    return completionFresh && radio.enabled === pending.targetEnabled
      ? terminal(true, "completed") : pendingResult()
  }

  const device = deviceUsable(view.devices, pending.deviceId)
  if (!device.ok)
    return terminal(false, device.removed ? "device-removed" : "invalid")

  if (pending.kind === "connect-enterprise") return pendingResult()

  if (pending.kind === "connect" || pending.kind === "connect-with-psk") {
    const network = rowResolution(view.networks, pending.entityId)
    if (!network.ok || network.count > 1
        || network.row && network.row.ambiguous === true)
      return terminal(false, "invalid")
    return completionFresh && network.count === 1
      && network.row.deviceId === pending.deviceId
      && network.row.connected === true
      && network.row.state === "connected"
      && network.row.stateChanging === false
        ? terminal(true, "completed") : pendingResult()
  }

  if (pending.kind === "disconnect") {
    const network = rowResolution(view.networks, pending.entityId)
    if (!network.ok || network.count > 1
        || network.row && network.row.ambiguous === true)
      return terminal(false, "invalid")
    if (completionFresh && network.count === 1
        && network.row.deviceId === pending.deviceId
        && network.row.connected === false
        && network.row.state === "disconnected"
        && network.row.stateChanging === false)
      return terminal(true, "completed")
    if (network.count === 0 && device.row.connected === false
        && view.generation > pending.dispatchGeneration)
      return terminal(true, "completed")
    return pendingResult()
  }

  if (pending.kind === "connect-profile") {
    const profile = rowResolution(view.profiles, pending.entityId)
    const network = rowResolution(view.networks, pending.relatedEntityId)
    if (!profile.ok || profile.count !== 1 || !profile.row
        || profile.row.ambiguous === true
        || profile.row.deviceId !== pending.deviceId
        || profile.row.networkId !== pending.relatedEntityId
        || !network.ok || network.count !== 1 || !network.row
        || network.row.ambiguous === true
        || network.row.deviceId !== pending.deviceId)
      return terminal(false, "invalid")
    return completionFresh && network.row.connected === true
      && network.row.state === "connected"
      && network.row.stateChanging === false
        ? terminal(true, "completed") : pendingResult()
  }

  const network = rowResolution(view.networks, pending.relatedEntityId)
  if (!network.ok || network.count !== 1 || !network.row
      || network.row.ambiguous === true
      || network.row.deviceId !== pending.deviceId)
    return pendingResult()
  const profile = rowResolution(view.profiles, pending.entityId)
  if (!profile.ok || profile.count > 1
      || profile.row && profile.row.ambiguous === true)
    return terminal(false, "invalid")
  return profile.count === 0 && view.generation > pending.dispatchGeneration
    ? terminal(true, "completed") : pendingResult()
}

function validPublicSnapshot(snapshot) {
  if (!exactKeys(snapshot, [
      "schemaVersion", "phase", "actionId", "kind", "entityId",
      "relatedEntityId", "targetEnabled", "code", "message",
      "dispatchGeneration", "observedGeneration", "generation"
    ]) || snapshot.schemaVersion !== SchemaVersion
      || ["idle", "pending", "succeeded", "failed"].indexOf(snapshot.phase) < 0
      || (snapshot.phase === "idle" ? snapshot.actionId !== ""
        : typeof snapshot.actionId !== "string"
          || snapshot.actionId.indexOf("shibumi-network-action-v1:") !== 0)
      || (snapshot.phase === "idle" ? snapshot.kind !== ""
        : !validKind(snapshot.kind))
      || !validEntityId(snapshot.entityId, snapshot.phase === "idle")
      || !validEntityId(snapshot.relatedEntityId, true)
      || !validMessage(snapshot.message)
      || !validGeneration(snapshot.dispatchGeneration)
      || !validGeneration(snapshot.observedGeneration)
      || snapshot.observedGeneration < snapshot.dispatchGeneration
      || !validGeneration(snapshot.generation)) return false
  if (snapshot.phase === "idle")
    return snapshot.code === "idle" && snapshot.message === ""
      && snapshot.entityId === "" && snapshot.relatedEntityId === ""
      && snapshot.targetEnabled === null
      && snapshot.dispatchGeneration === 0
      && snapshot.observedGeneration === 0
  const wifi = snapshot.kind === "wifi-enable"
    || snapshot.kind === "wifi-disable"
  const profile = snapshot.kind === "connect-profile"
    || snapshot.kind === "forget-profile"
  if ((wifi ? typeof snapshot.targetEnabled !== "boolean"
        : snapshot.targetEnabled !== null)
      || (profile ? snapshot.relatedEntityId === ""
        : snapshot.relatedEntityId !== "")) return false
  if (snapshot.phase === "pending")
    return snapshot.code === "pending" && snapshot.message === ""
  if (snapshot.phase === "succeeded")
    return snapshot.code === "completed" && snapshot.message === ""
  return ["timeout", "unavailable", "device-removed", "cancelled",
    "adapter-replaced", "invalid"].indexOf(snapshot.code) >= 0
    && snapshot.message === fixedTerminalMessage(snapshot.code)
}

function clonePublicSnapshot(snapshot) {
  if (!validPublicSnapshot(snapshot)) return null
  return {
    schemaVersion: snapshot.schemaVersion,
    phase: snapshot.phase,
    actionId: snapshot.actionId,
    kind: snapshot.kind,
    entityId: snapshot.entityId,
    relatedEntityId: snapshot.relatedEntityId,
    targetEnabled: snapshot.targetEnabled,
    code: snapshot.code,
    message: snapshot.message,
    dispatchGeneration: snapshot.dispatchGeneration,
    observedGeneration: snapshot.observedGeneration,
    generation: snapshot.generation
  }
}
