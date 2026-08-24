.pragma library

var SchemaVersion = 1
var MaxProfiles = 4096
var MaxProtocolLine = 2048
var MaxSafeInteger = 9007199254740991
var ProfileTypes = ["wifi", "wired", "other"]
var SecurityTokens = [
  "wpa3-suite-b-192", "sae", "wpa2-eap", "wpa2-psk",
  "wpa-eap", "wpa-psk", "static-wep", "dynamic-wep",
  "leap", "owe", "open", "unknown"
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
  for (let index = 0; index < expected.length; index++) {
    if (!own(value, expected[index])) return false
  }
  return true
}

function validInteger(value, maximum) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= maximum && Math.floor(value) === value
}

function utf8Bytes(value) {
  if (typeof value !== "string") return null
  try {
    const encoded = unescape(encodeURIComponent(value))
    const bytes = []
    for (let index = 0; index < encoded.length; index++)
      bytes.push(encoded.charCodeAt(index))
    return bytes
  } catch (error) {
    return null
  }
}

function hexBytes(bytes) {
  if (!Array.isArray(bytes)) return ""
  let result = ""
  for (let index = 0; index < bytes.length; index++)
    result += ("0" + bytes[index].toString(16)).slice(-2).toUpperCase()
  return result
}

function validText(value, minimum, maximum) {
  const bytes = utf8Bytes(value)
  return bytes !== null && bytes.length >= minimum && bytes.length <= maximum
    && !/[\u0000-\u001f\u007f-\u009f]/.test(value)
}

function validProfile(profile) {
  const fields = [
    "schemaVersion", "uuid", "name", "profileType", "ssid", "ssidHex",
    "security", "enterprise", "hidden", "autoconnect", "timestamp"
  ]
  if (!exactKeys(profile, fields) || profile.schemaVersion !== SchemaVersion)
    return false
  if (typeof profile.uuid !== "string"
      || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(profile.uuid)
      || !validText(profile.name, 1, 256)
      || ProfileTypes.indexOf(profile.profileType) < 0
      || SecurityTokens.indexOf(profile.security) < 0
      || typeof profile.enterprise !== "boolean"
      || typeof profile.hidden !== "boolean"
      || typeof profile.autoconnect !== "boolean"
      || !validInteger(profile.timestamp, MaxSafeInteger))
    return false

  if (profile.profileType !== "wifi")
    return profile.ssid === "" && profile.ssidHex === ""
      && profile.security === "unknown" && !profile.enterprise
      && !profile.hidden

  if (typeof profile.ssid !== "string" || typeof profile.ssidHex !== "string"
      || !/^[0-9A-F]{2}(?:[0-9A-F]{2}){0,31}$/.test(profile.ssidHex))
    return false
  const displayBytes = utf8Bytes(profile.ssid)
  if (profile.ssid !== "" && (displayBytes === null
      || displayBytes.length < 1 || displayBytes.length > 32
      || hexBytes(displayBytes) !== profile.ssidHex
      || /[\u0000-\u001f\u007f-\u009f]/.test(profile.ssid)))
    return false
  return true
}

function invalid(code) {
  return { ok: false, code: String(code || "invalid") }
}

function parseLine(value) {
  if (typeof value !== "string" || value.length < 2
      || value.length > MaxProtocolLine || value.trim() !== value
      || value.indexOf("\u0000") >= 0)
    return invalid("invalid-line")
  let parsed = null
  try { parsed = JSON.parse(value) }
  catch (error) { return invalid("invalid-json") }
  if (JSON.stringify(parsed) !== value) return invalid("noncanonical-json")
  if (!own(parsed, "event") || typeof parsed.event !== "string")
    return invalid("invalid-event")

  if (parsed.event === "begin" || parsed.event === "end") {
    if (!exactKeys(parsed,
        ["schemaVersion", "event", "sequence", "count"])
        || parsed.schemaVersion !== SchemaVersion
        || !validInteger(parsed.sequence, MaxProfiles + 2)
        || parsed.sequence < 1
        || !validInteger(parsed.count, MaxProfiles))
      return invalid("invalid-boundary")
    return {
      ok: true,
      event: parsed.event,
      sequence: parsed.sequence,
      count: parsed.count
    }
  }

  if (parsed.event !== "profile"
      || !exactKeys(parsed,
        ["schemaVersion", "event", "sequence", "index", "profile"])
      || parsed.schemaVersion !== SchemaVersion
      || !validInteger(parsed.sequence, MaxProfiles + 1)
      || parsed.sequence < 2
      || !validInteger(parsed.index, MaxProfiles - 1)
      || !validProfile(parsed.profile))
    return invalid("invalid-profile")
  return {
    ok: true,
    event: "profile",
    sequence: parsed.sequence,
    index: parsed.index,
    profile: parsed.profile
  }
}
