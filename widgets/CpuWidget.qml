pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.cpu"
  manageIpc: false

  readonly property var telemetry: bar ? bar.systemTelemetry : null
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property var gpuTelemetry: bar ? bar.gpuTelemetry : null
  readonly property bool compact: setting("compact", false) === true
  readonly property int percent: telemetry ? telemetry.cpuPercent : 0
  readonly property var history: telemetry ? telemetry.cpuHistory : []
  property var acquiredTelemetry: null

  implicitWidth: bar && bar.vertical ? bar.barSize : cpuSurface.implicitWidth
  implicitHeight: bar && bar.vertical ? cpuSurface.implicitHeight : bar ? bar.barSize : 28

  function syncTelemetryOwner() {
    if (acquiredTelemetry === telemetry) return
    if (acquiredTelemetry) acquiredTelemetry.release("cpu")
    acquiredTelemetry = telemetry
    if (acquiredTelemetry) acquiredTelemetry.acquire("cpu")
  }

  function syncPanelLoader() {
    if (!opened) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(Qt.resolvedUrl("CpuPanel.qml"), {
      anchorItem: cpuSurface,
      bar: root.bar,
      ownerWidget: root,
      systemTelemetry: root.telemetry,
      gpuTelemetry: root.gpuTelemetry
    })
  }

  function openSystemMonitor() {
    if (!bar || typeof bar.run !== "function") return false
    bar.run("omarchy-launch-or-focus-tui btop")
    return true
  }

  onTelemetryChanged: syncTelemetryOwner()
  onOpenedChanged: syncPanelLoader()
  Component.onCompleted: syncTelemetryOwner()
  Component.onDestruction: if (acquiredTelemetry) acquiredTelemetry.release("cpu")

  Item {
    id: cpuSurface

    anchors.centerIn: parent
    implicitWidth: root.bar && root.bar.vertical
      ? root.bar.barSize
      : content.implicitWidth + 2 * root.tokens.pillPaddingX
    implicitHeight: root.bar && root.bar.vertical
      ? content.implicitHeight + Commons.Style.space(10)
      : root.tokens ? root.tokens.slotHeight : 28
    width: implicitWidth
    height: implicitHeight

    PillSurface {
      bar: root.bar
      anchors.fill: parent
      anchors.topMargin: Math.round((parent.height - root.tokens.pillHeight) / 2)
      anchors.bottomMargin: Math.round((parent.height - root.tokens.pillHeight) / 2)
    }

    Loader {
      id: content
      anchors.centerIn: parent
      sourceComponent: root.bar && root.bar.vertical ? verticalContent : horizontalContent
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(cpuSurface, root.percent + "%")
      onExited: if (root.bar) root.bar.hideTooltip(cpuSurface)
      onClicked: {
        if (root.bar) root.bar.hideTooltip(cpuSurface)
        root.toggle()
      }
    }
  }

  Loader {
    id: panelLoader
  }

  Component {
    id: horizontalContent

    Row {
      spacing: root.compact ? root.tokens.compactGap : root.tokens.contentGap

      Text {
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
        text: "CPU"
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.6) : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      CpuWave {
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
        history: root.history
        accent: root.bar ? root.bar.urgent : Commons.Color.accent
      }

      IconText {
        visible: root.compact
        anchors.verticalCenter: parent.verticalCenter
        text: "planner_review"
        color: root.bar.urgent
        font.pixelSize: root.tokens.iconSize
        font.weight: Font.DemiBold
        fill: 1
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.percent).padStart(2, "0") + "%"
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }

  Component {
    id: verticalContent

    Column {
      spacing: Commons.Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "CPU"
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.62) : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: String(root.percent).padStart(2, "0") + "%"
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }
}
