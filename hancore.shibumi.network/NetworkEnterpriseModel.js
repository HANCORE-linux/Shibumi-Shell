.pragma library

.import "NetworkActionModel.js" as ActionModel

var SchemaVersion = 1
var Method = "peap-mschapv2"
var MaxPayloadBytes = 8192
var MaxCompletionBytes = 2048
var MaxIdentityBytes = 253
var MaxPasswordBytes = 1024
var MaxDomainBytes = 253
var MaxSafeInteger = 9007199254740991

function own(value, key) {
  return value !== null && typeof value === "object"
    && Object.prototype.hasOwnProperty.call(value, key)
}

function exactKeys(value, expected) {
  if (value === null || typeof value !== "object" || Array.isArray(value))
    return false
  const prototype = Object.getPrototypeOf(value)
  if (prototype !== Object.prototype && prototype !== null) return false
  const keys = Reflect.ownKeys(value)
  if (keys.length !== expected.length) return false
  for (let index = 0; index < expected.length; index++) {
    if (typeof keys[index] !== "string" || expected.indexOf(keys[index]) < 0)
      return false
  }
  return true
}

function utf8Length(value, maximum) {
  if (typeof value !== "string" || value.length > maximum) return -1
  try {
    const length = unescape(encodeURIComponent(value)).length
    return length <= maximum ? length : -1
  } catch (error) {
    return -1
  }
}

function boundedText(value, maximum) {
  const size = utf8Length(value, maximum)
  return size >= 1 && size <= maximum && value.trim() === value
    && !/[\u0000-\u001f\u007f-\u009f]/.test(value)
}

function boundedPassword(value) {
  const size = utf8Length(value, MaxPasswordBytes)
  return size >= 1 && size <= MaxPasswordBytes
    && value.indexOf("\u0000") < 0
}

function normalizedDomain(value) {
  if (typeof value !== "string" || value.trim() !== value) return ""
  const normalized = value.toLowerCase()
  if (utf8Length(normalized, MaxDomainBytes) < 1
      || normalized.length > MaxDomainBytes || normalized.indexOf(".") < 1
      || !/^[a-z0-9.-]+$/.test(normalized)) return ""
  const labels = normalized.split(".")
  if (labels.length < 2) return ""
  for (let index = 0; index < labels.length; index++) {
    const label = labels[index]
    if (label.length < 1 || label.length > 63
        || label[0] === "-" || label[label.length - 1] === "-") return ""
  }
  return normalized
}

function propertyValue(source, key) {
  const descriptor = Object.getOwnPropertyDescriptor(source, key)
  if (!descriptor) throw new Error("missing credential field")
  return "value" in descriptor
    ? descriptor.value : descriptor.get.call(source)
}

function credentialsData(value) {
  try {
    const fields = ["method", "identity", "password", "serverDomain"]
    if (!exactKeys(value, fields)) throw new Error("invalid credential schema")
    const method = propertyValue(value, "method")
    const identity = propertyValue(value, "identity")
    const password = propertyValue(value, "password")
    const serverDomain = propertyValue(value, "serverDomain")
    const domain = normalizedDomain(serverDomain)
    if (method !== Method || !boundedText(identity, MaxIdentityBytes)
        || !boundedPassword(password) || domain === "")
      throw new Error("invalid enterprise credential")
    return {
      ok: true,
      credentials: {
        identity: identity,
        method: Method,
        password: password,
        serverDomain: domain
      }
    }
  } catch (error) {
    return { ok: false, credentials: null }
  }
}

function validGeneration(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= MaxSafeInteger && Math.floor(value) === value
}

function validDescriptor(value) {
  return exactKeys(value, [
      "deviceId", "entityId", "generation", "hardwareAddress",
      "interfaceName", "security", "ssidHex"
    ]) && ActionModel.validEntityId(value.deviceId, false)
    && ActionModel.validEntityId(value.entityId, false)
    && validGeneration(value.generation)
    && typeof value.hardwareAddress === "string"
    && /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(value.hardwareAddress)
    && value.hardwareAddress !== "00:00:00:00:00:00"
    && value.hardwareAddress !== "FF:FF:FF:FF:FF:FF"
    && typeof value.interfaceName === "string"
    && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$/.test(value.interfaceName)
    && value.security === "wpa2-eap"
    && typeof value.ssidHex === "string"
    && /^[0-9A-F]{2}(?:[0-9A-F]{2}){0,31}$/.test(value.ssidHex)
}

function validRequestToken(value) {
  return typeof value === "string"
    && /^shibumi-enterprise-v1:\[[1-9][0-9]{0,9},[1-9][0-9]{0,15}\]$/.test(value)
}

function validCompletion(value) {
  return exactKeys(value, [
      "deviceId", "entityId", "generation", "hardwareAddress",
      "interfaceName", "requestToken", "sampleMonotonicMs", "schemaVersion",
      "security", "ssidHex", "status"
    ]) && value.schemaVersion === SchemaVersion
    && ActionModel.validEntityId(value.deviceId, false)
    && ActionModel.validEntityId(value.entityId, false)
    && validGeneration(value.generation)
    && typeof value.hardwareAddress === "string"
    && /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(value.hardwareAddress)
    && value.hardwareAddress !== "00:00:00:00:00:00"
    && value.hardwareAddress !== "FF:FF:FF:FF:FF:FF"
    && typeof value.interfaceName === "string"
    && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$/.test(value.interfaceName)
    && validRequestToken(value.requestToken)
    && validGeneration(value.sampleMonotonicMs)
    && value.security === "wpa2-eap"
    && typeof value.ssidHex === "string"
    && /^[0-9A-F]{2}(?:[0-9A-F]{2}){0,31}$/.test(value.ssidHex)
    && value.status === "connected"
}

function parseCompletionLine(value) {
  if (typeof value !== "string" || value.trim() !== value
      || value.indexOf("\u0000") >= 0
      || utf8Length(value, MaxCompletionBytes) < 2)
    return { ok: false, snapshot: null }
  let parsed = null
  try { parsed = JSON.parse(value) }
  catch (error) { return { ok: false, snapshot: null } }
  if (JSON.stringify(parsed) !== value
      || !exactKeys(parsed,
        ["event", "schemaVersion", "sequence", "snapshot"])
      || parsed.event !== "completion"
      || parsed.schemaVersion !== SchemaVersion || parsed.sequence !== 1
      || !validCompletion(parsed.snapshot))
    return { ok: false, snapshot: null }
  return { ok: true, snapshot: parsed.snapshot }
}

function completionMatches(value, requestToken, ssidHex, deviceId,
    entityId, dispatchGeneration, hardwareAddress, interfaceName, security) {
  return validCompletion(value) && value.requestToken === requestToken
    && value.ssidHex === ssidHex && value.deviceId === deviceId
    && value.entityId === entityId && value.generation === dispatchGeneration
    && value.hardwareAddress === hardwareAddress
    && value.interfaceName === interfaceName && value.security === security
}

function cloneCredentials(value) {
  const parsed = credentialsData(value)
  return parsed.ok ? parsed.credentials : null
}

function payloadObject(descriptor, credentials, requestToken) {
  if (!validDescriptor(descriptor) || !validRequestToken(requestToken))
    return null
  const safeCredentials = cloneCredentials(credentials)
  if (!safeCredentials) return null
  // Lexical field order keeps JSON.stringify canonical with Python sort_keys.
  return {
    deviceId: descriptor.deviceId,
    entityId: descriptor.entityId,
    generation: descriptor.generation,
    hardwareAddress: descriptor.hardwareAddress,
    identity: safeCredentials.identity,
    interfaceName: descriptor.interfaceName,
    method: safeCredentials.method,
    password: safeCredentials.password,
    requestToken: requestToken,
    schemaVersion: SchemaVersion,
    security: descriptor.security,
    serverDomain: safeCredentials.serverDomain,
    ssidHex: descriptor.ssidHex
  }
}

function payloadLine(descriptor, credentials, requestToken) {
  const payload = payloadObject(descriptor, credentials, requestToken)
  if (!payload) return ""
  const value = JSON.stringify(payload)
  const size = utf8Length(value, MaxPayloadBytes)
  return size >= 2 && size <= MaxPayloadBytes && value.indexOf("\n") < 0
    ? value : ""
}

function descriptorResult(value, entityId, generation) {
  return exactKeys(value, [
      "ok", "code", "message", "entityId", "generation", "descriptor"
    ]) && value.ok === true && value.code === "accepted" && value.message === ""
    && value.entityId === entityId && value.generation === generation
    && validDescriptor(value.descriptor)
    && value.descriptor.entityId === entityId
    && value.descriptor.generation === generation
}

function dispatchResult(ok, code, entityId, generation) {
  return {
    ok: ok === true,
    code: ok === true ? "accepted" : String(code || "unavailable"),
    message: "",
    entityId: typeof entityId === "string" ? entityId : "",
    generation: validGeneration(generation) ? generation : 0
  }
}
