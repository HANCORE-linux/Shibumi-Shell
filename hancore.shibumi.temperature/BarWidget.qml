pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.temperature"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var telemetryService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.telemetry") : null
  readonly property var telemetry: telemetryService
    ? telemetryService.thermal : null
  readonly property var stateService: hostShell
    && typeof hostShell.serviceFor === "function"
      ? hostShell.serviceFor("hancore.shibumi.state") : null
  property string hostGroupId: ""
  readonly property string stateGroupId: hostGroupId !== "" ? hostGroupId : "G16"
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property int iconSlotSize: 14
  readonly property int iconGlyphHorizontalOffset: 1
  readonly property int contentHorizontalOffset: bar && !bar.vertical
    && tokens.v2Shell !== true ? -1 : 0
  readonly property string selectedSource: {
    const candidate = String(setting("source", "cpu"))
    return telemetry && typeof telemetry.sourceValid === "function"
      && telemetry.sourceValid(candidate) ? candidate : "cpu"
  }
  readonly property string sourceLabel: telemetry
    && typeof telemetry.sourceLabel === "function"
    ? telemetry.sourceLabel(selectedSource) : "CPU package"
  readonly property int temperatureC: telemetry
    && typeof telemetry.temperatureFor === "function"
    ? telemetry.temperatureFor(selectedSource) : 0
  property var acquiredTelemetry: null

  implicitWidth: bar && bar.vertical ? bar.barSize : surface.implicitWidth
  implicitHeight: bar && bar.vertical ? surface.implicitHeight
    : bar ? bar.barSize : 28
  visible: root.temperatureC > 0

  function syncTelemetryOwner() {
    if (acquiredTelemetry === telemetry) return
    if (acquiredTelemetry) acquiredTelemetry.release()
    acquiredTelemetry = telemetry
    if (acquiredTelemetry) acquiredTelemetry.acquire()
  }

  function syncPanelLoader() {
    if (!opened) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(Qt.resolvedUrl("TemperaturePanel.qml"), {
      anchorItem: surface,
      bar: root.bar,
      ownerWidget: root,
      telemetry: root.telemetry
    })
  }

  function setTemperatureSource(source) {
    const candidate = String(source || "")
    if (!telemetry || typeof telemetry.sourceValid !== "function"
        || !telemetry.sourceValid(candidate)
        || typeof telemetry.sourceAvailable !== "function"
        || !telemetry.sourceAvailable(candidate)) return false
    return stateService && typeof stateService.setGroupSetting === "function"
      ? stateService.setGroupSetting(stateGroupId, "source", candidate) : false
  }

  onTelemetryChanged: syncTelemetryOwner()
  onOpenedChanged: syncPanelLoader()
  Component.onCompleted: syncTelemetryOwner()
  Component.onDestruction: if (acquiredTelemetry)
    acquiredTelemetry.release()

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
      anchors.horizontalCenterOffset: root.contentHorizontalOffset
      spacing: root.tokens.compactGap

      Item {
        id: temperatureIconSlot
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconSlotSize
        height: root.iconSlotSize

        Loader {
          anchors.centerIn: parent
          anchors.horizontalCenterOffset: root.iconGlyphHorizontalOffset
          sourceComponent: root.tokens.v2Shell === true
            ? v2TemperatureIcon : v1TemperatureIcon
        }
      }

      Text {
        visible: root.displayMode !== "icon"
        anchors.verticalCenter: parent.verticalCenter
        text: root.temperatureC + (root.tokens.v2Shell === true ? "°" : "°C")
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
      onEntered: if (root.bar)
        root.bar.showTooltip(surface,
          root.sourceLabel + " · " + root.temperatureC + "°C")
      onExited: if (root.bar) root.bar.hideTooltip(surface)
      onClicked: root.toggle()
    }
  }

  Loader { id: panelLoader }

  Component {
    id: v1TemperatureIcon
    IconText {
      text: "device_thermostat"
      color: root.widgetInk
      font.pixelSize: root.tokens.iconSize
      font.weight: Font.DemiBold
    }
  }

  Component {
    id: v2TemperatureIcon
    Text {
      text: ""
      color: root.widgetInk
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.tokens.iconSize
      renderType: Text.NativeRendering
    }
  }
}
