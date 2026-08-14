pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.gpu"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var cpuService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.cpu") : null
  readonly property var gpu: cpuService ? cpuService.gpu : null
  readonly property var stateService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.state") : null
  property string hostGroupId: ""
  readonly property string stateGroupId: hostGroupId !== ""
    ? hostGroupId : "G17"
  readonly property string configuredDeviceId: String(
    setting("device", "auto"))
  readonly property var availableGpus: gpu && Array.isArray(gpu.devices)
    ? gpu.devices : []
  readonly property var automaticGpu: availableGpus.length > 0
    ? availableGpus[0] : gpu && gpu.available ? gpu : null
  readonly property var configuredGpu: configuredDeviceId === "auto"
    ? automaticGpu : gpuForDevice(configuredDeviceId)
  readonly property var selectedGpu: configuredGpu || automaticGpu
  readonly property bool configuredDeviceMissing:
    configuredDeviceId !== "auto" && configuredGpu === null
  readonly property string selectedDeviceId: selectedGpu
    && selectedGpu.id !== undefined ? String(selectedGpu.id) : "auto"
  readonly property string selectedLabel: selectedGpu
    ? String(selectedGpu.name || selectedGpu.driverName || "GPU") : "GPU"
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool telemetryAvailable:
    root.selectedGpu && root.selectedGpu.available === true
  property var acquiredGpu: null
  readonly property bool panelLoaded: panelLoader.status === Loader.Ready
  readonly property var panelItem: panelLoader.item

  implicitWidth: bar && bar.vertical ? bar.barSize : surface.implicitWidth
  implicitHeight: bar && bar.vertical ? surface.implicitHeight
    : bar ? bar.barSize : 28
  // Activation is a layout choice, not a hardware-capability probe. Keep the
  // widget visible on unsupported/iGPU-only hosts and communicate that the
  // metric is unavailable instead of silently rendering a 0x0 active slot.
  visible: true

  function gpuForDevice(deviceId) {
    const target = String(deviceId || "")
    for (let index = 0; index < availableGpus.length; index++) {
      if (String(availableGpus[index].id || "") === target)
        return availableGpus[index]
    }
    return null
  }

  function gpuDeviceAvailable(deviceId) {
    const target = String(deviceId || "")
    return target === "auto" || gpuForDevice(target) !== null
  }

  function setGpuDevice(deviceId) {
    const target = String(deviceId || "")
    if (!gpuDeviceAvailable(target)) return false
    return stateService && typeof stateService.setGroupSetting === "function"
      ? stateService.setGroupSetting(stateGroupId, "device", target) : false
  }

  function syncGpuOwner() {
    if (acquiredGpu === gpu) return
    if (acquiredGpu) acquiredGpu.release()
    acquiredGpu = gpu
    if (acquiredGpu) acquiredGpu.acquire()
  }

  function syncPanelLoader() {
    if (!opened) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(Qt.resolvedUrl("GpuPanel.qml"), {
      anchorItem: surface,
      bar: root.bar,
      ownerWidget: root,
      gpuTelemetry: root.gpu
    })
  }

  onGpuChanged: syncGpuOwner()
  onOpenedChanged: syncPanelLoader()
  Component.onCompleted: syncGpuOwner()
  Component.onDestruction: if (acquiredGpu) acquiredGpu.release()

  Item {
    id: surface
    anchors.centerIn: parent
    implicitWidth: content.implicitWidth + 2 * root.tokens.pillPaddingX
    implicitHeight: root.tokens ? root.tokens.slotHeight : 28
    width: implicitWidth
    height: implicitHeight

    PillSurface {
      tokenSource: root.tokens
      bar: root.bar
      settings: root.settings
      v1AppearanceEnabled: true
      anchors.fill: parent
      anchors.topMargin: Math.round(
        (parent.height - root.tokens.pillHeight) / 2)
      anchors.bottomMargin: Math.round(
        (parent.height - root.tokens.pillHeight) / 2)
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: root.tokens.compactGap

      Item {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(20)
        height: Commons.Style.space(14)

        GpuCardIcon {
          anchors.fill: parent
          color: root.widgetInk
        }
      }

      Text {
        visible: root.displayMode !== "icon"
        anchors.verticalCenter: parent.verticalCenter
        text: root.telemetryAvailable
          ? String(Math.min(100, root.selectedGpu.utilization)).padStart(2, "0") + "%"
          : "--"
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar && root.gpu)
        root.bar.showTooltip(surface,
          root.telemetryAvailable
            ? root.selectedLabel + " · " + root.selectedGpu.utilization
              + "% · " + root.selectedGpu.temperatureC + "°C"
            : "GPU telemetry unavailable")
      onExited: if (root.bar) root.bar.hideTooltip(surface)
      onClicked: root.toggle()
    }
  }

  Loader { id: panelLoader }
}
