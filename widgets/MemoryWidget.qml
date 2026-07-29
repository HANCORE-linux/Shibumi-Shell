pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.memory"
  manageIpc: false

  readonly property var telemetry: bar ? bar.systemTelemetry : null
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property bool compact: setting("compact", false) === true
  readonly property int percent: telemetry ? telemetry.memPercent : 0
  readonly property real usedGiB: telemetry ? telemetry.memUsedGiB : 0
  readonly property real totalGiB: telemetry ? telemetry.memTotalGiB : 0
  readonly property string usedLabel: String(Math.round(usedGiB)).padStart(2, "0") + "G"
  readonly property string usageLabel: usedGiB.toFixed(1) + "/" + totalGiB.toFixed(1) + " GiB"
  property var acquiredTelemetry: null

  implicitWidth: bar && bar.vertical ? bar.barSize : memorySurface.implicitWidth
  implicitHeight: bar && bar.vertical ? memorySurface.implicitHeight : bar ? bar.barSize : 28

  function syncTelemetryOwner() {
    if (acquiredTelemetry === telemetry) return
    if (acquiredTelemetry) acquiredTelemetry.release("memory")
    acquiredTelemetry = telemetry
    if (acquiredTelemetry) acquiredTelemetry.acquire("memory")
  }

  function syncPanelLoader() {
    if (!opened) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(Qt.resolvedUrl("MemoryPanel.qml"), {
      anchorItem: memorySurface,
      bar: root.bar,
      ownerWidget: root,
      telemetry: root.telemetry
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
  Component.onDestruction: if (acquiredTelemetry) acquiredTelemetry.release("memory")

  Item {
    id: memorySurface

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
      onEntered: if (root.bar) root.bar.showTooltip(memorySurface, root.usageLabel)
      onExited: if (root.bar) root.bar.hideTooltip(memorySurface)
      onClicked: {
        if (root.bar) root.bar.hideTooltip(memorySurface)
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
        text: "MEM"
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.6) : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      MemoryRing {
        anchors.verticalCenter: parent.verticalCenter
        percent: root.percent
        foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        accent: root.bar ? root.bar.urgent : Commons.Color.accent
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.usedLabel
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

      MemoryRing {
        anchors.horizontalCenter: parent.horizontalCenter
        percent: root.percent
        foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
        accent: root.bar ? root.bar.urgent : Commons.Color.accent
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.usedLabel
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }
}
