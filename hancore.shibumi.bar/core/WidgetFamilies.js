.pragma library

// A Quattro manifest can prevent duplicate instances of its own ID, but it
// cannot know that a Shibumi composite already owns the same user-facing
// capability. Keep those cross-provider relationships explicit and small.
var Families = [
  {
    capabilities: ["workspaces"],
    group: "G2",
    shibumi: "Shibumi Workspaces",
    alternatives: ["omarchy.workspaces"],
    region: "left"
  },
  {
    capabilities: ["indicators", "notifications", "tray"],
    group: "G3",
    shibumi: "Shibumi Status",
    // omarchy.notifications is a keepLoaded service without a barWidget
    // entry point. Shibumi Status consumes that service; only presentation
    // providers belong in this mutually exclusive widget family.
    alternatives: ["omarchy.indicators", "omarchy.tray"],
    region: "left"
  },
  {
    capabilities: ["audio"],
    group: "G6",
    shibumi: "Shibumi Audio",
    alternatives: ["omarchy.audio"],
    region: "left"
  },
  {
    capabilities: ["model-usage"],
    group: "G7",
    shibumi: "Shibumi AI Usage",
    alternatives: ["omarchy.agents", "omarchy.model-usage"],
    region: "left"
  },
  {
    capabilities: ["clock", "weather", "system-update"],
    group: "G8",
    shibumi: "Shibumi Center",
    alternatives: [
      "omarchy.clock", "omarchy.weather", "omarchy.system-update"
    ],
    region: "center"
  },
  {
    capabilities: ["media"],
    group: "G9",
    shibumi: "Shibumi Media",
    alternatives: ["omarchy.media"],
    region: "right"
  },
  {
    capabilities: ["network"],
    group: "G11",
    shibumi: "Shibumi Network",
    alternatives: ["omarchy.network"],
    region: "right"
  },
  {
    capabilities: ["battery"],
    group: "G12",
    shibumi: "Shibumi Battery",
    alternatives: ["omarchy.power"],
    region: "right"
  },
  {
    capabilities: ["display"],
    group: "G13",
    shibumi: "Shibumi Display",
    alternatives: ["omarchy.monitor"],
    region: "right"
  },
  {
    capabilities: ["power-profile"],
    group: "G14",
    shibumi: "Shibumi Power Profile",
    alternatives: ["omarchy.power"],
    region: "right"
  },
  {
    capabilities: ["bluetooth"],
    group: "G15",
    shibumi: "Shibumi Bluetooth",
    alternatives: ["omarchy.bluetooth"],
    region: "right"
  }
]

var KnownCapabilities = {
  "omarchy.workspaces": ["workspaces"],
  "omarchy.indicators": ["indicators"],
  "omarchy.tray": ["tray"],
  "omarchy.audio": ["audio"],
  "omarchy.agents": ["model-usage"],
  "omarchy.model-usage": ["model-usage"],
  "omarchy.clock": ["clock"],
  "omarchy.weather": ["weather"],
  "omarchy.system-update": ["system-update"],
  "omarchy.media": ["media"],
  "omarchy.network": ["network"],
  "omarchy.power": ["battery", "power-profile"],
  "omarchy.monitor": ["display"],
  "omarchy.bluetooth": ["bluetooth"]
}

function stringList(value) {
  if (!Array.isArray(value)) return []
  var result = []
  for (var i = 0; i < value.length; i++) {
    var item = String(value[i] || "").trim().toLowerCase()
    if (item && result.indexOf(item) < 0) result.push(item)
  }
  return result
}

function manifestFor(pluginId, registry) {
  var installed = registry && registry.installedPlugins
    ? registry.installedPlugins : null
  return installed && Object.prototype.hasOwnProperty.call(installed, pluginId)
    ? installed[pluginId] || null : null
}

function declaredCapabilities(manifest) {
  var shibumi = manifest && manifest["x-shibumi"]
    ? manifest["x-shibumi"] : null
  var declared = shibumi ? stringList(shibumi.capabilities) : []
  if (declared.length > 0) return declared
  var barWidget = manifest && manifest.barWidget ? manifest.barWidget : null
  declared = barWidget ? stringList(barWidget.semanticCapabilities) : []
  if (declared.length > 0) return declared
  var single = barWidget ? String(barWidget.semanticRole || "")
    .trim().toLowerCase() : ""
  return single ? [single] : []
}

function legacyCapabilitiesForPlugin(pluginValue, registry) {
  var id = String(pluginValue || "")
  var seen = Object.create(null)
  // Native clones need not declare Shibumi semantics of their own. Inherit
  // only through exact installed source IDs, with bounded/cycle-safe lookup.
  for (var depth = 0; depth < 32; depth++) {
    if (!id || seen[id]) return []
    seen[id] = true
    var known = Object.prototype.hasOwnProperty.call(KnownCapabilities, id)
      ? KnownCapabilities[id] : null
    if (known) return known.slice()
    var manifest = manifestFor(id, registry)
    if (!manifest) return []
    var declared = declaredCapabilities(manifest)
    if (declared.length > 0) return declared
    var metadata = manifest.omarchy
    var source = metadata ? String(metadata.clonedFrom || "") : ""
    if (!source || !manifestFor(source, registry)) return []
    id = source
  }
  return []
}

function catalogId(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 160
    && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value) && !/\.\./.test(value)
}

function scopedSnapshot(observation) {
  try {
    if (!observation || typeof observation !== "object"
        || !Object.isFrozen(observation)
        || (Object.getPrototypeOf(observation) !== Object.prototype
          && Object.getPrototypeOf(observation) !== null)
        || !Object.prototype.hasOwnProperty.call(observation, "serial")
        || !Object.prototype.hasOwnProperty.call(observation, "generation")
        || !Object.prototype.hasOwnProperty.call(observation, "snapshot")
        || !Number.isInteger(observation.serial) || observation.serial <= 0
        || !Number.isInteger(observation.generation) || observation.generation <= 0)
      return null
    var snapshot = observation.snapshot
    if (!snapshot || typeof snapshot !== "object" || !Object.isFrozen(snapshot)
        || (Object.getPrototypeOf(snapshot) !== Object.prototype
          && Object.getPrototypeOf(snapshot) !== null)
        || !Object.prototype.hasOwnProperty.call(snapshot, "catalogKind")
        || !Object.prototype.hasOwnProperty.call(snapshot, "entries")
        || !Object.prototype.hasOwnProperty.call(snapshot, "byId")
        || snapshot.catalogKind !== "native-listPlugins"
        || !Array.isArray(snapshot.entries) || !Object.isFrozen(snapshot.entries)
        || !snapshot.byId || typeof snapshot.byId !== "object"
        || !Object.isFrozen(snapshot.byId)
        || Object.getPrototypeOf(snapshot.byId) !== null
        || Object.keys(snapshot.byId).length !== snapshot.entries.length) return null
    var seen = Object.create(null)
    for (var i = 0; i < snapshot.entries.length; i++) {
      var row = snapshot.entries[i]
      if (!row || typeof row !== "object" || !Object.isFrozen(row)
          || (Object.getPrototypeOf(row) !== Object.prototype
            && Object.getPrototypeOf(row) !== null)
          || !Object.prototype.hasOwnProperty.call(row, "id")
          || !Object.prototype.hasOwnProperty.call(row, "enabled")
          || !Object.prototype.hasOwnProperty.call(row, "clonedFrom")
          || !catalogId(row.id) || Object.prototype.hasOwnProperty.call(seen, row.id)
          || typeof row.enabled !== "boolean"
          || !(row.clonedFrom === "" || catalogId(row.clonedFrom))
          || !Object.prototype.hasOwnProperty.call(snapshot.byId, row.id)
          || snapshot.byId[row.id] !== row) return null
      seen[row.id] = true
    }
    return snapshot
  } catch (error) { return null }
}

function scopedCapabilitiesForPlugin(pluginValue, observation) {
  var id = String(pluginValue || "")
  var snapshot = scopedSnapshot(observation)
  if (!snapshot || !catalogId(id)
      || !Object.prototype.hasOwnProperty.call(snapshot.byId, id)) return []

  // Native enablement can restore an original by deleting its direct clone.
  // When such a clone is enabled, classifying the original would authorize the
  // wrong render/enable identity. The clone itself remains the render ID.
  for (var rowIndex = 0; rowIndex < snapshot.entries.length; rowIndex++) {
    var directClone = snapshot.entries[rowIndex]
    if (directClone.clonedFrom === id && directClone.enabled) return []
  }

  var seen = Object.create(null)
  var next = id
  var resolved = null
  for (var depth = 0; depth < 32; depth++) {
    if (!Object.prototype.hasOwnProperty.call(snapshot.byId, next)
        || Object.prototype.hasOwnProperty.call(seen, next)) return []
    var row = snapshot.byId[next]
    seen[next] = true
    if (Object.prototype.hasOwnProperty.call(KnownCapabilities, row.id)) {
      var known = KnownCapabilities[row.id].slice().sort()
      if (resolved !== null
          && JSON.stringify(resolved) !== JSON.stringify(known)) return []
      resolved = known
    }
    if (row.clonedFrom === "") return resolved === null ? [] : resolved.slice()
    next = row.clonedFrom
  }
  return []
}

function capabilitiesForPlugin(pluginValue, registry, observation, scoped) {
  return scoped === true
    ? scopedCapabilitiesForPlugin(pluginValue, observation)
    : legacyCapabilitiesForPlugin(pluginValue, registry)
}

function familyForCapability(capabilityValue) {
  var capability = String(capabilityValue || "").trim().toLowerCase()
  for (var i = 0; i < Families.length; i++) {
    if (Families[i].capabilities.indexOf(capability) >= 0) return Families[i]
  }
  return null
}

function familiesForPlugin(pluginValue, registry, observation, scoped) {
  var capabilities = capabilitiesForPlugin(
    pluginValue, registry, observation, scoped)
  var result = []
  for (var i = 0; i < capabilities.length; i++) {
    var family = familyForCapability(capabilities[i])
    if (!family) continue
    var duplicate = result.some(function(candidate) {
      return candidate.group === family.group
    })
    if (!duplicate) result.push(family)
  }
  return result
}

function familyForPlugin(pluginValue, registry, observation, scoped) {
  var families = familiesForPlugin(pluginValue, registry, observation, scoped)
  return families.length > 0 ? families[0] : null
}

function alternativesForFamily(family, registry, observation, scoped) {
  if (!family) return []
  if (scoped === true) {
    var snapshot = scopedSnapshot(observation)
    if (!snapshot) return []
    var scopedResult = []
    for (var entryIndex = 0; entryIndex < snapshot.entries.length; entryIndex++) {
      var scopedId = snapshot.entries[entryIndex].id
      var scopedCapabilities = scopedCapabilitiesForPlugin(scopedId, observation)
      var scopedMatch = scopedCapabilities.some(function(capability) {
        return family.capabilities.indexOf(capability) >= 0
      })
      if (scopedMatch && scopedResult.indexOf(scopedId) < 0)
        scopedResult.push(scopedId)
    }
    return scopedResult
  }
  var result = family.alternatives.slice()
  var installed = registry && registry.installedPlugins
    ? registry.installedPlugins : null
  if (!installed) return result
  var ids = Object.keys(installed)
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i]
    var manifest = installed[id] || {}
    var shibumi = manifest["x-shibumi"] || {}
    if (String(shibumi.suiteId || "") === "hancore.shibumi") continue
    var capabilities = capabilitiesForPlugin(id, registry, null, false)
    var sharesCapability = capabilities.some(function(capability) {
      return family.capabilities.indexOf(capability) >= 0
    })
    if (sharesCapability && result.indexOf(id) < 0) result.push(id)
  }
  return result
}

function familyForGroup(groupValue, registry, observation, scoped) {
  if (scoped === true && !scopedSnapshot(observation)) return null
  var groupId = String(groupValue || "")
  for (var i = 0; i < Families.length; i++) {
    if (Families[i].group === groupId) {
      var family = Families[i]
      return {
        capabilities: family.capabilities.slice(),
        group: family.group,
        shibumi: family.shibumi,
        alternatives: alternativesForFamily(
          family, registry, observation, scoped),
        region: family.region
      }
    }
  }
  return null
}

// Reuse one displaced fixed V1 slot for a newly placed family provider.
// Existing dynamic placements remain authoritative: no saved order, split,
// slot limit or schema is migrated merely by loading this version.
function v1SlotBindings(specs, order, registry, observation, scoped) {
  var result = Object.create(null)
  if (!Array.isArray(specs) || !order) return result
  var placed = Object.create(null)
  for (var r = 0; r < 3; r++) {
    var entries = order[["left", "center", "right"][r]]
    if (!Array.isArray(entries)) return Object.create(null)
    for (var i = 0; i < entries.length; i++) placed[entries[i]] = true
  }
  var seen = Object.create(null)
  for (var s = 0; s < specs.length; s++) {
    var spec = specs[s]
    if (!spec || typeof spec.pluginId !== "string") continue
    var id = spec.pluginId
    if (!id || id.length > 160 || !/^[a-z0-9][a-z0-9._-]*$/.test(id)
        || placed["G:" + id] || seen[id]) continue
    seen[id] = true
    var families = familiesForPlugin(id, registry, observation, scoped)
    for (var f = 0; f < families.length; f++) {
      var group = families[f].group
      if (!placed[group] || result[group]) continue
      result[group] = id
      break
    }
  }
  return result
}

function targetRegion(pluginValue, fallbackValue, registry, observation, scoped) {
  var family = familyForPlugin(pluginValue, registry, observation, scoped)
  if (family) return family.region
  var fallback = String(fallbackValue || "")
  return ["left", "center", "right"].indexOf(fallback) >= 0
    ? fallback : "right"
}

function replacementTargets(pluginValue, registry, observation, scoped) {
  return familiesForPlugin(pluginValue, registry, observation, scoped).map(function(family) {
    return family.shibumi
  })
}

function joinedLabels(values) {
  if (values.length < 2) return values.join("")
  if (values.length === 2) return values[0] + " and " + values[1]
  return values.slice(0, -1).join(", ") + ", and " + values[values.length - 1]
}

function replacementLabel(pluginValue, registry, observation, scoped) {
  var targets = replacementTargets(pluginValue, registry, observation, scoped)
  return targets.length > 0 ? "Replaces " + joinedLabels(targets) : ""
}
