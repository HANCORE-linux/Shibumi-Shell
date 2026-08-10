pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.cpu"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var telemetryService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.telemetry") : null
  readonly property var cpuService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.cpu") : null
  readonly property var telemetry: telemetryService
    ? telemetryService.system : null
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  // V1 exposes fill-only appearance controls. Ignore any stale hidden V2
  // surface mode so the selected color owns the native CPU pill interior.
  readonly property var effectiveAppearanceSettings: {
    const source = settings || ({})
    if (tokens && tokens.v2Shell === true) return source
    const effective = {}
    for (const key in source) effective[key] = source[key]
    effective.colorMode = "fill"
    effective.widgetBorder = false
    return effective
  }
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(effectiveAppearanceSettings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property var gpuTelemetry: cpuService ? cpuService.gpu : null
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  readonly property bool percentageVisible: displayMode !== "icon"
    || tokens.v2Shell !== true
  readonly property bool v1CustomFillActive: cpuPill.v1CustomFill
  readonly property color renderedPillFillColor: cpuPill.renderedFillColor
  readonly property real renderedPillFillOpacity: cpuPill.v1FillOpacity
  readonly property int percent: telemetry ? telemetry.cpuPercent : 0
  readonly property var history: telemetry ? telemetry.cpuHistory : []
  property url panelSource: Qt.resolvedUrl("CpuPanel.qml")
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
    panelLoader.setSource(panelSource, {
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
    id: cpuPill
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
      spacing: root.displayMode === "full" && root.tokens.v2Shell !== true
        ? root.tokens.contentGap : root.tokens.compactGap

      Text {
        visible: root.displayMode === "full" && root.tokens.v2Shell !== true
        anchors.verticalCenter: parent.verticalCenter
        text: "CPU"
        color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
          root.widgetInk.b, 0.68)
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      CpuWave {
        visible: root.displayMode === "full" && root.tokens.v2Shell !== true
        anchors.verticalCenter: parent.verticalCenter
        history: root.history
        accent: root.widgetInk
      }

      IconText {
        visible: root.displayMode === "icon"
          || (root.tokens.v2Shell === true && root.displayMode === "full")
        anchors.verticalCenter: parent.verticalCenter
        text: "planner_review"
        color: root.widgetInk
        font.pixelSize: root.tokens.iconSize
        font.weight: Font.DemiBold
        fill: 1
      }

      Text {
        // V1 Compact is the reference CPU glyph plus its live percentage,
        // not a generic icon-only mode. V2 retains its independent icon mode.
        visible: root.percentageVisible
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.percent).padStart(2, "0") + "%"
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

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "CPU"
        color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
          root.widgetInk.b, 0.68)
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: String(root.percent).padStart(2, "0") + "%"
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }
}
