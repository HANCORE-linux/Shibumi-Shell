pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  property var acquiredGpu: null

  implicitWidth: bar && bar.vertical ? bar.barSize : surface.implicitWidth
  implicitHeight: bar && bar.vertical ? surface.implicitHeight
    : bar ? bar.barSize : 28
  visible: root.gpu && root.gpu.available

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
      gpu: root.gpu
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
        width: Commons.Style.space(18)
        height: Commons.Style.space(13)

        Image {
          id: gpuIconSource
          anchors.fill: parent
          visible: false
          source: Qt.resolvedUrl("gpu-card.svg")
          sourceSize: Qt.size(54, 39)
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
        }

        MultiEffect {
          anchors.fill: parent
          source: gpuIconSource
          colorization: 1
          colorizationColor: root.widgetInk
        }
      }

      Text {
        visible: root.displayMode !== "icon"
        anchors.verticalCenter: parent.verticalCenter
        text: String(Math.min(100,
          root.gpu ? root.gpu.utilization : 0)).padStart(2, "0") + "%"
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
          root.gpu.utilization + "% · " + root.gpu.temperatureC + "°C")
      onExited: if (root.bar) root.bar.hideTooltip(surface)
      onClicked: root.toggle()
    }
  }

  Loader { id: panelLoader }
}
