.pragma library

.import "NetworkModel.js" as NetworkModel
.import "NetworkActionModel.js" as ActionModel

var SchemaVersion = 1
var MaxLine = 2048
var MaxSafeInteger = 9007199254740991
var TokenPattern = /^shibumi-qr-secret-v1:\[[1-9][0-9]{0,9},[1-9][0-9]{0,9}\]$/
var InterfacePattern = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$/
var MacPattern = /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/
var UuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
var SsidHexPattern = /^[0-9A-F]{2}(?:[0-9A-F]{2}){0,31}$/
var FailureCodes = [
  "preflight-manager", "preflight-device", "preflight-active",
  "preflight-active-connection", "preflight-active-device",
  "preflight-active-profile", "preflight-access-point",
  "preflight-active-network", "preflight-profile",
  "preflight-profile-identity", "preflight-profile-security",
  "preflight-profile-version", "authorization-request",
  "authorization-call", "authorization-runtime", "authorization-denied",
  "authorization-timeout", "authorization-failed", "secret-response",
  "secret-response-type", "secret-response-empty", "secret-response-groups",
  "secret-extra-groups", "secret-fields-empty", "secret-psk-missing",
  "secret-extra-fields",
  "secret-value-invalid", "connection-changed", "worker-runtime"
]

function own(value, key) {
  return value !== null && typeof value === "object"
    && Object.prototype.hasOwnProperty.call(value, key)
}

function exactKeys(value, expected) {
  if (value === null || typeof value !== "object" || Array.isArray(value))
    return false
  const keys = Object.keys(value)
  if (keys.length !== expected.length) return false
  for (let index = 0; index < expected.length; index++)
    if (!own(value, expected[index])) return false
  return true
}

function descriptor(value) {
  try {
    const keys = ["networkId", "profileUuid", "deviceId", "interfaceName",
      "hardwareAddress", "ssid", "ssidHex", "security", "generation"]
    if (!exactKeys(value, keys)) return null
    const result = {}
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index]
      const property = Object.getOwnPropertyDescriptor(value, key)
      result[key] = "value" in property
        ? property.value : property.get.call(value)
    }
    if (!ActionModel.validEntityId(result.networkId, false)
        || !UuidPattern.test(result.profileUuid)
        || !ActionModel.validEntityId(result.deviceId, false)
        || typeof result.interfaceName !== "string"
        || !InterfacePattern.test(result.interfaceName)
        || typeof result.hardwareAddress !== "string"
        || !MacPattern.test(result.hardwareAddress)
        || result.hardwareAddress === "00:00:00:00:00:00"
        || result.hardwareAddress === "FF:FF:FF:FF:FF:FF"
        || !NetworkModel.validSsid(result.ssid)
        || typeof result.ssidHex !== "string"
        || !SsidHexPattern.test(result.ssidHex)
        || NetworkModel.ssidHex(result.ssid) !== result.ssidHex
        || !NetworkModel.pskKind(result.security)
        || result.networkId !== NetworkModel.networkId(
          result.deviceId, result.ssid, result.security)
        || typeof result.generation !== "number"
        || !isFinite(result.generation) || result.generation < 0
        || result.generation > MaxSafeInteger
        || Math.floor(result.generation) !== result.generation) return null
    return result
  } catch (error) {
    return null
  }
}

function requestLine(value, requestToken) {
  const safe = descriptor(value)
  if (!safe || typeof requestToken !== "string"
      || !TokenPattern.test(requestToken)) return ""
  return JSON.stringify({
    schemaVersion: SchemaVersion,
    requestToken: requestToken,
    networkId: safe.networkId,
    profileUuid: safe.profileUuid,
    deviceId: safe.deviceId,
    interfaceName: safe.interfaceName,
    hardwareAddress: safe.hardwareAddress,
    ssidHex: safe.ssidHex,
    security: safe.security,
    generation: safe.generation
  })
}

function parseFailure(line) {
  if (typeof line !== "string" || line.length < 2 || line.length > MaxLine
      || line.trim() !== line || line.indexOf("\u0000") >= 0) return null
  let value = null
  try { value = JSON.parse(line) }
  catch (error) { return null }
  if (JSON.stringify(value) !== line
      || !exactKeys(value, ["schemaVersion", "status", "requestToken", "code"])
      || value.schemaVersion !== SchemaVersion || value.status !== "failed"
      || typeof value.requestToken !== "string"
      || !TokenPattern.test(value.requestToken)
      || typeof value.code !== "string"
      || FailureCodes.indexOf(value.code) < 0) return null
  return value
}

function parseCompletion(line) {
  if (typeof line !== "string" || line.length < 2 || line.length > MaxLine
      || line.trim() !== line || line.indexOf("\u0000") >= 0) return null
  let value = null
  try { value = JSON.parse(line) }
  catch (error) { return null }
  if (JSON.stringify(value) !== line
      || !exactKeys(value, ["schemaVersion", "status", "requestToken",
        "networkId", "profileUuid", "deviceId", "interfaceName",
        "hardwareAddress", "ssidHex", "security", "generation", "psk"]))
    return null
  // The descriptor's SSID is validated against the pending request below;
  // completion carries only the bounded hexadecimal identity.
  if (value.schemaVersion !== SchemaVersion || value.status !== "completed"
      || typeof value.requestToken !== "string"
      || !TokenPattern.test(value.requestToken)
      || !ActionModel.validEntityId(value.networkId, false)
      || !UuidPattern.test(value.profileUuid)
      || !ActionModel.validEntityId(value.deviceId, false)
      || !InterfacePattern.test(value.interfaceName)
      || !MacPattern.test(value.hardwareAddress)
      || !SsidHexPattern.test(value.ssidHex)
      || !NetworkModel.pskKind(value.security)
      || typeof value.generation !== "number" || !isFinite(value.generation)
      || value.generation < 0 || value.generation > MaxSafeInteger
      || Math.floor(value.generation) !== value.generation
      || !NetworkModel.validPsk(value.psk, value.security)) return null
  return value
}

function sameDescriptor(left, right) {
  const first = descriptor(left)
  const second = descriptor(right)
  return !!first && !!second
    && first.networkId === second.networkId
    && first.profileUuid === second.profileUuid
    && first.deviceId === second.deviceId
    && first.interfaceName === second.interfaceName
    && first.hardwareAddress === second.hardwareAddress
    && first.ssid === second.ssid
    && first.ssidHex === second.ssidHex
    && first.security === second.security
    && first.generation === second.generation
}

function completionMatches(value, pending, requestToken) {
  const safe = descriptor(pending)
  return !!value && !!safe && value.requestToken === requestToken
    && value.networkId === safe.networkId
    && value.profileUuid === safe.profileUuid
    && value.deviceId === safe.deviceId
    && value.interfaceName === safe.interfaceName
    && value.hardwareAddress === safe.hardwareAddress
    && value.ssidHex === safe.ssidHex
    && value.security === safe.security
    && value.generation === safe.generation
}
