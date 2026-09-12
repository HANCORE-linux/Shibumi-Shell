.pragma library

// Public listPlugins DTOs, NOT manifests, settings, components or native revision.
var MaximumText = 262144
var MaximumEntries = 512
var Fields = ["id", "name", "kinds", "enabled", "active", "canDisable", "firstParty", "clonedFrom",
  "description", "author", "version", "tags", "barWidget"]
var BarWidgetFields = ["displayName", "description", "category", "semanticCapabilities",
  "defaultSection", "allowMultiple"]

function plain(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function text(value, maximum, empty) {
  if (typeof value !== "string" || value.length > maximum || (!empty && !value.length)
      || /[\x00-\x1f\x7f-\x9f]/.test(value)) return false
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff) {
      var next = value.charCodeAt(++i)
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false
    } else if (code >= 0xdc00 && code <= 0xdfff) return false
  }
  return true
}

function id(value) {
  return text(value, 160, false) && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)
    && !/\.\./.test(value)
}

function stringList(value, maximumItems, maximumText) {
  if (!Array.isArray(value) || value.length > maximumItems) return null
  var result = []
  for (var i = 0; i < value.length; i++) {
    if (!text(value[i], maximumText, false) || result.indexOf(value[i]) >= 0) return null
    result.push(value[i])
  }
  return Object.freeze(result)
}

function normalize(value) {
  if (!Array.isArray(value) || value.length > MaximumEntries) return null
  var entries = []
  var byId = Object.create(null)
  for (var i = 0; i < value.length; i++) {
    var row = value[i]
    if (!plain(row) || Object.keys(row).length !== Fields.length
        || !Fields.every(function(key) { return Object.prototype.hasOwnProperty.call(row, key) })
        || !id(row.id) || Object.prototype.hasOwnProperty.call(byId, row.id)
        || !text(row.name, 512, false)
        || !Array.isArray(row.kinds) || !row.kinds.length || row.kinds.length > 8
        || typeof row.enabled !== "boolean" || typeof row.active !== "boolean"
        || typeof row.canDisable !== "boolean" || typeof row.firstParty !== "boolean"
        || !(row.clonedFrom === "" || id(row.clonedFrom))
        || !text(row.description, 4096, true) || !text(row.author, 512, true)
        || !text(row.version, 128, true) || !plain(row.barWidget)
        || Object.keys(row.barWidget).length !== BarWidgetFields.length
        || !BarWidgetFields.every(function(key) {
          return Object.prototype.hasOwnProperty.call(row.barWidget, key)
        })
        || !text(row.barWidget.displayName, 512, true)
        || !text(row.barWidget.description, 4096, true)
        || !text(row.barWidget.category, 128, true)
        || ["left", "center", "right"].indexOf(row.barWidget.defaultSection) < 0
        || typeof row.barWidget.allowMultiple !== "boolean") return null
    var kinds = []
    for (var k = 0; k < row.kinds.length; k++) {
      var kind = row.kinds[k]
      if (!text(kind, 64, false) || kinds.indexOf(kind) >= 0) return null
      kinds.push(kind)
    }
    var tags = stringList(row.tags, 64, 128)
    var capabilities = stringList(row.barWidget.semanticCapabilities, 32, 64)
    if (!tags || !capabilities) return null
    var bar = kinds.indexOf("bar") >= 0
    if (row.canDisable !== !bar || (bar ? row.enabled !== row.active : row.active)) return null
    var barWidget = Object.freeze({ displayName: row.barWidget.displayName,
      description: row.barWidget.description, category: row.barWidget.category,
      semanticCapabilities: capabilities, defaultSection: row.barWidget.defaultSection,
      allowMultiple: row.barWidget.allowMultiple })
    var entry = Object.freeze({ id: row.id, name: row.name, kinds: Object.freeze(kinds),
      enabled: row.enabled, active: row.active, canDisable: row.canDisable,
      firstParty: row.firstParty, clonedFrom: row.clonedFrom,
      description: row.description, author: row.author, version: row.version,
      tags: tags, barWidget: barWidget })
    byId[entry.id] = entry
    entries.push(entry)
  }
  return Object.freeze({ catalogKind: "native-listPlugins", entries: Object.freeze(entries),
    byId: Object.freeze(byId) })
}

// Check structural/key ambiguity BEFORE JSON.parse. This is not an alternative
// JSON grammar: JSON.parse still validates the entire text afterwards. The small
// depth bound also prevents deep explicit-fake input reaching its native parser.
function uniqueKeys(raw) {
  var stack = []
  for (var i = 0; i < raw.length; i++) {
    var char = raw[i]
    if (char === "{") stack.push({ object: true, key: true, keys: Object.create(null) })
    else if (char === "[") stack.push({ object: false })
    else if (char === "}" || char === "]") {
      var closed = stack.pop()
      if (!closed || closed.object !== (char === "}")) return false
    } else if (char === ",") {
      if (stack.length && stack[stack.length - 1].object) stack[stack.length - 1].key = true
    } else if (char === '"') {
      var start = i++
      while (i < raw.length && raw[i] !== '"') {
        if (raw[i] === "\\") i++
        i++
      }
      if (i >= raw.length) return false
      var frame = stack.length ? stack[stack.length - 1] : null
      if (frame && frame.object && frame.key) {
        var name = JSON.parse(raw.slice(start, i + 1))
        if (Object.prototype.hasOwnProperty.call(frame.keys, name)) return false
        frame.keys[name] = true
        frame.key = false
      }
    }
    if (stack.length > 8) return false
  }
  return stack.length === 0
}

function parse(raw) {
  if (typeof raw !== "string" || raw.length > MaximumText) return null
  try {
    if (!uniqueKeys(raw)) return null
    return normalize(JSON.parse(raw))
  } catch (_) { return null }
}

function entry(snapshot, pluginId) {
  if (!snapshot || snapshot.catalogKind !== "native-listPlugins" || !id(pluginId)
      || !snapshot.byId || !Object.prototype.hasOwnProperty.call(snapshot.byId, pluginId)) return null
  return snapshot.byId[pluginId]
}

function ancestry(snapshot, pluginId) {
  var chain = []
  var seen = Object.create(null)
  var next = pluginId
  for (var depth = 0; depth < 32; depth++) {
    var row = entry(snapshot, next)
    if (!row || Object.prototype.hasOwnProperty.call(seen, next)) return null
    seen[next] = true
    chain.push(row.id)
    if (row.clonedFrom === "") return chain
    next = row.clonedFrom
  }
  return null
}

function same(left, right) {
  return !!left && !!right && JSON.stringify(left.entries) === JSON.stringify(right.entries)
}
