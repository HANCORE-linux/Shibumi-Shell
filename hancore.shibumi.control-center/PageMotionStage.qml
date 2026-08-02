pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  property bool active: false
  property string pageKey: ""
  property string label: ""
  property string detail: ""
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool interactive: false
  readonly property string semanticKey: pageKey.split(":")[0]
  property real previewScale: 1
  property real previewOpacity: 0.62
  signal clicked()

  implicitWidth: Commons.Style.space(220)
  implicitHeight: Commons.Style.space(112)
  activeFocusOnTab: interactive
  radius: controller.controlRadius
  color: (pointer.containsMouse || activeFocus) && interactive
    ? controller.controlHoverFillColor : controller.controlFillColor
  border.width: controller.controlBorderWidth
  border.color: (pointer.containsMouse || activeFocus) && interactive
    ? controller.controlHoverBorderColor : controller.controlBorderColor
  clip: true

  onPageKeyChanged: previewTransition.restart()

  Item {
    id: previewImage
    anchors.centerIn: parent
    width: parent.width - Commons.Style.space(32)
    height: parent.height - Commons.Style.space(24)
    scale: root.previewScale
    opacity: root.previewOpacity

    SemanticPreviewImage {
      anchors.fill: parent
      controller: root.controller
      routeId: root.semanticKey
      compact: true
      foreground: root.foreground
      accent: root.accent
    }
  }

  SequentialAnimation {
    id: previewTransition
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "previewOpacity"
        to: 0.18
        duration: 90
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root
        property: "previewScale"
        to: 0.96
        duration: 90
        easing.type: Easing.OutCubic
      }
    }
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "previewOpacity"
        to: 0.62
        duration: 240
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root
        property: "previewScale"
        to: 1
        duration: 280
        easing.type: Easing.OutCubic
      }
    }
  }

  Column {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: Commons.Style.space(12)
    anchors.topMargin: Commons.Style.space(10)
    spacing: Commons.Style.space(2)
    visible: root.label !== ""

    Text {
      text: root.label
      color: root.accent
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption
      font.weight: Font.DemiBold
      font.letterSpacing: 1
    }

    Text {
      text: root.detail
      color: root.foreground
      opacity: 0.54
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Keys.onReturnPressed: function(event) {
    if (root.interactive) root.clicked()
    event.accepted = root.interactive
  }
  Keys.onEnterPressed: function(event) {
    if (root.interactive) root.clicked()
    event.accepted = root.interactive
  }
  Keys.onSpacePressed: function(event) {
    if (root.interactive) root.clicked()
    event.accepted = root.interactive
  }
}
