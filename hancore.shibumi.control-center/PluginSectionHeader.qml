pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string title
  property int count: 0
  property bool expanded: true
  property bool collapsible: true
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property color countColor: foreground
  signal toggled()

  implicitHeight: Commons.Style.space(28)
  radius: controller.controlRadius
  color: pointer.containsMouse && collapsible
    ? controller.controlHoverFillColor : "transparent"

  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Commons.Style.space(7)
    spacing: Commons.Style.space(7)

    IconText {
      visible: root.collapsible
      anchors.verticalCenter: parent.verticalCenter
      text: root.expanded ? "expand_more" : "chevron_right"
      color: root.expanded ? root.accent : root.foreground
      opacity: root.expanded ? 1 : 0.52
      font.pixelSize: Commons.Style.space(16) * root.uiScale
      fill: 0
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.title
      color: root.title === "PROVIDER SWITCHES"
        ? root.accent : root.foreground
      opacity: root.title === "PROVIDER SWITCHES" ? 1 : 0.54
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.DemiBold
      font.letterSpacing: 0.9
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.count
      color: root.countColor
      opacity: 1
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.DemiBold
      font.letterSpacing: 0.9
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: root.collapsible
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.toggled()
  }
}
