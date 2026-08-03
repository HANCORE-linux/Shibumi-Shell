pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui as Ui

Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property bool manageIpc: true
  property bool opened: false
  property bool brightnessAvailable: true
  property int brightnessPercent: 64
  property int pendingBrightnessPercent: 64
  property string internalMonitor: "eDP-1"
  property string externalMonitor: "DP-1"
  property string focusedMonitor: "eDP-1"
  property bool internalEnabled: true
  property bool mirrorEnabled: false
  property string monitorScale: "1.25"
  property int enabledDisplayCount: 2
  property int refreshCount: 0
  property int previewCount: 0
  property int setCount: 0
  property int scaleCount: 0
  property int toggleCount: 0
  property int textSizeSetCount: 0
  property int textSizePx: 12
  property int viewLoadCount: 0
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property var displays: [
    { name: "eDP-1", enabled: true, focused: true },
    { name: "DP-1", enabled: true, focused: false }
  ]
  readonly property var internalButton: button

  implicitWidth: 27
  implicitHeight: 35

  function open() {
    opened = true
    if (bar) bar.requestPopout(root)
  }
  function close() {
    opened = false
    if (bar) bar.releasePopout(root)
  }
  function refresh() { refreshCount++ }
  function setBrightness(value) {
    setCount++
    brightnessPercent = Math.max(1, Math.min(100, Math.round(value)))
    pendingBrightnessPercent = brightnessPercent
  }
  function previewBrightness(value) {
    previewCount++
    brightnessPercent = Math.max(1, Math.min(100, Math.round(value)))
  }
  function setScale(value) {
    scaleCount++
    monitorScale = normalizeScale(value)
  }
  function currentTextIndex() { return textSizeStops.indexOf(textSizePx) }
  function displayedTextPx() { return textSizePx }
  function setTextSize(value) {
    textSizeSetCount++
    textSizePx = Math.round(Number(value))
  }
  function toggleDisplay(name, enabled) {
    toggleCount++
    const next = []
    let count = 0
    for (let i = 0; i < displays.length; i++) {
      const row = displays[i]
      const item = {
        name: row.name,
        enabled: row.name === name ? !enabled : row.enabled,
        focused: row.focused
      }
      if (item.enabled) count++
      next.push(item)
    }
    displays = next
    enabledDisplayCount = count
  }
  function normalizeScale(value) {
    const number = parseFloat(String(value || ""))
    return isFinite(number) ? String(Math.round(number * 100) / 100) : ""
  }
  function brightnessName(value) {
    return Number(value) >= 50 ? "Test bright" : "Test dim"
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "monitor"
    onPressed: function(_button) { root.opened ? root.close() : root.open() }
  }
}
