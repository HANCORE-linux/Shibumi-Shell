pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var panel
  property string text: ""
  property string iconText: ""
  property bool materialIcon: false
  property string tooltipText: ""
  property bool selected: false
  property bool primary: false
  property bool destructive: false
  property color accent: panel.controlAccent
  property int fontSize: Commons.Style.font.bodySmall
  property int fontWeight: selected ? Font.Medium : Font.Normal
  property int controlHeight: Commons.Style.space(26)
  property int horizontalPadding: Commons.Style.space(8)
  property color idleTextColor: panel.controlForeground
  property color hoverTextColor: actionColor
  property color hoverBorderColor: actionColor
  signal clicked()

  readonly property bool hovered: pointer.containsMouse && enabled
  readonly property color actionColor: destructive
    ? (panel.bar ? panel.bar.urgent : panel.controlAccent) : accent

  implicitWidth: content.implicitWidth + horizontalPadding * 2
  implicitHeight: controlHeight
  radius: panel.shibumiTokens ? panel.shibumiTokens.tileRadius
    : Commons.Style.space(6)
  opacity: enabled ? 1 : 0.42
  color: primary
    ? (hovered ? panel.controlPrimaryHoverColor : actionColor)
    : selected ? panel.controlActiveFillColor
      : hovered ? panel.controlHoverFillColor : panel.controlFillColor
  border.width: primary ? 0 : panel.controlBorderWidth
  border.color: selected || hovered
    ? (selected ? actionColor : hoverBorderColor) : panel.controlBorderColor

  Behavior on color { ColorAnimation { duration: 100 } }
  Behavior on border.color { ColorAnimation { duration: 100 } }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.iconText !== "" && root.text !== ""
      ? Commons.Style.space(5) : 0

    Text {
      visible: root.iconText !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconText
      color: root.primary ? Commons.Color.background
        : root.selected ? root.actionColor
          : root.hovered ? root.hoverTextColor : root.idleTextColor
      font.family: root.materialIcon ? "Material Symbols Rounded"
        : root.panel.bar ? root.panel.bar.fontFamily : Commons.Style.font.family
      font.variableAxes: root.materialIcon ? ({ "FILL": 0 }) : ({})
      font.pixelSize: root.fontSize + 1
    }

    Text {
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.primary ? Commons.Color.background
        : root.selected ? root.actionColor
          : root.hovered ? root.hoverTextColor : root.idleTextColor
      font.family: root.panel.bar
        ? root.panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.fontSize
      font.weight: root.fontWeight
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  ShibumiPanelToolTip {
    panel: root.panel
    visible: root.tooltipText !== "" && pointer.containsMouse
    text: root.tooltipText
  }
}
