.pragma library

var GroupIds = [
  "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8",
  "G9", "G10", "G11", "G12", "G13", "G14", "G15",
  "G16", "G17", "G18"
]
var Regions = ["left", "center", "right"]
var DynamicGroupPrefix = "G:"
var Limits = {
  left: { min: 10, max: 13 },
  center: { min: 1, max: 4 },
  right: { min: 7, max: 13 }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function validPluginId(value) {
  var id = String(value || "")
  return id.length > 0 && id.length <= 160
    && /^[a-z0-9][a-z0-9._-]*$/.test(id)
}

function dynamicGroupId(pluginValue) {
  var pluginId = String(pluginValue || "")
  return validPluginId(pluginId) ? DynamicGroupPrefix + pluginId : ""
}

function dynamicPluginId(groupValue) {
  var groupId = String(groupValue || "")
  if (groupId.indexOf(DynamicGroupPrefix) !== 0) return ""
  var pluginId = groupId.slice(DynamicGroupPrefix.length)
  return validPluginId(pluginId) ? pluginId : ""
}

function isDynamicGroupId(value) {
  return dynamicPluginId(value) !== ""
}

function defaultLayout() {
  return {
    left: ["G1", "G2", "G3", "", "G5", "G6", "G4", "G7", "", ""],
    center: ["G8"],
    right: [
      "G9", "G10", "G11", "G14", "G12", "G13", "G16",
      "G18", "G17", "G15", "", "", ""
    ]
  }
}

function valid(value) {
  if (!isObject(value)) return false
  var seen = Object.create(null)
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    var entries = value[region]
    var limit = Limits[region]
    if (!Array.isArray(entries)
        || entries.length < limit.min || entries.length > limit.max)
      return false
    for (var i = 0; i < entries.length; i++) {
      var id = String(entries[i] || "")
      if (id !== "" && ((GroupIds.indexOf(id) < 0
          && !isDynamicGroupId(id)) || seen[id])) return false
      if (id !== "") seen[id] = true
    }
  }
  var fixedCount = 0
  for (var groupId in seen) {
    if (GroupIds.indexOf(groupId) >= 0) fixedCount++
  }
  return fixedCount === GroupIds.length
}

function copy(value) {
  if (!valid(value)) return null
  return {
    left: value.left.slice(),
    center: value.center.slice(),
    right: value.right.slice()
  }
}

function visibleOrder(value) {
  var source = valid(value) ? value : defaultLayout()
  return {
    left: source.left.filter(function(id) { return id !== "" }),
    center: source.center.filter(function(id) { return id !== "" }),
    right: source.right.filter(function(id) { return id !== "" })
  }
}

function locationFor(value, groupValue) {
  var source = valid(value) ? value : defaultLayout()
  var groupId = String(groupValue || "")
  if (GroupIds.indexOf(groupId) < 0 && !isDynamicGroupId(groupId)) return null
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    var index = source[region].indexOf(groupId)
    if (index >= 0) return { region: region, index: index, groupId: groupId }
  }
  return null
}

function swapGroups(value, sourceValue, targetValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var source = locationFor(result, sourceValue)
  var target = locationFor(result, targetValue)
  if (!source || !target || source.groupId === target.groupId) return null
  result[source.region][source.index] = target.groupId
  result[target.region][target.index] = source.groupId
  return result
}

function moveGroupToSlot(value, sourceValue, targetRegionValue, targetIndexValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var source = locationFor(result, sourceValue)
  var targetRegion = String(targetRegionValue || "")
  var targetIndex = Math.floor(Number(targetIndexValue))
  if (!source || Regions.indexOf(targetRegion) < 0
      || !Number.isFinite(targetIndex)
      || targetIndex < 0 || targetIndex >= result[targetRegion].length)
    return null
  if (source.region === targetRegion && source.index === targetIndex)
    return null
  var targetGroup = String(result[targetRegion][targetIndex] || "")
  result[targetRegion][targetIndex] = source.groupId
  result[source.region][source.index] = targetGroup
  return valid(result) ? result : null
}

function addSlot(value, regionValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var region = String(regionValue || "")
  if (!result || Regions.indexOf(region) < 0
      || result[region].length >= Limits[region].max) return null
  result[region].push("")
  return result
}

function removeSlot(value, regionValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var region = String(regionValue || "")
  if (!result || Regions.indexOf(region) < 0
      || result[region].length <= Limits[region].min) return null
  for (var index = result[region].length - 1; index >= 0; index--) {
    if (result[region][index] !== "") continue
    result[region].splice(index, 1)
    return result
  }
  return null
}

function removeSlotAt(value, regionValue, indexValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var region = String(regionValue || "")
  var index = Math.floor(Number(indexValue))
  if (!result || Regions.indexOf(region) < 0
      || !Number.isFinite(index)
      || result[region].length <= Limits[region].min
      || index < Limits[region].min || index >= result[region].length
      || result[region][index] !== "") return null
  result[region].splice(index, 1)
  return valid(result) ? result : null
}

function normalizedPluginSpecs(value) {
  if (!Array.isArray(value)) return null
  var result = []
  var seen = Object.create(null)
  for (var i = 0; i < value.length; i++) {
    var spec = value[i]
    if (!isObject(spec) || !validPluginId(spec.pluginId)) return null
    var pluginId = String(spec.pluginId)
    if (seen[pluginId]) continue
    seen[pluginId] = true
    var region = String(spec.region || "")
    result.push({
      pluginId: pluginId,
      region: Regions.indexOf(region) >= 0 ? region : "right"
    })
  }
  result.sort(function(left, right) {
    return left.pluginId.localeCompare(right.pluginId)
  })
  return result
}

function compactEmptyTail(value, regionValue) {
  var region = String(regionValue || "")
  var limit = Limits[region]
  if (!limit || !Array.isArray(value[region])) return false
  var changed = false
  while (value[region].length > limit.min
      && String(value[region][value[region].length - 1] || "") === "") {
    value[region].pop()
    changed = true
  }
  return changed
}

function addDynamicGroup(value, pluginValue, regionValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var groupId = dynamicGroupId(pluginValue)
  var region = String(regionValue || "")
  if (!result || groupId === "" || Regions.indexOf(region) < 0) return null
  if (locationFor(result, groupId)) return result
  for (var index = 0; index < result[region].length; index++) {
    if (String(result[region][index] || "") !== "") continue
    result[region][index] = groupId
    return valid(result) ? result : null
  }
  if (result[region].length >= Limits[region].max) return null
  result[region].push(groupId)
  return valid(result) ? result : null
}

function moveDynamicGroupToRegion(value, groupValue, regionValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var groupId = String(groupValue || "")
  var region = String(regionValue || "")
  var source = locationFor(result, groupId)
  if (!result || !source || !isDynamicGroupId(groupId)
      || Regions.indexOf(region) < 0) return null
  if (source.region === region) return result
  var targetIndex = -1
  for (var index = 0; index < result[region].length; index++) {
    if (String(result[region][index] || "") === "") {
      targetIndex = index
      break
    }
  }
  if (targetIndex < 0 && result[region].length < Limits[region].max) {
    result[region].push("")
    targetIndex = result[region].length - 1
  }
  if (targetIndex < 0) targetIndex = 0
  return moveGroupToSlot(result, groupId, region, targetIndex)
}

function removeDynamicGroup(value, groupValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var groupId = String(groupValue || "")
  var location = locationFor(result, groupId)
  if (!result || !isDynamicGroupId(groupId) || !location) return null
  result[location.region][location.index] = ""
  compactEmptyTail(result, location.region)
  return valid(result) ? result : null
}

function reconcilePluginGroups(value, specsValue, followRegionsValue) {
  var result = copy(valid(value) ? value : defaultLayout())
  var specs = normalizedPluginSpecs(specsValue)
  var followRegions = followRegionsValue === true
  if (!result || !specs) return null
  var desired = Object.create(null)
  for (var i = 0; i < specs.length; i++)
    desired[dynamicGroupId(specs[i].pluginId)] = specs[i]

  var stale = []
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    for (var index = 0; index < result[region].length; index++) {
      var groupId = String(result[region][index] || "")
      if (isDynamicGroupId(groupId) && !desired[groupId]
          && stale.indexOf(groupId) < 0)
        stale.push(groupId)
    }
  }
  for (var staleIndex = 0; staleIndex < stale.length; staleIndex++) {
    result = removeDynamicGroup(result, stale[staleIndex])
    if (!result) return null
  }

  var unplaced = []
  for (var specIndex = 0; specIndex < specs.length; specIndex++) {
    var spec = specs[specIndex]
    var requestedGroupId = dynamicGroupId(spec.pluginId)
    var currentLocation = locationFor(result, requestedGroupId)
    if (currentLocation && followRegions
        && currentLocation.region !== spec.region) {
      var moved = moveDynamicGroupToRegion(
        result, requestedGroupId, spec.region)
      if (!moved) unplaced.push(spec.pluginId)
      else result = moved
      continue
    }
    if (currentLocation) continue
    var placed = addDynamicGroup(result, spec.pluginId, spec.region)
    if (!placed) unplaced.push(spec.pluginId)
    else result = placed
  }
  // A full region must not silently publish a partially placed V2 layout.
  if (unplaced.length > 0) return { layout: result, unplaced: unplaced }
  return { layout: result, unplaced: [] }
}

function same(left, right) {
  if (!valid(left) || !valid(right)) return false
  return JSON.stringify(left) === JSON.stringify(right)
}
