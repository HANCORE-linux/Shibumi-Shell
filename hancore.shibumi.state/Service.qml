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
    if (ShibumiConfig.GroupIds.indexOf(group) < 0) return ({})
    return config && config.widgets && ShibumiConfig.isPlainObject(config.widgets[group])
      ? config.widgets[group] : ({})
  }

  function groupSetting(groupId, key, fallback) {
    const settings = groupSettings(groupId)
    const name = String(key || "")
    return name && Object.prototype.hasOwnProperty.call(settings, name)
      ? settings[name] : fallback
  }

  function groupEnabled(groupId) {
    return groupSetting(groupId, "enabled", true) !== false
  }

  function setGroupSetting(groupId, key, value) {
    const group = String(groupId || "")
    const name = String(key || "")
    if (ShibumiConfig.GroupIds.indexOf(group) < 0
        || !/^[A-Za-z][A-Za-z0-9_-]*$/.test(name)) return false

    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.widgets)) next.widgets = {}
      const settings = ShibumiConfig.isPlainObject(next.widgets[group])
        ? next.widgets[group] : {}
      settings[name] = value
      next.widgets[group] = settings
    })
  }

  function resetGroupAppearance(groupId) {
    const group = String(groupId || "")
    if (ShibumiConfig.GroupIds.indexOf(group) < 0) return false
    const appearanceKeys = [
      "displayMode", "compact", "color", "colorMode", "tone",
      "widgetBorder", "widgetBorderWidth", "widgetPadding",
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

  function toggleGroupSeparator(groupId) {
    const group = String(groupId || "")
    if (ShibumiConfig.GroupIds.indexOf(group) < 0) return false
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
    if (ShibumiConfig.GroupIds.indexOf(group) < 0
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
    } else if (name === "shellStyle") {
      if (["shibumi", "full", "fit", "dock", "notch"]
          .indexOf(String(value || "")) < 0) return false
      normalizedValue = String(value)
    } else {
      return false
    }

    return commit(function(next) {
      if (!ShibumiConfig.isPlainObject(next.presentation)) next.presentation = {}
      next.presentation[name] = normalizedValue
    })
  }

  function paletteColor(value) {
    return palette.colorFor(value)
  }

  function paletteContrastColor(value) {
    return palette.contrastColor(value)
  }

  function setPickerStyle(value) {
    const style = String(value || "")
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
    const style = String(value || "")
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
    const style = String(value || "")
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
      if (["default", "numbers", "magic", "kanji", "rings", "aurora"]
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

  function setMenuConfig(value) {
    const normalized = ShibumiConfig.normalizeMenu(value)
    if (!ShibumiConfig.isPlainObject(value)
        || Number(value.version) !== ShibumiConfig.MenuSchemaVersion) return false
    return commit(function(next) { next.menu = normalized })
  }

  function defaultMenuConfig() {
    return ShibumiConfig.defaultMenuConfig()
  }

  function normalizeMenuConfig(value) {
    return ShibumiConfig.normalizeMenu(value)
  }

  function setReactorMode(value) {
    const mode = Number(value)
    if (!Number.isInteger(mode) || mode < 0 || mode > 8) return false
    return commit(function(next) { next.reactor = { mode: mode } })
  }

  function setOrder(value) {
    const normalized = ShibumiConfig.normalizedOrder(value)
    if (!normalized) return false
    return commit(function(next) { next.order = normalized })
  }

  function setSplits(value) {
    const normalized = ShibumiConfig.normalizedSplits(value)
    if (!normalized) return false
    return commit(function(next) { next.splits = normalized })
  }

  function setLayout(order, splits) {
    const normalizedOrder = ShibumiConfig.normalizedOrder(order)
    const normalizedSplits = ShibumiConfig.normalizedSplits(splits)
    if (!normalizedOrder || !normalizedSplits) return false
    return commit(function(next) {
      next.order = normalizedOrder
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
