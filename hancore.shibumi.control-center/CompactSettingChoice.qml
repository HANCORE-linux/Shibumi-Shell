pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string label
  property bool selected: false
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property real uiScale: 1
  property real fontSize: Commons.Style.font.bodySmall * uiScale
  property int textWeight: selected || primary
    ? Font.DemiBold : Font.Normal
  property int horizontalPadding: Commons.Style.space(6)
  property int controlHeight: Commons.Style.space(25)
  property bool primary: false
  signal clicked()

  implicitHeight: controlHeight
  opacity: enabled ? 1 : 0.34
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: label
  radius: controller.controlRadius
  color: pointer.containsMouse
    ? controller.buttonHoverFillColor : controller.buttonFillColor
  border.width: controller.controlBorderWidth
  border.color: selected || primary || activeFocus ? accent
    : pointer.containsMouse ? controller.buttonHoverBorderColor
    : controller.controlBorderColor

  Behavior on color { ColorAnimation { duration: 100 } }

  Text {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.horizontalPadding
    anchors.rightMargin: root.horizontalPadding
    text: root.label
    color: root.selected || root.primary ? root.accent : root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: root.fontSize
    font.weight: root.textWeight
    font.letterSpacing: 0.35
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  Keys.onReturnPressed: if (enabled) root.clicked()
  Keys.onEnterPressed: if (enabled) root.clicked()
  Keys.onSpacePressed: if (enabled) root.clicked()
}
