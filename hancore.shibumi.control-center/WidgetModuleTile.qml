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
  property bool editable: false
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  signal toggled()
  signal editRequested()

  implicitHeight: Commons.Style.space(66)
  radius: controller.controlRadius
  color: pointer.containsMouse
    ? controller.controlHoverFillColor : controller.controlFillColor
  border.width: controller.controlBorderWidth
  border.color: controller.controlBorderColor

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 2
    visible: root.editable && pointer.containsMouse
    color: root.accent
  }

  Row {
    anchors.fill: parent
    anchors.margins: Commons.Style.space(8)
    spacing: Commons.Style.space(8)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(36)
      height: width
      radius: root.controller.controlRadius
      color: Commons.Util.alpha(root.accent, 0.09)
      border.width: 1
      border.color: root.controller.controlBorderColor

      IconText {
        anchors.centerIn: parent
        text: root.glyph
        color: root.inserted ? root.accent : root.foreground
        font.pixelSize: Commons.Style.space(19) * root.uiScale
        font.weight: Font.Medium
        fill: 0
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - enableSwitch.width - parent.spacing
      spacing: Commons.Style.space(3)

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
          text: root.editable ? "EDIT ›"
            : root.inserted ? "ACTIVE" : "AVAILABLE"
          color: root.editable ? root.accent : root.foreground
          opacity: root.editable ? 1 : 0.54
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
          font.letterSpacing: 0.45
        }
      }
    }

    Rectangle {
      id: enableSwitch
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(30)
      height: Commons.Style.space(17)
      radius: height / 2
      color: root.inserted ? root.accent : root.controller.controlHoverFillColor

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.inserted ? parent.width - width - Commons.Style.space(2)
          : Commons.Style.space(2)
        width: Commons.Style.space(13)
        height: width
        radius: width / 2
        color: root.inserted
          ? root.controller.marketBackground : root.foreground
        opacity: root.inserted ? 1 : 0.54
      }

      MouseArea {
        anchors.fill: parent
        anchors.margins: -Commons.Style.space(7)
        z: 2
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
      }
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.editable) root.editRequested()
      else root.toggled()
    }
  }
}
