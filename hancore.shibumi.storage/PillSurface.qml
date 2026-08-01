pragma ComponentBehavior: Bound

import QtQuick

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

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: root.tokens.shadowEnabled ? 2 : 0
    visible: root.shellPillVisible && root.tokens.shadowEnabled
    radius: root.tokens.pillRadius
    color: root.tokens.pillShadow
    opacity: 0.28
  }

  Rectangle {
    anchors.fill: parent
    visible: root.shellPillVisible
    radius: root.tokens.pillRadius
    color: root.tokens.pill
    border.color: root.tokens.pillBorder
    border.width: root.tokens.pillBorderWidth
  }
}
