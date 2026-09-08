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

function capabilitiesForPlugin(pluginValue, registry) {
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

function familyForCapability(capabilityValue) {
  var capability = String(capabilityValue || "").trim().toLowerCase()
  for (var i = 0; i < Families.length; i++) {
    if (Families[i].capabilities.indexOf(capability) >= 0) return Families[i]
  }
  return null
}

function familiesForPlugin(pluginValue, registry) {
  var capabilities = capabilitiesForPlugin(pluginValue, registry)
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

function familyForPlugin(pluginValue, registry) {
  var families = familiesForPlugin(pluginValue, registry)
  return families.length > 0 ? families[0] : null
}

function alternativesForFamily(family, registry) {
  if (!family) return []
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
    var capabilities = capabilitiesForPlugin(id, registry)
    var sharesCapability = capabilities.some(function(capability) {
      return family.capabilities.indexOf(capability) >= 0
    })
    if (sharesCapability && result.indexOf(id) < 0) result.push(id)
  }
  return result
}

function familyForGroup(groupValue, registry) {
  var groupId = String(groupValue || "")
  for (var i = 0; i < Families.length; i++) {
    if (Families[i].group === groupId) {
      var family = Families[i]
      return {
        capabilities: family.capabilities.slice(),
        group: family.group,
        shibumi: family.shibumi,
        alternatives: alternativesForFamily(family, registry),
        region: family.region
      }
    }
  }
  return null
}

// Reuse one displaced fixed V1 slot for a newly placed family provider.
// Existing dynamic placements remain authoritative: no saved order, split,
// slot limit or schema is migrated merely by loading this version.
function v1SlotBindings(specs, order, registry) {
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
    var families = familiesForPlugin(id, registry)
    for (var f = 0; f < families.length; f++) {
      var group = families[f].group
      if (!placed[group] || result[group]) continue
      result[group] = id
      break
    }
  }
  return result
}

function targetRegion(pluginValue, fallbackValue, registry) {
  var family = familyForPlugin(pluginValue, registry)
  if (family) return family.region
  var fallback = String(fallbackValue || "")
  return ["left", "center", "right"].indexOf(fallback) >= 0
    ? fallback : "right"
}

function replacementTargets(pluginValue, registry) {
  return familiesForPlugin(pluginValue, registry).map(function(family) {
    return family.shibumi
  })
}

function joinedLabels(values) {
  if (values.length < 2) return values.join("")
  if (values.length === 2) return values[0] + " and " + values[1]
  return values.slice(0, -1).join(", ") + ", and " + values[values.length - 1]
}

function replacementLabel(pluginValue, registry) {
  var targets = replacementTargets(pluginValue, registry)
  return targets.length > 0 ? "Replaces " + joinedLabels(targets) : ""
}
