pragma ComponentBehavior: Bound

import QtQuick
import "../adapters" as Adapters

// One process-wide owner for Quattro's monitor state and actions. The official
// component keeps hardware, scale, display, OSD, and IPC ownership; every
// output consumes this service through its own lazy Shibumi panel.
Item {
  id: root

  required property var bar
  readonly property url panelSource: bar
    ? bar.registeredWidgetSource("omarchy.monitor") : ""
  property Component panelComponent: String(panelSource) ? null
    : bar ? bar.registeredWidgetComponent("omarchy.monitor") : null

  readonly property var backend: bridge.panel
  readonly property bool ready: bridge.ready
  readonly property bool brightnessAvailable: bridge.brightnessAvailable
  readonly property int brightnessPercent: bridge.brightnessPercent
  readonly property string internalMonitor: bridge.internalMonitor
  readonly property string externalMonitor: bridge.externalMonitor
  readonly property string focusedMonitor: bridge.focusedMonitor
  readonly property bool internalEnabled: bridge.internalEnabled
  readonly property bool mirrorEnabled: bridge.mirrorEnabled
  readonly property string monitorScale: bridge.monitorScale
  readonly property var displays: bridge.displays
  readonly property int enabledDisplayCount: bridge.enabledDisplayCount
  readonly property var scaleValues: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property bool textSizeAvailable: bridge.textSizeAvailable
  readonly property var textSizeStops: bridge.textSizeStops
  readonly property int textSizeIndex: bridge.textSizeIndex
  readonly property real textSizePx: bridge.textSizePx

  visible: false
  width: 0
  height: 0

  function officialSettings() {
    return bar && typeof bar.widgetSettings === "function"
      ? bar.widgetSettings("G13", "omarchy.monitor") : ({})
  }

  function refresh() { return bridge.refresh() }
  function setBrightness(value) { return bridge.setBrightness(value) }
  function previewBrightness(value) { return bridge.previewBrightness(value) }
  function setScale(value) { return bridge.setScale(value) }
  function setTextSize(value) { return bridge.setTextSize(value) }
  function adjustTextSize(delta) { return bridge.adjustTextSize(delta) }
  function toggleDisplay(name, enabled) {
    return bridge.toggleDisplay(name, enabled)
  }
  function normalizeScale(value) { return bridge.normalizeScale(value) }
  function brightnessName(value) { return bridge.brightnessName(value) }

  Adapters.MonitorPanelBridge {
    id: bridge
    bar: root.bar
    ownerWidget: root.bar
    panelComponent: root.panelComponent
    panelSource: root.panelSource
    panelSettings: root.officialSettings()
  }
}
