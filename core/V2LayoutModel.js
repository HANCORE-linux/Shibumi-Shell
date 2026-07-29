.pragma library

var GroupIds = [
  "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8",
  "G9", "G10", "G11", "G12", "G13", "G14", "G15",
  "G16", "G17", "G18"
]
var Regions = ["left", "center", "right"]
var Limits = {
  left: { min: 10, max: 13 },
  center: { min: 1, max: 4 },
  right: { min: 7, max: 13 }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
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
  var seen = {}
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    var entries = value[region]
    var limit = Limits[region]
    if (!Array.isArray(entries)
        || entries.length < limit.min || entries.length > limit.max)
      return false
    for (var i = 0; i < entries.length; i++) {
      var id = String(entries[i] || "")
      if (id !== "" && (GroupIds.indexOf(id) < 0 || seen[id])) return false
      if (id !== "") seen[id] = true
    }
  }
  return Object.keys(seen).length === GroupIds.length
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
  if (GroupIds.indexOf(groupId) < 0) return null
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

function same(left, right) {
  if (!valid(left) || !valid(right)) return false
  return JSON.stringify(left) === JSON.stringify(right)
}
