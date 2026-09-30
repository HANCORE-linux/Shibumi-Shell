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
  padding: 12
  contentWidth: fittedContentWidth(320)
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
        Presentation.PanelHeading {
          width: parent.width - closeAction.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: "BATTERY"
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
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

      Row {
        width: parent.width; height: batteryRing.height; spacing: Commons.Style.space(16)
        BatteryRing {
          id: batteryRing
          percent: panel.powerState.percent
          foreground: panel.controlForeground; accent: panel.controlAccent
          panelOpen: panel.open; waves: true; plasma: panel.powerState.charging
        }
        Grid {
          id: primaryStats
          width: parent.width - batteryRing.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          columns: 2; columnSpacing: Commons.Style.space(8); rowSpacing: Commons.Style.space(8)
          BatteryStat { label: "Charge"; value: panel.powerState.percent + "%"; valueColor: panel.controlAccent }
          BatteryStat { label: "Status"; value: panel.powerState.batteryStatus }
          BatteryStat { label: panel.powerState.charging ? "Time to full" : "Time left"; value: panel.powerState.timeText || "—" }
          BatteryStat { label: panel.powerState.charging ? "Charge rate" : "Power draw"; value: panel.powerState.changeRate > 0 ? panel.powerState.changeRate.toFixed(1) + " W" : "—" }
        }
      }

      Grid {
        x: primaryStats.x
        width: primaryStats.width
        columns: 2
        columnSpacing: Commons.Style.space(8)
        rowSpacing: Commons.Style.space(8)
        BatteryStat {
          visible: panel.powerState.batteryHealthText !== ""
          label: panel.powerState.batteryId !== ""
            ? "Health (" + panel.powerState.batteryId + ")" : "Health"
          value: panel.powerState.batteryHealthText
        }
        BatteryStat {
          visible: panel.powerState.batteryInfo.size !== undefined
          label: "Battery size"
          value: String(panel.powerState.batteryInfo.size || "")
        }
        BatteryStat {
          visible: panel.powerState.batteryInfo.cycles !== undefined
          label: "Charge cycles"
          value: String(panel.powerState.batteryInfo.cycles || "")
        }
        BatteryStat {
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

  component BatteryStat: Column {
    required property string label
    required property string value
    property color valueColor: panel.controlForeground
    width: (parent.width - Commons.Style.space(8)) / 2
    spacing: Commons.Style.space(3)
    Text {
      width: parent.width; text: parent.value; elide: Text.ElideRight
      color: parent.valueColor; font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.subtitle; renderType: Text.NativeRendering
    }
    Text {
      width: parent.width; text: parent.label.toUpperCase(); elide: Text.ElideRight
      color: panel.controlMutedHigh; font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption; renderType: Text.NativeRendering
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
