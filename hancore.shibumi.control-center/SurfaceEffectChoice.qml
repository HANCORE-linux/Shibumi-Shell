pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string effectKey
  required property string label
  required property string detail
  property bool selected: false
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property real uiScale: 1
  signal clicked()

  height: Commons.Style.space(52)
  activeFocusOnTab: true
  Accessible.role: Accessible.CheckBox
  Accessible.name: label
  Accessible.description: detail
  Accessible.checked: selected
  radius: controller.controlRadius
  color: pointer.containsMouse
    ? controller.buttonHoverFillColor : controller.buttonFillColor
  border.width: selected || activeFocus
    ? Math.max(1, controller.controlBorderWidth)
    : controller.controlBorderWidth
  border.color: selected ? accent : activeFocus ? foreground
    : pointer.containsMouse ? controller.buttonHoverBorderColor
    : controller.controlBorderColor

  Behavior on color { ColorAnimation { duration: 100 } }

  Item {
    id: preview

    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: Commons.Style.space(4)
    width: Math.min(parent.width - Commons.Style.space(12),
      Commons.Style.space(52))
    height: Commons.Style.space(28)

    Grid {
      id: frostPattern

      anchors.centerIn: sample
      width: sample.width - Commons.Style.space(6)
      height: sample.height - Commons.Style.space(4)
      visible: root.effectKey === "frost"
      columns: 4
      rows: 2

      Repeater {
        model: 8

        delegate: Rectangle {
          required property int index
          width: frostPattern.width / frostPattern.columns
          height: frostPattern.height / frostPattern.rows
          color: (index + Math.floor(index / frostPattern.columns)) % 2 === 0
            ? Commons.Util.alpha(root.accent, 0.62)
            : Commons.Util.alpha(root.foreground, 0.22)
        }
      }
    }

    RectangularShadow {
      anchors.fill: sample
      visible: root.effectKey === "shadow"
      radius: sample.radius
      blur: 6
      spread: 0
      offset: Qt.vector2d(0, 2)
      color: Qt.rgba(0, 0, 0, 0.72)
    }

    Rectangle {
      id: sample

      anchors.centerIn: parent
      width: Math.min(parent.width, Commons.Style.space(44))
      height: Commons.Style.space(15)
      radius: height / 2
      color: root.effectKey === "frost"
        ? Commons.Util.alpha(root.controller.marketPanelRaised, 0.68)
        : Commons.Util.alpha(root.foreground, 0.11)
      border.width: root.effectKey === "border"
        || root.effectKey === "frost" ? 1 : 0
      border.color: root.selected
        ? root.accent : Commons.Util.alpha(root.foreground, 0.64)

      Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Commons.Style.space(2)
        width: parent.width - Commons.Style.space(12)
        height: 1
        visible: root.effectKey === "frost"
        color: Commons.Util.alpha(root.foreground, 0.46)
      }
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Commons.Style.space(4)
    text: root.label
    color: root.selected ? root.accent : root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: root.selected ? Font.DemiBold : Font.Normal
    font.letterSpacing: 0.25
    renderType: Text.NativeRendering
  }

  Rectangle {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Commons.Style.space(5)
    width: Commons.Style.space(4)
    height: width
    radius: width / 2
    visible: root.selected
    color: root.accent
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
