.pragma library

.import "NetworkModel.js" as NetworkModel
.import "NetworkTelemetryModel.js" as TelemetryModel

var SchemaVersion = 1
var MaxProtocolLine = 2048
var MaxSafeInteger = 9007199254740991
var HistoryLimit = 24
var AverageLimit = 5
var InternetTarget = "1.1.1.1"
var EndpointStatuses = ["reply", "timeout", "skipped", "error"]

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

function validInterface(value) {
  const bytes = utf8Bytes(value)
  return bytes !== null && bytes.length >= 1 && bytes.length <= 15
    && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value)
}

function validGateway(value) {
  return value === "" || TelemetryModel.validIpv4(value)
    || TelemetryModel.validIpv6(value)
}

function validEndpoint(endpoint, allowSkipped) {
  if (!exactKeys(endpoint, ["status", "latencyMs"])
      || EndpointStatuses.indexOf(endpoint.status) < 0
      || endpoint.status === "skipped" && !allowSkipped)
    return false
  if (endpoint.status === "reply")
    return typeof endpoint.latencyMs === "number"
      && isFinite(endpoint.latencyMs) && endpoint.latencyMs >= 0
      && endpoint.latencyMs <= 60000
  return endpoint.latencyMs === null
}

function validSnapshot(snapshot) {
  return exactKeys(snapshot, [
      "schemaVersion", "interfaceName", "gateway", "internetTarget",
      "sampleMonotonicMs", "router", "internet"
    ])
    && snapshot.schemaVersion === SchemaVersion
    && validInterface(snapshot.interfaceName)
    && validGateway(snapshot.gateway)
    && snapshot.internetTarget === InternetTarget
    && validInteger(snapshot.sampleMonotonicMs, MaxSafeInteger)
    && validEndpoint(snapshot.router, true)
    && validEndpoint(snapshot.internet, false)
    && (snapshot.gateway === ""
      ? snapshot.router.status === "skipped"
      : snapshot.router.status !== "skipped")
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

function routeInput(source) {
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
  let gateway = ""
  for (let index = 0; index < base.gateways.length; index++) {
    if (base.gateways[index].family === "ipv4") {
      gateway = base.gateways[index].address
      break
    }
  }
  if (gateway === "" && base.gateways.length > 0)
    gateway = base.gateways[0].address
  if (!validGateway(gateway)) return null
  return {
    connectionId: connectionId,
    deviceId: deviceId,
    interfaceName: base.interfaceName,
    gateway: gateway,
    internetTarget: InternetTarget
  }
}

function routeFingerprint(route) {
  return route ? JSON.stringify([
    route.connectionId, route.deviceId, route.interfaceName, route.gateway,
    route.internetTarget
  ]) : ""
}

function appendSample(samples, endpoint) {
  const values = Array.isArray(samples) ? samples.slice() : []
  if (endpoint.status === "reply") values.push(endpoint.latencyMs)
  else if (endpoint.status === "timeout") values.push(null)
  while (values.length > HistoryLimit) values.shift()
  return values
}

function average(samples) {
  const values = Array.isArray(samples) ? samples : []
  let total = 0
  let count = 0
  for (let index = values.length - 1;
       index >= 0 && count < AverageLimit; index--) {
    const value = values[index]
    if (typeof value !== "number" || !isFinite(value) || value < 0) continue
    total += value
    count++
  }
  return count > 0 ? total / count : -1
}

function packetLoss(samples) {
  const values = Array.isArray(samples) ? samples : []
  if (values.length === 0) return 0
  let lost = 0
  for (let index = 0; index < values.length; index++) {
    if (values[index] === null) lost++
  }
  return Math.round(lost * 100 / values.length)
}

function nextHistory(previous, route, probe) {
  if (!route || !validSnapshot(probe)
      || probe.interfaceName !== route.interfaceName
      || probe.gateway !== route.gateway
      || probe.internetTarget !== route.internetTarget
      || probe.router.status === "error" || probe.internet.status === "error")
    return null
  const fingerprint = routeFingerprint(route)
  const same = previous && previous.fingerprint === fingerprint
  if (same && (!validInteger(previous.sampleMonotonicMs, MaxSafeInteger)
      || probe.sampleMonotonicMs <= previous.sampleMonotonicMs)) return null
  const routerSamples = route.gateway === "" ? []
    : appendSample(same ? previous.routerSamples : [], probe.router)
  const internetSamples = appendSample(
    same ? previous.internetSamples : [], probe.internet)
  return {
    fingerprint: fingerprint,
    connectionId: route.connectionId,
    deviceId: route.deviceId,
    interfaceName: route.interfaceName,
    gateway: route.gateway,
    internetTarget: route.internetTarget,
    routerStatus: probe.router.status,
    internetStatus: probe.internet.status,
    routerSamples: routerSamples,
    internetSamples: internetSamples,
    routerLatencyMs: average(routerSamples),
    internetLatencyMs: average(internetSamples),
    internetPacketLossPercent: packetLoss(internetSamples),
    sampleMonotonicMs: probe.sampleMonotonicMs
  }
}

function validHistorySamples(samples) {
  if (!Array.isArray(samples) || samples.length > HistoryLimit) return false
  for (let index = 0; index < samples.length; index++) {
    const value = samples[index]
    if (value !== null && (typeof value !== "number" || !isFinite(value)
        || value < 0 || value > 60000)) return false
  }
  return true
}

function validEntityId(value) {
  const bytes = utf8Bytes(value)
  return bytes !== null && bytes.length >= 1 && bytes.length <= 1024
    && value.indexOf("shibumi-network-v1:") === 0
}

function endpointMatchesLast(status, samples, allowSkipped) {
  if (status === "skipped") return allowSkipped && samples.length === 0
  if (status !== "reply" && status !== "timeout" || samples.length === 0)
    return false
  const last = samples[samples.length - 1]
  return status === "reply" ? typeof last === "number" : last === null
}

function cloneHistory(history) {
  if (!history || typeof history !== "object"
      || !validInterface(history.interfaceName)
      || !validGateway(history.gateway)
      || history.internetTarget !== InternetTarget
      || typeof history.connectionId !== "string"
      || typeof history.deviceId !== "string"
      || EndpointStatuses.indexOf(history.routerStatus) < 0
      || EndpointStatuses.indexOf(history.internetStatus) < 0
      || !validHistorySamples(history.routerSamples)
      || !validHistorySamples(history.internetSamples)
      || !validInteger(history.sampleMonotonicMs, MaxSafeInteger)) return null
  return {
    connectionId: history.connectionId,
    deviceId: history.deviceId,
    interfaceName: history.interfaceName,
    gateway: history.gateway,
    internetTarget: history.internetTarget,
    routerStatus: history.routerStatus,
    internetStatus: history.internetStatus,
    routerSamples: history.routerSamples.slice(),
    internetSamples: history.internetSamples.slice(),
    routerLatencyMs: history.routerLatencyMs,
    internetLatencyMs: history.internetLatencyMs,
    internetPacketLossPercent: history.internetPacketLossPercent,
    sampleMonotonicMs: history.sampleMonotonicMs
  }
}

function validPublicSnapshot(snapshot) {
  const expected = [
    "connectionId", "deviceId", "interfaceName", "gateway",
    "internetTarget", "routerStatus", "internetStatus", "routerSamples",
    "internetSamples", "routerLatencyMs", "internetLatencyMs",
    "internetPacketLossPercent", "sampleMonotonicMs", "schemaVersion",
    "generation"
  ]
  if (!exactKeys(snapshot, expected) || snapshot.schemaVersion !== SchemaVersion
      || !validInteger(snapshot.generation, MaxSafeInteger)
      || !validEntityId(snapshot.connectionId)
      || !validEntityId(snapshot.deviceId)
      || !validInterface(snapshot.interfaceName)
      || !validGateway(snapshot.gateway)
      || snapshot.internetTarget !== InternetTarget
      || !validHistorySamples(snapshot.routerSamples)
      || !validHistorySamples(snapshot.internetSamples)
      || !validInteger(snapshot.sampleMonotonicMs, MaxSafeInteger)
      || !endpointMatchesLast(snapshot.routerStatus,
        snapshot.routerSamples, snapshot.gateway === "")
      || !endpointMatchesLast(snapshot.internetStatus,
        snapshot.internetSamples, false)
      || snapshot.routerLatencyMs !== average(snapshot.routerSamples)
      || snapshot.internetLatencyMs !== average(snapshot.internetSamples)
      || snapshot.internetPacketLossPercent
        !== packetLoss(snapshot.internetSamples)) return false
  return snapshot.gateway !== "" || snapshot.routerStatus === "skipped"
}

function clonePublicSnapshot(snapshot) {
  if (!validPublicSnapshot(snapshot)) return null
  return {
    connectionId: snapshot.connectionId,
    deviceId: snapshot.deviceId,
    interfaceName: snapshot.interfaceName,
    gateway: snapshot.gateway,
    internetTarget: snapshot.internetTarget,
    routerStatus: snapshot.routerStatus,
    internetStatus: snapshot.internetStatus,
    routerSamples: snapshot.routerSamples.slice(),
    internetSamples: snapshot.internetSamples.slice(),
    routerLatencyMs: snapshot.routerLatencyMs,
    internetLatencyMs: snapshot.internetLatencyMs,
    internetPacketLossPercent: snapshot.internetPacketLossPercent,
    sampleMonotonicMs: snapshot.sampleMonotonicMs,
    schemaVersion: snapshot.schemaVersion,
    generation: snapshot.generation
  }
}
