pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/lib/presentation" as Presentation

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var powerService
  readonly property var powerState: powerService || ({ percent: 0, batteryStatus: "",
    timeText: "", charging: false, batteryHealthText: "", batteryId: "",
    changeRate: 0, batteryInfo: ({}) })

  owner: ownerWidget
  open: ownerWidget.opened && !!powerService && powerService.hasBattery
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
        text: panel.powerState.percent + "%"
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
          width: parent.width * panel.powerState.percent / 100
          height: parent.height
          radius: height / 2
          color: panel.bar ? panel.bar.urgent : Commons.Color.accent
          Behavior on width { NumberAnimation { duration: 300 } }
        }
      }

      Column {
        width: parent.width
        spacing: Commons.Style.space(5)
        BatteryInfoRow { label: "Status"; value: panel.powerState.batteryStatus }
        BatteryInfoRow {
          visible: panel.powerState.timeText !== ""
          label: panel.powerState.charging ? "Time to full" : "Time left"
          value: panel.powerState.timeText
        }
        BatteryInfoRow {
          visible: panel.powerState.batteryHealthText !== ""
          label: panel.powerState.batteryId !== ""
            ? "Health (" + panel.powerState.batteryId + ")" : "Health"
          value: panel.powerState.batteryHealthText
        }
        BatteryInfoRow {
          visible: panel.powerState.changeRate > 0
          label: panel.powerState.charging ? "Charge rate" : "Power draw"
          value: panel.powerState.changeRate.toFixed(1) + " W"
        }
        BatteryInfoRow {
          visible: panel.powerState.batteryInfo.size !== undefined
          label: "Battery size"
          value: String(panel.powerState.batteryInfo.size || "")
        }
        BatteryInfoRow {
          visible: panel.powerState.batteryInfo.cycles !== undefined
          label: "Charge cycles"
          value: String(panel.powerState.batteryInfo.cycles || "")
        }
        BatteryInfoRow {
          visible: panel.powerState.batteryInfo.threshold !== undefined
          label: "Charge threshold"
          value: String(panel.powerState.batteryInfo.threshold || "")
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

    Presentation.IconText {
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

    Presentation.ShibumiPillToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
