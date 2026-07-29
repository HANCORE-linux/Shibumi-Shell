.pragma library

var MaxItems = 2048
var ItemFields = [
  "parent", "icon", "iconFont", "label", "target", "keywords",
  "description", "action", "provider", "aliases", "when", "checked"
]

function keyForId(id) {
  return "$" + String(id || "")
}

function own(object, key) {
  return object !== null && typeof object === "object"
    && Object.prototype.hasOwnProperty.call(object, key)
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function boundedString(value, maxLength) {
  var result = typeof value === "string" ? value : ""
  return result.length <= maxLength ? result : result.slice(0, maxLength)
}

function normalizeId(value) {
  var id = String(value || "").trim().toLowerCase()
  if (!/^[a-z0-9][a-z0-9._-]{0,254}$/.test(id)) return ""
  return id
}

function normalizeAliases(value) {
  var source = Array.isArray(value) ? value : (typeof value === "string" ? [value] : [])
  var result = []
  var seen = ({})
  for (var i = 0; i < source.length && result.length < 32; i++) {
    var alias = normalizeId(source[i])
    var key = keyForId(alias)
    if (!alias || seen[key]) continue
    seen[key] = true
    result.push(alias)
  }
  return result
}

function normalizeKeywords(value) {
  var source = boundedString(value, 2048).trim().split(/\s+/)
  var result = []
  var seen = ({})
  for (var i = 0; i < source.length; i++) {
    var word = source[i]
    var key = "$" + word.toLowerCase()
    if (!word || seen[key]) continue
    seen[key] = true
    result.push(word)
  }
  return result.join(" ")
}

function stripJsoncComments(raw) {
  var source = String(raw || "")
  var result = ""
  var inString = false
  var escaped = false
  var lineComment = false
  var blockComment = false

  for (var i = 0; i < source.length; i++) {
    var current = source.charAt(i)
    var next = i + 1 < source.length ? source.charAt(i + 1) : ""

    if (lineComment) {
      if (current === "\n") {
        lineComment = false
        result += current
      }
      continue
    }
    if (blockComment) {
      if (current === "*" && next === "/") {
        blockComment = false
        i++
      } else if (current === "\n") {
        result += current
      }
      continue
    }
    if (inString) {
      result += current
      if (escaped) escaped = false
      else if (current === "\\") escaped = true
      else if (current === "\"") inString = false
      continue
    }
    if (current === "\"") {
      inString = true
      result += current
    } else if (current === "/" && next === "/") {
      lineComment = true
      i++
    } else if (current === "/" && next === "*") {
      blockComment = true
      i++
    } else {
      result += current
    }
  }
  return result
}

function stripTrailingCommas(raw) {
  var source = String(raw || "")
  var result = ""
  var inString = false
  var escaped = false

  for (var i = 0; i < source.length; i++) {
    var current = source.charAt(i)
    if (inString) {
      result += current
      if (escaped) escaped = false
      else if (current === "\\") escaped = true
      else if (current === "\"") inString = false
      continue
    }
    if (current === "\"") {
      inString = true
      result += current
      continue
    }
    if (current === ",") {
      var cursor = i + 1
      while (cursor < source.length && /\s/.test(source.charAt(cursor))) cursor++
      if (cursor < source.length
          && (source.charAt(cursor) === "}" || source.charAt(cursor) === "]"))
        continue
    }
    result += current
  }
  return result
}

function stripJsonc(raw) {
  return stripTrailingCommas(stripJsoncComments(raw))
}

function normalizePatch(id, raw) {
  if (!id || !plainObject(raw)) return null
  var patch = { id: id, present: ({}) }
  for (var i = 0; i < ItemFields.length; i++) {
    var field = ItemFields[i]
    if (!own(raw, field)) continue
    patch.present[field] = true
    if (field === "aliases") patch[field] = normalizeAliases(raw[field])
    else if (field === "keywords") patch[field] = normalizeKeywords(raw[field])
    else if (field === "parent" || field === "target" || field === "provider")
      patch[field] = normalizeId(raw[field])
    else if (field === "icon") patch[field] = boundedString(raw[field], 32)
    else if (field === "label") patch[field] = boundedString(raw[field], 256)
    else if (field === "iconFont") patch[field] = boundedString(raw[field], 128)
    else patch[field] = boundedString(raw[field], 8192)
  }
  return patch
}

function patchForItem(id, raw) {
  return normalizePatch(normalizeId(id), raw)
}

function parseMenuJsonc(raw) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return { ok: true, items: [], error: "" }

  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (error) {
    return { ok: false, items: [], error: "invalid-jsonc" }
  }
  if (!plainObject(parsed)) return { ok: false, items: [], error: "invalid-root" }

  var source = plainObject(parsed.items) ? parsed.items : parsed
  var result = []
  for (var rawId in source) {
    if (result.length >= MaxItems) break
    var id = normalizeId(rawId)
    var patch = normalizePatch(id, source[rawId])
    if (patch) result.push(patch)
  }
  return { ok: true, items: result, error: "" }
}

function finalizeItem(id, values, order) {
  var parent = own(values, "parent") ? values.parent
    : (id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root")
  if (id === "root") parent = ""
  var action = values.action || ""
  var target = values.target || ""
  return {
    id: id,
    parent: parent,
    kind: action ? "action" : (target ? "link" : "menu"),
    icon: values.icon || "",
    iconFont: values.iconFont || "",
    label: values.label || id,
    target: target,
    keywords: values.keywords || "",
    description: values.description || "",
    action: action,
    provider: values.provider || "",
    aliases: Array.isArray(values.aliases) ? values.aliases.slice() : [],
    when: values.when || "",
    checked: values.checked || "",
    order: order
  }
}

function mergeMenuSources(defaultItems, userItems, runtimeItems) {
  var valuesById = ({})
  var order = []
  var sources = [defaultItems || [], userItems || [], runtimeItems || []]

  for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
    var source = sources[sourceIndex]
    for (var i = 0; i < source.length; i++) {
      var patch = source[i]
      var id = normalizeId(patch && patch.id)
      if (!id || !patch.present) continue
      var key = keyForId(id)
      if (!valuesById[key]) {
        valuesById[key] = ({})
        order.push(id)
      }
      for (var fieldIndex = 0; fieldIndex < ItemFields.length; fieldIndex++) {
        var field = ItemFields[fieldIndex]
        if (patch.present[field]) valuesById[key][field] = patch[field]
      }
    }
  }

  if (!valuesById[keyForId("root")]) {
    valuesById[keyForId("root")] = { label: "Go" }
    order.unshift("root")
  }

  var items = ({})
  for (var orderIndex = 0; orderIndex < order.length; orderIndex++) {
    var itemId = order[orderIndex]
    var itemValues = valuesById[keyForId(itemId)]
    items[keyForId(itemId)] = finalizeItem(itemId, itemValues, orderIndex)
  }
  return { items: items, itemOrder: order }
}

function item(model, id) {
  var normalized = normalizeId(id)
  return model && model.items && normalized
    ? (model.items[keyForId(normalized)] || null)
    : null
}

function resolveRoute(model, value) {
  var route = normalizeId(value)
  if (!route || route === "go" || route === "menu") return "root"
  if (item(model, route)) return route
  var order = model && Array.isArray(model.itemOrder) ? model.itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(model, order[i])
    if (entry && entry.aliases.indexOf(route) >= 0) return entry.id
  }
  return route
}

function children(model, parentId, whenResults, checkedResults) {
  var parent = normalizeId(parentId) || "root"
  var order = model && Array.isArray(model.itemOrder) ? model.itemOrder : []
  var result = []
  for (var i = 0; i < order.length; i++) {
    var entry = item(model, order[i])
    if (!entry || entry.parent !== parent) continue
    if (entry.when && (!whenResults || whenResults[keyForId(entry.id)] !== true)) continue
    var row = ({})
    for (var field in entry) row[field] = entry[field]
    row.checkedState = !!(entry.checked && checkedResults
      && checkedResults[keyForId(entry.id)] === true)
    result.push(row)
  }
  return result
}
