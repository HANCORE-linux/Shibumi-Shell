.pragma library

var SchemaVersion = 1
var MaxProtocolLine = 16384
var MaxSafeInteger = 9007199254740991
var MaxAddresses = 64
var MaxDnsServers = 64
var MaxDnsDomains = 64
var MeteredTokens = ["unknown", "yes", "no", "guess-yes", "guess-no"]

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

function validUuid(value) {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)
}

function validInterface(value) {
  return typeof value === "string" && value.length >= 1 && value.length <= 64
    && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value)
}

function validHardwareAddress(value) {
  return typeof value === "string"
    && /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(value)
    && value !== "00:00:00:00:00:00"
    && value !== "FF:FF:FF:FF:FF:FF"
}

function validIpv4(value) {
  if (typeof value !== "string") return false
  const parts = value.split(".")
  if (parts.length !== 4) return false
  for (let index = 0; index < parts.length; index++) {
    if (!/^(?:0|[1-9][0-9]{0,2})$/.test(parts[index])) return false
    const number = Number(parts[index])
    if (number < 0 || number > 255) return false
  }
  return true
}

function canonicalIpv6(value) {
  if (typeof value !== "string" || value.length < 2 || value.length > 39
      || !/^[0-9a-f:]+$/.test(value) || value.indexOf(":::") >= 0)
    return ""
  const pieces = value.split("::")
  if (pieces.length > 2) return ""
  const left = pieces[0] === "" ? [] : pieces[0].split(":")
  const right = pieces.length < 2 || pieces[1] === ""
    ? [] : pieces[1].split(":")
  const source = left.concat(right)
  for (let index = 0; index < source.length; index++) {
    if (!/^[0-9a-f]{1,4}$/.test(source[index])) return ""
  }
  if (pieces.length === 1 && source.length !== 8) return ""
  if (pieces.length === 2 && source.length >= 8) return ""
  const missing = pieces.length === 2 ? 8 - source.length : 0
  const groups = []
  for (let index = 0; index < left.length; index++)
    groups.push(parseInt(left[index], 16))
  for (let index = 0; index < missing; index++) groups.push(0)
  for (let index = 0; index < right.length; index++)
    groups.push(parseInt(right[index], 16))
  if (groups.length !== 8) return ""
  let bestStart = -1
  let bestLength = 0
  for (let index = 0; index < groups.length;) {
    if (groups[index] !== 0) { index++; continue }
    let end = index
    while (end < groups.length && groups[end] === 0) end++
    if (end - index > bestLength) {
      bestStart = index
      bestLength = end - index
    }
    index = end
  }
  if (bestLength < 2) return groups.map(group => group.toString(16)).join(":")
  const before = groups.slice(0, bestStart)
    .map(group => group.toString(16)).join(":")
  const after = groups.slice(bestStart + bestLength)
    .map(group => group.toString(16)).join(":")
  return before + "::" + after
}

function validIpv6(value) {
  return canonicalIpv6(value) === value
}

function validAddress(family, address) {
  return family === "ipv4" ? validIpv4(address)
    : family === "ipv6" ? validIpv6(address) : false
}

function validAddressRows(rows) {
  if (!Array.isArray(rows) || rows.length > MaxAddresses) return false
  const seen = ({})
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index]
    if (!exactKeys(row, ["family", "address", "prefix"])
        || !validAddress(row.family, row.address)
        || !validInteger(row.prefix, row.family === "ipv4" ? 32 : 128))
      return false
    const identity = row.family + ":" + row.address + "/" + row.prefix
    if (own(seen, identity)) return false
    seen[identity] = true
  }
  return true
}

function validGatewayRows(rows) {
  if (!Array.isArray(rows) || rows.length > 2) return false
  const seen = ({})
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index]
    if (!exactKeys(row, ["family", "address"])
        || !validAddress(row.family, row.address) || own(seen, row.family))
      return false
    seen[row.family] = true
  }
  return true
}

function validDnsServers(rows) {
  if (!Array.isArray(rows) || rows.length > MaxDnsServers) return false
  const seen = ({})
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index]
    if (!exactKeys(row, ["family", "address"])
        || !validAddress(row.family, row.address)) return false
    const identity = row.family + ":" + row.address
    if (own(seen, identity)) return false
    seen[identity] = true
  }
  return true
}

function validDnsDomains(rows) {
  if (!Array.isArray(rows) || rows.length > MaxDnsDomains) return false
  const seen = []
  for (let index = 0; index < rows.length; index++) {
    const domain = rows[index]
    if (!validText(domain, 1, 253) || seen.indexOf(domain) >= 0)
      return false
    seen.push(domain)
  }
  return true
}

function validWifi(value, connected, kind) {
  if (!exactKeys(value,
      ["ssid", "ssidHex", "signal", "frequencyMhz", "bitrateKbps"])
      || typeof value.ssid !== "string" || typeof value.ssidHex !== "string"
      || !validInteger(value.signal, 100)
      || !validInteger(value.frequencyMhz, 1000000)
      || !validInteger(value.bitrateKbps, 100000000)) return false
  if (!connected || kind !== "wifi")
    return value.ssid === "" && value.ssidHex === "" && value.signal === 0
      && value.frequencyMhz === 0 && value.bitrateKbps === 0
  if (!/^[0-9A-F]{2}(?:[0-9A-F]{2}){0,31}$/.test(value.ssidHex))
    return false
  const bytes = utf8Bytes(value.ssid)
  return value.ssid === "" || bytes !== null && bytes.length >= 1
    && bytes.length <= 32 && hexBytes(bytes) === value.ssidHex
    && !/[\u0000-\u001f\u007f-\u009f]/.test(value.ssid)
}

function validWired(value, connected, kind) {
  if (!exactKeys(value, ["speedMbps", "carrier"])
      || !validInteger(value.speedMbps, 100000000)
      || typeof value.carrier !== "boolean") return false
  return connected && kind === "wired"
    ? true : value.speedMbps === 0 && value.carrier === false
}

function validSnapshot(snapshot) {
  const fields = [
    "schemaVersion", "connected", "connectionUuid", "connectionName",
    "kind", "interfaceName", "hardwareAddress", "metered", "addresses",
    "gateways", "dnsServers", "dnsDomains", "rxBytes", "txBytes",
    "sampleMonotonicMs", "wifi", "wired"
  ]
  if (!exactKeys(snapshot, fields) || snapshot.schemaVersion !== SchemaVersion
      || typeof snapshot.connected !== "boolean"
      || !validInteger(snapshot.rxBytes, MaxSafeInteger)
      || !validInteger(snapshot.txBytes, MaxSafeInteger)
      || !validInteger(snapshot.sampleMonotonicMs, MaxSafeInteger)
      || MeteredTokens.indexOf(snapshot.metered) < 0
      || !validAddressRows(snapshot.addresses)
      || !validGatewayRows(snapshot.gateways)
      || !validDnsServers(snapshot.dnsServers)
      || !validDnsDomains(snapshot.dnsDomains)
      || !validWifi(snapshot.wifi, snapshot.connected, snapshot.kind)
      || !validWired(snapshot.wired, snapshot.connected, snapshot.kind))
    return false

  if (!snapshot.connected)
    return snapshot.connectionUuid === "" && snapshot.connectionName === ""
      && snapshot.kind === "none" && snapshot.interfaceName === ""
      && snapshot.hardwareAddress === "" && snapshot.metered === "unknown"
      && snapshot.addresses.length === 0 && snapshot.gateways.length === 0
      && snapshot.dnsServers.length === 0 && snapshot.dnsDomains.length === 0
      && snapshot.rxBytes === 0 && snapshot.txBytes === 0

  return validUuid(snapshot.connectionUuid)
    && validText(snapshot.connectionName, 1, 256)
    && (snapshot.kind === "wifi" || snapshot.kind === "wired")
    && validInterface(snapshot.interfaceName)
    && validHardwareAddress(snapshot.hardwareAddress)
}

function invalid(code) {
  return { ok: false, code: String(code || "invalid") }
}

function parseLine(value) {
  const bytes = utf8Bytes(value)
  if (bytes === null || bytes.length < 2 || bytes.length > MaxProtocolLine
      || value.trim() !== value || value.indexOf("\u0000") >= 0)
    return invalid("invalid-line")
  let parsed = null
  try { parsed = JSON.parse(value) }
  catch (error) { return invalid("invalid-json") }
  if (JSON.stringify(parsed) !== value) return invalid("noncanonical-json")
  if (!exactKeys(parsed,
      ["schemaVersion", "event", "sequence", "snapshot"])
      || parsed.schemaVersion !== SchemaVersion
      || parsed.event !== "snapshot" || parsed.sequence !== 1
      || !validSnapshot(parsed.snapshot))
    return invalid("invalid-snapshot")
  return { ok: true, snapshot: parsed.snapshot }
}

function cloneRows(rows) {
  const source = Array.isArray(rows) ? rows : []
  const result = []
  for (let index = 0; index < source.length; index++) {
    const row = source[index]
    if (own(row, "prefix")) {
      result.push({
        family: row.family, address: row.address, prefix: row.prefix
      })
    } else {
      result.push({ family: row.family, address: row.address })
    }
  }
  return result
}

function cloneSnapshot(snapshot) {
  if (snapshot === null || typeof snapshot !== "object") return null
  const raw = {
    schemaVersion: snapshot.schemaVersion,
    connected: snapshot.connected,
    connectionUuid: snapshot.connectionUuid,
    connectionName: snapshot.connectionName,
    kind: snapshot.kind,
    interfaceName: snapshot.interfaceName,
    hardwareAddress: snapshot.hardwareAddress,
    metered: snapshot.metered,
    addresses: snapshot.addresses,
    gateways: snapshot.gateways,
    dnsServers: snapshot.dnsServers,
    dnsDomains: snapshot.dnsDomains,
    rxBytes: snapshot.rxBytes,
    txBytes: snapshot.txBytes,
    sampleMonotonicMs: snapshot.sampleMonotonicMs,
    wifi: snapshot.wifi,
    wired: snapshot.wired
  }
  if (!validSnapshot(raw)) return null
  return {
    schemaVersion: raw.schemaVersion,
    connected: raw.connected,
    connectionUuid: raw.connectionUuid,
    connectionName: raw.connectionName,
    kind: raw.kind,
    interfaceName: raw.interfaceName,
    hardwareAddress: raw.hardwareAddress,
    metered: raw.metered,
    addresses: cloneRows(raw.addresses),
    gateways: cloneRows(raw.gateways),
    dnsServers: cloneRows(raw.dnsServers),
    dnsDomains: raw.dnsDomains.slice(),
    rxBytes: raw.rxBytes,
    txBytes: raw.txBytes,
    sampleMonotonicMs: raw.sampleMonotonicMs,
    wifi: {
      ssid: raw.wifi.ssid,
      ssidHex: raw.wifi.ssidHex,
      signal: raw.wifi.signal,
      frequencyMhz: raw.wifi.frequencyMhz,
      bitrateKbps: raw.wifi.bitrateKbps
    },
    wired: {
      speedMbps: raw.wired.speedMbps,
      carrier: raw.wired.carrier
    }
  }
}
