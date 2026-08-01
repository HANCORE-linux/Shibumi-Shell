.pragma library

var GroupIds = [
  "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8",
  "G9", "G10", "G11", "G12", "G13", "G14", "G15"
]
var Regions = ["left", "center", "right"]
var SplitRegions = ["left", "right", "boundaries"]
var BaseCounts = { left: 7, center: 1, right: 7 }
var ExtraLimits = { left: 2, center: 0, right: 2 }
var DynamicGroupPrefix = "G:"

function defaultOrder() {
  return {
    left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
    center: ["G8"],
    right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
  }
}

function defaultSplits() {
  return {
    left: [false, false, false, false, false, false],
    boundaries: [false, false],
    right: [false, false, false, false, false, false]
  }
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

function baseCount(regionValue) {
  return Number(BaseCounts[String(regionValue || "")] || 0)
}

function maxCount(regionValue) {
  var region = String(regionValue || "")
  return baseCount(region) + Number(ExtraLimits[region] || 0)
}

function expectedSplitLength(regionValue, orderValue) {
  var region = String(regionValue || "")
  if (region === "boundaries") return 2
  var source = validOrder(orderValue) ? orderValue : defaultOrder()
  return Regions.indexOf(region) >= 0
    ? Math.max(0, source[region].length - 1) : 0
}

function validOrder(value) {
  if (!isObject(value)) return false
  var seen = {}
  var fixedCount = 0
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    var entries = value[region]
    if (!Array.isArray(entries)
        || entries.length < baseCount(region)
        || entries.length > maxCount(region)) return false
    for (var i = 0; i < entries.length; i++) {
      var id = String(entries[i] || "")
      if (id === "") continue
      if ((GroupIds.indexOf(id) < 0 && !isDynamicGroupId(id)) || seen[id])
        return false
      seen[id] = true
      if (GroupIds.indexOf(id) >= 0) fixedCount++
    }
  }
  return fixedCount === GroupIds.length
}

function copyOrder(value) {
  if (!validOrder(value)) return null
  return {
    left: value.left.slice(),
    center: value.center.slice(),
    right: value.right.slice()
  }
}

function slotRoles(value) {
  var source = validOrder(value) ? value : defaultOrder()
  var result = { left: [], center: [], right: [] }
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    for (var i = 0; i < source[region].length; i++)
      result[region].push(i < baseCount(region) ? "base" : "extra")
  }
  return result
}

function validSlotRoles(value, orderValue) {
  if (!isObject(value) || !validOrder(orderValue)) return false
  var expected = slotRoles(orderValue)
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    if (!Array.isArray(value[region])
        || value[region].length !== expected[region].length) return false
    for (var i = 0; i < value[region].length; i++) {
      if (String(value[region][i] || "") !== expected[region][i]) return false
    }
  }
  return true
}

function isExtraSlot(value, regionValue, indexValue) {
  var region = String(regionValue || "")
  var index = Math.floor(Number(indexValue))
  return validOrder(value) && Regions.indexOf(region) >= 0
    && Number.isFinite(index) && index >= baseCount(region)
    && index < value[region].length
}

function locationFor(value, groupValue) {
  if (!validOrder(value)) return null
  var groupId = String(groupValue || "")
  if (GroupIds.indexOf(groupId) < 0 && !isDynamicGroupId(groupId)) return null
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

function moveGroupToSlot(value, sourceValue, targetRegionValue,
    targetIndexValue) {
  var result = copyOrder(value)
  var source = locationFor(result, sourceValue)
  var targetRegion = String(targetRegionValue || "")
  var targetIndex = Math.floor(Number(targetIndexValue))
  if (!result || !source || Regions.indexOf(targetRegion) < 0
      || !Number.isFinite(targetIndex) || targetIndex < 0
      || targetIndex >= result[targetRegion].length) return null
  if (source.region === targetRegion && source.index === targetIndex) return null
  var targetGroup = String(result[targetRegion][targetIndex] || "")
  result[targetRegion][targetIndex] = source.groupId
  result[source.region][source.index] = targetGroup
  return validOrder(result) ? result : null
}

function addSlot(value, regionValue) {
  var result = copyOrder(value)
  var region = String(regionValue || "")
  if (!result || (region !== "left" && region !== "right")
      || result[region].length >= maxCount(region)) return null
  result[region].push("")
  return validOrder(result) ? result : null
}

function validSplits(value, orderValue) {
  if (!isObject(value)) return false
  var sourceOrder = validOrder(orderValue) ? orderValue : defaultOrder()
  for (var r = 0; r < SplitRegions.length; r++) {
    var region = SplitRegions[r]
    var entries = value[region]
    if (!Array.isArray(entries)
        || entries.length !== expectedSplitLength(region, sourceOrder))
      return false
    for (var i = 0; i < entries.length; i++) {
      if (typeof entries[i] !== "boolean") return false
    }
  }
  return true
}

function copySplits(value, orderValue) {
  if (!validSplits(value, orderValue)) return null
  return {
    left: value.left.slice(),
    boundaries: value.boundaries.slice(),
    right: value.right.slice()
  }
}

function resizeSplits(value, orderValue) {
  if (!isObject(value) || !validOrder(orderValue)) return null
  var result = { left: [], boundaries: [], right: [] }
  for (var r = 0; r < SplitRegions.length; r++) {
    var region = SplitRegions[r]
    var source = Array.isArray(value[region]) ? value[region] : []
    var length = expectedSplitLength(region, orderValue)
    for (var i = 0; i < length; i++)
      result[region].push(typeof source[i] === "boolean" ? source[i] : false)
  }
  return validSplits(result, orderValue) ? result : null
}

function removeSlotAt(orderValue, splitsValue, regionValue, indexValue) {
  var order = copyOrder(orderValue)
  var splits = copySplits(splitsValue, orderValue)
  var region = String(regionValue || "")
  var index = Math.floor(Number(indexValue))
  if (!order || !splits || !isExtraSlot(order, region, index)
      || order[region][index] !== "") return null

  var sourceSplits = splits[region].slice()
  var lastIndex = order[region].length - 1
  order[region].splice(index, 1)
  if (index === 0) sourceSplits.splice(0, 1)
  else if (index === lastIndex) sourceSplits.splice(index - 1, 1)
  else {
    var merged = sourceSplits[index - 1] === true
      || sourceSplits[index] === true
    sourceSplits.splice(index - 1, 2, merged)
  }
  splits[region] = sourceSplits
  return validOrder(order) && validSplits(splits, order)
    ? { order: order, splits: splits } : null
}

function removeSlot(orderValue, splitsValue, regionValue) {
  var order = copyOrder(orderValue)
  var region = String(regionValue || "")
  if (!order || (region !== "left" && region !== "right")) return null
  for (var index = order[region].length - 1;
      index >= baseCount(region); index--) {
    if (order[region][index] === "")
      return removeSlotAt(orderValue, splitsValue, region, index)
  }
  return null
}

function removeEmptyExtraAt(orderValue, splitsValue, regionValue, indexValue) {
  return removeSlotAt(orderValue, splitsValue, regionValue, indexValue)
}

function removeDynamicGroup(orderValue, splitsValue, groupValue) {
  var order = copyOrder(orderValue)
  var splits = copySplits(splitsValue, orderValue)
  var groupId = String(groupValue || "")
  var location = locationFor(order, groupId)
  if (!order || !splits || !isDynamicGroupId(groupId) || !location) return null

  order[location.region][location.index] = ""
  if (location.index >= baseCount(location.region))
    return removeEmptyExtraAt(
      order, splits, location.region, location.index)

  // A dynamic group may have been swapped into a locked base slot. Move the
  // outer extra occupant into that empty base before shrinking the extra.
  var candidates = preferredOuterRegions(location.region, order)
  for (var outer = 0; outer < candidates.length; outer++) {
    var outerRegion = candidates[outer]
    for (var extraIndex = order[outerRegion].length - 1;
        extraIndex >= baseCount(outerRegion); extraIndex--) {
      if (order[outerRegion][extraIndex] === "") continue
      order[location.region][location.index] = order[outerRegion][extraIndex]
      order[outerRegion][extraIndex] = ""
      return removeEmptyExtraAt(order, splits, outerRegion, extraIndex)
    }
  }
  return null
}

function preferredOuterRegions(regionValue, orderValue) {
  var region = String(regionValue || "")
  if (region === "left") return ["left", "right"]
  if (region === "right") return ["right", "left"]
  return orderValue.left.length < orderValue.right.length
    ? ["left", "right"] : ["right", "left"]
}

function addDynamicGroup(orderValue, splitsValue, pluginValue, regionValue) {
  var order = copyOrder(orderValue)
  var splits = copySplits(splitsValue, orderValue)
  var groupId = dynamicGroupId(pluginValue)
  if (!order || !splits || groupId === "") return null
  if (locationFor(order, groupId)) return { order: order, splits: splits }

  var candidates = preferredOuterRegions(regionValue, order)
  for (var c = 0; c < candidates.length; c++) {
    var region = candidates[c]
    for (var index = baseCount(region); index < order[region].length; index++) {
      if (order[region][index] !== "") continue
      order[region][index] = groupId
      return validOrder(order) ? { order: order, splits: splits } : null
    }
    var expanded = addSlot(order, region)
    if (!expanded) continue
    var expandedSplits = resizeSplits(splits, expanded)
    expanded[region][expanded[region].length - 1] = groupId
    return validOrder(expanded) && validSplits(expandedSplits, expanded)
      ? { order: expanded, splits: expandedSplits } : null
  }
  return null
}

function normalizedPluginSpecs(value) {
  if (!Array.isArray(value)) return null
  var result = []
  var seen = {}
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

function reconcilePluginGroups(orderValue, splitsValue, specsValue) {
  var order = copyOrder(orderValue)
  var splits = copySplits(splitsValue, orderValue)
  var specs = normalizedPluginSpecs(specsValue)
  if (!order || !splits || !specs) return null
  var desired = {}
  for (var i = 0; i < specs.length; i++)
    desired[dynamicGroupId(specs[i].pluginId)] = specs[i]

  var stale = []
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    for (var index = 0; index < order[region].length; index++) {
      var groupId = String(order[region][index] || "")
      if (isDynamicGroupId(groupId) && !desired[groupId]) stale.push(groupId)
    }
  }
  for (var s = 0; s < stale.length; s++) {
    var removed = removeDynamicGroup(order, splits, stale[s])
    if (!removed) return null
    order = removed.order
    splits = removed.splits
  }

  var unplaced = []
  for (var p = 0; p < specs.length; p++) {
    var dynamicId = dynamicGroupId(specs[p].pluginId)
    if (locationFor(order, dynamicId)) continue
    var added = addDynamicGroup(
      order, splits, specs[p].pluginId, specs[p].region)
    if (!added) {
      unplaced.push(specs[p].pluginId)
      continue
    }
    order = added.order
    splits = added.splits
  }
  return { order: order, splits: splits, unplaced: unplaced }
}

function splitEnabled(value, regionValue, indexValue, orderValue) {
  if (!validSplits(value, orderValue)) return false
  var region = String(regionValue || "")
  var index = Number(indexValue)
  return SplitRegions.indexOf(region) >= 0
    && Number.isInteger(index) && index >= 0
    && index < value[region].length && value[region][index] === true
}

function toggleSplit(value, regionValue, indexValue, orderValue) {
  var result = copySplits(value, orderValue)
  var region = String(regionValue || "")
  var index = Number(indexValue)
  if (!result || SplitRegions.indexOf(region) < 0
      || !Number.isInteger(index) || index < 0
      || index >= result[region].length) return null
  result[region][index] = !result[region][index]
  return result
}

function allSplits(enabledValue, orderValue) {
  if (typeof enabledValue !== "boolean") return null
  var order = validOrder(orderValue) ? orderValue : defaultOrder()
  var result = { left: [], boundaries: [], right: [] }
  for (var r = 0; r < SplitRegions.length; r++) {
    var region = SplitRegions[r]
    for (var i = 0; i < expectedSplitLength(region, order); i++)
      result[region].push(enabledValue)
  }
  return result
}

function sameOrder(left, right) {
  if (!validOrder(left) || !validOrder(right)) return false
  for (var r = 0; r < Regions.length; r++) {
    var region = Regions[r]
    if (left[region].length !== right[region].length) return false
    for (var i = 0; i < left[region].length; i++) {
      if (left[region][i] !== right[region][i]) return false
    }
  }
  return true
}

function sameSplits(left, right, orderValue) {
  if (!validSplits(left, orderValue) || !validSplits(right, orderValue))
    return false
  for (var r = 0; r < SplitRegions.length; r++) {
    var region = SplitRegions[r]
    for (var i = 0; i < left[region].length; i++) {
      if (left[region][i] !== right[region][i]) return false
    }
  }
  return true
}
