pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "." as Local
import "BluetoothModel.js" as Model

// The process-wide Bluetooth state and action owner. This deliberately uses
// Quickshell's data APIs directly; no foreign UI component is instantiated.
Item {
  id: root

  // Runtime tests inject a side-effect-free backend. Production leaves this
  // null and therefore uses the native BlueZ/PipeWire implementation below.
  property var backendOverride: null
  property var adapterOverride: null
  // Lets the component smoke test drive native device property transitions
  // without touching the host's real Bluetooth devices.
  property var nativeDevicesOverride: null
  property var pipewireNodesOverride: null
  property var commandRunnerOverride: null
  property var audioOutputOverride: null
  property int audioSwitchInterval: 500
  property int audioIntentTimeoutInterval: 60000
  property int discoveryRequestTimeoutInterval: 1500
  property int discoveryDestructionGuardInterval: 30000
  property bool discoveryOwned: false
  property var discoveryOwnerAdapter: null
  property var discoveryRequestedAdapter: null
  property var retiredDiscoveryAdapter: null
  property bool discoveryDesired: false
  property var nativePendingActions: ({})
  property var audioHandoffIntent: null
  property var pendingAudioOutputDevice: null
  property int pendingAudioOutputAttempts: 0

  readonly property var backend: backendOverride !== null ? backendOverride : root
  readonly property bool ready: true
  readonly property var adapter: backendOverride !== null
    ? ("adapter" in backendOverride ? backendOverride.adapter : null)
    : (adapterOverride !== null ? adapterOverride : Bluetooth.defaultAdapter)
  readonly property bool adapterAvailable: adapter !== null
  readonly property bool radioEnabled: adapterAvailable
    && adapter.enabled !== undefined && adapter.enabled === true
  readonly property bool discovering: adapterAvailable
    && adapter.discovering !== undefined && adapter.discovering === true
  readonly property var nativeDevices: nativeDevicesOverride !== null
    ? nativeDevicesOverride
    : (backendOverride === null && Bluetooth.devices ? Bluetooth.devices.values : [])
  readonly property var pipewireNodes: pipewireNodesOverride !== null
    ? pipewireNodesOverride
    : (backendOverride === null && Pipewire.nodes ? Pipewire.nodes.values : [])
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
    if (backendOverride !== null
        && typeof backendOverride.deviceLabel === "function")
      return String(backendOverride.deviceLabel(device) || "")
    return Model.deviceLabel(device)
  }

  function pendingAction(address) {
    const key = String(address || "")
    if (backendOverride !== null
        && typeof backendOverride.pendingAction === "function")
      return String(backendOverride.pendingAction(key) || "")
    return key && nativePendingActions[key] ? nativePendingActions[key] : ""
  }

  // discoveryOwned is only set if Shibumi changed false -> true. An already
  // active external scan is observed but never claimed or stopped by Shibumi.
  function startDiscovery() {
    if (!adapterAvailable || !radioEnabled) return false
    // A replacement service must first retire a teardown guard from its own
    // predecessor. If that pending start has already completed, inherit the
    // proven Shibumi request instead of misclassifying it as external and
    // letting the old guard stop it.
    const target = adapter
    const inheritedRequest = Local.BluetoothDiscoveryGuard.disarm(target)
    // Read the native property directly: the derived QML binding may still
    // hold the previous value inside the adapter's discoveringChanged turn.
    if (target && !!target.discovering) {
      if (inheritedRequest) {
        discoveryRequestedAdapter = null
        if (retiredDiscoveryAdapter === target)
          retiredDiscoveryAdapter = null
        discoveryOwned = true
        discoveryOwnerAdapter = target
        if (!retiredDiscoveryAdapter) discoveryRequestTimeout.stop()
      }
      return true
    }
    if (discoveryRequestedAdapter === target) return true
    if (retiredDiscoveryAdapter === target) retiredDiscoveryAdapter = null
    discoveryRequestedAdapter = target
    discoveryRequestTimeout.restart()
    requestAdapterDiscovery(target)
    return true
  }

  function requestAdapterDiscovery(target) {
    if (backendOverride !== null
        && typeof backendOverride.requestDiscovery === "function")
      backendOverride.requestDiscovery(target)
    else target.discovering = true
  }

  function confirmRequestedDiscovery() {
    const requested = discoveryRequestedAdapter
    if (!requested || !requested.discovering) return
    discoveryRequestedAdapter = null
    if (!discoveryDesired || requested !== adapter) {
      retiredDiscoveryAdapter = requested
      requested.discovering = false
      return
    }
    discoveryOwned = true
    discoveryOwnerAdapter = requested
    if (!retiredDiscoveryAdapter) discoveryRequestTimeout.stop()
  }

  function retirePendingDiscovery() {
    const requested = discoveryRequestedAdapter
    if (!requested) return
    discoveryRequestedAdapter = null
    retiredDiscoveryAdapter = requested
    discoveryRequestTimeout.restart()
    if (requested.discovering !== undefined && requested.discovering)
      requested.discovering = false
  }

  function expireDiscoveryRequestWindow() {
    confirmRequestedDiscovery()
    if (discoveryRequestedAdapter && !discoveryRequestedAdapter.discovering)
      discoveryRequestedAdapter = null
    const retired = retiredDiscoveryAdapter
    retiredDiscoveryAdapter = null
    if (retired && retired.discovering !== undefined && retired.discovering)
      retired.discovering = false
  }

  function stopDiscovery() {
    retirePendingDiscovery()
    const owner = discoveryOwnerAdapter
    if (discoveryOwned && owner && owner.discovering !== undefined
        && owner.discovering)
      owner.discovering = false
    discoveryOwned = false
    discoveryOwnerAdapter = null
    return true
  }

  function destroyDiscovery() {
    const requested = discoveryRequestedAdapter
    const retired = retiredDiscoveryAdapter
    if (requested)
      Local.BluetoothDiscoveryGuard.arm(requested, discoveryDestructionGuardInterval)
    if (retired && retired !== requested)
      Local.BluetoothDiscoveryGuard.arm(retired, discoveryDestructionGuardInterval)
    stopDiscovery()
  }

  function restartDiscovery() {
    if (!adapterAvailable || !radioEnabled) return false
    // A scan that was already active before Shibumi opened is externally
    // owned. Refresh must observe it without toggling or claiming it.
    if (discovering && !discoveryOwned) return true
    if (discovering) return stopDiscovery()
    return startDiscovery()
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
    nativePendingActions = Model.withPendingAction(
      nativePendingActions, String(address), String(action || ""))
    if (action) pendingTimeout.restart()
  }

  function rememberAudioHandoffIntent(device) {
    if (!device || !device.address) return
    // There can only be one default sink. A newer explicit connect request
    // therefore replaces every older, not-yet-consumed handoff intent.
    cancelPendingAudioOutput("")
    audioHandoffIntent = {
      address: String(device.address),
      name: device.name ? String(device.name) : "",
      deviceName: device.deviceName ? String(device.deviceName) : ""
    }
    audioIntentTimeout.restart()
  }

  function clearAudioHandoffIntent(address) {
    const key = String(address || "")
    if (!audioHandoffIntent || !key
        || String(audioHandoffIntent.address || "") !== key) return
    audioHandoffIntent = null
    audioIntentTimeout.stop()
  }

  function cancelPendingAudioOutput(address) {
    const key = String(address || "")
    if (pendingAudioOutputDevice && (!key
        || String(pendingAudioOutputDevice.address || "") === key)) {
      pendingAudioOutputDevice = null
      pendingAudioOutputAttempts = 0
      audioSwitchTimer.stop()
    }
  }

  function cancelAudioHandoff(address) {
    clearAudioHandoffIntent(address)
    cancelPendingAudioOutput(address)
  }

  function cancelAllAudioHandoffs() {
    audioHandoffIntent = null
    audioIntentTimeout.stop()
    cancelPendingAudioOutput("")
  }

  function deviceCommand(action, address) {
    return ["omarchy-bluetooth-device", String(action), String(address)]
  }

  function executeDeviceCommand(command) {
    if (commandRunnerOverride !== null
        && typeof commandRunnerOverride.run === "function") {
      commandRunnerOverride.run(command)
      return
    }
    Quickshell.execDetached(command)
  }

  function runNativeDeviceAction(device, action, pending) {
    if (!device || !device.address) return false
    setNativePendingAction(device.address, pending)
    executeDeviceCommand(deviceCommand(action, device.address))
    return true
  }

  function connectDevice(device) {
    if (!device || device.connected) return false
    if (backendOverride !== null) {
      if (typeof backendOverride.connectDevice !== "function") return false
      backendOverride.connectDevice(device)
      return true
    }
    const action = device.paired || device.bonded || device.trusted
      ? "connect" : "pair"
    rememberAudioHandoffIntent(device)
    return runNativeDeviceAction(device, action, "connecting")
  }

  function disconnectDevice(device) {
    if (!device || !device.address || !device.connected) return false
    if (backendOverride !== null) {
      if (typeof backendOverride.disconnectDevice !== "function") return false
      backendOverride.disconnectDevice(device)
      return true
    }
    cancelAudioHandoff(device.address)
    setNativePendingAction(device.address, "disconnecting")
    if (typeof device.disconnect === "function") device.disconnect()
    executeDeviceCommand(deviceCommand("disconnect", device.address))
    return true
  }

  function forgetDevice(device) {
    if (!device || !device.address) return false
    if (backendOverride !== null) {
      if (typeof backendOverride.forgetDevice !== "function") return false
      backendOverride.forgetDevice(device)
      return true
    }
    cancelAudioHandoff(device.address)
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
    if (audioOutputOverride !== null
        && typeof audioOutputOverride.setDefaultSink === "function") {
      audioOutputOverride.setDefaultSink(sink)
      return
    }
    Pipewire.preferredDefaultAudioSink = sink
    if (sink.id === undefined || !sink.name) return
    Quickshell.execDetached([
      "omarchy-audio-output-set-default",
      String(sink.id),
      String(sink.name)
    ])
  }

  function scheduleAudioOutputSwitch(device) {
    if (!device || !device.address || !device.connected) return
    pendingAudioOutputDevice = {
      address: device && device.address ? device.address : "",
      name: device && device.name ? device.name : "",
      deviceName: device && device.deviceName ? device.deviceName : ""
    }
    pendingAudioOutputAttempts = 0
    audioSwitchTimer.restart()
  }

  function nativeDeviceByAddress(address) {
    const key = String(address || "")
    for (let i = 0; i < nativeDevices.length; i++) {
      const device = nativeDevices[i]
      if (device && String(device.address || "") === key) return device
    }
    return null
  }

  function deviceUsesCurrentAdapter(device) {
    return device && (device.adapter === undefined || device.adapter === null
      || device.adapter === adapter)
  }

  function validatePendingAudioOutput() {
    if (!pendingAudioOutputDevice) return false
    const device = nativeDeviceByAddress(pendingAudioOutputDevice.address)
    if (!radioEnabled || !device || !device.connected
        || !deviceUsesCurrentAdapter(device)) {
      cancelPendingAudioOutput("")
      return false
    }
    return true
  }

  function switchPendingAudioOutput() {
    if (!validatePendingAudioOutput()) return
    const device = nativeDeviceByAddress(pendingAudioOutputDevice.address)
    const sink = bluetoothAudioSink(device)
    if (sink) {
      setDefaultAudioSink(sink)
      pendingAudioOutputDevice = null
      audioSwitchTimer.stop()
      return
    }
    pendingAudioOutputAttempts++
    if (pendingAudioOutputAttempts >= 8) {
      pendingAudioOutputDevice = null
      return
    }
    audioSwitchTimer.restart()
  }

  function syncNativeAudioHandoffIntents() {
    if (backendOverride !== null) return
    const intent = audioHandoffIntent
    if (intent) {
      const device = nativeDeviceByAddress(intent.address)
      if (device && device.connected && deviceUsesCurrentAdapter(device)) {
        scheduleAudioOutputSwitch(device)
        audioHandoffIntent = null
        audioIntentTimeout.stop()
      }
    }
    validatePendingAudioOutput()
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
        if (device && device.address === address) {
          found = device
          break
        }
      }

      const finishedConnecting = action === "connecting" && found && found.connected
      if (finishedConnecting
          || (action === "disconnecting" && found && !found.connected)
          || (action === "forgetting" && (!found
            || (!found.paired && !found.bonded && !found.trusted)))) {
        delete next[address]
        changed = true
      }
    }
    if (changed) nativePendingActions = next
  }

  onNativeDevicesChanged: {
    syncNativePendingActions()
    syncNativeAudioHandoffIntents()
  }
  // ScriptModel.values changes when the collection changes, while a device's
  // connection/pairing flags have their own signals. The derived group signals
  // cover both paths and complete pending actions as soon as state settles.
  onConnectedDevicesChanged: {
    syncNativePendingActions()
    syncNativeAudioHandoffIntents()
  }
  onKnownDevicesChanged: {
    syncNativePendingActions()
    syncNativeAudioHandoffIntents()
  }
  onDiscoveredDevicesChanged: {
    syncNativePendingActions()
    syncNativeAudioHandoffIntents()
  }
  onDiscoveryDesiredChanged: if (!discoveryDesired) stopDiscovery()
  onRadioEnabledChanged: if (!radioEnabled) cancelAllAudioHandoffs()
  onAdapterChanged: {
    // Ownership is tied to the adapter instance on which Shibumi started the
    // scan. Stop that scan before observing a replacement adapter as external.
    retirePendingDiscovery()
    const owner = discoveryOwnerAdapter
    if (discoveryOwned && owner && owner !== adapter
        && owner.discovering !== undefined && owner.discovering)
      owner.discovering = false
    discoveryOwned = false
    discoveryOwnerAdapter = null
    cancelAllAudioHandoffs()
  }
  Component.onDestruction: destroyDiscovery()

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.nativePendingActions = ({})
  }

  Timer {
    id: audioSwitchTimer
    interval: root.audioSwitchInterval
    repeat: false
    onTriggered: root.switchPendingAudioOutput()
  }

  Timer {
    id: audioIntentTimeout
    interval: root.audioIntentTimeoutInterval
    repeat: false
    onTriggered: root.audioHandoffIntent = null
  }

  Timer {
    id: discoveryRequestTimeout
    interval: root.discoveryRequestTimeoutInterval
    repeat: false
    onTriggered: root.expireDiscoveryRequestWindow()
  }

  Connections {
    target: root.discoveryRequestedAdapter
    ignoreUnknownSignals: true
    function onDiscoveringChanged() { root.confirmRequestedDiscovery() }
  }

  Connections {
    target: root.discoveryOwnerAdapter
    ignoreUnknownSignals: true
    function onDiscoveringChanged() {
      const owner = root.discoveryOwnerAdapter
      if (owner && !owner.discovering) {
        root.discoveryOwned = false
        root.discoveryOwnerAdapter = null
      }
    }
  }

  Connections {
    target: root.retiredDiscoveryAdapter
    ignoreUnknownSignals: true
    function onDiscoveringChanged() {
      const retired = root.retiredDiscoveryAdapter
      if (!retired) return
      if (retired.discovering) retired.discovering = false
      else {
        root.retiredDiscoveryAdapter = null
        if (!root.discoveryRequestedAdapter)
          discoveryRequestTimeout.stop()
      }
    }
  }
}
