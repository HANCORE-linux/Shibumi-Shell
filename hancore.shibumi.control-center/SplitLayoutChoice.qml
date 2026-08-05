pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string label
  required property string detail
  required property bool splitAll
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property real uiScale: 1
  signal clicked()

  height: Commons.Style.space(52)
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: label
  Accessible.description: detail
  radius: controller.controlRadius
  color: pointer.containsMouse
    ? controller.buttonHoverFillColor : controller.buttonFillColor
  border.width: activeFocus
    ? Math.max(1, controller.controlBorderWidth)
    : controller.controlBorderWidth
  border.color: activeFocus ? accent
    : pointer.containsMouse ? controller.buttonHoverBorderColor
    : controller.controlBorderColor

  Behavior on color { ColorAnimation { duration: 100 } }

  Item {
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: Commons.Style.space(4)
    width: Math.min(parent.width - Commons.Style.space(12),
      Commons.Style.space(52))
    height: Commons.Style.space(28)

    Row {
      id: splitPreview

      anchors.centerIn: parent
      spacing: Commons.Style.space(3)
      visible: root.splitAll

      Repeater {
        model: 3

        delegate: Rectangle {
          required property int index
          width: Commons.Style.space(14)
          height: width
          radius: height / 2
          color: Commons.Util.alpha(root.foreground, 0.11)
          border.width: 1
          border.color: Commons.Util.alpha(root.foreground, 0.64)

          Rectangle {
            anchors.centerIn: parent
            width: Commons.Style.space(4)
            height: width
            radius: width / 2
            color: Commons.Util.alpha(root.foreground, 0.56)
          }
        }
      }
    }

    Rectangle {
      id: mergePreview

      anchors.centerIn: parent
      width: Commons.Style.space(44)
      height: Commons.Style.space(14)
      radius: height / 2
      visible: !root.splitAll
      color: Commons.Util.alpha(root.foreground, 0.11)
      border.width: 1
      border.color: Commons.Util.alpha(root.foreground, 0.64)

      Row {
        anchors.centerIn: parent
        spacing: Commons.Style.space(7)

        Repeater {
          model: 3

          delegate: Rectangle {
            required property int index
            width: Commons.Style.space(4)
            height: width
            radius: width / 2
            color: Commons.Util.alpha(root.foreground, 0.56)
          }
        }
      }
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Commons.Style.space(4)
    text: root.label
    color: root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Normal
    font.letterSpacing: 0.25
    renderType: Text.NativeRendering
  }

  MouseArea {
    id: pointer

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()
}
