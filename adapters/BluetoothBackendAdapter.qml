pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "BluetoothModel.js" as Model

Item {
  id: root

  property var backendOverride: null
  property var nativeDevicesOverride: null
  property bool discoveryOwned: false
  property var discoveryOwnerAdapter: null
  property int discoveryGeneration: 0
  property var nativePendingActions: ({})
  property var pendingAudioOutputDevice: null
  property int pendingAudioOutputAttempts: 0

  readonly property var backend: backendOverride !== null ? backendOverride : root
  readonly property bool ready: true
  readonly property var adapter: backendOverride !== null
    ? ("adapter" in backendOverride ? backendOverride.adapter : null)
    : Bluetooth.defaultAdapter
  readonly property bool adapterAvailable: adapter !== null
  readonly property bool radioEnabled: adapterAvailable
    && adapter.enabled !== undefined && adapter.enabled === true
  readonly property bool discovering: adapterAvailable
    && adapter.discovering !== undefined && adapter.discovering === true
  readonly property var nativeDevices: nativeDevicesOverride !== null
    ? nativeDevicesOverride
    : (backendOverride === null && Bluetooth.devices ? Bluetooth.devices.values : [])
  readonly property var pipewireNodes: backendOverride === null && Pipewire.nodes
    ? Pipewire.nodes.values : []
  readonly property var nativeDeviceGroups: Model.deviceLists(nativeDevices)
  readonly property var connectedDevices: backendOverride !== null
    ? backendList("connectedDevices") : nativeDeviceGroups.connected
  readonly property var knownDevices: backendOverride !== null
    ? backendList("knownDevices") : nativeDeviceGroups.known
  readonly property var discoveredDevices: backendOverride !== null
    ? backendList("discoveredDevices") : nativeDeviceGroups.discovered
  readonly property var pendingActions: backendOverride !== null
    && "pendingActions" in backendOverride
    ? backendOverride.pendingActions : nativePendingActions

  visible: false
  width: 0
  height: 0

  function backendList(name) {
    if (backendOverride === null || !(name in backendOverride)) return []
    const values = backendOverride[name]
    return Array.isArray(values) ? values : []
  }
  function deviceLabel(device) {
    if (backendOverride !== null && typeof backendOverride.deviceLabel === "function")
      return String(backendOverride.deviceLabel(device) || "")
    return Model.deviceLabel(device)
  }
  function pendingAction(address) {
    const key = String(address || "")
    if (backendOverride !== null && typeof backendOverride.pendingAction === "function")
      return String(backendOverride.pendingAction(key) || "")
    return key && nativePendingActions[key] ? nativePendingActions[key] : ""
  }
  function startDiscovery() {
    if (!adapterAvailable || !radioEnabled) return false
    discoveryGeneration++
    if (!discovering) {
      adapter.discovering = true
      discoveryOwned = true
      discoveryOwnerAdapter = adapter
    }
    return true
  }
  function stopDiscovery() {
    discoveryGeneration++
    const owner = discoveryOwnerAdapter
    if (discoveryOwned && owner && owner.discovering !== undefined
        && owner.discovering)
      owner.discovering = false
    discoveryOwned = false
    discoveryOwnerAdapter = null
    return true
  }
  function restartDiscovery() {
    if (!adapterAvailable || !radioEnabled) return false
    if (discovering && !discoveryOwned) return true
    discoveryGeneration++
    const generation = discoveryGeneration
    if (discovering) adapter.discovering = false
    Qt.callLater(function() {
      if (root.discoveryGeneration !== generation || !root.adapterAvailable
          || !root.radioEnabled) return
      root.adapter.discovering = true
      root.discoveryOwned = true
      root.discoveryOwnerAdapter = root.adapter
    })
    return true
  }
  function toggleBluetooth() {
    if (!adapterAvailable) return false
    if (backendOverride !== null) {
      if (typeof backendOverride.toggleBluetooth !== "function") return false
      backendOverride.toggleBluetooth()
      return true
    }
    if (radioEnabled) stopDiscovery()
    adapter.enabled = !adapter.enabled
    return true
  }
  function setNativePendingAction(address, action) {
    if (!address) return
    nativePendingActions = Model.withPendingAction(nativePendingActions, String(address), String(action || ""))
    if (action) pendingTimeout.restart()
  }
  function deviceCommand(action, address) {
    return ["omarchy-bluetooth-device", String(action), String(address)]
  }
  function runNativeDeviceAction(device, action, pending) {
    if (!device || !device.address) return false
    setNativePendingAction(device.address, pending)
    Quickshell.execDetached(deviceCommand(action, device.address))
    return true
  }
  function connectDevice(device) {
    if (!device || device.connected) return false
    if (backendOverride !== null) {
      if (typeof backendOverride.connectDevice !== "function") return false
      backendOverride.connectDevice(device)
      return true
    }
    const action = device.paired || device.bonded || device.trusted ? "connect" : "pair"
    return runNativeDeviceAction(device, action, "connecting")
  }
  function disconnectDevice(device) {
    if (!device || !device.address || !device.connected) return false
    if (backendOverride !== null) {
      if (typeof backendOverride.disconnectDevice !== "function") return false
      backendOverride.disconnectDevice(device)
      return true
    }
    setNativePendingAction(device.address, "disconnecting")
    if (typeof device.disconnect === "function") device.disconnect()
    Quickshell.execDetached(deviceCommand("disconnect", device.address))
    return true
  }
  function forgetDevice(device) {
    if (!device || !device.address) return false
    if (backendOverride !== null) {
      if (typeof backendOverride.forgetDevice !== "function") return false
      backendOverride.forgetDevice(device)
      return true
    }
    return runNativeDeviceAction(device, "forget", "forgetting")
  }
  function audioSinks() {
    const sinks = []
    for (let i = 0; i < pipewireNodes.length; i++) {
      const node = pipewireNodes[i]
      if (node && node.isSink && !node.isStream) sinks.push(node)
    }
    return sinks
  }
  function bluetoothAudioSink(device) {
    const sinks = audioSinks()
    for (let i = 0; i < sinks.length; i++)
      if (Model.bluetoothSinkMatchesDevice(sinks[i], device)) return sinks[i]
    return null
  }
  function setDefaultAudioSink(sink) {
    if (!sink) return
    Pipewire.preferredDefaultAudioSink = sink
    if (sink.id === undefined || !sink.name) return
    Quickshell.execDetached(["omarchy-audio-output-set-default", String(sink.id), String(sink.name)])
  }
  function scheduleAudioOutputSwitch(device) {
    pendingAudioOutputDevice = {
      address: device && device.address ? device.address : "",
      name: device && device.name ? device.name : "",
      deviceName: device && device.deviceName ? device.deviceName : ""
    }
    pendingAudioOutputAttempts = 0
    audioSwitchTimer.restart()
  }
  function switchPendingAudioOutput() {
    if (!pendingAudioOutputDevice) return
    const sink = bluetoothAudioSink(pendingAudioOutputDevice)
    if (sink) {
      setDefaultAudioSink(sink)
      pendingAudioOutputDevice = null
      audioSwitchTimer.stop()
      return
    }
    pendingAudioOutputAttempts++
    if (pendingAudioOutputAttempts >= 8) { pendingAudioOutputDevice = null; return }
    audioSwitchTimer.restart()
  }
  function syncNativePendingActions() {
    if (backendOverride !== null) return
    const next = Model.cloneMap(nativePendingActions)
    let changed = false
    for (const address in next) {
      const action = next[address]
      let found = null
      for (let i = 0; i < nativeDevices.length; i++) {
        const device = nativeDevices[i]
        if (device && device.address === address) { found = device; break }
      }
      const finishedConnecting = action === "connecting" && found && found.connected
      if (finishedConnecting
          || (action === "disconnecting" && found && !found.connected)
          || (action === "forgetting" && (!found
            || (!found.paired && !found.bonded && !found.trusted)))) {
        if (finishedConnecting) scheduleAudioOutputSwitch(found)
        delete next[address]
        changed = true
      }
    }
    if (changed) nativePendingActions = next
  }

  onNativeDevicesChanged: syncNativePendingActions()
  onConnectedDevicesChanged: syncNativePendingActions()
  onKnownDevicesChanged: syncNativePendingActions()
  onDiscoveredDevicesChanged: syncNativePendingActions()
  onAdapterChanged: {
    discoveryGeneration++
    const owner = discoveryOwnerAdapter
    if (discoveryOwned && owner && owner !== adapter
        && owner.discovering !== undefined && owner.discovering)
      owner.discovering = false
    discoveryOwned = false
    discoveryOwnerAdapter = null
  }
  Component.onDestruction: stopDiscovery()

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.nativePendingActions = ({})
  }
  Timer {
    id: audioSwitchTimer
    interval: 500
    repeat: false
    onTriggered: root.switchPendingAudioOutput()
  }
}
