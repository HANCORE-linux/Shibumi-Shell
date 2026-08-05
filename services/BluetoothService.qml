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
  property var backendOverride: null
  property var sessionOwners: []
  property int discoveryRetryInterval: 1000
  property int discoveryRequestTimeoutInterval: 1500

  readonly property var backend: adapter.backend
  readonly property bool ready: adapter.ready
  readonly property bool adapterAvailable: adapter.adapterAvailable
  readonly property bool radioEnabled: adapter.radioEnabled
  readonly property bool discovering: adapter.discovering
  readonly property var connectedDevices: adapter.connectedDevices
  readonly property var knownDevices: adapter.knownDevices
  readonly property var discoveredDevices: adapter.discoveredDevices
  readonly property var pendingActions: adapter.pendingActions
  readonly property int connectedCount: connectedDevices.length
  readonly property int sessionCount: sessionOwners.length

  visible: false
  width: 0
  height: 0

  function beginSession(owner) {
    if (!owner) return false
    if (sessionOwners.indexOf(owner) < 0)
      sessionOwners = sessionOwners.concat([owner])
    if (sessionOwners.length === 1 && radioEnabled) adapter.startDiscovery()
    return true
  }

  function endSession(owner) {
    sessionOwners = sessionOwners.filter(item => item !== owner)
    if (sessionOwners.length === 0) adapter.stopDiscovery()
  }

  function restartDiscovery() {
    return sessionOwners.length > 0 && adapter.restartDiscovery()
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
    return adapter.toggleBluetooth()
  }
  function connectDevice(device) { return adapter.connectDevice(device) }
  function disconnectDevice(device) { return adapter.disconnectDevice(device) }
  function forgetDevice(device) { return adapter.forgetDevice(device) }
  function pendingAction(address) { return adapter.pendingAction(address) }
  function deviceLabel(device) { return adapter.deviceLabel(device) }

  onRadioEnabledChanged: {
    if (!radioEnabled) adapter.stopDiscovery()
  }

  Component.onDestruction: adapter.stopDiscovery()

  // Preserve Quattro's public contract with one process-wide Shibumi owner.
  IpcHandler {
    target: "omarchy.bluetooth"

    function open(): void { root.openPanel() }
    function show(): void { root.openPanel() }
    function toggle(): void { root.togglePanel() }
    function close(): void { root.closePanel() }
    function hide(): void { root.closePanel() }
    function toggleBluetooth(): void { root.toggleBluetooth() }
  }

  Adapters.BluetoothBackendAdapter {
    id: adapter
    backendOverride: root.backendOverride
    discoveryDesired: root.sessionCount > 0
    discoveryRequestTimeoutInterval: root.discoveryRequestTimeoutInterval
  }

  Timer {
    id: discoveryRetry
    interval: root.discoveryRetryInterval
    repeat: true
    triggeredOnStart: true
    running: root.sessionCount > 0 && root.adapterAvailable
      && root.radioEnabled && !root.discovering
    onTriggered: adapter.startDiscovery()
  }
}
