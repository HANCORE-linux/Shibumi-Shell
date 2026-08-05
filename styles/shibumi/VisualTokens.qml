pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var bar
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property var presentation: stateService && stateService.config
    ? stateService.config.presentation || ({}) : ({})
  readonly property string shellStyle:
    ["shibumi", "full", "fit", "dock", "notch"]
      .indexOf(String(presentation.shellStyle || "")) >= 0
      ? String(presentation.shellStyle) : "shibumi"
  readonly property bool v2Shell: shellStyle !== "shibumi"

  readonly property string fontFamily: Commons.Style.font.family
  // Preserve the approved 35/38px V1 geometry. The original V2 contract uses
  // a 33px visible strip and reserves three additional pixels.
  readonly property int barHeight: Commons.Style.space(v2Shell ? 33 : 35)
  readonly property int exclusiveHeight: Commons.Style.space(v2Shell ? 36 : 38)
  readonly property int islandHeight: Commons.Style.space(32)
  readonly property int islandInsetX: Commons.Style.space(5)
  readonly property int islandContentInsetX: Commons.Style.space(4)
  readonly property int islandOffsetY: Commons.Style.space(3)
  readonly property int slotHeight: Commons.Style.space(28)
  readonly property int pillHeight: Commons.Style.space(24)
  readonly property int pillRadius: Commons.Style.space(
    presentation.radius === "small" ? 6 : 12)
  readonly property int islandRadius: Commons.Style.space(
    presentation.radius === "small" ? 8 : 16)
  readonly property int tileRadius: v2Shell
    ? Commons.Style.space(10)
    : Math.max(1, pillRadius - Commons.Style.space(2))
  readonly property int pillPaddingX: Commons.Style.space(9)
  readonly property int labelSize: Commons.Style.font.body
  readonly property int captionSize: Commons.Style.font.caption
  readonly property int iconSize: Commons.Style.space(15)
  readonly property int contentGap: Commons.Style.space(5)
  readonly property int compactGap: Commons.Style.space(4)
  readonly property int groupGap: Commons.Style.space(6)
  readonly property int splitGap: Commons.Style.space(16)
  readonly property int tooltipRadius: Commons.Style.space(6)
  readonly property int tooltipPaddingX: Commons.Style.space(10)
  readonly property int tooltipPaddingY: Commons.Style.space(4)
  readonly property int widgetFadeDuration: 140
  readonly property int geometryDuration: 160
  readonly property int colorDuration: 160
  readonly property int invalidDropDuration: 230
  readonly property int returnCleanupDuration: 240
  // V2 notch contract: 14px shoulder flowing directly from the screen edge.
  readonly property int shellWingWidth: Commons.Style.space(14)
  readonly property int shellFitRadius: Commons.Style.space(6)
  readonly property int shellDockRadius: Commons.Style.space(8)

  readonly property bool borderEnabled: v2Shell
    ? (presentation.v2Border === undefined
      ? presentation.border !== false : presentation.v2Border !== false)
    : (presentation.v1Border === undefined
      ? presentation.border !== false : presentation.v1Border !== false)
  readonly property bool panelBorderEnabled: v2Shell
    ? presentation.panelBorder !== false : borderEnabled
  readonly property bool shadowEnabled: presentation.shadow === true
  readonly property bool frostEnabled: !v2Shell && presentation.frost === true
  readonly property color paper: Commons.Color.background
  readonly property color ink: Commons.Color.foreground
  readonly property color sumi: Commons.Color.muted
  readonly property color sumiHi: mix(sumi, ink, 0.55)
  readonly property color seal: stateService
    ? stateService.selectedColor : Commons.Color.bar.active
  readonly property color mutedInk: sumi
  readonly property color pill: Qt.rgba(paper.r, paper.g, paper.b, 0.18)
  readonly property color barBackground: Qt.rgba(paper.r, paper.g, paper.b,
    frostEnabled ? 0.68 : 0.94)
  readonly property color panelBackground: Qt.rgba(paper.r, paper.g, paper.b, 0.94)
  readonly property color pillBorder: mix(paper, ink, 0.13)
  readonly property color islandBorder: mix(paper, ink, 0.16)
  readonly property color shellBorder: mix(paper, ink, 0.22)
  readonly property color pillShadow: Qt.rgba(0, 0, 0, 0.55)
  readonly property int pillBorderWidth: borderEnabled ? 1 : 0
  readonly property color panelBorder: pillBorder
  readonly property int panelBorderWidth: panelBorderEnabled ? 1 : 0
  readonly property int panelRadius: v2Shell
    ? Commons.Style.space(6) : pillRadius
  readonly property color shellShadow: Qt.rgba(0, 0, 0, 0.46)
  readonly property color separator: Qt.rgba(ink.r, ink.g, ink.b, 0.18)
  readonly property color fillActive: Qt.rgba(seal.r, seal.g, seal.b, 0.18)
  readonly property color fillHover: Qt.rgba(seal.r, seal.g, seal.b, 0.10)
  readonly property color fillIdle: Qt.rgba(0, 0, 0, 0.12)
  readonly property color fillPrimaryHover: Qt.lighter(seal, 1.15)

  function workspacePillPadding(style) {
    if (style !== "numbers") return Commons.Style.space(4)
    const outerRadius = v2Shell ? Commons.Style.space(12) : pillRadius
    const badgeRadius = v2Shell ? Commons.Style.space(10)
      : Commons.Style.space(presentation.radius === "small" ? 5 : 10)
    return Math.max(1, outerRadius - badgeRadius)
  }

  function widgetColorId(settings) {
    const value = settings && settings.color !== undefined
      ? String(settings.color) : "inherit"
    return value === "inherit" ? "inherit"
      : stateService && typeof stateService.paletteColor === "function"
        ? value : "inherit"
  }

  function widgetBorderColorId(settings) {
    const legacySurfaceColor = settings
      && settings.widgetBorderUsesSurfaceColor === true
    const value = settings && settings.widgetBorderColor !== undefined
      ? String(settings.widgetBorderColor)
      : legacySurfaceColor ? widgetColorId(settings) : "inherit"
    return value === "inherit" ? "inherit"
      : stateService && typeof stateService.paletteColor === "function"
        ? value : "inherit"
  }

  function widgetColorMode(settings) {
    const value = settings && settings.colorMode !== undefined
      ? String(settings.colorMode) : "fill"
    return ["none", "fill", "border", "both"].indexOf(value) >= 0
      ? value : "fill"
  }

  function widgetHasFill(settings) {
    const mode = widgetColorMode(settings)
    return widgetColorId(settings) !== "inherit"
      && (mode === "fill" || mode === "both")
  }

  function widgetHasBorder(settings) {
    const mode = widgetColorMode(settings)
    return settings && settings.widgetBorder === true
      || mode === "border" || mode === "both"
  }

  function widgetSurfaceOpacity(settings) {
    const value = settings && settings.surfaceOpacity !== undefined
      ? Number(settings.surfaceOpacity) : 1
    return Math.max(0.35, Math.min(1, Number.isFinite(value) ? value : 1))
  }

  function widgetRadius(settings) {
    const value = settings && settings.widgetRadius !== undefined
      ? String(settings.widgetRadius) : "auto"
    if (value === "square") return 0
    if (value === "soft") return Commons.Style.space(6)
    if (value === "round") return pillHeight / 2
    return tileRadius
  }

  function widgetPadding(settings, decorated) {
    const value = settings && settings.widgetPadding !== undefined
      ? String(settings.widgetPadding) : "auto"
    if (value === "none") return 0
    if (value === "compact") return Commons.Style.space(3)
    if (value === "roomy") return Commons.Style.space(6)
    return decorated ? Commons.Style.space(3) : 0
  }

  function widgetBorderWidth(settings) {
    const value = settings && settings.widgetBorderWidth !== undefined
      ? Number(settings.widgetBorderWidth) : 1
    const bounded = Math.max(0.5, Math.min(2,
      Number.isFinite(value) ? value : 1))
    return Math.round(bounded * 2) / 2
  }

  function widgetFillColor(settings) {
    const id = widgetColorId(settings)
    return widgetHasFill(settings) && stateService
      ? stateService.paletteColor(id) : "transparent"
  }

  function widgetBorderColor(settings) {
    if (!widgetHasBorder(settings)) return "transparent"
    const id = widgetBorderColorId(settings)
    return id !== "inherit" && stateService
      ? stateService.paletteColor(id) : panelBorder
  }

  function widgetContentColor(settings, fallback) {
    const id = widgetColorId(settings)
    if (!widgetHasFill(settings)) return fallback
    const tone = settings && settings.tone !== undefined
      ? String(settings.tone) : "auto"
    if (tone === "background") return paper
    if (tone === "foreground") return ink
    return stateService
        && typeof stateService.paletteContrastColor === "function"
      ? stateService.paletteContrastColor(id) : fallback
  }

  function mix(base, toward, amount) {
    return Qt.rgba(
      base.r * (1 - amount) + toward.r * amount,
      base.g * (1 - amount) + toward.g * amount,
      base.b * (1 - amount) + toward.b * amount,
      1)
  }

  visible: false
  width: 0
  height: 0
}
