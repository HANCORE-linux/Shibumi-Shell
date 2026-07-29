pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var powerService

  owner: ownerWidget
  open: ownerWidget.opened && powerService.hasBattery
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(300))
  contentHeight: fittedContentHeight(column.implicitHeight)

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }

    Column {
      id: column
      width: parent.width
      spacing: Commons.Style.space(8)

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)
        Text {
          width: parent.width - closeAction.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: "Battery"
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.heading
          font.weight: Font.Medium
        }
        IconAction {
          id: closeAction
          anchors.verticalCenter: parent.verticalCenter
          icon: "close"
          tooltip: "Close"
          onClicked: panel.ownerWidget.close()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
          panel.bar.foreground.b, 0.18) : Commons.Color.popups.border
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: panel.powerService.percent + "%"
        color: panel.bar ? panel.bar.urgent : Commons.Color.accent
        font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.heading
        font.weight: Font.Medium
      }

      Rectangle {
        width: parent.width
        height: Commons.Style.space(8)
        radius: height / 2
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
          panel.bar.foreground.b, 0.12) : Commons.Color.background
        Rectangle {
          width: parent.width * panel.powerService.percent / 100
          height: parent.height
          radius: height / 2
          color: panel.bar ? panel.bar.urgent : Commons.Color.accent
          Behavior on width { NumberAnimation { duration: 300 } }
        }
      }

      Column {
        width: parent.width
        spacing: Commons.Style.space(5)
        BatteryInfoRow { label: "Status"; value: panel.powerService.batteryStatus }
        BatteryInfoRow {
          visible: panel.powerService.timeText !== ""
          label: panel.powerService.charging ? "Time to full" : "Time left"
          value: panel.powerService.timeText
        }
        BatteryInfoRow {
          visible: panel.powerService.batteryHealthText !== ""
          label: panel.powerService.batteryId !== ""
            ? "Health (" + panel.powerService.batteryId + ")" : "Health"
          value: panel.powerService.batteryHealthText
        }
        BatteryInfoRow {
          visible: panel.powerService.changeRate > 0
          label: panel.powerService.charging ? "Charge rate" : "Power draw"
          value: panel.powerService.changeRate.toFixed(1) + " W"
        }
        BatteryInfoRow {
          visible: panel.powerService.batteryInfo.size !== undefined
          label: "Battery size"
          value: String(panel.powerService.batteryInfo.size || "")
        }
        BatteryInfoRow {
          visible: panel.powerService.batteryInfo.cycles !== undefined
          label: "Charge cycles"
          value: String(panel.powerService.batteryInfo.cycles || "")
        }
        BatteryInfoRow {
          visible: panel.powerService.batteryInfo.threshold !== undefined
          label: "Charge threshold"
          value: String(panel.powerService.batteryInfo.threshold || "")
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
          panel.bar.foreground.b, 0.18) : Commons.Color.popups.border
      }

      Rectangle {
        width: parent.width
        height: Commons.Style.space(30)
        radius: panel.controlRadius
        color: btopMouse.containsMouse && panel.bar
          ? Qt.lighter(panel.bar.urgent, 1.08)
          : panel.bar ? panel.bar.urgent : Commons.Color.accent
        Text {
          anchors.centerIn: parent
          text: "Open btop"
          color: panel.bar ? panel.bar.background : Commons.Color.background
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.body
        }
        MouseArea {
          id: btopMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            panel.ownerWidget.close()
            panel.ownerWidget.openSystemMonitor()
          }
        }
      }
    }
  }

  component BatteryInfoRow: Row {
    required property string label
    required property string value
    width: parent ? parent.width : 0
    height: Commons.Style.space(16)
    spacing: Commons.Style.space(6)
    Text {
      id: infoLabel
      width: parent.width * 0.45
      text: parent.label
      color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
        panel.bar.foreground.b, 0.65) : Commons.Color.foreground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.body
    }
    Text {
      width: Math.max(0, parent.width - infoLabel.width - parent.spacing)
      text: parent.value
      color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.body
      elide: Text.ElideRight
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

    IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
