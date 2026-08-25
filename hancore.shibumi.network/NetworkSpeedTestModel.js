.pragma library

.import "NetworkModel.js" as NetworkModel
.import "NetworkTelemetryModel.js" as TelemetryModel

var SchemaVersion = 1
var MaxProtocolLine = 2048
var MaxSafeInteger = 9007199254740991
var Endpoint = "speed.cloudflare.com"
var Directions = ["down", "up"]
var MeteredTokens = ["unknown", "yes", "no", "guess-yes", "guess-no"]
var MaxDownloadBytes = 1073741824
var MaxUploadBytes = 536870912
var MaxElapsedMs = 15000

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

function validInteger(value, maximum) {
  return typeof value === "number" && isFinite(value) && value >= 0
    && value <= maximum && Math.floor(value) === value
}

function validEntityId(value) {
  const bytes = utf8Bytes(value)
  return bytes !== null && bytes.length >= 1 && bytes.length <= 1024
    && value.indexOf("shibumi-network-v1:") === 0
}

function validInterface(value) {
  const bytes = utf8Bytes(value)
  return bytes !== null && bytes.length >= 1 && bytes.length <= 15
    && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value)
}

function ipv4MappedIpv6(value) {
  if (typeof value !== "string" || value.indexOf("::ffff:") !== 0)
    return false
  return value.slice(7).split(":").length === 2
}

function validSourceAddress(value) {
  if (TelemetryModel.validIpv4(value)) {
    const first = Number(value.split(".")[0])
    const second = Number(value.split(".")[1])
    return value !== "0.0.0.0" && first !== 127 && first < 224
      && !(first === 169 && second === 254)
  }
  if (!TelemetryModel.validIpv6(value)) return false
  return value !== "::" && value !== "::1"
    && !ipv4MappedIpv6(value)
    && value.indexOf("fe8") !== 0 && value.indexOf("fe9") !== 0
    && value.indexOf("fea") !== 0 && value.indexOf("feb") !== 0
    && value.indexOf("ff") !== 0
}

function testInput(source) {
  if (source === null || typeof source !== "object"
      || source.connected !== true) return null
  const base = TelemetryModel.cloneSnapshot(source)
  if (!base || !base.connected || !validInterface(base.interfaceName))
    return null
  const connectionId = NetworkModel.connectionId(base.connectionUuid)
  const deviceId = NetworkModel.deviceId(
    base.kind, base.hardwareAddress, base.interfaceName)
  if (!connectionId || !deviceId || source.id !== connectionId
      || source.deviceId !== deviceId) return null
  let sourceAddress = ""
  for (let index = 0; index < base.addresses.length; index++) {
    const row = base.addresses[index]
    if (row.family === "ipv4" && validSourceAddress(row.address)) {
      sourceAddress = row.address
      break
    }
  }
  if (sourceAddress === "") {
    for (let index = 0; index < base.addresses.length; index++) {
      const row = base.addresses[index]
      if (row.family === "ipv6" && validSourceAddress(row.address)) {
        sourceAddress = row.address
        break
      }
    }
  }
  if (sourceAddress === "") return null
  return {
    connectionId: connectionId,
    deviceId: deviceId,
    kind: base.kind,
    interfaceName: base.interfaceName,
    sourceAddress: sourceAddress,
    metered: base.metered
  }
}

function inputFingerprint(input) {
  return input ? JSON.stringify([
    input.connectionId, input.deviceId, input.kind, input.interfaceName,
    input.sourceAddress, input.metered
  ]) : ""
}

function validRunToken(value) {
  return typeof value === "string"
    && /^[1-9][0-9]{0,9}:[1-9][0-9]{0,15}:[0-9]{1,16}$/.test(value)
}

function validMeasurement(snapshot) {
  if (!exactKeys(snapshot, [
      "schemaVersion", "direction", "endpoint", "interfaceName",
      "interfaceIndex", "sourceAddress", "runToken", "bytesTransferred",
      "elapsedMs", "sampleMonotonicMs"
    ]) || snapshot.schemaVersion !== SchemaVersion
      || Directions.indexOf(snapshot.direction) < 0
      || snapshot.endpoint !== Endpoint
      || !validInterface(snapshot.interfaceName)
      || !validInteger(snapshot.interfaceIndex, 2147483647)
      || snapshot.interfaceIndex < 1
      || !validSourceAddress(snapshot.sourceAddress)
      || !validRunToken(snapshot.runToken)
      || !validInteger(snapshot.bytesTransferred,
        snapshot.direction === "down" ? MaxDownloadBytes : MaxUploadBytes)
      || snapshot.bytesTransferred < 1
      || !validInteger(snapshot.elapsedMs, MaxElapsedMs)
      || snapshot.elapsedMs < 1
      || !validInteger(snapshot.sampleMonotonicMs, MaxSafeInteger))
    return false
  return true
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
      || parsed.event !== "result" || parsed.sequence !== 1
      || !validMeasurement(parsed.snapshot))
    return invalid("invalid-result")
  return { ok: true, snapshot: parsed.snapshot }
}

function measurementMatches(input, direction, runToken, measurement) {
  return input !== null && validMeasurement(measurement)
    && measurement.direction === direction
    && measurement.interfaceName === input.interfaceName
    && measurement.sourceAddress === input.sourceAddress
    && measurement.runToken === runToken
}

function speedMbps(measurement) {
  if (!validMeasurement(measurement)) return -1
  return Math.round(measurement.bytesTransferred * 8
    / measurement.elapsedMs / 1000 * 1000) / 1000
}

function result(input, runId, runToken, down, up) {
  if (!input || !validEntityId(input.connectionId)
      || !validEntityId(input.deviceId)
      || (input.kind !== "wifi" && input.kind !== "wired")
      || !validInterface(input.interfaceName)
      || !validSourceAddress(input.sourceAddress)
      || MeteredTokens.indexOf(input.metered) < 0
      || !validInteger(runId, MaxSafeInteger) || runId < 1
      || !validRunToken(runToken)
      || !measurementMatches(input, "down", runToken, down)
      || !measurementMatches(input, "up", runToken, up)
      || up.interfaceIndex !== down.interfaceIndex
      || up.sampleMonotonicMs <= down.sampleMonotonicMs) return null
  const downloadMbps = speedMbps(down)
  const uploadMbps = speedMbps(up)
  if (!validSpeed(downloadMbps) || !validSpeed(uploadMbps)) return null
  return {
    runId: runId,
    connectionId: input.connectionId,
    deviceId: input.deviceId,
    kind: input.kind,
    interfaceName: input.interfaceName,
    interfaceIndex: down.interfaceIndex,
    sourceAddress: input.sourceAddress,
    metered: input.metered,
    downloadMbps: downloadMbps,
    uploadMbps: uploadMbps,
    downloadBytes: down.bytesTransferred,
    uploadBytes: up.bytesTransferred,
    downloadElapsedMs: down.elapsedMs,
    uploadElapsedMs: up.elapsedMs,
    completedMonotonicMs: up.sampleMonotonicMs
  }
}

function validSpeed(value) {
  return typeof value === "number" && isFinite(value)
    && value > 0 && value <= 1000000
}

function validPublicResult(value) {
  return exactKeys(value, [
      "runId", "connectionId", "deviceId", "kind", "interfaceName",
      "interfaceIndex", "sourceAddress", "metered", "downloadMbps", "uploadMbps",
      "downloadBytes", "uploadBytes", "downloadElapsedMs",
      "uploadElapsedMs", "completedMonotonicMs", "schemaVersion",
      "generation"
    ]) && validInteger(value.runId, MaxSafeInteger) && value.runId >= 1
    && validEntityId(value.connectionId) && validEntityId(value.deviceId)
    && (value.kind === "wifi" || value.kind === "wired")
    && validInterface(value.interfaceName)
    && validInteger(value.interfaceIndex, 2147483647)
    && value.interfaceIndex >= 1
    && validSourceAddress(value.sourceAddress)
    && MeteredTokens.indexOf(value.metered) >= 0
    && validSpeed(value.downloadMbps) && validSpeed(value.uploadMbps)
    && validInteger(value.downloadBytes, MaxDownloadBytes)
    && value.downloadBytes >= 1
    && validInteger(value.uploadBytes, MaxUploadBytes)
    && value.uploadBytes >= 1
    && validInteger(value.downloadElapsedMs, MaxElapsedMs)
    && value.downloadElapsedMs >= 1
    && validInteger(value.uploadElapsedMs, MaxElapsedMs)
    && value.uploadElapsedMs >= 1
    && validInteger(value.completedMonotonicMs, MaxSafeInteger)
    && value.downloadMbps === Math.round(value.downloadBytes * 8
      / value.downloadElapsedMs / 1000 * 1000) / 1000
    && value.uploadMbps === Math.round(value.uploadBytes * 8
      / value.uploadElapsedMs / 1000 * 1000) / 1000
    && value.schemaVersion === SchemaVersion
    && validInteger(value.generation, MaxSafeInteger)
}

function clonePublicResult(value) {
  if (!validPublicResult(value)) return null
  return {
    runId: value.runId,
    connectionId: value.connectionId,
    deviceId: value.deviceId,
    kind: value.kind,
    interfaceName: value.interfaceName,
    interfaceIndex: value.interfaceIndex,
    sourceAddress: value.sourceAddress,
    metered: value.metered,
    downloadMbps: value.downloadMbps,
    uploadMbps: value.uploadMbps,
    downloadBytes: value.downloadBytes,
    uploadBytes: value.uploadBytes,
    downloadElapsedMs: value.downloadElapsedMs,
    uploadElapsedMs: value.uploadElapsedMs,
    completedMonotonicMs: value.completedMonotonicMs,
    schemaVersion: value.schemaVersion,
    generation: value.generation
  }
}
