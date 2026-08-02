pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  property string routeId: "bars"
  property string label: ""
  property string detail: ""
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText

  radius: controller.controlRadius
  color: controller.controlFillColor
  border.width: controller.controlBorderWidth
  border.color: controller.controlBorderColor

  SemanticPreviewImage {
    id: preview
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Commons.Style.space(13)
    height: Math.max(1, parent.height - Commons.Style.space(58))
    controller: root.controller
    routeId: root.routeId
    foreground: root.foreground
    accent: root.accent
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Commons.Style.space(11)
    spacing: 1

    Text {
      width: parent.width
      text: root.label
      color: root.foreground
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
      font.weight: Font.DemiBold
      horizontalAlignment: Text.AlignHCenter
    }
    Text {
      width: parent.width
      text: root.detail
      color: root.foreground
      opacity: 0.42
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }
}
