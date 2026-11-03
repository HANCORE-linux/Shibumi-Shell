.pragma library

function positiveId(value) {
  var id = Number(value)
  return Number.isInteger(id) && id > 0 && id <= 9999 ? id : 0
}

function toplevelCount(workspace) {
  if (!workspace || !workspace.toplevels) return 0
  var values = workspace.toplevels.values
  return values && typeof values.length === "number"
    ? Math.max(0, values.length) : 0
}

function snapshot(source, focusedValue) {
  var values = source && typeof source.length === "number" ? source : []
  var focusedId = positiveId(focusedValue)
  var byId = {}
  for (var i = 0; i < values.length; i++) {
    var id = positiveId(values[i] ? values[i].id : 0)
    if (!id) continue
    var count = toplevelCount(values[i])
    if (!byId[id] || count > byId[id].windowCount)
      byId[id] = { id: id, windowCount: count }
  }
  if (focusedId && !byId[focusedId])
    byId[focusedId] = { id: focusedId, windowCount: 0 }

  var ids = Object.keys(byId).map(Number)
  ids.sort(function(left, right) { return left - right })
  var result = []
  for (var j = 0; j < ids.length; j++) {
    var entry = byId[ids[j]]
    result.push({
      id: entry.id,
      windowCount: entry.windowCount,
      focused: entry.id === focusedId,
      occupied: entry.windowCount > 0
    })
  }
  return result
}

function visibleIds(modeValue, entries, focusedValue) {
  var mode = ["10", "5", "active"].indexOf(String(modeValue || "")) !== -1
    ? String(modeValue) : "10"
  var focusedId = positiveId(focusedValue)
  var source = entries && typeof entries.length === "number" ? entries : []
  var ids = []

  if (mode === "active") {
    for (var i = 0; i < source.length; i++) {
      var activeId = positiveId(source[i] ? source[i].id : 0)
      if (activeId && ids.indexOf(activeId) === -1) ids.push(activeId)
    }
    if (focusedId && ids.indexOf(focusedId) === -1) ids.push(focusedId)
    ids.sort(function(left, right) { return left - right })
    return ids
  }

  var limit = mode === "5" ? 5 : 10
  for (var id = 1; id <= limit; id++) ids.push(id)
  // Persist modes guarantee a minimum range; they are not a visibility cap.
  // Keep every real positive Hyprland workspace reachable even when it sits
  // beyond that range, including occupied workspaces on another monitor.
  for (var entryIndex = 0; entryIndex < source.length; entryIndex++) {
    var existingId = positiveId(source[entryIndex] ? source[entryIndex].id : 0)
    if (existingId && ids.indexOf(existingId) === -1) ids.push(existingId)
  }
  if (focusedId && ids.indexOf(focusedId) === -1) ids.push(focusedId)
  ids.sort(function(left, right) { return left - right })
  return ids
}

// The host keeps disconnected identities with an empty connector. They must
// not claim block zero or overwrite the connected monitor after an unplug.
function readBlocks(text) {
  var result = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].split("\t")
    if (fields.length !== 3 || !/^\d+$/.test(fields[0])
        || !/^[A-Za-z0-9_.:-]+$/.test(fields[1]) || !fields[2]) continue
    var block = Number(fields[0])
    if (!Number.isInteger(block) || block < 0 || block > 998
        || fields[1] === "__proto__") continue
    result[fields[1]] = block
  }
  return result
}

function monitorIds(mode, source, block, connector, activeValue) {
  var ids = [], guests = []
  var minimum = mode === "active" ? 0 : mode === "5" ? 5 : 10
  for (var slot = 1; slot <= minimum; slot++) ids.push(block * 10 + slot)
  var active = positiveId(activeValue)
  if (active && Math.floor((active - 1) / 10) === block
      && ids.indexOf(active) < 0) ids.push(active)
  for (var i = 0; i < source.length; i++) {
    var workspace = source[i], id = positiveId(workspace ? workspace.id : 0)
    if (!id) continue
    if (Math.floor((id - 1) / 10) === block) {
      if (ids.indexOf(id) < 0) ids.push(id)
    } else if (workspace.monitor && workspace.monitor.name === connector
        && guests.indexOf(id) < 0) guests.push(id)
  }
  ids.sort(function(a, b) { return a - b })
  guests.sort(function(a, b) { return a - b })
  return ids.concat(guests)
}

function stateFor(idValue, entries, focusedValue) {
  var id = positiveId(idValue)
  var focusedId = positiveId(focusedValue)
  var source = entries && typeof entries.length === "number" ? entries : []
  var count = 0
  for (var i = 0; i < source.length; i++) {
    if (positiveId(source[i] ? source[i].id : 0) !== id) continue
    count = Math.max(0, Number(source[i].windowCount) || 0)
    break
  }
  return {
    id: id,
    focused: id !== 0 && id === focusedId,
    occupied: count > 0,
    windowCount: count
  }
}
