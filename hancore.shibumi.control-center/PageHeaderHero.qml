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

  width: parent ? parent.width : implicitWidth
  implicitHeight: Commons.Style.space(112)

  Row {
    anchors.fill: parent
    spacing: Commons.Style.space(16)

    Column {
      width: parent.width - motionStage.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
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
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }

    PageMotionStage {
      id: motionStage
      width: Math.min(Commons.Style.space(220), parent.width * 0.43)
      height: parent.height
      controller: root.controller
      active: root.active
      pageKey: root.pageKey
      foreground: root.foreground
      accent: root.accent
    }
  }
}
