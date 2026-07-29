pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "ThemePaletteModel.js" as ThemePaletteModel

// Quattro owns the foundational background/foreground roles. Read the seven
// terminal swatches that its public Commons palette does not expose so the
// V1 bar-color contract can be reproduced without duplicating theme ownership.
Item {
  id: root

  required property var config

  readonly property string home: Quickshell.env("HOME")
  readonly property string colorsPath:
    home + "/.local/state/omarchy/current/theme/colors.toml"
  readonly property string themeNamePath:
    home + "/.local/state/omarchy/current/theme.name"
  readonly property string selectedId: ThemePaletteModel.selection(
    config && config.presentation ? config.presentation.accent : "color01")
  property color color01: Commons.Color.urgent
  property color color02: Commons.Color.accent
  property color color03: Commons.Color.accent
  property color color04: Commons.Color.accent
  property color color05: Commons.Color.accent
  property color color06: Commons.Color.accent
  property color color07: Commons.Color.foreground
  property color color08: Commons.Color.muted
  readonly property color foregroundSoft: Qt.rgba(
    Commons.Color.foreground.r * 0.88 + Commons.Color.background.r * 0.12,
    Commons.Color.foreground.g * 0.88 + Commons.Color.background.g * 0.12,
    Commons.Color.foreground.b * 0.88 + Commons.Color.background.b * 0.12,
    1.0)
  readonly property color selectedColor: colorFor(selectedId)

  visible: false
  width: 0
  height: 0

  function apply(raw) {
    const palette = ThemePaletteModel.parse(raw)
    color01 = palette.color01 || Commons.Color.urgent
    color02 = palette.color02 || Commons.Color.accent
    color03 = palette.color03 || Commons.Color.accent
    color04 = palette.color04 || Commons.Color.accent
    color05 = palette.color05 || Commons.Color.accent
    color06 = palette.color06 || Commons.Color.accent
    color07 = palette.color07 || Commons.Color.foreground
    color08 = palette.color08 || Commons.Color.muted
  }

  function colorFor(value) {
    const id = ThemePaletteModel.selection(value)
    if (id === "color02") return color02
    if (id === "color03") return color03
    if (id === "color04") return color04
    if (id === "color05") return color05
    if (id === "color06") return color06
    if (id === "color07") return color07
    if (id === "color08") return color08
    if (id === "foreground") return foregroundSoft
    return color01
  }

  function linearChannel(value) {
    return value <= 0.04045
      ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
  }

  function relativeLuminance(value) {
    return 0.2126 * linearChannel(value.r)
      + 0.7152 * linearChannel(value.g)
      + 0.0722 * linearChannel(value.b)
  }

  function contrastRatio(left, right) {
    const leftLuminance = relativeLuminance(left)
    const rightLuminance = relativeLuminance(right)
    return (Math.max(leftLuminance, rightLuminance) + 0.05)
      / (Math.min(leftLuminance, rightLuminance) + 0.05)
  }

  function contrastColor(value) {
    const fill = colorFor(value)
    return contrastRatio(fill, Commons.Color.background)
      >= contrastRatio(fill, Commons.Color.foreground)
      ? Commons.Color.background : Commons.Color.foreground
  }

  function refresh() {
    colorsFile.reload()
  }

  // Quattro replaces the complete current/theme directory before rewriting
  // theme.name. Watching that stable sibling guarantees a reload after the
  // atomic swap, including a reapply whose theme name and base colors did not
  // change.
  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: colorsFile.reload()
  }

  FileView {
    id: colorsFile
    path: root.colorsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: root.apply("")
  }

  Connections {
    target: Commons.Color
    function onBackgroundChanged() { root.refresh() }
    function onForegroundChanged() { root.refresh() }
    function onAccentChanged() { root.refresh() }
    function onUrgentChanged() { root.refresh() }
  }
}
