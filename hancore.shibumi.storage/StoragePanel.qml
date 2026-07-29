pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var storage

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(390))
  contentHeight: fittedContentHeight(content.implicitHeight)

  function capacity(bytes) {
    const value = Math.max(0, Number(bytes) || 0) / 1073741824
    return value >= 1024
      ? (value / 1024).toFixed(1) + " TiB"
      : value.toFixed(value >= 100 ? 0 : 1) + " GiB"
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
        text: "STORAGE · " + (panel.storage ? panel.storage.percent : 0) + "%"
        color: panel.bar.foreground
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.heading
        font.weight: Font.Medium
      }

      Rectangle {
        width: parent.width
        height: Commons.Style.space(7)
        radius: height / 2
        color: panel.shibumiTokens.fillIdle

        Rectangle {
          width: parent.width * Math.max(0, Math.min(100,
            panel.storage ? panel.storage.percent : 0)) / 100
          height: parent.height
          radius: height / 2
          color: panel.bar.urgent
        }
      }

      Text {
        width: parent.width
        text: panel.storage
          ? panel.storage.usedGiB.toFixed(1) + " GiB used · "
            + panel.storage.freeGiB.toFixed(1) + " GiB free" : ""
        color: panel.bar.foreground
        opacity: 0.68
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.body
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.shibumiTokens.separator
      }

      Repeater {
        model: panel.storage ? panel.storage.drives : []

        delegate: Row {
          required property var modelData
          width: parent.width
          spacing: Commons.Style.space(8)

          IconText {
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(20)
            text: modelData.transport === "usb" ? "usb" : "hard_drive"
            color: panel.bar.urgent
            font.pixelSize: Commons.Style.font.iconLarge
          }

          Column {
            width: parent.width - x - size.width

            Text {
              width: parent.width
              text: (modelData.model || modelData.name)
                + (modelData.mountPoint ? " · " + modelData.mountPoint : "")
              color: panel.bar.foreground
              elide: Text.ElideRight
              font.family: panel.bar.fontFamily
              font.pixelSize: Commons.Style.font.body
            }
            Text {
              width: parent.width
              text: [modelData.type, modelData.fileSystem]
                .filter(function(value) { return value !== "" }).join(" · ")
              color: panel.bar.foreground
              opacity: 0.46
              font.family: panel.bar.fontFamily
              font.pixelSize: Commons.Style.font.caption
            }
          }

          Text {
            id: size
            anchors.verticalCenter: parent.verticalCenter
            text: panel.capacity(modelData.sizeBytes)
            color: panel.bar.urgent
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.body
          }
        }
      }
    }
  }
}
