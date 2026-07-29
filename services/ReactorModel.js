.pragma library

function sanitize(value, limitValue) {
  var source = String(value || "").toUpperCase()
  try { source = source.normalize("NFD").replace(/[\u0300-\u036f]/g, "") }
  catch (_error) {}
  source = source.replace(/ß/g, "SS")
    .replace(/Ø/g, "O")
    .replace(/Æ/g, "AE")
    .replace(/[—–]/g, "-")
    .replace(/[’`´]/g, "'")
  var allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,'!-/;+< "
  var limit = Math.max(1, Math.min(160, Number(limitValue) || 64))
  var result = ""
  for (var index = 0; index < source.length && result.length < limit; index++) {
    var character = source.charAt(index)
    if (allowed.indexOf(character) >= 0) result += character
  }
  return result.replace(/ +/g, " ").trim()
}

function workspaceLabel(countValue) {
  var count = Math.max(0, Number(countValue) || 0)
  return count === 0 ? "EMPTY" : count === 1 ? "1 APP" : count + " APPS"
}

function parseAddress(value) {
  var source = String(value || "").trim()
  if (!source) return ""
  var comma = source.indexOf(",")
  if (comma >= 0) source = source.slice(0, comma)
  return source.replace(/^0x/, "").toLowerCase()
}

function parseExternal(rawValue, lastTimestampValue, nowValue) {
  var raw = String(rawValue || "")
  if (raw.length > 4096) raw = raw.slice(raw.length - 4096)
  raw = raw.trim()
  if (!raw) return null
  var newline = raw.lastIndexOf("\n")
  if (newline >= 0) raw = raw.slice(newline + 1)
  var parts = raw.split("\t")
  var timestamp = Number(parts[0])
  var lastTimestamp = Number(lastTimestampValue) || 0
  var now = Number(nowValue) || Date.now()
  if (!isFinite(timestamp) || timestamp <= lastTimestamp
      || timestamp > now + 300000) return null
  var left = sanitize(parts[1], 64)
  var right = sanitize(parts.length > 2 ? parts.slice(2).join("\t") : "", 28)
  if (!left && !right) return null
  return { timestamp: timestamp, left: left, right: right }
}

function profile(value) {
  var name = String(value || "long")
  return ["short", "long", "warn", "quote"].indexOf(name) >= 0 ? name : "long"
}

function parseQuotes(rawValue) {
  var raw = String(rawValue || "")
  if (raw.length > 65536) raw = raw.slice(0, 65536)
  var lines = raw.split(/\r?\n/)
  var result = []
  for (var index = 0; index < lines.length && result.length < 256; index++) {
    var line = String(lines[index] || "").trim()
    if (!line || line.charAt(0) === "#") continue
    var cut = line.lastIndexOf("|")
    var quote = sanitize(cut >= 0 ? line.slice(0, cut) : line, 160)
    var author = sanitize(cut >= 0 ? line.slice(cut + 1) : "", 36)
    if (quote) result.push({ quote: quote, author: author })
  }
  return result
}

function boundedAppend(sourceValue, eventValue, limitValue) {
  var source = Array.isArray(sourceValue) ? sourceValue : []
  var limit = Math.max(1, Math.min(32, Number(limitValue) || 8))
  var result = source.slice(Math.max(0, source.length - limit + 1))
  result.push(eventValue)
  return result
}
