pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var controller
  property bool active: false
  property string pageKey: ""
  property string eyebrow: ""
  property string title: ""
  property string description: ""
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property real uiScale: 1
  property real preferredHeight: Commons.Style.space(80)
  property real previewWidth: Commons.Style.space(150)
  property string actionLabel: ""
  property string actionGlyph: ""
  signal actionRequested()

  width: parent ? parent.width : implicitWidth
  implicitHeight: preferredHeight

  Row {
    anchors.fill: parent
    spacing: Commons.Style.space(16)

    Column {
      width: parent.width - trailingStage.width - parent.spacing
      anchors.top: parent.top
      anchors.topMargin: Commons.Style.space(5)
      spacing: Commons.Style.space(7)

      Text {
        width: parent.width
        text: root.eyebrow
        color: root.accent
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
      }

      Text {
        width: parent.width
        text: root.title
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.space(24) * root.uiScale
        font.weight: Font.DemiBold
      }

      Text {
        width: parent.width
        visible: root.description !== ""
        text: root.description
        color: root.foreground
        opacity: 0.58
        wrapMode: Text.NoWrap
        maximumLineCount: 1
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }

    Item {
      id: trailingStage
      width: Math.min(root.previewWidth, parent.width * 0.43)
      height: parent.height

      PageMotionStage {
        anchors.fill: parent
        visible: root.actionLabel === ""
        controller: root.controller
        active: root.active
        pageKey: root.pageKey
        foreground: root.foreground
        accent: root.accent
      }

      Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.actionLabel !== ""
        width: Commons.Style.space(116)
        height: Commons.Style.space(34)
        radius: root.controller.controlRadius
        color: actionPointer.containsMouse
          ? root.controller.controlHoverFillColor
          : root.controller.controlFillColor
        border.width: root.controller.controlBorderWidth
        border.color: root.controller.controlBorderColor

        Row {
          anchors.centerIn: parent
          spacing: Commons.Style.space(6)

          IconText {
            visible: root.actionGlyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.actionGlyph
            color: root.accent
            font.pixelSize: Commons.Style.space(17) * root.uiScale
            font.weight: Font.Medium
            fill: 0
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.actionLabel
            color: root.foreground
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
            font.weight: Font.Medium
          }
        }

        MouseArea {
          id: actionPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.actionRequested()
        }
      }
    }
  }
}
