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
  contentWidth: fittedContentWidth(Commons.Style.space(320))
  contentHeight: fittedContentHeight(content.implicitHeight)

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
        text: "GPU · " + (panel.gpu ? panel.gpu.backend.toUpperCase() : "")
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

      Metric {
        label: "Load"
        value: (panel.gpu ? panel.gpu.utilization : 0) + "%"
      }
      Metric {
        label: "Temperature"
        value: (panel.gpu ? panel.gpu.temperatureC : 0) + "°C"
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
    width: content.width

    Text {
      width: parent.width * 0.48
      text: parent.label
      color: panel.bar.foreground
      opacity: 0.62
      font.family: panel.bar.fontFamily
      font.pixelSize: Commons.Style.font.body
    }
    Text {
      width: parent.width * 0.52
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: panel.bar.urgent
      font.family: panel.bar.fontFamily
      font.pixelSize: Commons.Style.font.body
    }
  }
}
