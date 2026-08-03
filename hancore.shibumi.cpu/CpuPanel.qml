pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var systemTelemetry
  required property var gpuTelemetry

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  padding: 12
  contentWidth: fittedContentWidth(320)
  contentHeight: fittedContentHeight(panelColumn.implicitHeight)

  Component.onCompleted: if (gpuTelemetry) gpuTelemetry.acquire()
  Component.onDestruction: if (gpuTelemetry) gpuTelemetry.release()

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }

    Column {
      id: panelColumn
      width: parent.width
      spacing: 8

      Item {
        width: parent.width
        height: 24

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "CPU · GPU"
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 13
          font.letterSpacing: 2
          font.weight: Font.Medium
          renderType: Text.NativeRendering
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "\u2715"
          color: closeMouse.containsMouse
            ? panel.controlAccent : panel.controlMuted
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 12
          renderType: Text.NativeRendering

          Behavior on color { ColorAnimation { duration: 120 } }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.ownerWidget.close()
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
          panel.bar.foreground.b, 0.18) : Commons.Color.popups.border
      }

      UsageRow {
        width: parent.width
        label: "CPU"
        value: panel.systemTelemetry.cpuPercent
        bar: panel.bar
      }

      UsageRow {
        width: parent.width
        visible: panel.gpuTelemetry && panel.gpuTelemetry.available
        label: "GPU"
        value: panel.gpuTelemetry ? panel.gpuTelemetry.utilization : 0
        bar: panel.bar
      }

      Row {
        width: parent.width
        visible: panel.gpuTelemetry && panel.gpuTelemetry.available
          && panel.gpuTelemetry.temperatureC > 0

        Text {
          width: parent.width * 0.4
          text: "Temperature"
          color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
            panel.bar.foreground.b, 0.65) : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }
        Text {
          width: parent.width * 0.3
          text: panel.gpuTelemetry ? panel.gpuTelemetry.temperatureC + "°C" : ""
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }
      }

      Row {
        width: parent.width
        visible: panel.gpuTelemetry && panel.gpuTelemetry.memoryTotalMiB > 0

        Text {
          width: parent.width * 0.4
          text: "VRAM"
          color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
            panel.bar.foreground.b, 0.65) : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }
        Text {
          width: parent.width * 0.3
          text: panel.gpuTelemetry
            ? panel.gpuTelemetry.memoryUsedMiB + " / " + panel.gpuTelemetry.memoryTotalMiB + " MiB"
            : ""
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Rectangle {
        width: parent.width
        height: 28
        radius: panel.controlRadius
        color: monitorMouse.containsMouse
          ? panel.controlPrimaryHoverColor
          : panel.bar ? panel.bar.urgent : Commons.Color.accent

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          anchors.centerIn: parent
          text: "Open btop"
          color: panel.bar ? panel.bar.background : Commons.Color.background
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: monitorMouse
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

  component UsageRow: Item {
    id: usageRow

    required property string label
    required property int value
    required property var bar

    height: 16

    Text {
      id: usageLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      color: parent.bar ? Qt.rgba(parent.bar.foreground.r, parent.bar.foreground.g,
        parent.bar.foreground.b, 0.65) : Commons.Color.foreground
      font.family: parent.bar ? parent.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: 11
      font.letterSpacing: 1
      renderType: Text.NativeRendering
    }

    Text {
      id: usageValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.value + "%"
      color: parent.bar ? parent.bar.urgent : Commons.Color.accent
      font.family: parent.bar ? parent.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: 11
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }

    Rectangle {
      anchors.left: usageLabel.right
      anchors.leftMargin: 8
      anchors.right: usageValue.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      height: 8
      radius: height / 2
      color: panel.controlActiveFillColor

      Rectangle {
        width: parent.width * Math.max(0, Math.min(100, usageRow.value)) / 100
        height: parent.height
        radius: height / 2
        color: usageRow.bar ? usageRow.bar.urgent : Commons.Color.accent
        Behavior on width { NumberAnimation { duration: 300 } }
      }
    }
  }
}
