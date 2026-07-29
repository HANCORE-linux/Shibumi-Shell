.pragma library

function keyForId(id) {
  return "$" + String(id || "")
}
function shellQuote(value) {
  return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
}

function item(model, id) {
  return model && model.items ? (model.items[keyForId(id)] || null) : null
}

function initialState(model) {
  var whenResults = ({})
  var checkedResults = ({})
  var guardCount = 0
  var order = model && Array.isArray(model.itemOrder) ? model.itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(model, order[i])
    if (!entry) continue
    if (entry.when) {
      whenResults[keyForId(entry.id)] = false
      guardCount++
    }
    if (entry.checked) {
      checkedResults[keyForId(entry.id)] = false
      guardCount++
    }
  }
  return {
    whenResults: whenResults,
    checkedResults: checkedResults,
    guardCount: guardCount
  }
}

function scriptFor(model) {
  var lines = ["set +e"]
  var order = model && Array.isArray(model.itemOrder) ? model.itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(model, order[i])
    if (!entry) continue
    if (entry.when) {
      lines.push("if ( eval -- " + shellQuote(entry.when)
        + " ) >/dev/null 2>&1; then printf '%s\\n' "
        + shellQuote(entry.id + ":w:1") + "; else printf '%s\\n' "
        + shellQuote(entry.id + ":w:0") + "; fi")
    }
    if (entry.checked) {
      lines.push("if ( eval -- " + shellQuote(entry.checked)
        + " ) >/dev/null 2>&1; then printf '%s\\n' "
        + shellQuote(entry.id + ":c:1") + "; else printf '%s\\n' "
        + shellQuote(entry.id + ":c:0") + "; fi")
    }
  }
  return lines.length > 1 ? lines.join("\n") : ""
}

function parseOutput(model, raw) {
  var state = initialState(model)
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = /^([a-z0-9][a-z0-9._-]{0,254}):(w|c):(0|1)$/.exec(lines[i].trim())
    if (!match) continue
    var entry = item(model, match[1])
    if (!entry) continue
    var value = match[3] === "1"
    if (match[2] === "w" && entry.when)
      state.whenResults[keyForId(entry.id)] = value
    else if (match[2] === "c" && entry.checked)
      state.checkedResults[keyForId(entry.id)] = value
  }
  return state
}
