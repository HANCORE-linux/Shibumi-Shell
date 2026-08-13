pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "ShibumiConfig.js" as ShibumiConfig

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  readonly property string pluginSourceDir: manifest
    ? String(manifest.__sourceDir || "") : ""
  property string suitePayloadDigest: ""
  property bool suitePayloadLoaded: false

  readonly property int contractVersion: 1
  readonly property bool ready: shell !== null
  readonly property var sourceConfig: shell && shell.shellConfig
    && shell.shellConfig.bar ? shell.shellConfig.bar.shibumi : null

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
    return JSON.stringify(left) === JSON.stringify(right)
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
    if (!shell || typeof shell.mutateShellConfig !== "function"
        || typeof mutator !== "function") return false

    const current = ShibumiConfig.normalize(sourceConfig)
    const next = JSON.parse(JSON.stringify(current))
    if (mutator(next) === false) return false
    const normalized = ShibumiConfig.normalize(next)
    if (same(current, normalized)) return false

    shell.mutateShellConfig(function(shellConfig) {
      if (!ShibumiConfig.isPlainObject(shellConfig.bar)) shellConfig.bar = {}
      shellConfig.bar.shibumi = normalized
    })
    applySourceConfig(normalized)
    return true
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
    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      for (let index = 0; index < groups.length; index++) {
        const group = groups[index]
        const settings = ShibumiConfig.isPlainObject(next.widgets[group])
          ? next.widgets[group] : {}
        settings.enabledV1 = stateValues[group].v1
        settings.enabledV2 = stateValues[group].v2
        next.widgets[group] = settings
      }
    })
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
      ? ShibumiConfig.normalizedSplits(config.splits, normalized) : null
    if (!normalized || !splits) return false
    return commit(function(next) {
      next.order = normalized
      next.v1SlotRoles = ShibumiConfig.slotRolesForOrder(normalized)
      next.splits = splits
    })
  }

  function setSplits(value) {
    const order = ShibumiConfig.normalizedOrder(config.order)
    const normalized = order
      ? ShibumiConfig.normalizedSplits(value, order) : null
    if (!normalized) return false
    return commit(function(next) { next.splits = normalized })
  }

  function setLayout(order, splits) {
    const normalizedOrder = ShibumiConfig.normalizedOrder(order)
    const normalizedSplits = normalizedOrder
      ? ShibumiConfig.normalizedSplits(splits, normalizedOrder) : null
    if (!normalizedOrder || !normalizedSplits) return false
    return commit(function(next) {
      next.order = normalizedOrder
      next.v1SlotRoles = ShibumiConfig.slotRolesForOrder(normalizedOrder)
      next.splits = normalizedSplits
    })
  }

  function setV2Layout(value) {
    const normalized = ShibumiConfig.normalizedV2Layout(value)
    if (!normalized) return false
    return commit(function(next) { next.v2Layout = normalized })
  }

  function resetV2Layout() {
    return commit(function(next) {
      next.v2Layout = ShibumiConfig.defaultV2Layout()
      next.v2Boundaries = ShibumiConfig.defaultV2Boundaries()
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      for (let index = 0; index < ShibumiConfig.GroupIds.length; index++) {
        const group = ShibumiConfig.GroupIds[index]
        if (!ShibumiConfig.isPlainObject(next.widgets[group])) continue
        delete next.widgets[group].separator
      }
    })
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
    path: root.pluginSourceDir !== ""
      ? root.pluginSourceDir + "/.shibumi-managed.json" : ""
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
