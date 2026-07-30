pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string glyph
  required property string label
  required property string mode
  property bool selected: false
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  signal chosen()

  implicitHeight: Commons.Style.space(62)
  radius: Math.max(controller.controlRadius, Commons.Style.space(7))
  color: selected
    ? Commons.Util.alpha(accent, 0.10)
    : pointer.containsMouse
      ? controller.controlHoverFillColor : controller.controlFillColor
  border.width: 1
  border.color: selected ? accent : controller.controlBorderColor

  Row {
    anchors.fill: parent
    anchors.margins: Commons.Style.space(8)
    spacing: Commons.Style.space(8)

    IconText {
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(22)
      text: root.glyph
      color: root.selected ? root.accent : root.foreground
      font.pixelSize: Commons.Style.space(19) * root.uiScale
      font.weight: Font.Medium
      fill: 0
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x
      spacing: Commons.Style.space(2)

      Text {
        width: parent.width
        text: root.label
        color: root.foreground
        elide: Text.ElideRight
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        font.weight: Font.Medium
      }

      Text {
        width: parent.width
        text: root.mode
        color: root.selected ? root.accent : root.foreground
        opacity: root.selected ? 0.92 : 0.44
        elide: Text.ElideRight
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.chosen()
  }
}
