pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string glyph
  required property string label
  property string provider: "Shibumi"
  property string relationship: ""
  property bool inserted: false
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  signal toggled()

  implicitHeight: Commons.Style.space(78)
  radius: 0
  color: pointer.containsMouse
    ? controller.controlHoverFillColor : controller.controlFillColor
  border.width: 1
  border.color: inserted ? accent : controller.controlBorderColor

  Row {
    anchors.fill: parent
    anchors.margins: Commons.Style.space(10)
    spacing: Commons.Style.space(10)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(42)
      height: width
      radius: 0
      color: Commons.Util.alpha(root.accent, 0.09)
      border.width: 1
      border.color: root.controller.controlBorderColor

      IconText {
        anchors.centerIn: parent
        text: root.glyph
        color: root.inserted ? root.accent : root.foreground
        font.pixelSize: Commons.Style.space(22) * root.uiScale
        font.weight: Font.Medium
        fill: 0
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x
      spacing: Commons.Style.space(4)

      Text {
        width: parent.width
        text: root.label
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        font.weight: Font.DemiBold
      }

      Row {
        width: parent.width
        spacing: Commons.Style.space(7)

        Text {
          width: parent.width - statusLabel.implicitWidth - parent.spacing
          text: root.relationship !== "" ? root.relationship : root.provider
          color: root.foreground
          opacity: 0.46
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
        }

        Text {
          id: statusLabel
          text: root.inserted ? "INSTALLED" : "AVAILABLE"
          color: root.inserted ? root.accent : root.foreground
          opacity: root.inserted ? 1 : 0.54
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
          font.letterSpacing: 0.45
        }
      }
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }
}
