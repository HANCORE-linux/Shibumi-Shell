.pragma library

var GroupIds = [
  "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8",
  "G9", "G10", "G11", "G12", "G13", "G14", "G15",
  "G16", "G17", "G18"
]

var BaseEntries = {
  G1: ["hancore.shibumi.control-center"],
  G2: ["hancore.shibumi.workspaces"],
  G3: ["hancore.shibumi.status"],
  G4: ["hancore.shibumi.memory"],
  G5: ["hancore.shibumi.cpu"],
  G6: ["hancore.shibumi.audio"],
  G7: ["hancore.shibumi.ai"],
  G8: ["hancore.shibumi.center"],
  G9: ["hancore.shibumi.media"],
  G10: ["hancore.shibumi.quick-access"],
  G11: ["hancore.shibumi.network"],
  G12: ["hancore.shibumi.battery"],
  G13: ["hancore.shibumi.brightness"],
  G14: ["hancore.shibumi.power-profile"],
  G15: ["hancore.shibumi.bluetooth"],
  G16: ["hancore.shibumi.temperature"],
  G17: ["hancore.shibumi.gpu"],
  G18: ["hancore.shibumi.storage"]
}

var OptionalGroups = {
  "omarchy.dropbox": "G3",
  "omarchy.microphone": "G6",
  "omarchy.active-window": "G8",
  "omarchy.keyboard-layout": "G8",
  "omarchy.tailscale": "G11"
}

// Official Omarchy entries represented by Shibumi composites stay hidden
// unless the user explicitly installs the original as a Shibumi module.
var ConsumedAliases = [
  "omarchy.menu",
  "omarchy.workspaces",
  "omarchy.agents",
  "omarchy.model-usage",
  "omarchy.audio",
  "omarchy.media",
  "omarchy.system-update",
  "omarchy.tray",
  "omarchy.notifications",
  "omarchy.network",
  "omarchy.monitor",
  "omarchy.bluetooth",
  "omarchy.power",
  "omarchy.weather",
  "omarchy.clock",
  "omarchy.indicators"
]
var Regions = ["left", "center", "right"]
var DynamicGroupPrefix = "G:"

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  return isObject(entry) ? String(entry.id || "") : ""
}

function validPluginId(value) {
  var id = String(value || "")
  return id.length > 0 && id.length <= 160
    && /^[a-z0-9][a-z0-9._-]*$/.test(id)
}

function dynamicGroupIdForModule(moduleValue) {
  var moduleId = String(moduleValue || "")
  return validPluginId(moduleId) ? DynamicGroupPrefix + moduleId : ""
}

function dynamicModuleIdForGroup(groupValue) {
  var groupId = String(groupValue || "")
  if (groupId.indexOf(DynamicGroupPrefix) !== 0) return ""
  var moduleId = groupId.slice(DynamicGroupPrefix.length)
  return validPluginId(moduleId) ? moduleId : ""
}

function copySettings(value) {
  if (!isObject(value)) return {}
  var result = {}
  for (var key in value) {
    if (key !== "id") result[key] = value[key]
  }
  return result
}

function copyGroupModuleSettings(value) {
  var result = copySettings(value)
  // Group activation is owned by GroupSlot and is variant-aware. Forwarding
  // the legacy group-level `enabled` flag to WidgetSlot would disable the
  // inner loader even when enabledV1/enabledV2 activates the group.
  delete result.enabled
  delete result.enabledV1
  delete result.enabledV2
  return result
}

function configuredEntries(layout) {
  var result = []
  var source = isObject(layout) ? layout : {}
  for (var r = 0; r < Regions.length; r++) {
    var entries = Array.isArray(source[Regions[r]]) ? source[Regions[r]] : []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (id) result.push({ id: id, entry: entries[i], region: Regions[r] })
    }
  }
  return result
}

function configuredEntry(layout, moduleId) {
  var configured = configuredEntries(layout)
  for (var i = 0; i < configured.length; i++) {
    if (configured[i].id === moduleId) return configured[i].entry
  }
  return null
}

function groupSettings(groupValue, moduleId, moduleCount) {
  if (!isObject(groupValue)) return {}
  if (moduleId === "hancore.shibumi.center")
    return copyGroupModuleSettings(groupValue)
  if (moduleId === "hancore.shibumi.audio"
      || moduleId === "hancore.shibumi.network") {
    if (isObject(groupValue[moduleId])) return copySettings(groupValue[moduleId])
    return copyGroupModuleSettings(groupValue)
  }
  if (moduleCount === 1) return copyGroupModuleSettings(groupValue)
  return copySettings(groupValue[moduleId])
}

function childSettingsFor(groupValue, layout, moduleId) {
  var result = copySettings(configuredEntry(layout, moduleId))
  var local = isObject(groupValue) ? copySettings(groupValue[moduleId]) : {}
  for (var key in local) result[key] = local[key]
  return result
}

function mergeEntry(moduleId, hostEntry, overrides) {
  var result = { id: moduleId }
  var host = copySettings(hostEntry)
  var local = copySettings(overrides)
  for (var hostKey in host) result[hostKey] = host[hostKey]
  for (var localKey in local) result[localKey] = local[localKey]
  return result
}

function moduleIdsFor(groupValue, layout) {
  var groupId = String(groupValue || "")
  var dynamicModule = dynamicModuleIdForGroup(groupId)
  if (dynamicModule !== "")
    return configuredEntry(layout, dynamicModule) !== null
      ? [dynamicModule] : []
  if (GroupIds.indexOf(groupId) < 0) return []
  var result = (BaseEntries[groupId] || []).slice()
  var configured = configuredEntries(layout)
  var explicitlyInstalled = {}
  for (var i = 0; i < configured.length; i++) {
    if (isObject(configured[i].entry)
        && configured[i].entry.shibumiModule === true)
      explicitlyInstalled[configured[i].id] = true
  }
  for (var j = 0; j < configured.length; j++) {
    var optionalId = configured[j].id
    if (OptionalGroups[optionalId] === groupId
        && explicitlyInstalled[optionalId] !== true
        && result.indexOf(optionalId) < 0) result.push(optionalId)
  }
  return result
}

function entriesFor(groupValue, groupValueSettings, layout) {
  var ids = moduleIdsFor(groupValue, layout)
  var result = []
  for (var i = 0; i < ids.length; i++) {
    result.push(entryFor(groupValue, ids[i], groupValueSettings, layout))
  }
  return result
}

function entryFor(groupValue, moduleValue, groupValueSettings, layout) {
  var id = String(moduleValue || "")
  var ids = moduleIdsFor(groupValue, layout)
  if (!id || ids.indexOf(id) < 0) return { id: id }
  return mergeEntry(id, configuredEntry(layout, id),
    groupSettings(groupValueSettings, id, ids.length))
}

// WidgetSlot needs explicit host and group-local layers so an inline host-state
// write can preserve equal-valued overrides and survive consecutive updates.
function hostEntryFor(moduleValue, layout) {
  var id = String(moduleValue || "")
  var entry = configuredEntry(layout, id)
  return entry !== null ? entry : { id: id }
}

function settingsOverridesFor(groupValue, moduleValue, groupValueSettings,
    layout) {
  var id = String(moduleValue || "")
  var ids = moduleIdsFor(groupValue, layout)
  return groupSettings(groupValueSettings, id, ids.length)
}

function assignedModuleIds() {
  var result = []
  for (var i = 0; i < GroupIds.length; i++) {
    var entries = BaseEntries[GroupIds[i]] || []
    for (var j = 0; j < entries.length; j++) {
      if (result.indexOf(entries[j]) < 0) result.push(entries[j])
    }
  }
  for (var optionalId in OptionalGroups) {
    if (result.indexOf(optionalId) < 0) result.push(optionalId)
  }
  return result
}

function isOptionalModule(moduleValue) {
  return Object.prototype.hasOwnProperty.call(
    OptionalGroups, String(moduleValue || ""))
}

function isAssignedModule(moduleValue) {
  var moduleId = String(moduleValue || "")
  return assignedModuleIds().indexOf(moduleId) >= 0
    || ConsumedAliases.indexOf(moduleId) >= 0
}

function unassignedEntries(layout, regionValue) {
  var region = String(regionValue || "")
  if (Regions.indexOf(region) < 0 || !isObject(layout)
      || !Array.isArray(layout[region])) return []
  var result = []
  for (var i = 0; i < layout[region].length; i++) {
    var entry = layout[region][i]
    var moduleId = entryId(entry)
    var explicitlyInstalled = isObject(entry)
      && entry.shibumiModule === true
    if (!isAssignedModule(moduleId) || explicitlyInstalled)
      result.push(entry)
  }
  return result
}
