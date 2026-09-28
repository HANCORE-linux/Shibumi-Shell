pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var systemTelemetry
  required property var gpuTelemetry
  readonly property string cpuModelText: cpuModelLabel.text
  readonly property string loadAverageText: systemTelemetry && systemTelemetry.loadAverage.length === 3
    ? systemTelemetry.loadAverage.map(value => value.toFixed(2)).join(" / ") : "—"
  readonly property var gpuUsageView: gpuUsage

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  padding: 12
  contentWidth: fittedContentWidth(320)
  contentHeight: fittedContentHeight(panelColumn.implicitHeight)

  property var acquiredGpuTelemetry: null
  property var acquiredSystemTelemetry: null
  function openMonitor() {
    const owner = panel.ownerWidget, accepted = panel.ownerWidget.openSystemMonitor()
    if (accepted) owner.close()
    return accepted
  }
  function syncGpuLease() {
    const system = open ? systemTelemetry : null
    if (acquiredSystemTelemetry !== system) {
      if (acquiredSystemTelemetry) acquiredSystemTelemetry.release("cpuPanel")
      acquiredSystemTelemetry = system
      if (system) system.acquire("cpuPanel")
    }
    const next = open ? gpuTelemetry : null
    if (acquiredGpuTelemetry === next) return
    if (acquiredGpuTelemetry) acquiredGpuTelemetry.release()
    acquiredGpuTelemetry = next
    if (acquiredGpuTelemetry) acquiredGpuTelemetry.acquire()
  }
  onGpuTelemetryChanged: syncGpuLease()
  onSystemTelemetryChanged: syncGpuLease()
  onOpenChanged: syncGpuLease()
  Component.onCompleted: syncGpuLease()
  Component.onDestruction: {
    if (acquiredGpuTelemetry) acquiredGpuTelemetry.release()
    if (acquiredSystemTelemetry) acquiredSystemTelemetry.release("cpuPanel")
  }

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
          text: gpuUsage.visible ? "CPU · GPU" : "CPU"
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

      Text {
        id: cpuModelLabel
        width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
        text: panel.systemTelemetry ? panel.systemTelemetry.cpuModel : ""
        color: panel.controlMutedHigh; renderType: Text.NativeRendering
        font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
          panel.bar.foreground.b, 0.18) : Commons.Color.popups.border
      }

      Row {
        width: parent.width
        height: cpuDial.height
        spacing: Commons.Style.space(16)

        Item {
          id: cpuDial
          width: Commons.Style.space(80); height: width
          WaterRing {
            id: gpuUsage
            anchors.fill: parent
            visible: panel.gpuTelemetry && panel.gpuTelemetry.available
              && panel.ownerWidget.gpuActivitySeen === true
            percent: panel.gpuTelemetry ? panel.gpuTelemetry.utilization : 0
            readonly property color panelBackground: panel.surfaceOverrideEnabled ? panel.surfaceColorOverride
              : panel.shibumiTokens ? panel.shibumiTokens.panelBackground : Commons.Color.popups.background
            readonly property bool lightSurface: panelBackground.hslLightness > panel.controlForeground.hslLightness
            readonly property color lightTone: lightSurface ? panelBackground : panel.controlForeground
            foreground: panel.controlForeground
            accent: Qt.tint(panel.controlAccent, Qt.rgba(lightTone.r, lightTone.g, lightTone.b, lightSurface ? 0.78 : 0.55))
            waterOpacity: 0.65
            holeRatio: 0.78; phaseOffset: Math.PI; progressArc: false
            panelOpen: panel.open && visible
          }
          CpuRing {
            id: cpuRing
            anchors.centerIn: parent
            width: gpuUsage.visible ? Commons.Style.space(48) : parent.width
            height: width
            percent: panel.systemTelemetry ? panel.systemTelemetry.cpuPercent : 0
            foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
            accent: panel.bar ? panel.bar.urgent : Commons.Color.accent
            water: true; panelOpen: panel.open; outlined: !gpuUsage.visible
          }
          Text {
            visible: gpuUsage.visible
            anchors.centerIn: parent; text: "CPU"
            color: panel.controlForeground; font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption; renderType: Text.NativeRendering
          }
          Text {
            visible: gpuUsage.visible
            anchors.horizontalCenter: parent.horizontalCenter; y: Commons.Style.space(3)
            text: "GPU"; color: panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption; renderType: Text.NativeRendering
          }
        }

        Grid {
          width: parent.width - cpuDial.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          columns: 2; columnSpacing: Commons.Style.space(8); rowSpacing: Commons.Style.space(8)
          Repeater {
            model: gpuUsage.visible ? ["CPU", "GPU", "Load 1 min", "Load 5 / 15"]
              : ["Usage", "Load 1 min", "Load 5 min", "Load 15 min"]
            CpuStatRow {
              required property int index; required property string modelData
              width: (parent.width - parent.columnSpacing) / 2
              label: modelData
              value: index === 0 ? cpuRing.percent + "%"
                : gpuUsage.visible && index === 1 ? panel.gpuTelemetry.utilization + "%"
                : panel.systemTelemetry && panel.systemTelemetry.loadAverage.length === 3
                  ? gpuUsage.visible ? index === 2 ? panel.systemTelemetry.loadAverage[0].toFixed(2)
                    : panel.systemTelemetry.loadAverage.slice(1).map(value => value.toFixed(2)).join(" / ")
                  : panel.systemTelemetry.loadAverage[index - 1].toFixed(2) : "—"
              bar: panel.bar
            }
          }
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
        radius: panel.renderedSurfaceRadius
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
          onClicked: panel.openMonitor()
        }
      }
    }
  }

  component CpuStatRow: Item {
    required property string label
    required property string value
    required property var bar
    implicitHeight: valueText.height + Commons.Style.space(3) + labelText.height

    Text {
      id: labelText
      y: valueText.height + Commons.Style.space(3); width: parent.width
      text: parent.label.toUpperCase()
      color: parent.bar ? Qt.rgba(parent.bar.foreground.r, parent.bar.foreground.g,
        parent.bar.foreground.b, 0.65) : Commons.Color.foreground
      font.family: parent.bar ? parent.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      renderType: Text.NativeRendering
    }
    Text {
      id: valueText
      width: parent.width
      text: parent.value
      color: parent.bar ? parent.bar.foreground : Commons.Color.foreground
      font.family: parent.bar ? parent.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.subtitle
      renderType: Text.NativeRendering
    }
  }

}
