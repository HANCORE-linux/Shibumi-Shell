.pragma library

var SchemaVersion = 1
var IdPrefix = "shibumi-network-v1:"
var SecurityTokens = [
  "wpa3-suite-b-192", "sae", "wpa2-eap", "wpa2-psk",
  "wpa-eap", "wpa-psk", "static-wep", "dynamic-wep",
  "leap", "owe", "open", "unknown"
]
var DeviceTypeTokens = ["none", "wifi", "wired"]
var ConnectionStateTokens = [
  "unknown", "connecting", "connected", "disconnecting", "disconnected"
]
var ConnectivityTokens = ["unknown", "none", "portal", "limited", "full"]
var ConnectionFailureTokens = [
  "unknown", "no-secrets", "client-disconnected", "client-failed",
  "authentication-timeout", "network-lost"
]
var MaxBackendObjects = 8192
var MaxSnapshotRows = 4096

function tupleId(kind, fields) {
  var values = [String(kind || "")]
  var source = Array.isArray(fields) ? fields : []
  for (var index = 0; index < source.length; index++)
    values.push(String(source[index]))
  return IdPrefix + JSON.stringify(values)
}

function radioId() {
  return tupleId("radio", ["wifi"])
}

function normalizeHardwareAddress(value) {
  var raw = typeof value === "string" ? value : ""
  var match = raw.match(/^([0-9A-Fa-f]{2})([:-])([0-9A-Fa-f]{2})\2([0-9A-Fa-f]{2})\2([0-9A-Fa-f]{2})\2([0-9A-Fa-f]{2})\2([0-9A-Fa-f]{2})$/)
  if (!match) return ""
  var normalized = [match[1], match[3], match[4], match[5], match[6], match[7]]
    .join(":").toUpperCase()
  if (normalized === "00:00:00:00:00:00"
      || normalized === "FF:FF:FF:FF:FF:FF") return ""
  return normalized
}

function usableInterfaceName(value) {
  if (typeof value !== "string" || value.length < 1 || value.length > 64)
    return false
  if (value.trim() === "" || /[\u0000-\u001f\u007f/]/.test(value))
    return false
  return true
}

function deviceTypeToken(value) {
  if (typeof value === "string") {
    var token = value.toLowerCase()
    return DeviceTypeTokens.indexOf(token) >= 0 ? token : "none"
  }
  if (typeof value !== "number" || !isFinite(value)) return "none"
  return value >= 0 && value < DeviceTypeTokens.length
    && Math.floor(value) === value ? DeviceTypeTokens[value] : "none"
}

function connectionStateToken(value) {
  if (typeof value === "string") {
    var token = value.toLowerCase()
    return ConnectionStateTokens.indexOf(token) >= 0 ? token : "unknown"
  }
  if (typeof value !== "number" || !isFinite(value)) return "unknown"
  return value >= 0 && value < ConnectionStateTokens.length
    && Math.floor(value) === value ? ConnectionStateTokens[value] : "unknown"
}

function connectivityToken(value) {
  if (typeof value === "string") {
    var token = value.toLowerCase()
    return ConnectivityTokens.indexOf(token) >= 0 ? token : "unknown"
  }
  if (typeof value !== "number" || !isFinite(value)) return "unknown"
  return value >= 0 && value < ConnectivityTokens.length
    && Math.floor(value) === value ? ConnectivityTokens[value] : "unknown"
}

function securityToken(value) {
  if (typeof value === "string") {
    var token = value.toLowerCase()
    return SecurityTokens.indexOf(token) >= 0 ? token : "unknown"
  }
  if (typeof value !== "number" || !isFinite(value)) return "unknown"
  return value >= 0 && value < SecurityTokens.length
    && Math.floor(value) === value ? SecurityTokens[value] : "unknown"
}

function validSsid(value) {
  return typeof value === "string" && utf8Length(value) >= 1
    && utf8Length(value) <= 32 && !/[\u0000\r\n]/.test(value)
}

function canonicalUuid(value) {
  if (typeof value !== "string"
      || !/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(value))
    return ""
  return value.toLowerCase()
}

function deviceId(typeValue, addressValue, nameValue) {
  var type = deviceTypeToken(typeValue)
  if (type !== "wifi" && type !== "wired") return ""
  var address = normalizeHardwareAddress(addressValue)
  if (address !== "") return tupleId("device", [type, "mac", address])
  if (!usableInterfaceName(nameValue)) return ""
  return tupleId("device", [type, "ifname", nameValue])
}

function networkId(deviceEntityId, ssidValue, securityValue) {
  var device = typeof deviceEntityId === "string" ? deviceEntityId : ""
  var ssid = typeof ssidValue === "string" ? ssidValue : ""
  if (device.indexOf(IdPrefix) !== 0 || !validSsid(ssid)) return ""
  return tupleId("network", [device, ssid, securityToken(securityValue)])
}

function profileId(deviceEntityId, uuidValue) {
  var device = typeof deviceEntityId === "string" ? deviceEntityId : ""
  var uuid = canonicalUuid(uuidValue)
  if (device.indexOf(IdPrefix) !== 0 || uuid === "") return ""
  return tupleId("profile", [device, uuid])
}

function catalogProfileId(uuidValue) {
  var uuid = canonicalUuid(uuidValue)
  return uuid === "" ? "" : tupleId("saved-profile", [uuid])
}

function connectionId(uuidValue) {
  var uuid = canonicalUuid(uuidValue)
  return uuid === "" ? "" : tupleId("active-connection", [uuid])
}

function boundedDisplayName(value) {
  if (typeof value !== "string" || value.length > 256
      || /[\u0000-\u001f\u007f-\u009f]/.test(value)) return ""
  var size = utf8Length(value)
  return size >= 0 && size <= 256 ? value : ""
}

function pskKind(token) {
  return token === "wpa-psk" || token === "wpa2-psk" || token === "sae"
}

function knownConnectKind(token) {
  return token === "open" || token === "owe"
}

function utf8Bytes(value) {
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

function ssidHex(value) {
  if (!validSsid(value)) return ""
  const bytes = utf8Bytes(value)
  if (!bytes || bytes.length < 1 || bytes.length > 32) return ""
  let result = ""
  for (let index = 0; index < bytes.length; index++)
    result += ("0" + bytes[index].toString(16)).slice(-2).toUpperCase()
  return result
}

function utf8Length(value) {
  try {
    return unescape(encodeURIComponent(value)).length
  } catch (error) {
    return -1
  }
}

function validPsk(value, securityValue) {
  if (typeof value !== "string" || /[\u0000\r\n]/.test(value)) return false
  var token = securityToken(securityValue)
  var size = utf8Length(value)
  if (token === "sae") return size >= 1 && size <= 63
  if (token !== "wpa-psk" && token !== "wpa2-psk") return false
  return /^[0-9A-Fa-f]{64}$/.test(value) || size >= 8 && size <= 63
}

function cloneWithGeneration(rows, generation) {
  var source = Array.isArray(rows) ? rows : []
  var result = []
  for (var index = 0; index < source.length; index++) {
    var row = source[index] || {}
    var next = {}
    for (var key in row) next[key] = row[key]
    next.generation = generation
    result.push(next)
  }
  return result
}

function sortedTopologyRows(rows, fields) {
  var source = Array.isArray(rows) ? rows : []
  var keys = Array.isArray(fields) ? fields : []
  var result = []
  for (var index = 0; index < source.length; index++) {
    var row = source[index] || {}
    var next = {}
    for (var field = 0; field < keys.length; field++)
      next[keys[field]] = row[keys[field]]
    result.push(next)
  }
  result.sort(function(left, right) {
    var leftId = String(left.id || "")
    var rightId = String(right.id || "")
    if (leftId < rightId) return -1
    if (leftId > rightId) return 1
    return JSON.stringify(left).localeCompare(JSON.stringify(right))
  })
  return result
}

function topologyFingerprint(backendAvailable, degraded, radio, devices,
    networks, profiles) {
  return JSON.stringify({
    schemaVersion: SchemaVersion,
    backendAvailable: backendAvailable === true,
    degraded: degraded === true,
    radio: {
      id: radio && radio.id || "",
      available: radio && radio.available === true,
      hardwareEnabled: radio && radio.hardwareEnabled === true,
      enabled: radio && radio.enabled === true
    },
    devices: sortedTopologyRows(devices, [
      "id", "type", "name", "address", "connected", "state",
      "managed", "autoconnect", "ambiguous"
    ]),
    networks: sortedTopologyRows(networks, [
      "id", "deviceId", "ssid", "security", "connected", "known",
      "state", "stateChanging", "profileCount", "validProfileCount",
      "canConnect", "canConnectWithPsk", "canDisconnect", "canForget",
      "ambiguous"
    ]),
    profiles: sortedTopologyRows(profiles, [
      "id", "uuid", "deviceId", "networkId", "ssid", "name",
      "security", "lastSuccessful", "canConnect", "canForget",
      "ambiguous"
    ])
  })
}
