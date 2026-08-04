pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var gpu

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(360))
  contentHeight: fittedContentHeight(content.implicitHeight)

  function driverLabel() {
    if (!gpu) return "--"
    const driver = String(gpu.driverName || "").trim()
    const version = String(gpu.driverVersion || "").trim()
    if (driver !== "" && version !== "") return driver + " · " + version
    return driver !== "" ? driver : "--"
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) {
      panel.ownerWidget.switchPanel(direction)
    }

    Column {
      id: content
      width: parent.width
      spacing: Commons.Style.space(10)

      Text {
        text: panel.gpu && panel.gpu.available
          ? "GPU · " + String(panel.gpu.driverName
            || panel.gpu.backend).toUpperCase()
          : "GPU · UNAVAILABLE"
        color: panel.bar.foreground
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.heading
        font.weight: Font.Medium
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.shibumiTokens.separator
      }

      Text {
        visible: panel.gpu && panel.gpu.probeFailed
        width: parent.width
        text: "Last GPU refresh failed · showing previous sample"
        color: panel.bar.foreground
        opacity: 0.58
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
      }

      Metric {
        label: "Device"
        value: panel.gpu && panel.gpu.available
          ? String(panel.gpu.name || "Unknown GPU") : "--"
        valueColor: panel.bar.foreground
      }
      Metric {
        label: "Driver"
        value: panel.driverLabel()
        valueColor: panel.bar.foreground
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.shibumiTokens.separator
      }

      Metric {
        label: "Load"
        value: panel.gpu && panel.gpu.available
          ? panel.gpu.utilization + "%" : "--"
      }
      Metric {
        label: "Temperature"
        value: panel.gpu && panel.gpu.available
          && panel.gpu.temperatureC > 0
          ? panel.gpu.temperatureC + "°C" : "--"
      }
      Metric {
        visible: panel.gpu && panel.gpu.memoryTotalMiB > 0
        label: "VRAM"
        value: panel.gpu
          ? panel.gpu.memoryUsedMiB + " / "
            + panel.gpu.memoryTotalMiB + " MiB" : ""
      }
    }
  }

  component Metric: Row {
    required property string label
    required property string value
    property color valueColor: panel.bar.urgent
    width: content.width
    height: Math.max(metricLabel.implicitHeight, metricValue.implicitHeight)

    Text {
      id: metricLabel
      width: parent.width * 0.26
      text: parent.label
      color: panel.bar.foreground
      opacity: 0.62
      font.family: panel.bar.fontFamily
      font.pixelSize: Commons.Style.font.body
    }
    Text {
      id: metricValue
      width: parent.width * 0.74
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: parent.valueColor
      font.family: panel.bar.fontFamily
      font.pixelSize: Commons.Style.font.body
      wrapMode: Text.WordWrap
    }
  }
}
