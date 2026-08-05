pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
  id: root

  required property var bar
  property var settings: ({})
  property var tokenSource: null
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

    anchors.fill: parent
    visible: root.shellPillVisible
    radius: root.tokens.pillRadius
    color: root.tokens.pill
    border.color: root.tokens.pillBorder
    border.width: root.tokens.pillBorderWidth
  }
}
