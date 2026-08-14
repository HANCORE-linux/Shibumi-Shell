pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var gpuTelemetry
  readonly property var selectedGpu: ownerWidget
    ? ownerWidget.selectedGpu : null
  readonly property var devices: gpuTelemetry
    && Array.isArray(gpuTelemetry.devices) ? gpuTelemetry.devices : []
  readonly property bool selectorVisible: devices.length > 1
    || (ownerWidget && ownerWidget.configuredDeviceId !== "auto")
  readonly property int sourceChoiceCount: devices.length + 1
  readonly property string deviceSignature: devices.map(function(device) {
    return String(device.id || "")
  }).join("|")
  property int sourceCursor: 0

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(360))
  contentHeight: fittedContentHeight(content.implicitHeight)

  function driverLabel(device) {
    if (!device) return "--"
    const driver = String(device.driverName || "").trim()
    const version = String(device.driverVersion || "").trim()
    if (driver !== "" && version !== "") return driver + " · " + version
    return driver !== "" ? driver : "--"
  }

  function slotLabel(device) {
    if (!device) return ""
    const id = String(device.id || "")
    return id.indexOf("pci:") === 0 ? id.substring(4) : id
  }

  function selectDevice(deviceId) {
    return ownerWidget && typeof ownerWidget.setGpuDevice === "function"
      ? ownerWidget.setGpuDevice(deviceId) : false
  }

  function syncSourceCursor() {
    const configured = ownerWidget
      ? String(ownerWidget.configuredDeviceId || "auto") : "auto"
    sourceCursor = 0
    if (configured === "auto") return
    for (let index = 0; index < devices.length; index++) {
      if (String(devices[index].id || "") === configured) {
        sourceCursor = index + 1
        return
      }
    }
  }

  function ensureSourceCursorVisible() {
    if (!selectorVisible || !sourceViewport) return
    const target = sourceCursor === 0 ? automaticChoice
      : deviceRepeater.itemAt(sourceCursor - 1)
    if (!target) return
    const mapped = target.mapToItem(content, 0, 0)
    const top = mapped.y
    const bottom = top + target.height
    if (top < sourceViewport.contentY)
      sourceViewport.contentY = Math.max(0, top)
    else if (bottom > sourceViewport.contentY + sourceViewport.height)
      sourceViewport.contentY = Math.min(
        Math.max(0, sourceViewport.contentHeight - sourceViewport.height),
        bottom - sourceViewport.height)
  }

  function moveSourceCursor(dx, dy) {
    if (!selectorVisible || sourceChoiceCount <= 0) return false
    const delta = dy !== 0 ? dy : dx
    if (delta === 0) return false
    sourceCursor = (sourceCursor + (delta > 0 ? 1 : -1)
      + sourceChoiceCount) % sourceChoiceCount
    Qt.callLater(ensureSourceCursorVisible)
    return true
  }

  function activateSourceCursor() {
    if (!selectorVisible || sourceCursor < 0
        || sourceCursor >= sourceChoiceCount) return false
    const deviceId = sourceCursor === 0 ? "auto"
      : String(devices[sourceCursor - 1].id || "")
    return selectDevice(deviceId)
  }

  onDeviceSignatureChanged: {
    if (sourceCursor >= sourceChoiceCount) sourceCursor = 0
    syncSourceCursor()
  }
  onOpenChanged: if (open) {
    syncSourceCursor()
    Qt.callLater(ensureSourceCursorVisible)
  }

  property Connections ownerConnections: Connections {
    target: panel.ownerWidget
    function onConfiguredDeviceIdChanged() { panel.syncSourceCursor() }
  }

  component DeviceChoice: Rectangle {
    id: choice

    required property string sourceId
    required property string label
    required property string detail
    required property string metric
    required property int cursorIndex
    property bool selected: false
    readonly property bool cursorSelected: panel.sourceCursor === cursorIndex
    readonly property bool hovered: pointer.containsMouse
    signal triggered()

    width: parent ? parent.width : 0
    implicitHeight: Commons.Style.space(42)
    radius: panel.controlRadius
    color: selected ? panel.controlActiveFillColor
      : hovered ? panel.controlHoverFillColor : panel.controlFillColor
    border.width: cursorSelected
      ? Math.max(1, panel.controlBorderWidth) : panel.controlBorderWidth
    border.color: activeFocus || cursorSelected ? panel.bar.foreground
      : selected ? panel.controlAccent
      : hovered ? panel.controlHoverBorderColor : panel.controlBorderColor
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label + (detail !== "" ? " " + detail : "")
    Accessible.checked: selected
    Accessible.onPressAction: choice.triggered()

    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
      id: pointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: choice.triggered()
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(9)
      anchors.rightMargin: Commons.Style.space(9)
      spacing: Commons.Style.space(8)

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - metricText.width - parent.spacing
        spacing: Commons.Style.space(1)

        Text {
          width: parent.width
          text: choice.label
          color: choice.selected ? panel.controlAccent : panel.bar.foreground
          font.family: panel.bar.fontFamily
          font.pixelSize: Commons.Style.font.body
          font.weight: choice.selected ? Font.DemiBold : Font.Normal
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: choice.detail
          color: panel.bar.foreground
          opacity: 0.56
          font.family: panel.bar.fontFamily
          font.pixelSize: Commons.Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: metricText
        anchors.verticalCenter: parent.verticalCenter
        text: choice.metric
        color: choice.selected ? panel.controlAccent : panel.controlMutedHigh
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.body
        font.weight: Font.Medium
      }
    }

    Keys.onReturnPressed: triggered()
    Keys.onEnterPressed: triggered()
    Keys.onSpacePressed: triggered()
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) {
      panel.ownerWidget.switchPanel(direction)
    }
    onMoveRequested: function(dx, dy) { panel.moveSourceCursor(dx, dy) }
    onActivateRequested: panel.activateSourceCursor()

    Flickable {
      id: sourceViewport
      anchors.fill: parent
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: contentHeight > height
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: content
        width: sourceViewport.width
        spacing: Commons.Style.space(10)

      Text {
        text: panel.selectedGpu
          ? "GPU · " + String(panel.selectedGpu.driverName
            || panel.selectedGpu.backend).toUpperCase()
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
        visible: panel.gpuTelemetry && panel.gpuTelemetry.probeFailed
        width: parent.width
        text: "Last GPU refresh failed · showing previous sample"
        color: panel.bar.foreground
        opacity: 0.58
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        visible: panel.ownerWidget
          && panel.ownerWidget.configuredDeviceMissing
        width: parent.width
        text: "Configured GPU is unavailable · using automatic fallback"
        color: panel.bar.foreground
        opacity: 0.58
        font.family: panel.bar.fontFamily
        font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
      }

      Column {
        id: sourceSelector
        visible: panel.selectorVisible
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: Commons.Style.space(6)

        Text {
          width: parent.width
          text: "BAR SOURCE"
          color: panel.bar.foreground
          opacity: 0.62
          font.family: panel.bar.fontFamily
          font.pixelSize: Commons.Style.font.caption
          font.weight: Font.Medium
        }

        DeviceChoice {
          id: automaticChoice
          sourceId: "auto"
          label: "Automatic"
          detail: panel.devices.length > 0
            ? String(panel.devices[0].name || "First available GPU")
            : "First available GPU"
          metric: "AUTO"
          cursorIndex: 0
          selected: panel.ownerWidget
            && panel.ownerWidget.configuredDeviceId === "auto"
          onTriggered: {
            panel.sourceCursor = cursorIndex
            panel.selectDevice(sourceId)
          }
        }

        Repeater {
          id: deviceRepeater
          model: panel.devices.length

          delegate: DeviceChoice {
            required property int index
            readonly property var device: index >= 0
              && index < panel.devices.length ? panel.devices[index] : null
            sourceId: device ? String(device.id || "") : ""
            label: device
              ? String(device.name || device.driverName || "GPU") : "GPU"
            detail: device
              ? String(device.driverName || device.backend).toUpperCase()
                + (panel.slotLabel(device) !== ""
                  ? " · " + panel.slotLabel(device) : "") : ""
            metric: device ? String(device.utilization || 0) + "%" : "--"
            cursorIndex: index + 1
            selected: device && panel.ownerWidget
              && panel.ownerWidget.configuredDeviceId === sourceId
            onTriggered: {
              panel.sourceCursor = cursorIndex
              panel.selectDevice(sourceId)
            }
          }
        }
      }

      Rectangle {
        visible: panel.selectorVisible
        width: parent.width
        height: visible ? 1 : 0
        color: panel.shibumiTokens.separator
      }

      Metric {
        label: "Device"
        value: panel.selectedGpu
          ? String(panel.selectedGpu.name || "Unknown GPU") : "--"
        valueColor: panel.bar.foreground
      }
      Metric {
        label: "Driver"
        value: panel.driverLabel(panel.selectedGpu)
        valueColor: panel.bar.foreground
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.shibumiTokens.separator
      }

      Metric {
        label: "Load"
        value: panel.selectedGpu
          ? panel.selectedGpu.utilization + "%" : "--"
      }
      Metric {
        label: "Temperature"
        value: panel.selectedGpu && panel.selectedGpu.temperatureC > 0
          ? panel.selectedGpu.temperatureC + "°C" : "--"
      }
        Metric {
          visible: panel.selectedGpu && panel.selectedGpu.memoryTotalMiB > 0
          label: "VRAM"
          value: panel.selectedGpu
            ? panel.selectedGpu.memoryUsedMiB + " / "
              + panel.selectedGpu.memoryTotalMiB + " MiB" : ""
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
