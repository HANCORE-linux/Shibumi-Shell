pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var telemetry
  readonly property var sourceOptions: [
    { id: "cpu", label: "CPU" },
    { id: "core", label: "CORE" },
    { id: "gpu", label: "GPU" },
    { id: "nvme", label: "NVME" },
    { id: "memory", label: "RAM" }
  ]
  property int unitCursor: -1

  function moveUnitCursor(direction) {
    const step = Number(direction || 0)
    if (step === 0) return false
    if (unitCursor < 0) unitCursor = step > 0 ? 0 : 1
    else unitCursor = Math.max(0, Math.min(1, unitCursor + step))
    return true
  }

  function activateUnitCursor() {
    if (unitCursor < 0) return false
    return ownerWidget.setTemperatureUnit(
      unitCursor === 0 ? "metric" : "imperial")
  }

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(320))
  contentHeight: fittedContentHeight(content.implicitHeight)

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onMoveRequested: function(dx, _dy) {
      if (dx !== 0) panel.moveUnitCursor(dx)
    }
    onActivateRequested: panel.activateUnitCursor()
    onTextKey: function(text) {
      const key = String(text || "").toLowerCase()
      if (key === "c") panel.ownerWidget.setTemperatureUnit("metric")
      else if (key === "f") panel.ownerWidget.setTemperatureUnit("imperial")
    }
    onTabRequested: function(direction) {
      panel.unitCursor = -1
      panel.ownerWidget.switchPanel(direction)
    }

    Column {
      id: content
      width: parent.width
      spacing: Commons.Style.space(9)

      Row {
        width: parent.width
        spacing: Commons.Style.space(5)

        Text {
          id: headerTitle
          width: parent.width - unitChoices.width - close.width
            - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          text: "THERMALS"
          color: panel.bar.foreground
          font.family: panel.bar.fontFamily
          font.pixelSize: Commons.Style.font.heading
          font.weight: Font.Medium
        }

        Row {
          id: unitChoices
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(2)

          UnitChoice {
            label: "°C"
            unit: "metric"
            unitIndex: 0
          }

          UnitChoice {
            label: "°F"
            unit: "imperial"
            unitIndex: 1
          }
        }

        Text {
          id: close
          anchors.verticalCenter: parent.verticalCenter
          text: "×"
          color: panel.bar.foreground
          font.pixelSize: Commons.Style.font.heading
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Commons.Style.space(6)
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.ownerWidget.close()
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.shibumiTokens.separator
      }

      Item {
        width: parent.width
        height: Commons.Style.space(16)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "BAR SENSOR"
          color: panel.bar.foreground
          opacity: 0.62
          font.family: panel.bar.fontFamily
          font.pixelSize: Commons.Style.font.caption
          font.letterSpacing: 1
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: panel.ownerWidget.sourceLabel
          color: panel.bar.urgent
          font.family: panel.bar.fontFamily
          font.pixelSize: Commons.Style.font.caption
          font.weight: Font.Medium
        }
      }

      Row {
        width: parent.width
        height: Commons.Style.space(28)
        spacing: Commons.Style.space(4)

        Repeater {
          model: panel.sourceOptions

          delegate: Rectangle {
            id: sourceButton
            required property var modelData
            readonly property bool selected:
              panel.ownerWidget.selectedSource === modelData.id
            readonly property bool available: panel.telemetry
              && typeof panel.telemetry.sourceAvailable === "function"
              && panel.telemetry.sourceAvailable(modelData.id)
            width: (parent.width - parent.spacing * 4) / 5
            height: parent.height
            radius: panel.controlRadius
            opacity: available ? 1 : 0.35
            color: selected ? panel.controlActiveFillColor
              : sourcePointer.containsMouse && available
                ? panel.controlHoverFillColor : panel.controlFillColor
            border.width: 1
            border.color: selected || sourcePointer.containsMouse && available
              ? panel.controlHoverBorderColor : panel.controlBorderColor

            Text {
              anchors.centerIn: parent
              text: sourceButton.modelData.label
              color: sourceButton.selected
                ? panel.controlAccent : panel.controlForeground
              font.family: panel.bar.fontFamily
              font.pixelSize: Commons.Style.font.caption
              font.weight: sourceButton.selected ? Font.Medium : Font.Normal
            }

            MouseArea {
              id: sourcePointer
              anchors.fill: parent
              enabled: sourceButton.available
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked:
                panel.ownerWidget.setTemperatureSource(sourceButton.modelData.id)
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.shibumiTokens.separator
      }

      Repeater {
        model: panel.telemetry ? panel.telemetry.temperatures : []

        delegate: Row {
          required property var modelData
          width: parent.width

          Text {
            width: parent.width * 0.7
            text: modelData.label
            color: panel.bar.foreground
            opacity: 0.68
            elide: Text.ElideRight
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.body
          }

          Text {
            width: parent.width * 0.3
            horizontalAlignment: Text.AlignRight
            text: panel.ownerWidget.temperatureText(modelData.temperatureC)
            color: panel.bar.urgent
            font.family: panel.bar.fontFamily
            font.pixelSize: Commons.Style.font.body
          }
        }
      }

      Text {
        visible: !panel.telemetry
          || panel.telemetry.temperatures.length === 0
        width: parent.width
        text: "No readable hardware sensors"
        color: panel.bar.foreground
        opacity: 0.5
        horizontalAlignment: Text.AlignHCenter
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.body
      }
    }
  }

  component UnitChoice: Rectangle {
    id: unitChoice

    required property string label
    required property string unit
    required property int unitIndex
    readonly property bool selected:
      panel.ownerWidget.temperatureUnit === unit
    readonly property bool hovered: unitPointer.containsMouse
    readonly property bool keyboardFocused: panel.unitCursor === unitIndex
    readonly property bool highlighted: hovered || keyboardFocused
    signal triggered()

    width: Commons.Style.space(27)
    height: headerTitle.implicitHeight
    radius: panel.controlRadius
    color: selected ? panel.controlActiveFillColor
      : highlighted ? panel.controlHoverFillColor : "transparent"
    border.width: keyboardFocused
      ? Math.max(1, panel.controlBorderWidth) : 0
    border.color: panel.controlAccent
    Accessible.role: Accessible.RadioButton
    Accessible.name: label
    Accessible.description: unit === "metric"
      ? "Show temperatures in Celsius"
      : "Show temperatures in Fahrenheit"
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.focusable: true
    Accessible.focused: keyboardFocused
    Accessible.onPressAction: unitChoice.triggered()

    Behavior on color { ColorAnimation { duration: 100 } }

    onTriggered: panel.ownerWidget.setTemperatureUnit(unit)

    Text {
      anchors.centerIn: parent
      text: unitChoice.label
      color: unitChoice.selected || unitChoice.highlighted
        ? panel.controlAccent : panel.controlForeground
      opacity: unitChoice.selected || unitChoice.highlighted ? 1 : 0.62
      font.family: panel.bar.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.weight: unitChoice.selected ? Font.DemiBold : Font.Normal
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: unitPointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: unitChoice.triggered()
    }
  }
}
