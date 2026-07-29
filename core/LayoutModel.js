.pragma library

var GroupIds = [
  "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8",
  "G9", "G10", "G11", "G12", "G13", "G14", "G15"
]
var Regions = ["left", "center", "right"]
var SplitRegions = ["left", "right", "boundaries"]

function defaultOrder() {
  return {
    left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
    center: ["G8"],
    right: ["G9", "G10", "G11", "G12", "G13", "G14", "G15"]
  }
}

function defaultSplits() {
  return {
    left: [false, false, false, false, false, false],
    boundaries: [true, true],
    right: [false, false, false, false, false, false]
  }
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function expectedLength(region) {
  if (region === "left" || region === "right") return 7
  if (region === "center") return 1
  return 0
}

function expectedSplitLength(region) {
  if (region === "left" || region === "right") return 6
  if (region === "boundaries") return 2
  return 0
}

function validOrder(value) {
  if (!isObject(value)) return false
  var seen = {}
  var count = 0
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    var entries = value[region]
    if (!Array.isArray(entries) || entries.length !== expectedLength(region))
      return false
    for (var i = 0; i < entries.length; i++) {
      var id = String(entries[i] || "")
      if (GroupIds.indexOf(id) < 0 || seen[id]) return false
      seen[id] = true
      count++
    }
  }
  return count === GroupIds.length
}

function copyOrder(value) {
  if (!validOrder(value)) return null
  return {
    left: value.left.slice(),
    center: value.center.slice(),
    right: value.right.slice()
  }
}

function locationFor(value, groupValue) {
  if (!validOrder(value)) return null
  var groupId = String(groupValue || "")
  if (GroupIds.indexOf(groupId) < 0) return null
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    var index = value[region].indexOf(groupId)
    if (index >= 0) return { region: region, index: index, groupId: groupId }
  }
  return null
}

function swapGroups(value, sourceValue, targetValue) {
  var result = copyOrder(value)
  if (!result) return null
  var source = locationFor(result, sourceValue)
  var target = locationFor(result, targetValue)
  if (!source || !target || source.groupId === target.groupId) return null
  result[source.region][source.index] = target.groupId
  result[target.region][target.index] = source.groupId
  return result
}

function validSplits(value) {
  if (!isObject(value)) return false
  for (var r = 0; r < SplitRegions.length; r++) {
    var region = SplitRegions[r]
    var entries = value[region]
    if (!Array.isArray(entries)
        || entries.length !== expectedSplitLength(region)) return false
    for (var i = 0; i < entries.length; i++) {
      if (typeof entries[i] !== "boolean") return false
    }
  }
  return true
}

function copySplits(value) {
  if (!validSplits(value)) return null
  return {
    left: value.left.slice(),
    boundaries: value.boundaries.slice(),
    right: value.right.slice()
  }
}

function splitEnabled(value, regionValue, indexValue) {
  if (!validSplits(value)) return false
  var region = String(regionValue || "")
  var index = Number(indexValue)
  return SplitRegions.indexOf(region) >= 0
    && Number.isInteger(index)
    && index >= 0
    && index < value[region].length
    && value[region][index] === true
}

function toggleSplit(value, regionValue, indexValue) {
  var result = copySplits(value)
  var region = String(regionValue || "")
  var index = Number(indexValue)
  if (!result || SplitRegions.indexOf(region) < 0
      || !Number.isInteger(index) || index < 0
      || index >= result[region].length) return null
  result[region][index] = !result[region][index]
  return result
}

function allSplits(enabledValue) {
  if (typeof enabledValue !== "boolean") return null
  return {
    left: [enabledValue, enabledValue, enabledValue, enabledValue,
      enabledValue, enabledValue],
    boundaries: [enabledValue, enabledValue],
    right: [enabledValue, enabledValue, enabledValue, enabledValue,
      enabledValue, enabledValue]
  }
}

function sameOrder(left, right) {
  if (!validOrder(left) || !validOrder(right)) return false
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    for (var i = 0; i < left[region].length; i++) {
      if (left[region][i] !== right[region][i]) return false
    }
  }
  return true
}

function sameSplits(left, right) {
  if (!validSplits(left) || !validSplits(right)) return false
  for (var r = 0; r < SplitRegions.length; r++) {
    var region = SplitRegions[r]
    for (var i = 0; i < left[region].length; i++) {
      if (left[region][i] !== right[region][i]) return false
    }
  }
  return true
}
