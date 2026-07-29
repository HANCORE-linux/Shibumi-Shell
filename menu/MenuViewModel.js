.pragma library

var MaxRows = 256

function keyForId(id) {
  return "$" + String(id || "")
}

function item(model, id) {
  return model && model.items ? (model.items[keyForId(id)] || null) : null
}

function visible(entry, whenResults) {
  if (!entry) return false
  return !entry.when || !!(whenResults && whenResults[keyForId(entry.id)] === true)
}

function isDescendant(model, id, ancestorId) {
  if (ancestorId === "root") return id !== "root"
  var current = item(model, id)
  var seen = ({})
  for (var depth = 0; current && current.parent && depth < 64; depth++) {
    if (current.parent === ancestorId) return true
    var key = keyForId(current.parent)
    if (seen[key]) return false
    seen[key] = true
    current = item(model, current.parent)
  }
  return false
}

function pathFor(model, id) {
  var labels = []
  var current = item(model, id)
  var seen = ({})
  for (var depth = 0; current && current.id !== "root" && depth < 64; depth++) {
    labels.unshift(current.label)
    var key = keyForId(current.parent)
    if (!current.parent || seen[key]) break
    seen[key] = true
    current = item(model, current.parent)
  }
  return labels.join(" › ")
}

function childCount(model, parentId, whenResults) {
  var order = model && Array.isArray(model.itemOrder) ? model.itemOrder : []
  var count = 0
  for (var i = 0; i < order.length; i++) {
    var entry = item(model, order[i])
    if (entry && entry.parent === parentId && visible(entry, whenResults)) count++
  }
  return count
}

function checked(entry, checkedResults) {
  return !!(entry && entry.checked && checkedResults
    && checkedResults[keyForId(entry.id)] === true)
}

function rowFor(model, entry, activeId, whenResults, checkedResults, section, score) {
  return {
    id: entry.id,
    isApp: false,
    kind: entry.id === "apps" ? "menu" : entry.kind,
    target: entry.id === "apps" ? "apps" : (entry.target || entry.id),
    label: entry.label,
    icon: entry.icon,
    iconFont: entry.iconFont,
    description: entry.description,
    detail: entry.parent === activeId ? entry.description : pathFor(model, entry.parent),
    action: entry.action,
    checkedState: checked(entry, checkedResults),
    childCount: entry.id === "apps" ? 1 : childCount(model, entry.id, whenResults),
    section: section || "",
    score: Number(score) || 0
  }
}

function searchTerms(query) {
  var values = String(query || "").toLowerCase().trim().split(/\s+/)
  var result = []
  for (var i = 0; i < values.length; i++) if (values[i]) result.push(values[i])
  return result
}

function searchText(entry) {
  return [entry.label, entry.id.replace(/[._-]+/g, " "), entry.keywords,
    entry.description, Array.isArray(entry.aliases) ? entry.aliases.join(" ") : ""]
    .join(" ").toLowerCase()
}

function matches(entry, terms) {
  var text = searchText(entry)
  for (var i = 0; i < terms.length; i++) {
    if (text.indexOf(terms[i]) < 0) return false
  }
  return true
}

function score(entry, query, direct) {
  var needle = String(query || "").toLowerCase().trim()
  var label = String(entry.label || "").toLowerCase()
  var value = label === needle ? 0
    : (label.indexOf(needle) === 0 ? 10
      : (label.indexOf(needle) >= 0 ? 20 : 40))
  return value + (direct ? 0 : 100) + Number(entry.order || 0) / 10000
}

function routeRows(model, activeId, query, whenResults, checkedResults, limit) {
  var active = item(model, activeId) ? activeId : "root"
  var order = model && Array.isArray(model.itemOrder) ? model.itemOrder : []
  var terms = searchTerms(query)
  var cap = Math.max(1, Math.min(MaxRows, Number(limit) || MaxRows))
  var rows = []

  for (var i = 0; i < order.length; i++) {
    var entry = item(model, order[i])
    if (!entry || entry.id === "root" || !visible(entry, whenResults)) continue
    var direct = entry.parent === active
    if (terms.length === 0 && !direct) continue
    if (terms.length > 0 && !isDescendant(model, entry.id, active)) continue
    if (terms.length > 0 && !matches(entry, terms)) continue
    rows.push(rowFor(model, entry, active, whenResults, checkedResults,
      direct ? "" : "drilldown", score(entry, query, direct)))
  }

  if (terms.length > 0) rows.sort(function(a, b) {
    if (a.score !== b.score) return a.score - b.score
    return a.label.localeCompare(b.label)
  })
  return rows.slice(0, cap)
}

function providerIds(model, activeId, query) {
  var active = item(model, activeId) ? activeId : "root"
  var includeDescendants = searchTerms(query).length > 0
  var order = model && Array.isArray(model.itemOrder) ? model.itemOrder : []
  var result = []
  for (var i = 0; i < order.length; i++) {
    var entry = item(model, order[i])
    if (!entry || !entry.provider) continue
    if (entry.id === active || entry.parent === active
        || (includeDescendants && isDescendant(model, entry.id, active)))
      result.push(entry.id)
  }
  return result
}
