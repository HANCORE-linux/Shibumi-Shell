pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../adapters" as Adapters

// One process-wide owner for Quattro's Bluetooth and Bluetooth-audio state.
// Screen-local widgets and panels consume this facade without constructing
// additional BlueZ or PipeWire models.
Item {
  id: root

  required property var bar
  readonly property url panelSource: bar
    ? bar.registeredWidgetSource("omarchy.bluetooth") : ""
  property Component panelComponent: String(panelSource) ? null
    : bar ? bar.registeredWidgetComponent("omarchy.bluetooth") : null
  property var sessionOwners: []

  readonly property var backend: bridge.panel
  readonly property bool ready: bridge.ready
  readonly property bool adapterAvailable: bridge.adapterAvailable
  readonly property bool radioEnabled: bridge.radioEnabled
  readonly property bool discovering: bridge.discovering
  readonly property var connectedDevices: bridge.connectedDevices
  readonly property var knownDevices: bridge.knownDevices
  readonly property var discoveredDevices: bridge.discoveredDevices
  readonly property var pendingActions: bridge.pendingActions
  readonly property int connectedCount: connectedDevices.length
  readonly property int sessionCount: sessionOwners.length

  visible: false
  width: 0
  height: 0

  function officialSettings() {
    return bar && typeof bar.widgetSettings === "function"
      ? bar.widgetSettings("G15", "omarchy.bluetooth") : ({})
  }

  function beginSession(owner) {
    if (!owner) return false
    if (sessionOwners.indexOf(owner) < 0)
      sessionOwners = sessionOwners.concat([owner])
    if (sessionOwners.length === 1 && radioEnabled) bridge.startDiscovery()
    return true
  }

  function endSession(owner) {
    sessionOwners = sessionOwners.filter(item => item !== owner)
    if (sessionOwners.length === 0) bridge.stopDiscovery()
  }

  function restartDiscovery() {
    return sessionOwners.length > 0 && bridge.restartDiscovery()
  }

  function openPanel() {
    return bar && typeof bar.summonBarWidget === "function"
      ? bar.summonBarWidget("omarchy.bluetooth") : false
  }

  function closePanel() {
    return bar && typeof bar.hideBarWidget === "function"
      ? bar.hideBarWidget("omarchy.bluetooth") : false
  }

  function togglePanel() {
    return bar && typeof bar.isBarWidgetOpen === "function"
      && bar.isBarWidgetOpen("omarchy.bluetooth")
      ? closePanel() : openPanel()
  }

  function toggleBluetooth() {
    const enabling = !radioEnabled
    const accepted = bridge.toggleBluetooth()
    if (accepted && enabling && sessionOwners.length === 0) {
      // Quattro starts discovery after enabling the radio. A closed Shibumi
      // panel must not leave that scan running in the background.
      Qt.callLater(function() { Qt.callLater(function() {
        if (root.sessionOwners.length === 0) bridge.stopDiscovery()
      }) })
    }
    return accepted
  }
  function connectDevice(device) { return bridge.connectDevice(device) }
  function disconnectDevice(device) { return bridge.disconnectDevice(device) }
  function forgetDevice(device) { return bridge.forgetDevice(device) }
  function pendingAction(address) { return bridge.pendingAction(address) }
  function deviceLabel(device) { return bridge.deviceLabel(device) }

  function ensureSessionDiscovery() {
    // Quattro's toggle schedules discovery one event turn after enabling the
    // adapter. Wait behind that callback and only fill the gap for external
    // radio changes that did not originate in the official component.
    Qt.callLater(function() { Qt.callLater(function() {
      if (root.radioEnabled && root.sessionOwners.length > 0
          && !root.discovering) bridge.startDiscovery()
    }) })
  }

  onRadioEnabledChanged: {
    if (radioEnabled && sessionOwners.length > 0) ensureSessionDiscovery()
    else if (!radioEnabled) bridge.stopDiscovery()
  }

  Component.onDestruction: bridge.stopDiscovery()

  // Keep Quattro's public target while routing both halves of its lifecycle to
  // the screen-local Shibumi panel. The hidden official owner has IPC disabled.
  IpcHandler {
    target: "omarchy.bluetooth"

    function open(): void { root.openPanel() }
    function show(): void { root.openPanel() }
    function toggle(): void { root.togglePanel() }
    function close(): void { root.closePanel() }
    function hide(): void { root.closePanel() }
  }

  Adapters.BluetoothPanelBridge {
    id: bridge
    bar: root.bar
    ownerWidget: root.bar
    panelComponent: root.panelComponent
    panelSource: root.panelSource
    panelSettings: root.officialSettings()
  }
}
