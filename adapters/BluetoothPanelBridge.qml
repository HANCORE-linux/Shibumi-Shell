pragma ComponentBehavior: Bound

import QtQuick

// Hosts Quattro's complete Bluetooth component as the single process-wide
// BlueZ, pairing, pending-action, and Bluetooth-audio owner.
Item {
  id: root

  required property var bar
  required property Item ownerWidget
  property Component panelComponent: null
  property url panelSource: ""
  property var panelSettings: ({})
  property bool discoveryOwned: false
  property int discoveryGeneration: 0

  readonly property var panel: panelLoader.item
  readonly property bool ready: panel !== null
  readonly property bool opened: ready && panel.opened === true
  readonly property var adapter: ready && panel.adapter !== undefined
    ? panel.adapter : null
  readonly property bool adapterAvailable: adapter !== null
  readonly property bool radioEnabled: adapterAvailable
    && adapter.enabled !== undefined ? adapter.enabled === true : false
  readonly property bool discovering: adapterAvailable
    && adapter.discovering !== undefined ? adapter.discovering === true : false
  readonly property var connectedDevices: ready
    && panel.connectedDevices !== undefined && Array.isArray(panel.connectedDevices)
    ? panel.connectedDevices : []
  readonly property var knownDevices: ready
    && panel.knownDevices !== undefined && Array.isArray(panel.knownDevices)
    ? panel.knownDevices : []
  readonly property var discoveredDevices: ready
    && panel.discoveredDevices !== undefined && Array.isArray(panel.discoveredDevices)
    ? panel.discoveredDevices : []
  readonly property var pendingActions: ready && panel.pendingActions !== undefined
    ? panel.pendingActions : ({})

  function deviceLabel(device) {
    if (ready && typeof panel.deviceLabel === "function")
      return String(panel.deviceLabel(device) || "")
    return device ? String(device.deviceName || device.name || "").trim() : ""
  }

  function pendingAction(address) {
    return ready && typeof panel.pendingAction === "function"
      ? String(panel.pendingAction(String(address || "")) || "") : ""
  }

  function startDiscovery() {
    if (!adapterAvailable || !radioEnabled) return false
    discoveryGeneration++
    discoveryOwned = true
    if (!discovering) adapter.discovering = true
    return true
  }

  function stopDiscovery() {
    discoveryGeneration++
    if (discoveryOwned && adapterAvailable && discovering)
      adapter.discovering = false
    discoveryOwned = false
    return true
  }

  function restartDiscovery() {
    if (!adapterAvailable || !radioEnabled) return false
    discoveryGeneration++
    const generation = discoveryGeneration
    discoveryOwned = true
    if (discovering) adapter.discovering = false
    Qt.callLater(function() {
      if (root.discoveryOwned && root.discoveryGeneration === generation
          && root.adapterAvailable && root.radioEnabled)
        root.adapter.discovering = true
    })
    return true
  }

  function toggleBluetooth() {
    if (!ready || !adapterAvailable
        || typeof panel.toggleBluetooth !== "function") return false
    if (radioEnabled) stopDiscovery()
    else discoveryOwned = true
    panel.toggleBluetooth()
    return true
  }

  function connectDevice(device) {
    if (!ready || !device || typeof panel.connectDevice !== "function") return false
    panel.connectDevice(device)
    return true
  }

  function disconnectDevice(device) {
    if (!ready || !device || typeof panel.disconnectDevice !== "function") return false
    panel.disconnectDevice(device)
    return true
  }

  function forgetDevice(device) {
    if (!ready || !device || typeof panel.forgetDevice !== "function") return false
    panel.forgetDevice(device)
    return true
  }

  function injectPanel() {
    if (!panel) return
    if ("bar" in panel) panel.bar = hostProxy
    if ("moduleName" in panel) panel.moduleName = "omarchy.bluetooth"
    if ("settings" in panel) panel.settings = panelSettings
    if ("manageIpc" in panel) panel.manageIpc = false
    if (panel.opened === true && typeof panel.close === "function") panel.close()
    panel.opacity = 0
  }

  function syncPanelSource() {
    panelLoader.sourceComponent = null
    panelLoader.source = ""
    if (panelComponent !== null) {
      panelLoader.sourceComponent = panelComponent
    } else if (String(panelSource)) {
      panelLoader.setSource(panelSource, {
        bar: hostProxy,
        moduleName: "omarchy.bluetooth",
        manageIpc: false,
        settings: panelSettings
      })
    }
  }

  onPanelSettingsChanged: injectPanel()
  onBarChanged: injectPanel()
  onPanelComponentChanged: Qt.callLater(syncPanelSource)
  onPanelSourceChanged: Qt.callLater(syncPanelSource)
  Component.onCompleted: Qt.callLater(syncPanelSource)
  Component.onDestruction: {
    stopDiscovery()
    if (!panel || !bar) return
    if (panel.opened === true && typeof panel.close === "function") panel.close()
  }

  // Defensive redirect for any direct open on the hidden official owner. The
  // process-wide service owns the public IPC target for symmetric open/close.
  Connections {
    target: root.panel
    function onOpenedChanged() {
      if (!root.panel || root.panel.opened !== true) return
      if (root.adapterAvailable && root.discovering) root.discoveryOwned = true
      if (root.bar && typeof root.bar.summonBarWidget === "function")
        root.bar.summonBarWidget("omarchy.bluetooth")
      Qt.callLater(function() {
        if (root.panel && root.panel.opened === true
            && typeof root.panel.close === "function") root.panel.close()
      })
    }
  }

  QtObject {
    id: hostProxy

    readonly property var realBar: root.bar
    readonly property bool vertical: realBar ? realBar.vertical === true : false
    readonly property int barSize: realBar ? Number(realBar.barSize) : 35
    readonly property int sizeHorizontal: realBar && realBar.sizeHorizontal !== undefined
      ? Number(realBar.sizeHorizontal) : barSize
    readonly property string position: realBar ? String(realBar.position || "top") : "top"
    readonly property string fontFamily: realBar ? String(realBar.fontFamily || "monospace") : "monospace"
    readonly property color foreground: realBar ? realBar.foreground : "#ffffff"
    readonly property color barForeground: foreground
    readonly property color urgent: realBar ? realBar.urgent : foreground
    readonly property bool foregroundAnimationEnabled: realBar
      ? realBar.foregroundAnimationEnabled !== false : false
    readonly property var shell: realBar ? realBar.shell : null
    readonly property var activePopout: null
    readonly property var clickTargets: []

    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(_owner) {}
    function releasePopout(_owner) {}
    function switchPanelFrom(_owner, direction) {
      return realBar && typeof realBar.switchPanelFrom === "function"
        ? realBar.switchPanelFrom(root.ownerWidget, direction) : false
    }
    function targetBelongsToWindow(target, window) {
      return realBar && typeof realBar.targetBelongsToWindow === "function"
        ? realBar.targetBelongsToWindow(target, window) : false
    }
    function run(command) {
      if (realBar && typeof realBar.run === "function") realBar.run(command)
    }
  }

  Loader {
    id: panelLoader
    anchors.fill: parent
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
