pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var controller
  property string selectedProvider: "All"
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property string title: "SOURCE"
  property var options: ["All", "Shibumi", "Omarchy Quattro", "Third-party"]
  readonly property real filterFontSize:
    Commons.Style.font.caption * uiScale
  readonly property int filterFontWeight: Font.Medium
  signal selected(string provider)

  implicitHeight: Commons.Style.space(34)

  Rectangle {
    anchors.fill: parent
    radius: root.controller.controlRadius
    clip: true
    color: "transparent"
    border.width: 1
    border.color: root.controller.controlBorderColor

    Row {
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(10)
      anchors.rightMargin: Commons.Style.space(10)
      spacing: Commons.Style.space(17)

      Text {
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: root.title
        color: root.foreground
        opacity: 0.48
        font.family: root.controller.marketFont
        font.pixelSize: root.filterFontSize
        font.weight: root.filterFontWeight
        font.letterSpacing: 1
      }

      Repeater {
        model: root.options

        delegate: Item {
          id: option
          required property string modelData
          readonly property bool active:
            root.selectedProvider === option.modelData
          width: label.implicitWidth
          height: parent.height

          Text {
            id: label
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: option.modelData
            color: option.active ? root.accent : root.foreground
            opacity: option.active ? 1
              : optionPointer.containsMouse ? 0.82 : 0.48
            font.family: root.controller.marketFont
            font.pixelSize: root.filterFontSize
            font.weight: root.filterFontWeight
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Commons.Style.space(2)
            color: root.accent
            visible: option.active
          }

          MouseArea {
            id: optionPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selected(option.modelData)
          }
        }
      }
    }
  }
}
