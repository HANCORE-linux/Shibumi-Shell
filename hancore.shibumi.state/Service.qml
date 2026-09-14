pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "ShibumiConfig.js" as ShibumiConfig
import "StateStorageModel.js" as StorageModel
import "runtime" as SuiteRuntime

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.state"
    implementationVersion: "0.1.1-beta.14"
    owner: root
    host: root.shell
    manifest: root.manifest
  }
  readonly property string suiteMarkerPath: {
    const url = String(Qt.resolvedUrl(".shibumi-managed.json"))
    if (url.indexOf("file:///") !== 0) return ""
    // FileView takes a filesystem path, not a percent-encoded QML URL.
    try { return decodeURIComponent(url.substring(7)) } catch (error) { return "" }
  }
  property string suitePayloadDigest: ""
  property bool suitePayloadLoaded: false

  readonly property int contractVersion: 1
  readonly property bool ready: storage.ready
  readonly property var sourceConfig: storage.value
  readonly property bool writePending: storage.pending
  readonly property string writeStatus: storage.writeStatus
  readonly property int writeSerial: storage.requestSerial
  signal persistenceSettled(int throughSerial, string result)
  StateStorage {
    id: storage
    host: root.shell
    authorityToken: runtimeProvider.lease
    enabled: runtimeProvider.registered && root.omarchyPath !== ""
    omarchyPath: root.omarchyPath
    onSettled: function(throughSerial, result) { root.persistenceSettled(throughSerial, result) }
  }

  property var config: ShibumiConfig.defaultConfig()
  property int revision: 0

  readonly property string selectedAccent: palette.selectedId
  readonly property color color01: palette.color01
  readonly property color color02: palette.color02
  readonly property color color03: palette.color03
  readonly property color color04: palette.color04
  readonly property color color05: palette.color05
  readonly property color color06: palette.color06
  readonly property color color07: palette.color07
  readonly property color color08: palette.color08
  readonly property color foregroundSoft: palette.foregroundSoft
  readonly property color selectedColor: palette.selectedColor

  function same(left, right) {
    return StorageModel.same(left, right)
  }

  function captureSuiteMarker(raw) {
    suitePayloadDigest = ""
    suitePayloadLoaded = false
    try {
      const marker = JSON.parse(String(raw || ""))
      const digest = String(marker.suitePayloadDigest || "")
      if (marker.suiteId === "hancore.shibumi"
          && /^[0-9a-f]{64}$/.test(digest)) {
        suitePayloadDigest = digest
        suitePayloadLoaded = true
      }
    } catch (error) {}
  }

  function applySourceConfig(value) {
    const normalized = ShibumiConfig.normalize(value)
    if (same(config, normalized)) return false
    config = normalized
    revision++
    return true
  }

  function commit(mutator) {
    if (!ready || typeof mutator !== "function") return false

    const current = storage.draft()
    const next = JSON.parse(JSON.stringify(current))
    if (mutator(next) === false || !StorageModel.finiteNumbers(next)) return false
    const normalized = ShibumiConfig.normalize(next)
    if (same(current, normalized)) return false

    // A queued request is not a completed save. Publication and settled status
    // come exclusively from file readback, never from the Bar or API return.
    return storage.queue(normalized)
  }

  function groupSettings(groupId) {
    const group = String(groupId || "")
    if (!ShibumiConfig.isGroupId(group)) return ({})
    return config && config.widgets && ShibumiConfig.isPlainObject(config.widgets[group])
      ? config.widgets[group] : ({})
  }

  function groupSetting(groupId, key, fallback) {
    const settings = groupSettings(groupId)
    const name = String(key || "")
    return name && Object.prototype.hasOwnProperty.call(settings, name)
      ? settings[name] : fallback
  }

  readonly property var appearanceKeys: [
    "displayMode", "compact", "mediaStyle", "color", "colorMode", "tone",
    "widgetBorder", "widgetBorderWidth",
    "widgetBorderColor", "widgetBorderUsesSurfaceColor", "widgetPadding",
    "widgetRadius", "surfaceOpacity"
  ]
  readonly property var v1ExtensionAppearanceGroupIds: [
    "G:hancore.shibumi.temperature",
    "G:hancore.shibumi.gpu",
    "G:hancore.shibumi.storage"
  ]

  function normalizedVariant(value) {
    return String(value || "").toLowerCase() === "v2" ? "v2" : "v1"
  }

  function defaultAppearanceProfileForVariant(variantValue) {
    // V1 and V2 expose different labels and capabilities, while their current
    // canonical persisted defaults intentionally share these neutral values.
    void(variantValue)
    return {
      displayMode: "full", compact: false, mediaStyle: "default",
      color: "inherit", colorMode: "fill", tone: "auto",
      widgetBorder: false, widgetBorderWidth: 1,
      widgetBorderColor: "inherit", widgetBorderUsesSurfaceColor: false,
      widgetPadding: "auto", widgetRadius: "auto", surfaceOpacity: 1
    }
  }

  function appearanceGroupSupportedForVariant(groupId, variantValue) {
    const group = String(groupId || "")
    const variant = normalizedVariant(variantValue)
    return ShibumiConfig.GroupIds.indexOf(group) >= 0
      || variant === "v1"
        && v1ExtensionAppearanceGroupIds.indexOf(group) >= 0
  }

  function appearanceProfile(settings, variantValue) {
    const appearance = settings && ShibumiConfig.isPlainObject(
      settings.appearance) ? settings.appearance : ({})
    const variant = normalizedVariant(variantValue)
    return ShibumiConfig.isPlainObject(appearance[variant])
      ? appearance[variant] : ({})
  }

  function normalizedDisplayMode(groupId, variantValue, value) {
    const group = String(groupId || "")
    const variant = normalizedVariant(variantValue)
    const mode = String(value || "full")
    if (variant === "v2")
      return ["full", "icon", "text"].indexOf(mode) >= 0 ? mode : "full"
    const compactGroups = [
      "G4", "G5", "G6", "G11", "G12", "G13", "G14", "G15", "G18",
      "G:hancore.shibumi.storage"
    ]
    return compactGroups.indexOf(group) >= 0 && mode === "icon"
      ? "icon" : "full"
  }

  function groupAppearanceSettingForVariant(groupId, variantValue, key, fallback) {
    const settings = groupSettings(groupId)
    const name = String(key || "")
    const variant = normalizedVariant(variantValue)
    const profile = appearanceProfile(settings, variant)
    let value = Object.prototype.hasOwnProperty.call(profile, name)
      ? profile[name]
      : Object.prototype.hasOwnProperty.call(settings, name)
        ? settings[name] : fallback
    if (name === "displayMode") {
      if (!Object.prototype.hasOwnProperty.call(profile, name)
          && !Object.prototype.hasOwnProperty.call(settings, name)
          && settings.compact === true)
        value = "icon"
      value = normalizedDisplayMode(groupId, variant, value)
    }
    if (name === "compact")
      value = normalizedDisplayMode(groupId, variant,
        groupAppearanceSettingForVariant(
          groupId, variant, "displayMode", "full")) === "icon"
    if (name === "mediaStyle") {
      if (!Object.prototype.hasOwnProperty.call(profile, name)
          && !Object.prototype.hasOwnProperty.call(settings, name)
          && settings.compact === true)
        value = "full"
      value = String(value || "default") === "full" ? "full" : "default"
    }
    return value
  }

  function groupSettingsForVariant(groupId, variantValue) {
    const settings = groupSettings(groupId)
    const effective = ({})
    for (const key in settings) {
      if (key !== "appearance") effective[key] = settings[key]
    }
    for (let index = 0; index < appearanceKeys.length; index++) {
      const key = appearanceKeys[index]
      effective[key] = groupAppearanceSettingForVariant(
        groupId, variantValue, key, effective[key])
    }
    return effective
  }

  function activeShellVariant() {
    const presentation = config && config.presentation
      ? config.presentation : ({})
    return String(presentation.shellStyle || "shibumi") === "shibumi"
      ? "v1" : "v2"
  }

  function groupEnabledForVariant(groupId, variantValue) {
    const settings = groupSettings(groupId)
    const variant = String(variantValue || "").toLowerCase()
    const key = variant === "v2" ? "enabledV2" : "enabledV1"
    if (Object.prototype.hasOwnProperty.call(settings, key))
      return settings[key] !== false
    return Object.prototype.hasOwnProperty.call(settings, "enabled")
      ? settings.enabled !== false : true
  }

  function groupEnabled(groupId) {
    return groupEnabledForVariant(groupId, activeShellVariant())
  }

  function setGroupEnabledForVariant(groupId, variantValue, enabled) {
    const group = String(groupId || "")
    const variant = String(variantValue || "").toLowerCase()
    if (!ShibumiConfig.isGroupId(group)
        || ["v1", "v2"].indexOf(variant) < 0
        || typeof enabled !== "boolean") return false
    const key = variant === "v2" ? "enabledV2" : "enabledV1"
    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const settings = ShibumiConfig.isPlainObject(next.widgets[group])
        ? next.widgets[group] : {}
      settings[key] = enabled
      next.widgets[group] = settings
    })
  }

  function setGroupVariantStates(stateValues) {
    if (!ShibumiConfig.isPlainObject(stateValues)) return false
    const groups = Object.keys(stateValues)
    if (groups.length === 0) return false
    for (let index = 0; index < groups.length; index++) {
      const group = groups[index]
      const states = stateValues[group]
      if (!ShibumiConfig.isGroupId(group)
          || !ShibumiConfig.isPlainObject(states)
          || typeof states.v1 !== "boolean"
          || typeof states.v2 !== "boolean") return false
    }
    return setLayoutFamilyTransition({familyStates: stateValues})
  }

  function setGroupsEnabledForAllVariants(groupValues, enabled) {
    if (!Array.isArray(groupValues) || typeof enabled !== "boolean")
      return false
    const states = {}
    for (let index = 0; index < groupValues.length; index++) {
      const group = String(groupValues[index] || "")
      if (!ShibumiConfig.isGroupId(group)) return false
      states[group] = { v1: enabled, v2: enabled }
    }
    return setGroupVariantStates(states)
  }

  function setGroupSetting(groupId, key, value) {
    const group = String(groupId || "")
    const name = String(key || "")
    if (!ShibumiConfig.isGroupId(group)
        || !/^[A-Za-z][A-Za-z0-9_-]*$/.test(name)) return false

    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const settings = ShibumiConfig.isPlainObject(next.widgets[group])
        ? next.widgets[group] : {}
      settings[name] = value
      next.widgets[group] = settings
    })
  }

  function setGroupAppearanceSettingForVariant(groupId, variantValue, key, value) {
    const group = String(groupId || "")
    const variant = normalizedVariant(variantValue)
    const name = String(key || "")
    if (!ShibumiConfig.isGroupId(group)
        || appearanceKeys.indexOf(name) < 0) return false

    let normalizedValue = value
    if (name === "displayMode")
      normalizedValue = normalizedDisplayMode(group, variant, value)
    else if (name === "compact")
      normalizedValue = value === true
    else if (name === "mediaStyle")
      normalizedValue = String(value || "") === "full" ? "full" : "default"

    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const settings = ShibumiConfig.isPlainObject(next.widgets[group])
        ? next.widgets[group] : {}
      const appearance = ShibumiConfig.isPlainObject(settings.appearance)
        ? settings.appearance : {}
      const profile = ShibumiConfig.isPlainObject(appearance[variant])
        ? appearance[variant] : {}
      profile[name] = normalizedValue
      if (name === "compact")
        profile.displayMode = normalizedDisplayMode(group, variant,
          normalizedValue ? "icon" : "full")
      else if (name === "displayMode")
        profile.compact = normalizedValue === "icon"
      appearance[variant] = profile
      settings.appearance = appearance
      next.widgets[group] = settings
    })
  }

  function resetGroupAppearance(groupId) {
    const group = String(groupId || "")
    if (!ShibumiConfig.isGroupId(group)) return false
    const appearanceKeys = [
      "displayMode", "compact", "mediaStyle", "color", "colorMode", "tone",
      "widgetBorder", "widgetBorderWidth",
      "widgetBorderColor", "widgetBorderUsesSurfaceColor", "widgetPadding",
      "widgetRadius", "surfaceOpacity"
    ]
    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const settings = ShibumiConfig.isPlainObject(next.widgets[group])
        ? next.widgets[group] : {}
      for (let index = 0; index < appearanceKeys.length; index++)
        delete settings[appearanceKeys[index]]
      next.widgets[group] = settings
    })
  }

  function resetGroupAppearanceForVariant(groupId, variantValue) {
    const group = String(groupId || "")
    const variant = normalizedVariant(variantValue)
    if (!ShibumiConfig.isGroupId(group)) return false
    const defaults = defaultAppearanceProfileForVariant(variant)
    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const settings = ShibumiConfig.isPlainObject(next.widgets[group])
        ? next.widgets[group] : {}
      const appearance = ShibumiConfig.isPlainObject(settings.appearance)
        ? settings.appearance : {}
      appearance[variant] = JSON.parse(JSON.stringify(defaults))
      settings.appearance = appearance
      next.widgets[group] = settings
    })
  }

  function resetAllGroupAppearancesForVariant(variantValue) {
    const variant = String(variantValue || "").toLowerCase()
    if (["v1", "v2"].indexOf(variant) < 0) return false
    const defaults = defaultAppearanceProfileForVariant(variant)
    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const groups = Object.keys(next.widgets)
      for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        const group = groups[groupIndex]
        if (!appearanceGroupSupportedForVariant(group, variant)) continue
        const settings = ShibumiConfig.isPlainObject(next.widgets[group])
          ? next.widgets[group] : {}
        const appearance = ShibumiConfig.isPlainObject(settings.appearance)
          ? settings.appearance : {}
        const hasVariantProfile = ShibumiConfig.isPlainObject(
          appearance[variant])
        let hasLegacyAppearance = false
        for (let keyIndex = 0; keyIndex < appearanceKeys.length; keyIndex++) {
          if (Object.prototype.hasOwnProperty.call(
                settings, appearanceKeys[keyIndex])) {
            hasLegacyAppearance = true
            break
          }
        }
        if (!hasVariantProfile && !hasLegacyAppearance) continue
        appearance[variant] = JSON.parse(JSON.stringify(defaults))
        settings.appearance = appearance
        next.widgets[group] = settings
      }
    })
  }

  function setLayoutProtection(variantValue, enabled) {
    const variant = String(variantValue || "").toLowerCase()
    if (["v1", "v2"].indexOf(variant) < 0
        || typeof enabled !== "boolean") return false
    return commit(function(next) {
      const protection = ShibumiConfig.normalizeLayoutProtection(
        next.layoutProtection)
      protection[variant] = enabled
      next.layoutProtection = protection
    })
  }

  function toggleGroupSeparator(groupId) {
    const group = String(groupId || "")
    if (!ShibumiConfig.isGroupId(group)) return false
    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const settings = ShibumiConfig.isPlainObject(next.widgets[group])
        ? next.widgets[group] : {}
      settings.separator = settings.separator !== true
      next.widgets[group] = settings
    })
  }

  function toggleV2Boundary(indexValue) {
    const index = Number(indexValue)
    if (!Number.isInteger(index) || index < 0 || index > 1) return false
    return commit(function(next) {
      const boundaries = ShibumiConfig.normalizedV2Boundaries(
        next.v2Boundaries) || ShibumiConfig.defaultV2Boundaries()
      boundaries[index] = !boundaries[index]
      next.v2Boundaries = boundaries
    })
  }

  function setAllV2Separators(enabled) {
    if (typeof enabled !== "boolean") return false
    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      for (let index = 0; index < ShibumiConfig.GroupIds.length; index++) {
        const group = ShibumiConfig.GroupIds[index]
        const settings = ShibumiConfig.isPlainObject(next.widgets[group])
          ? next.widgets[group] : {}
        settings.separator = enabled
        next.widgets[group] = settings
      }
      next.v2Boundaries = [enabled, enabled]
    })
  }

  function setWidgetSetting(groupId, moduleId, key, value) {
    const group = String(groupId || "")
    const module = String(moduleId || "")
    const name = String(key || "")
    if (!ShibumiConfig.isGroupId(group)
        || !/^[a-z0-9.-]+$/.test(module)
        || !/^[A-Za-z][A-Za-z0-9_-]*$/.test(name)) return false

    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const groupSettings = ShibumiConfig.isPlainObject(next.widgets[group])
        ? next.widgets[group] : {}
      const moduleSettings = ShibumiConfig.isPlainObject(groupSettings[module])
        ? groupSettings[module] : {}
      moduleSettings[name] = value
      groupSettings[module] = moduleSettings
      next.widgets[group] = groupSettings
    })
  }

  function setPresentationSetting(key, value) {
    const name = String(key || "")
    let normalizedValue = value
    if (["border", "panelBorder", "shadow", "frost"].indexOf(name) >= 0) {
      if (typeof value !== "boolean") return false
    } else if (name === "radius") {
      if (["large", "small"].indexOf(String(value || "")) < 0) return false
    } else if (name === "accent") {
      if (!ShibumiConfig.paletteIdValid(value)) return false
      normalizedValue = ShibumiConfig.normalizedPaletteId(value)
    } else if (name === "shellStyle" || name === "v2ShellStyle") {
      const allowed = name === "shellStyle"
        ? ["shibumi", "full", "fit", "dock", "notch"]
        : ["full", "fit", "dock", "notch"]
      if (allowed
          .indexOf(String(value || "")) < 0) return false
      normalizedValue = String(value)
    } else {
      return false
    }

    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.presentation)) next.presentation = {}
      if (name === "border") {
        const shellStyle = String(next.presentation.shellStyle || "shibumi")
        next.presentation[shellStyle === "shibumi"
          ? "v1Border" : "v2Border"] = normalizedValue
      } else next.presentation[name] = normalizedValue
      if (name === "shellStyle" && normalizedValue !== "shibumi")
        next.presentation.v2ShellStyle = normalizedValue
    })
  }

  function setShellVariant(target) {
    const requested = String(target || "")
    if (requested !== "v1" && requested !== "v2") return false
    const v2Styles = ["full", "fit", "dock", "notch"]
    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.presentation))
        next.presentation = {}
      const current = String(next.presentation.shellStyle || "shibumi")
      if (requested === "v1") {
        if (v2Styles.indexOf(current) >= 0)
          next.presentation.v2ShellStyle = current
        next.presentation.shellStyle = "shibumi"
        return
      }
      const remembered = v2Styles.indexOf(current) >= 0
        ? current : v2Styles.indexOf(
          String(next.presentation.v2ShellStyle || "")) >= 0
          ? String(next.presentation.v2ShellStyle) : "full"
      next.presentation.v2ShellStyle = remembered
      next.presentation.shellStyle = remembered
    })
  }

  function paletteColor(value) {
    return palette.colorFor(value)
  }

  function paletteContrastColor(value) {
    return palette.contrastColor(value)
  }

  function setPickerStyle(value) {
    const candidate = String(value || "")
    const style = candidate === "default" ? "carousel" : candidate
    if (["tanzaku", "hearthstone", "carousel"].indexOf(style) < 0) return false
    return commit(function(next) {
      next.picker = {
        style: style,
        imageStyle: style === "carousel" ? "omarchy" : style,
        mediaStyle: style
      }
    })
  }

  function setImagePickerStyle(value) {
    const candidate = String(value || "")
    const style = candidate === "default" ? "omarchy" : candidate
    if (["omarchy", "tanzaku", "hearthstone"].indexOf(style) < 0)
      return false
    return commit(function(next) {
      const picker = ShibumiConfig.normalize(next).picker
      next.picker = {
        style: picker.mediaStyle,
        imageStyle: style,
        mediaStyle: picker.mediaStyle
      }
    })
  }

  function setMediaPickerStyle(value) {
    const candidate = String(value || "")
    const style = candidate === "default" ? "carousel" : candidate
    if (["tanzaku", "hearthstone", "carousel"].indexOf(style) < 0) return false
    return commit(function(next) {
      const picker = ShibumiConfig.normalize(next).picker
      next.picker = {
        style: style,
        imageStyle: picker.imageStyle,
        mediaStyle: style
      }
    })
  }

  function setWorkspacePreference(key, value) {
    const name = String(key || "")
    if (name === "mode") {
      if (["10", "5", "active"].indexOf(String(value || "")) < 0) return false
    } else if (name === "style") {
      if (["default", "numbers", "magic", "kanji", "rings", "aurora", "pacman"]
          .indexOf(String(value || "")) < 0)
        return false
    } else {
      return false
    }

    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.workspace))
        next.workspace = ShibumiConfig.defaultWorkspaceConfig()
      next.workspace[name] = String(value)
    })
  }

  function setLauncherConfig(value) {
    if (!ShibumiConfig.isPlainObject(value)) return false
    const normalized = ShibumiConfig.normalizeLauncher(value)
    return commit(function(next) { next.launcher = normalized })
  }

  function setPluginFavorite(pluginId, favorite) {
    const id = String(pluginId || "").trim()
    if (id === "" || id.length > 255 || /[\x00-\x1f\x7f/\\]/.test(id)
        || typeof favorite !== "boolean") return false
    return commit(function(next) {
      const plugins = ShibumiConfig.normalizePlugins(next.plugins)
      const favorites = plugins.favorites.slice()
      const index = favorites.indexOf(id)
      if (favorite && index < 0) favorites.push(id)
      if (!favorite && index >= 0) favorites.splice(index, 1)
      next.plugins = { favorites: favorites }
    })
  }

  function defaultLauncherConfig() {
    return ShibumiConfig.defaultLauncherConfig()
  }

  function normalizeLauncherConfig(value) {
    return ShibumiConfig.normalizeLauncher(value)
  }

  function setReactorMode(value) {
    const mode = Number(value)
    if (!Number.isInteger(mode) || mode < 0 || mode > 8) return false
    return commit(function(next) { next.reactor = { mode: mode } })
  }

  function setOrder(value) {
    const normalized = ShibumiConfig.normalizedOrder(value)
    const splits = normalized
      ? ShibumiConfig.normalizedSplits(storage.draft().splits, normalized) : null
    if (!normalized || !splits) return false
    return commit(function(next) {
      next.order = normalized
      next.v1SlotRoles = ShibumiConfig.slotRolesForOrder(normalized)
      next.splits = splits
    })
  }

  function setSplits(value) {
    const order = ShibumiConfig.normalizedOrder(storage.draft().order)
    const normalized = order
      ? ShibumiConfig.normalizedSplits(value, order) : null
    if (!normalized) return false
    return commit(function(next) { next.splits = normalized })
  }

  // A transition writes all affected State fields in one existing own-entry
  // request. The caller still waits for persistenceSettled before native work.
  function exactKeys(value, keys) {
    return ShibumiConfig.isPlainObject(value)
      && Object.keys(value).length === keys.length
      && keys.every(key => Object.prototype.hasOwnProperty.call(value, key))
  }

  function transitionLayout(value, variant) {
    const regions = ["left", "center", "right"]
    if (!exactKeys(value, regions) || !regions.every(region =>
        Array.isArray(value[region]) && value[region].every(id => typeof id === "string"))) return null
    return variant === "v1" ? ShibumiConfig.normalizedOrder(value)
      : ShibumiConfig.normalizedV2Layout(value)
  }

  function normalizedLayoutFamilyPatch(patch) {
    if (!ShibumiConfig.isPlainObject(patch)) return null
    const keys = Object.keys(patch)
    const allowed = ["v1Layout", "v2Layout", "v2Boundaries", "separators", "familyStates"]
    if (!keys.length || keys.some(key => allowed.indexOf(key) < 0)) return null
    const result = {}
    for (const key of keys) {
      const value = patch[key]
      if (key === "v1Layout") {
        if (!exactKeys(value, ["order", "splits"])) return null
        const order = transitionLayout(value.order, "v1")
        if (!order || !exactKeys(value.splits, ["left", "right", "boundaries"])) return null
        const splits = ShibumiConfig.normalizedSplits(value.splits, order)
        if (!splits) return null
        result[key] = {order: order, splits: splits}
      } else if (key === "v2Layout") {
        result[key] = transitionLayout(value, "v2")
        if (!result[key]) return null
      } else if (key === "v2Boundaries") {
        result[key] = ShibumiConfig.normalizedV2Boundaries(value)
        if (!result[key]) return null
      } else {
        if (!ShibumiConfig.isPlainObject(value)) return null
        const groups = Object.keys(value)
        if (!groups.length || groups.length > 512) return null
        result[key] = {}
        for (const group of groups) {
          if (!ShibumiConfig.isGroupId(group)) return null
          const item = value[group]
          // null restores absence rather than inventing an explicit false.
          if (key === "separators") {
            if (item !== null && typeof item !== "boolean") return null
            result[key][group] = item
          } else {
            if (!exactKeys(item, ["v1", "v2"])
                || [item.v1, item.v2].some(flag => flag !== null && typeof flag !== "boolean")) return null
            result[key][group] = {v1: item.v1, v2: item.v2}
          }
        }
      }
    }
    return result
  }

  function layoutFamilyProjection(source, patch) {
    const result = {}
    for (const key of Object.keys(patch)) {
      if (key === "v1Layout") result[key] = {order: source.order, splits: source.splits}
      else if (key === "v2Layout" || key === "v2Boundaries") result[key] = source[key]
      else {
        result[key] = {}
        for (const group of Object.keys(patch[key])) {
          const settings = source.widgets && source.widgets[group] || {}
          const field = name => Object.prototype.hasOwnProperty.call(settings, name) ? settings[name] : null
          result[key][group] = key === "separators" ? field("separator")
            : {v1: field("enabledV1"), v2: field("enabledV2")}
        }
      }
    }
    return JSON.parse(JSON.stringify(result))
  }

  function layoutFamilySnapshot(patch) {
    const normalized = normalizedLayoutFamilyPatch(patch)
    if (!ready || !normalized) return null
    const snapshot = layoutFamilyProjection(config, normalized)
    return normalizedLayoutFamilyPatch(snapshot)
  }

  function applyLayoutFamilyPatch(next, patch) {
    if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
    for (const key of Object.keys(patch)) {
      const value = patch[key]
      if (key === "v1Layout") {
        next.order = value.order
        next.splits = value.splits
        next.v1SlotRoles = ShibumiConfig.slotRolesForOrder(value.order)
      } else if (key === "v2Layout" || key === "v2Boundaries") next[key] = value
      else {
        for (const group of Object.keys(value)) {
          const item = value[group]
          const settings = ShibumiConfig.isPlainObject(next.widgets[group]) ? next.widgets[group] : {}
          const assign = function(name, flag) {
            if (flag === null) delete settings[name]
            else settings[name] = flag
          }
          if (key === "separators") assign("separator", item)
          else { assign("enabledV1", item.v1); assign("enabledV2", item.v2) }
          // Removing an absent flag does not need to create an empty group.
          if (Object.keys(settings).length || Object.prototype.hasOwnProperty.call(next.widgets, group))
            next.widgets[group] = settings
        }
      }
    }
    // Existing bounded widget normalization may refuse a saturated settings
    // object. Do not enqueue only the surviving portion of an atomic patch.
    return same(layoutFamilyProjection(ShibumiConfig.normalize(next), patch), patch)
  }

  function setLayoutFamilyTransition(patch) {
    const normalized = normalizedLayoutFamilyPatch(patch)
    return normalized ? commit(next => applyLayoutFamilyPatch(next, normalized)) : false
  }

  function sameLayoutFamilyScope(left, right) {
    if (!exactKeys(left, Object.keys(right))) return false
    for (const key of ["separators", "familyStates"]) {
      if (Object.prototype.hasOwnProperty.call(left, key)
          && !exactKeys(left[key], Object.keys(right[key]))) return false
    }
    return true
  }

  function compensateLayoutFamilyTransition(expectedSerial, expectedPatch, rollbackPatch) {
    if (!ready || writePending || !Number.isInteger(expectedSerial)
        || expectedSerial !== writeSerial) return false
    const expected = normalizedLayoutFamilyPatch(expectedPatch)
    const rollback = normalizedLayoutFamilyPatch(rollbackPatch)
    // Both patches cover exactly the same fields/groups. Serial and projected
    // file truth protect this caller's local intent; this is not native CAS.
    if (!expected || !rollback || !sameLayoutFamilyScope(expected, rollback)
        || !same(layoutFamilyProjection(config, expected), expected)) return false
    return commit(function(next) {
      if (writePending || writeSerial !== expectedSerial
          || !same(layoutFamilyProjection(next, expected), expected)) return false
      return applyLayoutFamilyPatch(next, rollback)
    })
  }

  function setLayout(order, splits) {
    return setLayoutFamilyTransition({v1Layout: {order: order, splits: splits}})
  }

  function setV2Layout(value) {
    return setLayoutFamilyTransition({v2Layout: value})
  }

  function resetV2Layout() {
    const separators = {}
    for (const group of ShibumiConfig.GroupIds) separators[group] = null
    return setLayoutFamilyTransition({v2Layout: ShibumiConfig.defaultV2Layout(),
      v2Boundaries: ShibumiConfig.defaultV2Boundaries(), separators: separators})
  }

  function resetLayout() {
    return setLayout(ShibumiConfig.defaultOrder(), ShibumiConfig.defaultSplits())
  }

  onSourceConfigChanged: applySourceConfig(sourceConfig)
  Component.onCompleted: applySourceConfig(sourceConfig)

  IpcHandler {
    target: "shibumi-suite-runtime"

    function verifyPayload(expectedDigest: string): string {
      const expected = String(expectedDigest || "")
      return root.ready
          && runtimeProvider.registered
          && SuiteRuntime.Runtime.ready
          && SuiteRuntime.Runtime.payloadDigest === root.suitePayloadDigest
          && root.suitePayloadLoaded
          && expected.length === 64
          && expected === root.suitePayloadDigest
        ? "ok" : "not-ready"
    }

    function reloadPayload(): string {
      Qt.callLater(function() { Quickshell.reload(false) })
      return "ok"
    }
  }

  FileView {
    path: root.suiteMarkerPath
    watchChanges: false
    printErrors: false
    onLoaded: root.captureSuiteMarker(text())
    onLoadFailed: {
      root.suitePayloadDigest = ""
      root.suitePayloadLoaded = false
    }
  }

  ThemePalette {
    id: palette
    config: root.config
  }
}
