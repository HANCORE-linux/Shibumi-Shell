pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
  id: root

  required property var bar
  property var settings: ({})
  property var tokenSource: null
  // Each visible V1 widget opts in explicitly. V2 continues to render its
  // independent decoration in GroupSlot.
  property bool v1AppearanceEnabled: false
  readonly property var tokens: tokenSource
    || (bar && "visualTokens" in bar ? bar.visualTokens : null)
  readonly property string shellStyle: tokens
    && tokens.shellStyle !== undefined ? String(tokens.shellStyle) : "shibumi"
  readonly property bool customDecorated: shellStyle !== "shibumi" && !!(tokens
    && ((typeof tokens.widgetHasFill === "function"
          && tokens.widgetHasFill(settings))
      || (typeof tokens.widgetHasBorder === "function"
          && tokens.widgetHasBorder(settings))))
  readonly property bool surfaceDisabled: shellStyle !== "shibumi" && !!(tokens
    && typeof tokens.widgetColorMode === "function"
    && tokens.widgetColorMode(settings) === "none")
  readonly property var v1FillSettings: {
    if (!v1AppearanceEnabled) return settings
    const source = settings || ({})
    const effective = {}
    for (const key in source) effective[key] = source[key]
    effective.colorMode = "fill"
    effective.widgetBorder = false
    return effective
  }
  readonly property bool v1CustomFill: v1AppearanceEnabled
    && shellStyle === "shibumi" && !!(tokens
      && typeof tokens.widgetHasFill === "function"
      && tokens.widgetHasFill(v1FillSettings))
  readonly property color v1FillColor: v1CustomFill
    && typeof tokens.widgetFillColor === "function"
    ? tokens.widgetFillColor(v1FillSettings) : "transparent"
  readonly property real v1FillOpacity: v1CustomFill
    && typeof tokens.widgetSurfaceOpacity === "function"
    ? tokens.widgetSurfaceOpacity(v1FillSettings) : 1
  readonly property color renderedFillColor: v1CustomFill
    ? Qt.rgba(v1FillColor.r, v1FillColor.g, v1FillColor.b,
        v1FillColor.a * v1FillOpacity)
    : tokens && tokens.pill !== undefined ? tokens.pill : "transparent"
  // V1 owns the individual rounded widget pills. V2 Full/Fit/Dock/Notch
  // instead use one shared shell surface; optional per-widget fill/border
  // decoration is rendered by GroupSlot. Suppress the opaque native pill
  // whenever that custom surface is active, otherwise it would cover the
  // selected fill. "None" intentionally removes both surface layers.
  readonly property bool shellPillVisible: shellStyle === "shibumi"
    && !customDecorated && !surfaceDisabled
  readonly property int renderedSurfaceCount: shellPillVisible ? 1 : 0
  readonly property int renderedShadowCount: shellPillVisible && tokens
    && tokens.shadowEnabled === true ? 1 : 0

  RectangularShadow {
    anchors.fill: pill
    visible: root.renderedShadowCount === 1
    radius: pill.radius
    blur: 8
    spread: 0
    offset: Qt.vector2d(0,
      root.bar && root.bar.position === "bottom" ? -1 : 1)
    color: root.tokens && root.tokens.pillShadow !== undefined
      ? root.tokens.pillShadow : Qt.rgba(0, 0, 0, 0.55)
    z: -1
  }

  Rectangle {
    id: pill

    // The fill and border share the exact pill bounds. Qt draws the border
    // inside those bounds, so the selected fill reaches its inner edge with
    // no inset or transparent seam.
    anchors.fill: parent
    visible: root.shellPillVisible
    radius: root.tokens.pillRadius
    color: root.renderedFillColor
    border.color: root.tokens.pillBorder
    border.width: root.tokens.pillBorderWidth
  }
}
