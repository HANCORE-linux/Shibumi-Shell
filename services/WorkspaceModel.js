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
