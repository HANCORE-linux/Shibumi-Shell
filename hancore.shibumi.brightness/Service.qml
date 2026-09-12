pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/runtime" as SuiteRuntime

// One process-wide owner for Quattro's monitor state and actions. The official
// component keeps hardware, scale, display, OSD, and IPC ownership; every
// output consumes this service through its own lazy Shibumi panel.
Item {
  id: root

  property var shell: null
  property var manifest: null
  SuiteRuntime.Provider {
    pluginId: "hancore.shibumi.brightness"
    implementationVersion: "0.1.1-beta.12"
    owner: root
    host: root.shell
    manifest: root.manifest
  }
  property var barWidgetRegistry: null
  property var bar: Qt.isQtObject(shell) && "bar" in shell ? shell.bar : null
  property var _visualBarLeases: []
  readonly property var visualBar: {
    let selected = null
    for (let index = 0; index < _visualBarLeases.length; index++) {
      const lease = _visualBarLeases[index]
      const candidate = lease && lease.hostedBar
      if (!Qt.isQtObject(candidate)) continue
      if (selected !== null && selected !== candidate) return null
      selected = candidate
    }
    return selected
  }
  readonly property bool scopedHost: Qt.isQtObject(shell) && "pluginId" in shell
  readonly property url panelSource: scopedHost ? ""
    : registeredSource("omarchy.monitor")
  property Component panelComponent: String(panelSource) ? null
    : registeredComponent("omarchy.monitor")

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

  function acquireVisualBar(holder, candidate) {
    if (!Qt.isQtObject(holder) || !Qt.isQtObject(candidate)) return null
    for (let index = 0; index < _visualBarLeases.length; index++) {
      const record = _visualBarLeases[index]
      if (Qt.isQtObject(record) && record.holder === holder) {
        if (record.hostedBar === candidate) return record.token
        releaseVisualBar(record.token)
        break
      }
    }
    if (_visualBarLeases.length >= 16) return null
    const token = Object.freeze({})
    const record = visualBarLeaseComponent.createObject(holder, {
      manager: root, holder: holder, hostedBar: candidate
    })
    if (!record) return null
    record.token = token
    _visualBarLeases = _visualBarLeases.concat([record])
    return token
  }

  function releaseVisualBar(token) {
    let found = null
    const next = []
    for (let index = 0; index < _visualBarLeases.length; index++) {
      const record = _visualBarLeases[index]
      if (found === null && Qt.isQtObject(record) && record.token === token)
        found = record
      else next.push(record)
    }
    if (found === null) return false
    _visualBarLeases = next
    found.manager = null
    found.destroy()
    return true
  }

  function visualBarRecordDestroyed(record) {
    if (!Qt.isQtObject(record) || _visualBarLeases.indexOf(record) < 0) return
    _visualBarLeases = _visualBarLeases.filter(function(value) {
      return value !== record
    })
  }

  function registeredSource(id) {
    if (bar && typeof bar.registeredWidgetSource === "function")
      return bar.registeredWidgetSource(id)
    const registry = Qt.isQtObject(shell) && "pluginRegistry" in shell
      ? shell.pluginRegistry : null
    const pluginManifest = registry && registry.installedPlugins
      ? registry.installedPlugins[String(id || "")] : null
    return registry && typeof registry.entryPointUrl === "function"
      ? registry.entryPointUrl(pluginManifest, "barWidget") : ""
  }

  function registeredComponent(id) {
    // Scoped 4.0.3 services receive the accepted public component snapshot
    // directly; the scalar shell.bar object is intentionally not a visual Item.
    const injected = barWidgetRegistry
    if (injected) void(injected.revision)
    const injectedWidgets = injected && injected.widgets ? injected.widgets : ({})
    const injectedEntry = injectedWidgets[String(id || "")]
    if (injectedEntry && injectedEntry.component) return injectedEntry.component
    if (scopedHost) return null
    if (bar && typeof bar.registeredWidgetComponent === "function")
      return bar.registeredWidgetComponent(id)
    const registry = bar && "barWidgetRegistry" in bar
      ? bar.barWidgetRegistry : null
    if (registry) void(registry.revision)
    const widgets = registry && registry.widgets ? registry.widgets : ({})
    const entry = widgets[String(id || "")]
    return entry && entry.component ? entry.component : null
  }

  visible: false
  width: 0
  height: 0

  function officialSettings() {
    const host = visualBar || bar
    return host && typeof host.widgetSettings === "function"
      ? host.widgetSettings("G13", "omarchy.monitor") : ({})
  }

  function refresh() { return bridge.refresh() }
  function setBrightness(value) { return bridge.setBrightness(value) }
  function previewBrightness(value) { return bridge.previewBrightness(value) }
  function showBrightnessOsd(value) { return bridge.showBrightnessOsd(value) }
  function setScale(value) { return bridge.setScale(value) }
  function setTextSize(value) { return bridge.setTextSize(value) }
  function adjustTextSize(delta) { return bridge.adjustTextSize(delta) }
  function toggleDisplay(name, enabled) {
    return bridge.toggleDisplay(name, enabled)
  }
  function normalizeScale(value) { return bridge.normalizeScale(value) }
  function brightnessName(value) { return bridge.brightnessName(value) }

  Component.onDestruction: {
    bridge.shutdown()
    const leases = _visualBarLeases.slice()
    _visualBarLeases = []
    for (let index = 0; index < leases.length; index++) {
      const record = leases[index]
      if (!Qt.isQtObject(record)) continue
      record.manager = null
      record.destroy()
    }
  }

  Component {
    id: visualBarLeaseComponent
    VisualBarLease {}
  }

  MonitorPanelBridge {
    id: bridge
    bar: root.visualBar || root.bar
    ownerShell: root.shell
    ownerWidget: root
    panelComponent: root.panelComponent
    panelSource: root.panelSource
    panelSettings: root.officialSettings()
  }
}
