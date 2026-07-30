pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string styleValue
  required property string label
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  readonly property bool selected:
    String(controller.workspaceConfig.style || "default") === styleValue

  signal chosen(string styleValue)

  function ink(alpha) {
    return Qt.rgba(foreground.r, foreground.g, foreground.b, alpha)
  }

  height: Commons.Style.space(78)
  radius: controller.controlRadius
  color: selected || pointer.containsMouse
    ? controller.controlHoverFillColor : controller.controlFillColor
  border.width: selected ? Math.max(1, controller.controlBorderWidth) : 1
  border.color: selected ? accent : controller.controlBorderColor

  Row {
    id: markerRow
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Commons.Style.space(10)
    spacing: root.styleValue === "rings" || root.styleValue === "aurora"
      ? Commons.Style.space(3) : Commons.Style.space(2)

    Repeater {
      model: [1, 2, 3]

      delegate: Item {
        id: marker

        required property int modelData
        readonly property bool focused: modelData === 2
        readonly property bool occupied: modelData < 3

        width: root.styleValue === "numbers"
            || root.styleValue === "kanji" ? Commons.Style.space(22)
          : root.styleValue === "magic" ? Commons.Style.space(focused ? 20 : 18)
          : root.styleValue === "rings" ? Commons.Style.space(20)
          : root.styleValue === "aurora"
            ? Commons.Style.space(focused ? 34 : 12)
          : Commons.Style.space(focused ? 32 : 16)
        height: Commons.Style.space(24)

        Rectangle {
          visible: root.styleValue === "default"
          anchors.centerIn: parent
          width: Commons.Style.space(marker.focused ? 32 : 16)
          height: Commons.Style.space(16)
          radius: height / 2
          color: root.ink(marker.focused ? 0.20
            : marker.occupied ? 0.18 : 0.06)
        }

        Rectangle {
          visible: root.styleValue === "default"
          anchors.centerIn: parent
          width: Commons.Style.space(marker.focused ? 24 : 8)
          height: Commons.Style.space(8)
          radius: height / 2
          color: root.ink(marker.focused || marker.occupied ? 1 : 0.25)
        }

        Rectangle {
          visible: root.styleValue === "numbers"
          anchors.centerIn: parent
          width: Commons.Style.space(20)
          height: width
          radius: root.controller.controlRadius <= Commons.Style.space(5)
            ? Commons.Style.space(5) : height / 2
          color: root.ink(marker.focused ? 0.30
            : marker.occupied ? 0.12 : 0.04)

          Text {
            anchors.centerIn: parent
            text: marker.modelData
            color: root.ink(marker.focused ? 1
              : marker.occupied ? 0.58 : 0.32)
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
            font.weight: marker.focused ? Font.Bold : Font.Normal
          }
        }

        Text {
          visible: root.styleValue === "magic"
          anchors.centerIn: parent
          text: marker.focused ? "✦" : marker.occupied ? "✧" : "·"
          color: root.ink(marker.focused ? 1
            : marker.occupied ? 0.70 : 0.30)
          font.family: "Adwaita Mono"
          font.pixelSize: Commons.Style.space(marker.focused ? 20 : 17)
        }

        Text {
          visible: root.styleValue === "kanji"
          anchors.centerIn: parent
          text: ["一", "二", "三"][marker.modelData - 1]
          color: root.ink(marker.focused ? 1
            : marker.occupied ? 0.70 : 0.30)
          font.family: "Noto Sans CJK JP"
          font.pixelSize: Commons.Style.space(marker.focused ? 15 : 13)
        }

        Rectangle {
          visible: root.styleValue === "rings" && marker.focused
          anchors.centerIn: parent
          width: Commons.Style.space(18)
          height: width
          radius: Commons.Style.space(5)
          color: "transparent"
          border.width: 1
          border.color: root.foreground
          antialiasing: true
        }

        Text {
          visible: root.styleValue === "rings"
          anchors.centerIn: parent
          text: marker.modelData
          color: root.foreground
          opacity: marker.focused ? 1 : marker.occupied ? 0.64 : 0.24
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.space(12)
        }

        Rectangle {
          visible: root.styleValue === "aurora"
          anchors.centerIn: parent
          width: Commons.Style.space(
            marker.focused ? 27 : marker.occupied ? 6 : 4)
          height: Commons.Style.space(
            marker.focused ? 3 : marker.occupied ? 6 : 4)
          radius: height / 2
          color: root.foreground
          opacity: marker.focused ? 0.92 : marker.occupied ? 0.62 : 0.18
          antialiasing: true
        }
      }
    }
  }

  Row {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Commons.Style.space(7)
    anchors.rightMargin: Commons.Style.space(7)
    anchors.bottomMargin: Commons.Style.space(7)
    spacing: Commons.Style.space(4)

    Text {
      width: parent.width - stateMark.width - parent.spacing
      text: root.label
      color: root.foreground
      elide: Text.ElideRight
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.DemiBold
    }

    Text {
      id: stateMark
      anchors.verticalCenter: parent.verticalCenter
      text: root.selected ? "●" : ""
      color: root.accent
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.chosen(root.styleValue)
  }
}
