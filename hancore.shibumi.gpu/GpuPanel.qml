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

  Component.onCompleted: if (gpu) gpu.acquireDetails()
  Component.onDestruction: if (gpu) gpu.releaseDetails()

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

      Rectangle {
        visible: panel.gpu && panel.gpu.available
        width: parent.width
        height: 1
        color: panel.shibumiTokens.separator
      }

      Item {
        visible: panel.gpu && panel.gpu.available
        width: parent.width
        height: Commons.Style.space(18)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "TOP GPU PROCESSES"
          color: panel.bar.foreground
          opacity: 0.62
          font.family: panel.bar.fontFamily
          font.pixelSize: Commons.Style.font.caption
          font.letterSpacing: 0.8
          font.weight: Font.Medium
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(10)

          Text {
            width: Commons.Style.space(42)
            horizontalAlignment: Text.AlignLeft
            text: "LOAD"
            color: panel.bar.foreground
            opacity: 0.48
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.caption
          }

          Text {
            width: Commons.Style.space(70)
            horizontalAlignment: Text.AlignRight
            text: "VRAM"
            color: panel.bar.foreground
            opacity: 0.48
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.caption
          }
        }
      }

      Text {
        visible: panel.gpu && panel.gpu.available
          && panel.gpu.topProcesses.length === 0
        width: parent.width
        text: panel.gpu && panel.gpu.detailsReady
          ? panel.gpu.detailsFailed
            ? "GPU process data unavailable"
            : "No GPU processes reported"
          : "Collecting process activity…"
        color: panel.bar.foreground
        opacity: 0.58
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.body
        elide: Text.ElideRight
      }

      Repeater {
        model: panel.gpu && panel.gpu.available
          ? panel.gpu.topProcesses : []

        delegate: Item {
          id: processRow
          required property var modelData
          required property int index

          width: content.width
          height: Commons.Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(22)
            text: String(processRow.index + 1).padStart(2, "0")
            color: panel.bar.foreground
            opacity: 0.42
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.caption
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Commons.Style.space(28)
            anchors.right: loadText.left
            anchors.rightMargin: Commons.Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: String(processRow.modelData.name || "GPU process")
            color: panel.bar.foreground
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.body
            elide: Text.ElideRight
          }

          Text {
            id: loadText
            anchors.right: memoryText.left
            anchors.rightMargin: Commons.Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(42)
            horizontalAlignment: Text.AlignLeft
            text: processRow.modelData.percent >= 0
              ? processRow.modelData.percent + "%" : "--"
            color: panel.bar.urgent
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.body
            font.weight: Font.Medium
          }

          Text {
            id: memoryText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(70)
            horizontalAlignment: Text.AlignRight
            text: processRow.modelData.memoryMiB > 0
              ? processRow.modelData.memoryMiB + " MiB" : "--"
            color: panel.bar.foreground
            opacity: 0.68
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.caption
          }
        }
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
