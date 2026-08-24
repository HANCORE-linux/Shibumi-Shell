.pragma library

var SchemaVersion = 1
var MaxProtocolLine = 256
var MaxSequence = 9007199254740991

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

function validSequence(value) {
  return typeof value === "number" && isFinite(value) && value >= 1
    && value <= MaxSequence && Math.floor(value) === value
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
  // The shipped helper emits this canonical key order and compact encoding.
  // Exact reserialization also rejects duplicate keys collapsed by JSON.parse.
  if (JSON.stringify(parsed) !== value) return invalid("noncanonical-json")

  if (!own(parsed, "event") || typeof parsed.event !== "string")
    return invalid("invalid-event")
  const snapshot = parsed.event === "snapshot"
  const owner = parsed.event === "owner"
  if (!snapshot && !owner) return invalid("invalid-event")
  if (!exactKeys(parsed, snapshot
      ? ["schemaVersion", "event", "sequence", "present"]
      : ["schemaVersion", "event", "sequence", "present", "replacement"]))
    return invalid("invalid-shape")
  if (parsed.schemaVersion !== SchemaVersion)
    return invalid("invalid-schema")
  if (!validSequence(parsed.sequence))
    return invalid("invalid-sequence")
  if (typeof parsed.present !== "boolean")
    return invalid("invalid-present")
  if (snapshot && parsed.sequence !== 1)
    return invalid("invalid-snapshot-sequence")
  if (owner && (typeof parsed.replacement !== "boolean"
      || (parsed.replacement && !parsed.present)))
    return invalid("invalid-replacement")

  return {
    ok: true,
    code: "accepted",
    event: parsed.event,
    sequence: parsed.sequence,
    present: parsed.present,
    replacement: owner && parsed.replacement === true
  }
}
