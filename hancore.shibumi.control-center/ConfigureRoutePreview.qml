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
  property real previewScale: 1
  property real previewOpacity: 1

  radius: controller.controlRadius
  color: controller.controlFillColor
  border.width: controller.controlBorderWidth
  border.color: controller.controlBorderColor

  onRouteIdChanged: previewTransition.restart()

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
    scale: root.previewScale
    opacity: root.previewOpacity
  }

  SequentialAnimation {
    id: previewTransition
    ParallelAnimation {
      NumberAnimation {
        target: root; property: "previewOpacity"
        to: 0.22; duration: 80; easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root; property: "previewScale"
        to: 0.97; duration: 80; easing.type: Easing.OutCubic
      }
    }
    ParallelAnimation {
      NumberAnimation {
        target: root; property: "previewOpacity"
        to: 1; duration: 220; easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root; property: "previewScale"
        to: 1; duration: 260; easing.type: Easing.OutCubic
      }
    }
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
