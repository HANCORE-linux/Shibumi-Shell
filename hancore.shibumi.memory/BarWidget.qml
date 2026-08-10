pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.memory"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var telemetryService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.telemetry") : null
  readonly property var telemetry: telemetryService
    ? telemetryService.system : null
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  readonly property bool horizontalValueVisible: displayMode !== "icon"
    || tokens.v2Shell !== true
  readonly property int percent: telemetry ? telemetry.memPercent : 0
  readonly property real usedGiB: telemetry ? telemetry.memUsedGiB : 0
  readonly property real totalGiB: telemetry ? telemetry.memTotalGiB : 0
  readonly property string usedLabel: String(Math.round(usedGiB)).padStart(2, "0") + "G"
  readonly property string usageLabel: usedGiB.toFixed(1) + "/" + totalGiB.toFixed(1) + " GiB"
  property url panelSource: Qt.resolvedUrl("MemoryPanel.qml")
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
    panelLoader.setSource(panelSource, {
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
      tokenSource: root.tokens
      bar: root.bar
      settings: root.settings
      v1AppearanceEnabled: true
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
      spacing: root.displayMode === "full" && root.tokens.v2Shell !== true
        ? root.tokens.contentGap : root.tokens.compactGap

      Text {
        visible: root.displayMode === "full" && root.tokens.v2Shell !== true
        anchors.verticalCenter: parent.verticalCenter
        text: "MEM"
        color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
          root.widgetInk.b, 0.68)
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      MemoryRing {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        percent: root.percent
        foreground: root.widgetInk
        accent: root.widgetInk
      }

      Text {
        visible: root.horizontalValueVisible
        anchors.verticalCenter: parent.verticalCenter
        text: root.usedLabel
        color: root.widgetInk
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
        foreground: root.widgetInk
        accent: root.widgetInk
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.usedLabel
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }
}
