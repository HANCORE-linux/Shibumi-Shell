.pragma library

.import "NetworkModel.js" as NetworkModel
.import "NetworkActionModel.js" as ActionModel

var SchemaVersion = 1
var MaxLine = 4096
var MaxSafeInteger = 9007199254740991

function exact(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || Object.keys(value).length !== keys.length) return false
  for (let index = 0; index < keys.length; index++)
    if (!Object.prototype.hasOwnProperty.call(value, keys[index])) return false
  return true
}

function validToken(value) {
  return typeof value === "string"
    && /^shibumi-profile-action-v1:\[[1-9][0-9]{0,15},[1-9][0-9]{0,15}\]$/.test(value)
}

function validGeneration(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= MaxSafeInteger && Math.floor(value) === value
}

function validDevice(value, required) {
  if (!required) return value.deviceId === "" && value.interfaceName === ""
      && value.hardwareAddress === ""
  return ActionModel.validEntityId(value.deviceId, false)
    && typeof value.interfaceName === "string"
    && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$/.test(value.interfaceName)
    && typeof value.hardwareAddress === "string"
    && /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(value.hardwareAddress)
    && value.hardwareAddress !== "00:00:00:00:00:00"
    && value.hardwareAddress !== "FF:FF:FF:FF:FF:FF"
}

function descriptor(value) {
  if (!exact(value, [
      "action", "uuid", "deviceId", "interfaceName", "hardwareAddress",
      "generation"
    ]) || (value.action !== "connect" && value.action !== "forget")
      || NetworkModel.canonicalUuid(value.uuid) !== value.uuid
      || !validGeneration(value.generation)
      || !validDevice(value, value.action === "connect")) return null
  return {
    action: value.action, uuid: value.uuid, deviceId: value.deviceId,
    interfaceName: value.interfaceName,
    hardwareAddress: value.hardwareAddress, generation: value.generation
  }
}

function payloadLine(value, token) {
  const safe = descriptor(value)
  if (!safe || !validToken(token)) return ""
  const line = JSON.stringify({
    schemaVersion: SchemaVersion,
    action: safe.action,
    requestToken: token,
    uuid: safe.uuid,
    deviceId: safe.deviceId,
    interfaceName: safe.interfaceName,
    hardwareAddress: safe.hardwareAddress,
    generation: safe.generation
  })
  return line.length <= MaxLine ? line : ""
}

function parseCompletion(line) {
  if (typeof line !== "string" || line.length < 2 || line.length > MaxLine
      || line.trim() !== line || line.indexOf("\u0000") >= 0)
    return null
  let value = null
  try { value = JSON.parse(line) } catch (error) { return null }
  if (JSON.stringify(value) !== line || !exact(value, [
      "schemaVersion", "status", "action", "requestToken", "uuid",
      "deviceId", "interfaceName", "hardwareAddress", "generation"
    ]) || value.schemaVersion !== SchemaVersion || value.status !== "completed"
      || !validToken(value.requestToken)) return null
  const safe = descriptor({
    action: value.action, uuid: value.uuid, deviceId: value.deviceId,
    interfaceName: value.interfaceName,
    hardwareAddress: value.hardwareAddress, generation: value.generation
  })
  if (!safe) return null
  safe.requestToken = value.requestToken
  return safe
}

function completionMatches(value, expected, token) {
  const safe = descriptor(expected)
  return !!safe && !!value && validToken(token)
    && value.requestToken === token && value.action === safe.action
    && value.uuid === safe.uuid && value.deviceId === safe.deviceId
    && value.interfaceName === safe.interfaceName
    && value.hardwareAddress === safe.hardwareAddress
    && value.generation === safe.generation
}
