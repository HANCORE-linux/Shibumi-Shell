.pragma library

var SchemaVersion = 1
var IdentityVersion = 3
var WorkspaceSchemaVersion = 1
var MaxWidgetCollectionItems = 128
var MaxWidgetObjectKeys = 128
var MaxWidgetStringLength = 4096
var PaletteIds = [
  "color01", "color02", "color03", "color04",
  "color05", "color06", "color07", "color08", "foreground"
]
var LegacyPaletteIds = [
  "red", "accent", "0", "1", "color1",
  "green", "color2", "yellow", "color3", "color8"
]
var GroupIds = [
  "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8",
  "G9", "G10", "G11", "G12", "G13", "G14", "G15",
  "G16", "G17", "G18"
]
var V1GroupIds = GroupIds.slice(0, 15)
var V1DynamicGroupPrefix = "G:"
var TemperatureSourceIds = ["cpu", "core", "gpu", "nvme", "memory"]
var TemperatureUnitIds = ["metric", "imperial"]

function defaultOrder() {
  return {
    left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
    center: ["G8"],
    right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
  }
}

function slotRolesForOrder(value) {
  var order = normalizedOrder(value) || defaultOrder()
  var result = { left: [], center: [], right: [] }
  var baseCounts = { left: 7, center: 1, right: 7 }
  for (var region in result) {
    for (var index = 0; index < order[region].length; index++)
      result[region].push(index < baseCounts[region] ? "base" : "extra")
  }
  return result
}

function defaultSplits(orderValue) {
  var order = normalizedOrder(orderValue) || defaultOrder()
  return {
    left: Array(Math.max(0, order.left.length - 1)).fill(false),
    boundaries: [false, false],
    right: Array(Math.max(0, order.right.length - 1)).fill(false)
  }
}

function defaultV2Layout() {
  return {
    left: ["G1", "G2", "G3", "", "G5", "G6", "G4", "G7", "", ""],
    center: ["G8"],
    right: [
      "G9", "G10", "G11", "G14", "G12", "G13", "G16",
      "G18", "G17", "G15", "", "", ""
    ]
  }
}

function defaultV2Boundaries() {
  return [false, false]
}

function defaultLayoutProtectionConfig() {
  return { v1: false, v2: false }
}

function defaultConfig() {
  return {
    version: SchemaVersion,
    identityVersion: IdentityVersion,
    order: defaultOrder(),
    v1SlotRoles: slotRolesForOrder(defaultOrder()),
    splits: defaultSplits(),
    v2Layout: defaultV2Layout(),
    v2Boundaries: defaultV2Boundaries(),
    layoutProtection: defaultLayoutProtectionConfig(),
    widgets: defaultWidgetConfig(),
    presentation: defaultPresentationConfig(),
    workspace: defaultWorkspaceConfig(),
    launcher: defaultLauncherConfig(),
    plugins: defaultPluginConfig(),
    picker: defaultPickerConfig(),
    reactor: defaultReactorConfig()
  }
}

function defaultWidgetConfig() {
  // Preserve the V1 defaults: optional AI, power-profile, and Bluetooth
  // groups start disabled until the user explicitly enables them.
  return {
    G7: { enabled: false },
    G14: { enabled: false },
    G15: { enabled: false },
    G16: { source: "cpu", unit: "metric" }
  }
}

function defaultPresentationConfig() {
  return {
    border: true,
    v1Border: true,
    v2Border: true,
    panelBorder: true,
    shadow: false,
    frost: false,
    radius: "large",
    accent: "color01",
    shellStyle: "shibumi",
    v2ShellStyle: "full"
  }
}

function defaultWorkspaceConfig() {
  return {
    version: WorkspaceSchemaVersion,
    mode: "10",
    style: "default"
  }
}

function defaultPluginConfig() {
  return { favorites: [] }
}

function defaultLauncherConfig() {
  return {
    mode: "text",
    text: "shibumi",
    icon: "omarchy"
  }
}

function defaultPickerConfig() {
  return {
    // `style` remains a compatibility alias for mixed-version deployments.
    style: "carousel",
    imageStyle: "omarchy",
    mediaStyle: "carousel"
  }
}

function defaultReactorConfig() {
  return { mode: 0 }
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function isV1DynamicGroupId(value) {
  var groupId = String(value || "")
  if (groupId.indexOf(V1DynamicGroupPrefix) !== 0) return false
  var pluginId = groupId.slice(V1DynamicGroupPrefix.length)
  return pluginId.length > 0 && pluginId.length <= 160
    && /^[a-z0-9][a-z0-9._-]*$/.test(pluginId)
}

function isGroupId(value) {
  var groupId = String(value || "")
  return GroupIds.indexOf(groupId) >= 0 || isV1DynamicGroupId(groupId)
}

function boolArray(value, length) {
  if (!Array.isArray(value) || value.length !== length) return null
  var result = []
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] !== "boolean") return null
    result.push(value[i])
  }
  return result
}

function normalizedOrder(value) {
  if (!isPlainObject(value)) return null
  if (!Array.isArray(value.left)
      || value.left.length < 7 || value.left.length > 9) return null
  if (!Array.isArray(value.center) || value.center.length !== 1) return null
  if (!Array.isArray(value.right)
      || value.right.length < 7 || value.right.length > 9) return null

  var combined = value.left.concat(value.center, value.right)
  var seen = {}
  var fixedCount = 0
  for (var i = 0; i < combined.length; i++) {
    var id = String(combined[i] || "")
    if (id === "") continue
    if ((V1GroupIds.indexOf(id) === -1 && !isV1DynamicGroupId(id))
        || seen[id]) return null
    seen[id] = true
    if (V1GroupIds.indexOf(id) >= 0) fixedCount++
  }
  if (fixedCount !== V1GroupIds.length) return null

  return {
    left: value.left.slice(),
    center: value.center.slice(),
    right: value.right.slice()
  }
}

function normalizedV1SlotRoles(value, orderValue) {
  var order = normalizedOrder(orderValue)
  if (!order) return null
  var expected = slotRolesForOrder(order)
  // Missing roles identify the legacy fixed-order format. The normalized
  // config writes the explicit role map on the first subsequent mutation.
  if (value === undefined || value === null) return expected
  if (!isPlainObject(value)) return null
  for (var region in expected) {
    if (!Array.isArray(value[region])
        || value[region].length !== expected[region].length) return null
    for (var index = 0; index < expected[region].length; index++) {
      if (String(value[region][index] || "") !== expected[region][index])
        return null
    }
  }
  return expected
}

function normalizedV2Layout(value) {
  if (!isPlainObject(value)) return null
  var limits = {
    left: { min: 10, max: 13 },
    center: { min: 1, max: 4 },
    right: { min: 7, max: 13 }
  }
  var result = { left: [], center: [], right: [] }
  var seen = {}
  for (var region in limits) {
    var entries = value[region]
    var limit = limits[region]
    if (!Array.isArray(entries)
        || entries.length < limit.min || entries.length > limit.max)
      return null
    for (var i = 0; i < entries.length; i++) {
      var id = String(entries[i] || "")
      if (id !== "" && (GroupIds.indexOf(id) < 0 || seen[id])) return null
      if (id !== "") seen[id] = true
      result[region].push(id)
    }
  }
  return Object.keys(seen).length === GroupIds.length ? result : null
}

function normalizedV2Boundaries(value) {
  return boolArray(value, 2)
}

function normalizedSplits(value, orderValue) {
  var order = normalizedOrder(orderValue)
  if (!isPlainObject(value) || !order) return null
  var left = boolArray(value.left, Math.max(0, order.left.length - 1))
  var boundaries = boolArray(value.boundaries, 2)
  var right = boolArray(value.right, Math.max(0, order.right.length - 1))
  if (!left || !boundaries || !right) return null
  return { left: left, boundaries: boundaries, right: right }
}

function safeScalar(value) {
  return value === null
    || typeof value === "boolean"
    || (typeof value === "number" && Number.isFinite(value))
    || (typeof value === "string" && value.length <= MaxWidgetStringLength)
}

function safeValue(value, depth) {
  if (depth > 4) return undefined
  if (safeScalar(value)) return value
  if (Array.isArray(value)) {
    if (value.length > MaxWidgetCollectionItems) return undefined
    var arrayResult = []
    for (var i = 0; i < value.length; i++) {
      var arrayValue = safeValue(value[i], depth + 1)
      if (arrayValue !== undefined) arrayResult.push(arrayValue)
    }
    return arrayResult
  }
  if (!isPlainObject(value)) return undefined

  var keys = Object.keys(value)
  if (keys.length > MaxWidgetObjectKeys) return undefined
  var objectResult = {}
  for (var k = 0; k < keys.length; k++) {
    var key = keys[k]
    if (key === "__proto__" || key === "prototype" || key === "constructor")
      return undefined
    var child = safeValue(value[key], depth + 1)
    if (child !== undefined) objectResult[key] = child
  }
  return objectResult
}

function normalizedWidgets(value) {
  if (!isPlainObject(value)) return {}
  var result = {}
  for (var key in value) {
    if (!isGroupId(key) || !isPlainObject(value[key])) continue
    var settings = safeValue(value[key], 0)
    if (settings !== undefined) result[key] = settings
  }
  return result
}

function mergeWidgetConfig(value) {
  var result = defaultWidgetConfig()
  var overrides = normalizedWidgets(value)
  for (var key in overrides) {
    var base = isPlainObject(result[key]) ? result[key] : {}
    var next = overrides[key]
    var merged = {}
    for (var baseKey in base) merged[baseKey] = base[baseKey]
    for (var overrideKey in next) merged[overrideKey] = next[overrideKey]
    result[key] = merged
  }
  if (!isPlainObject(result.G16)) result.G16 = {}
  if (TemperatureSourceIds.indexOf(String(result.G16.source || "")) < 0)
    result.G16.source = "cpu"
  if (TemperatureUnitIds.indexOf(String(result.G16.unit || "")) < 0)
    result.G16.unit = "metric"
  return result
}

function paletteIdValid(value) {
  var candidate = String(value || "").toLowerCase()
  return PaletteIds.indexOf(candidate) !== -1
    || LegacyPaletteIds.indexOf(candidate) !== -1
}

function normalizedPaletteId(value) {
  var candidate = String(value || "").toLowerCase()
  if (candidate === "red" || candidate === "accent"
      || candidate === "0" || candidate === "1"
      || candidate === "color1") return "color01"
  if (candidate === "green" || candidate === "color2") return "color02"
  if (candidate === "yellow" || candidate === "color3") return "color03"
  if (candidate === "color8") return "color08"
  return PaletteIds.indexOf(candidate) !== -1 ? candidate : "color01"
}

function normalizePresentation(value) {
  var result = defaultPresentationConfig()
  var v2Styles = ["full", "fit", "dock", "notch"]
  if (!isPlainObject(value)) return result
  if (typeof value.border === "boolean") result.border = value.border
  result.v1Border = typeof value.v1Border === "boolean"
    ? value.v1Border : result.border
  result.v2Border = typeof value.v2Border === "boolean"
    ? value.v2Border : result.border
  if (typeof value.panelBorder === "boolean")
    result.panelBorder = value.panelBorder
  if (typeof value.shadow === "boolean") result.shadow = value.shadow
  if (typeof value.frost === "boolean") result.frost = value.frost
  if (["large", "small"].indexOf(String(value.radius || "")) !== -1)
    result.radius = String(value.radius)
  if (paletteIdValid(value.accent))
    result.accent = normalizedPaletteId(value.accent)
  if (["shibumi", "full", "fit", "dock", "notch"]
      .indexOf(String(value.shellStyle || "")) !== -1)
    result.shellStyle = String(value.shellStyle)
  if (v2Styles.indexOf(String(value.v2ShellStyle || "")) !== -1)
    result.v2ShellStyle = String(value.v2ShellStyle)
  else if (v2Styles.indexOf(result.shellStyle) !== -1)
    result.v2ShellStyle = result.shellStyle
  return result
}

function normalizedDesktopIds(value) {
  if (!Array.isArray(value)) return []
  var result = []
  var seen = {}
  for (var i = 0; i < value.length && result.length < 128; i++) {
    var id = String(value[i] || "").trim()
    if (id.slice(-8).toLowerCase() === ".desktop") id = id.slice(0, -8)
    var key = "$" + id
    if (!id || id.length > 255 || /[\x00-\x1f\x7f/\\]/.test(id) || seen[key]) continue
    seen[key] = true
    result.push(id)
  }
  return result
}

function normalizedPluginIds(value) {
  if (!Array.isArray(value)) return []
  var result = []
  var seen = {}
  for (var i = 0; i < value.length && result.length < 256; i++) {
    var id = String(value[i] || "").trim()
    var key = "$" + id
    if (!id || id.length > 255 || /[\x00-\x1f\x7f/\\]/.test(id)
        || seen[key]) continue
    seen[key] = true
    result.push(id)
  }
  return result
}

function normalizePlugins(value) {
  var result = defaultPluginConfig()
  if (!isPlainObject(value)) return result
  result.favorites = normalizedPluginIds(value.favorites)
  return result
}

function normalizeLauncher(value) {
  var result = defaultLauncherConfig()
  if (!isPlainObject(value)) return result
  if (["text", "icon"].indexOf(String(value.mode || "")) !== -1)
      result.mode = String(value.mode)
    if (["shibumi", "omarchy", "hyprland", "arch", "omacom"]
        .indexOf(String(value.text || "")) !== -1)
      result.text = String(value.text)
    if (["shibumi", "omarchy", "hyprland", "arch", "grid", "spark", "power",
         "dragon", "mark", "nix", "branch", "rebel"]
        .indexOf(String(value.icon || "")) !== -1)
      result.icon = String(value.icon)
  return result
}

function normalizeWorkspace(value) {
  var result = defaultWorkspaceConfig()
  if (!isPlainObject(value)
      || Number(value.version) !== WorkspaceSchemaVersion) return result
  if (["10", "5", "active"].indexOf(String(value.mode || "")) !== -1)
    result.mode = String(value.mode)
  var style = String(value.style || "")
  // Pre-alpha Shibumi briefly exposed two names that never existed in the
  // QS Rise contract. Preserve their visual intent while returning to the
  // canonical V2 tokens.
  if (style === "frame") style = "rings"
  if (style === "aurora-streak") style = "aurora"
  if (["default", "numbers", "magic", "kanji", "rings", "aurora", "pacman"]
      .indexOf(style) !== -1)
    result.style = style
  return result
}

function normalizePicker(value) {
  var result = defaultPickerConfig()
  if (!isPlainObject(value)) return result

  var legacyCandidate = String(value.style || "")
  if (legacyCandidate === "default") legacyCandidate = "carousel"
  var legacyStyle = ["tanzaku", "hearthstone", "carousel"].indexOf(
    legacyCandidate) >= 0 ? legacyCandidate : ""
  var imageStyle = String(value.imageStyle || legacyStyle || result.imageStyle)
  var mediaStyle = String(value.mediaStyle || legacyStyle || result.mediaStyle)

  // Carousel is the stock Omarchy experience for themes and wallpapers.
  // Pre-release Shibumi configs used the same name for a separate image view;
  // migrate those configs instead of retaining a hidden fourth UI state.
  if (imageStyle === "default" || imageStyle === "carousel") imageStyle = "omarchy"
  if (mediaStyle === "default") mediaStyle = "carousel"
  if (["omarchy", "tanzaku", "hearthstone"].indexOf(imageStyle) >= 0)
    result.imageStyle = imageStyle
  if (["tanzaku", "hearthstone", "carousel"].indexOf(mediaStyle) >= 0)
    result.mediaStyle = mediaStyle
  result.style = result.mediaStyle
  return result
}

function normalizeReactor(value) {
  var result = defaultReactorConfig()
  if (!isPlainObject(value)) return result
  var mode = Number(value.mode)
  if (Number.isInteger(mode) && mode >= 0 && mode <= 8)
    result.mode = mode
  return result
}

function normalizeLayoutProtection(value) {
  var result = defaultLayoutProtectionConfig()
  if (!isPlainObject(value)) return result
  if (typeof value.v1 === "boolean") result.v1 = value.v1
  if (typeof value.v2 === "boolean") result.v2 = value.v2
  return result
}

function normalize(value) {
  var result = defaultConfig()
  if (!isPlainObject(value) || Number(value.version) !== SchemaVersion) return result

  var order = normalizedOrder(value.order)
  var roles = order ? normalizedV1SlotRoles(value.v1SlotRoles, order) : null
  var splits = order ? normalizedSplits(value.splits, order) : null
  var v2Layout = normalizedV2Layout(value.v2Layout)
  var v2Boundaries = normalizedV2Boundaries(value.v2Boundaries)
  // V1 layout state is one transaction: invalid/partial order, roles, or
  // split lengths fall back together instead of publishing mixed geometry.
  if (order && roles && splits) {
    result.order = order
    result.v1SlotRoles = roles
    result.splits = splits
  }
  if (v2Layout) result.v2Layout = v2Layout
  if (v2Boundaries) result.v2Boundaries = v2Boundaries
  result.layoutProtection = normalizeLayoutProtection(value.layoutProtection)
  result.widgets = mergeWidgetConfig(value.widgets)
  result.presentation = normalizePresentation(value.presentation)
  result.workspace = normalizeWorkspace(value.workspace)
  var launcherSource = value.launcher
  if (!isPlainObject(launcherSource) && isPlainObject(value.menu))
    launcherSource = value.menu.launcher
  result.launcher = normalizeLauncher(launcherSource)
  result.plugins = normalizePlugins(value.plugins)
  // Initial pre-release Shibumi payloads inherited the predecessor's Omarchy
  // wordmark. Migrate that one default once, while retaining Omarchy as an
  // explicit choice after the identity contract has been recorded.
  if (Number(value.identityVersion || 0) < 2
      && result.launcher.text === "omarchy")
    result.launcher.text = "shibumi"
  result.picker = normalizePicker(value.picker)
  result.reactor = normalizeReactor(value.reactor)
  return result
}
