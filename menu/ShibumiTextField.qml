pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons as Commons
import qs.Ui as Ui

// Quattro text-field behavior with radius supplied by Shibumi tokens.
TextField {
  id: root

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color selectionTint: Commons.Style.selectionFillFor(
    foreground, accent)
  property bool password: false
  property real horizontalPadding: Commons.Style.spacing.controlPaddingX
  property real verticalPadding: Commons.Style.spacing.inputPaddingY
  property bool hasCursor: false
  property real controlRadius: Commons.Style.cornerRadius

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor
  readonly property var _borderSpec: Commons.Border.controlSpec(
    _focused ? "focus" : (_hot ? "hover-cursor" : "normal"),
    root.foreground, root.accent)

  echoMode: password ? TextInput.Password : TextInput.Normal
  font.family: Commons.Style.font.family
  font.pixelSize: Commons.Style.font.body
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)

  leftPadding: horizontalPadding + Commons.Border.left(_borderSpec)
  rightPadding: horizontalPadding + Commons.Border.right(_borderSpec)
  topPadding: verticalPadding + Commons.Border.top(_borderSpec)
  bottomPadding: verticalPadding + Commons.Border.bottom(_borderSpec)

  background: Ui.BorderSurface {
    color: Commons.Style.controlFill(root._focused, root._hot,
      root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: root.controlRadius
  }
}
