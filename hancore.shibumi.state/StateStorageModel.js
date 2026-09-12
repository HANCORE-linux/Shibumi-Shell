.pragma library

var pluginId = "hancore.shibumi.state"
var schemaKey = "shibumiStateSchemaVersion"

function plain(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function copy(value) { return JSON.parse(JSON.stringify(value)) }

// Iterative comparison avoids treating equal preserved deep fields as a
// conflict. The work budget covers every node in the bounded JSON input;
// arbitrary cyclic/non-JSON callers cannot recurse forever.
function same(left, right) {
  var pending = [[left, right]]
  var visited = 0
  while (pending.length) {
    if (++visited > 1048576) return false
    var pair = pending.pop(), a = pair[0], b = pair[1]
    if (a === b) continue
    if (!a || !b || typeof a !== "object" || typeof b !== "object"
        || Array.isArray(a) !== Array.isArray(b)) return false
    var keys = Object.keys(a)
    if (keys.length !== Object.keys(b).length) return false
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (!Object.prototype.hasOwnProperty.call(b, key)) return false
      pending.push([a[key], b[key]])
    }
  }
  return true
}

function finiteNumbers(value) {
  var pending = [value]
  var visited = 0
  while (pending.length) {
    if (++visited > 1048576) return false
    var current = pending.pop()
    if (typeof current === "number" && !isFinite(current)) return false
    if (current && typeof current === "object") {
      var keys = Object.keys(current)
      for (var i = 0; i < keys.length; i++) pending.push(current[keys[i]])
    }
  }
  return true
}

// Parser budget only: FileView, like the native host, acquires the local file.
function parse(raw) {
  if (typeof raw !== "string" || raw.length > 1048576) return null
  var config
  try { config = JSON.parse(raw) } catch (error) { return null }
  if (!finiteNumbers(config) || !plain(config) || config.version !== 1 || !Array.isArray(config.plugins)
      || config.plugins.length > 512 || !plain(config.bar)
      || !plain(config.bar.layout)) return null
  var found = null
  for (var i = 0; i < config.plugins.length; i++) {
    var item = config.plugins[i]
    if (item === pluginId) return null // native inline replacement needs an object
    if (!plain(item) || item.id !== pluginId) continue
    if (found) return null
    found = item
  }
  // The host gives layout entries priority over plugins[]. Never write there.
  for (var r = 0; r < 3; r++) {
    var entries = config.bar.layout[["left", "center", "right"][r]]
    if (!Array.isArray(entries)) return null
    for (var j = 0; j < entries.length; j++)
      if (entries[j] === pluginId || (plain(entries[j]) && entries[j].id === pluginId)) return null
  }
  // Migration belongs to the drained suite lifecycle. Runtime never revives
  // legacy bar settings after native disable/delete/re-enable of the entry.
  if (!found || found[schemaKey] !== 1 || !plain(found.shibumi)
      || found.shibumi.version !== 1) return null
  return copy(found)
}

// Merge the validated projection into file truth instead of replacing it.
// Keep unknown settings, also inside known objects. Known defaults/identity
// metadata still materialize together (e.g. an explicit "omarchy" launcher must
// not be interpreted as a legacy default). Arrays are whole-value edits;
// deletions remove only keys which the prior normalized view exposed.
function mergeSettings(original, before, after) {
  if (!plain(after)) return copy(after)
  if (!plain(before)) before = ({})
  var result = plain(original) ? copy(original) : ({})
  var keys = Object.keys(before)
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    if (!Object.prototype.hasOwnProperty.call(after, key)) delete result[key]
  }
  keys = Object.keys(after)
  for (var j = 0; j < keys.length; j++) {
    var name = keys[j]
    result[name] = mergeSettings(result[name], before[name], after[name])
  }
  return result
}

function replacement(entry, before, settings) {
  var result = copy(entry)
  result.id = pluginId
  result[schemaKey] = 1
  result.shibumi = mergeSettings(entry.shibumi, before, settings)
  return result
}
