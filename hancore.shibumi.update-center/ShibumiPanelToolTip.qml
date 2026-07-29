pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons as Commons

ToolTip {
  id: root

  required property var panel
  readonly property var tokens: panel ? panel.shibumiTokens : null
  readonly property color resolvedBackground: panel && panel.bar
    && panel.bar.background !== undefined
    ? panel.bar.background
    : panel && panel.controlFillColor !== undefined
      ? panel.controlFillColor : Commons.Color.tooltip.background
  readonly property color resolvedBorderColor: tokens
    && tokens.panelBorder !== undefined
    ? tokens.panelBorder
    : panel && panel.controlBorderColor !== undefined
      ? panel.controlBorderColor : Commons.Color.tooltip.border
  readonly property real resolvedBorderWidth: tokens
    && tokens.panelBorderWidth !== undefined
    ? tokens.panelBorderWidth
    : (tokens && tokens.pillBorderWidth !== undefined ? tokens.pillBorderWidth : 1)
  readonly property color resolvedTextColor: panel
    && panel.controlForeground !== undefined
    ? panel.controlForeground : Commons.Color.tooltip.text
  readonly property string resolvedFontFamily: panel && panel.bar
    && panel.bar.fontFamily !== undefined
    ? panel.bar.fontFamily : Commons.Style.font.family

  delay: 320
  padding: 0

  background: Rectangle {
    color: root.resolvedBackground
    border.color: root.resolvedBorderColor
    border.width: root.resolvedBorderWidth
    radius: root.tokens && root.tokens.tooltipRadius !== undefined
      ? root.tokens.tooltipRadius : Commons.Style.space(6)
  }

  contentItem: Text {
    text: root.text
    color: root.resolvedTextColor
    font.family: root.resolvedFontFamily
    font.pixelSize: 12
    font.letterSpacing: 1
    leftPadding: root.resolvedBorderWidth + Commons.Style.space(10)
    rightPadding: root.resolvedBorderWidth + Commons.Style.space(10)
    topPadding: root.resolvedBorderWidth + Commons.Style.space(4)
    bottomPadding: root.resolvedBorderWidth + Commons.Style.space(4)
    renderType: Text.NativeRendering
  }
}
