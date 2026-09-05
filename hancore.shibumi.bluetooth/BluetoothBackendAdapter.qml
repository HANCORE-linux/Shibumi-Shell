pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
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
  property var audioRouteOverride: null
  property bool audioRouteHandoffReady: true
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
  // Raw native entities remain private here. The registry assigns a monotonic
  // incarnation whenever a device or adapter QObject is replaced.
  property var nativeAdapterEntity: null
  property int nativeAdapterGeneration: 0
  property var nativeEntityRegistry: []
  property int nativeEntitySequence: 0
  property int nativeIdentityEpoch: 0
  property int nativeEntityLimit: 512
  property var audioHandoffIntent: null
  property var pendingAudioOutputDevice: null
  property int pendingAudioOutputAttempts: 0

  readonly property bool ready: true
  readonly property var adapter: backendOverride !== null
    ? ("adapter" in backendOverride ? backendOverride.adapter : null)
    : (adapterOverride !== null ? adapterOverride : Bluetooth.defaultAdapter)
  readonly property var nativeAdapters: backendOverride === null
    && adapterOverride === null && Bluetooth.adapters
    ? Model.toArray(Bluetooth.adapters.values) : (adapter ? [adapter] : [])
  readonly property bool adapterAvailable: adapter !== null
  readonly property bool radioEnabled: adapterAvailable
    && adapter.enabled !== undefined && adapter.enabled === true
  readonly property bool discovering: adapterAvailable
    && adapter.discovering !== undefined && adapter.discovering === true
  readonly property var nativeDevices: nativeDevicesOverride !== null
    ? nativeDevicesOverride
    : (backendOverride === null && Bluetooth.devices ? Bluetooth.devices.values : [])
  readonly property var audioRoute: audioRouteOverride !== null
    ? audioRouteOverride : nativeAudioRoute
  readonly property var pipewireNodes: nativeAudioRoute.nodes
  readonly property var nativeDeviceGroups: Model.deviceLists(
    nativeDeviceSnapshots())
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

  Local.BluetoothAudioRouteAdapter {
    id: nativeAudioRoute
    enabled: root.audioRouteHandoffReady
      && root.audioRouteOverride === null && root.backendOverride === null
    nodesOverride: root.pipewireNodesOverride
    outputOverride: root.audioOutputOverride
  }

  function backendList(name) {
    if (backendOverride === null || !(name in backendOverride)) return []
    const values = backendOverride[name]
    return Array.isArray(values) ? values : []
  }

  function entityText(entity, name) {
    if (!entity || !(name in entity)) return ""
    return String(entity[name] || "").trim()
  }

  function validDbusPath(value) {
    return typeof value === "string" && value.length > 1
      && value.length <= 512 && value.charAt(0) === "/"
      && value.indexOf("//") < 0
  }

  function validGeneration(value) {
    return typeof value === "number" && Number.isFinite(value)
      && value > 0 && Math.floor(value) === value
  }

  function observeNativeAdapter() {
    if (backendOverride !== null || nativeAdapterEntity === adapter) return
    nativeAdapterEntity = adapter
    nativeAdapterGeneration++
  }

  function registryEntry(device) {
    void(nativeIdentityEpoch)
    for (let i = 0; i < nativeEntityRegistry.length; i++) {
      const entry = nativeEntityRegistry[i]
      if (entry.entity === device
          && entry.adapterEntity === adapter
          && entry.adapterGeneration === nativeAdapterGeneration)
        return entry
    }
    return null
  }

  function reconcileNativeEntities() {
    if (backendOverride !== null) return
    observeNativeAdapter()
    const values = Model.toArray(nativeDevices)
    const next = []
    const count = Math.min(values.length, nativeEntityLimit)
    for (let i = 0; i < count; i++) {
      const device = values[i]
      if (!device) continue
      let entry = registryEntry(device)
      if (!entry) {
        nativeEntitySequence++
        entry = {
          entity: device,
          generation: nativeEntitySequence,
          adapterEntity: adapter,
          adapterGeneration: nativeAdapterGeneration
        }
      }
      next.push(entry)
    }
    let changed = next.length !== nativeEntityRegistry.length
    if (!changed) {
      for (let i = 0; i < next.length; i++) {
        if (next[i].entity !== nativeEntityRegistry[i].entity
            || next[i].generation !== nativeEntityRegistry[i].generation
            || next[i].adapterGeneration
              !== nativeEntityRegistry[i].adapterGeneration) {
          changed = true
          break
        }
      }
    }
    if (changed) {
      nativeEntityRegistry = next
      nativeIdentityEpoch++
    }
  }

  function nativeDeviceSnapshot(device) {
    const entry = registryEntry(device)
    const deviceAdapter = device && "adapter" in device ? device.adapter : null
    return Model.deviceRecord(device, {
      entityId: entityText(device, "dbusPath"),
      generation: entry ? entry.generation : 0,
      adapterId: entityText(deviceAdapter, "adapterId"),
      adapterEntityId: entityText(deviceAdapter, "dbusPath"),
      adapterGeneration: entry ? entry.adapterGeneration : 0
    })
  }

  function nativeDeviceSnapshots() {
    void(nativeIdentityEpoch)
    const values = Model.toArray(nativeDevices)
    const records = []
    const count = Math.min(values.length, nativeEntityLimit)
    for (let i = 0; i < count; i++) {
      if (values[i]) records.push(nativeDeviceSnapshot(values[i]))
    }
    return records
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
      deviceName: device.deviceName ? String(device.deviceName) : "",
      entityId: String(device.entityId || ""),
      generation: Number(device.generation || 0),
      adapterId: String(device.adapterId || ""),
      adapterEntityId: String(device.adapterEntityId || ""),
      adapterGeneration: Number(device.adapterGeneration || 0)
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

  function deviceActionResult(ok, code, message, request, action) {
    return {
      ok: ok === true,
      code: String(code || (ok ? "dispatched" : "unavailable")),
      message: String(message || ""),
      action: String(action || ""),
      entityId: request && typeof request.entityId === "string"
        ? request.entityId : "",
      generation: request && validGeneration(request.generation)
        ? request.generation : 0
    }
  }

  function normalizeDeviceActionResult(value, request, action) {
    if (value && typeof value === "object"
        && typeof value.ok === "boolean"
        && typeof value.code === "string") return value
    return deviceActionResult(false, "unavailable",
      "Bluetooth action backend returned no typed result", request, action)
  }

  function validateDeviceRequest(request, action) {
    if (!request || typeof request !== "object"
        || typeof request.address !== "string"
        || !Model.isAddressLike(request.address)
        || typeof request.entityId !== "string"
        || !validDbusPath(request.entityId)
        || !validGeneration(request.generation)
        || typeof request.adapterId !== "string"
        || request.adapterId.length < 1 || request.adapterId.length > 256
        || typeof request.adapterEntityId !== "string"
        || !validDbusPath(request.adapterEntityId)
        || !validGeneration(request.adapterGeneration))
      return deviceActionResult(false, "invalid-request",
        "Bluetooth device identity is malformed", request, action)
    return null
  }

  function resolveNativeDevice(request, action) {
    const invalid = validateDeviceRequest(request, action)
    if (invalid) return { result: invalid, entity: null }
    if (!adapterAvailable || !radioEnabled)
      return { result: deviceActionResult(false, "unavailable",
        "Bluetooth adapter is unavailable", request, action), entity: null }
    // The retained Omarchy 4.0.2 helper accepts an address but no controller.
    // Fail closed unless production has exactly one controller and it is the
    // incarnation validated below, so bluetoothctl cannot select a different
    // already-present adapter after this boundary.
    if (backendOverride === null && adapterOverride === null
        && (nativeAdapters.length !== 1 || nativeAdapters[0] !== adapter))
      return { result: deviceActionResult(false, "ambiguous-entity",
        "Bluetooth helper cannot bind an ambiguous adapter inventory",
        request, action), entity: null }

    reconcileNativeEntities()
    const values = Model.toArray(nativeDevices)
    if (values.length > nativeEntityLimit)
      return { result: deviceActionResult(false, "unavailable",
        "Bluetooth device inventory exceeds the supported bound",
        request, action), entity: null }

    if (request.adapterGeneration !== nativeAdapterGeneration
        || request.adapterId !== entityText(adapter, "adapterId")
        || request.adapterEntityId !== entityText(adapter, "dbusPath"))
      return { result: deviceActionResult(false, "stale-entity",
        "Bluetooth adapter incarnation changed", request, action), entity: null }

    const matches = []
    for (let i = 0; i < values.length; i++) {
      const entity = values[i]
      if (!entity) continue
      const entityAdapter = "adapter" in entity ? entity.adapter : null
      if (Model.normalizedAddress(entityText(entity, "address"))
            === Model.normalizedAddress(request.address)
          && entityText(entity, "dbusPath") === request.entityId
          && entityAdapter === adapter
          && entityText(entityAdapter, "adapterId") === request.adapterId
          && entityText(entityAdapter, "dbusPath") === request.adapterEntityId)
        matches.push(entity)
    }
    if (matches.length > 1)
      return { result: deviceActionResult(false, "ambiguous-entity",
        "Bluetooth device identity is ambiguous", request, action), entity: null }
    if (matches.length === 0)
      return { result: deviceActionResult(false, "stale-entity",
        "Bluetooth device is no longer current", request, action), entity: null }

    const entry = registryEntry(matches[0])
    if (!entry || entry.generation !== request.generation)
      return { result: deviceActionResult(false, "stale-entity",
        "Bluetooth device incarnation changed", request, action), entity: null }
    return { result: null, entity: matches[0] }
  }

  function runNativeDeviceAction(request, action, pending) {
    const resolved = resolveNativeDevice(request, action)
    if (resolved.result) return resolved.result
    const entity = resolved.entity
    const address = entityText(entity, "address")
    let commandAction = action
    if (action === "connect") {
      if (entity.connected)
        return deviceActionResult(false, "state-conflict",
          "Bluetooth device is already connected", request, action)
      commandAction = entity.paired || entity.bonded || entity.trusted
        ? "connect" : "pair"
      rememberAudioHandoffIntent(request)
    } else if (action === "disconnect") {
      if (!entity.connected)
        return deviceActionResult(false, "state-conflict",
          "Bluetooth device is not connected", request, action)
      cancelAudioHandoff(address)
    } else if (action === "forget") {
      if (!entity.paired && !entity.bonded && !entity.trusted)
        return deviceActionResult(false, "state-conflict",
          "Bluetooth device is not known", request, action)
      cancelAudioHandoff(address)
    }

    setNativePendingAction(address, pending)
    try {
      // This helper is the one mutation path for every device action in this
      // compatibility release. Never also invoke a native device method.
      executeDeviceCommand(deviceCommand(commandAction, address))
    } catch (error) {
      setNativePendingAction(address, "")
      if (action === "connect") cancelAudioHandoff(address)
      return deviceActionResult(false, "dispatch-failed",
        "Bluetooth action dispatch failed", request, action)
    }
    return deviceActionResult(true, "dispatched", "", request, action)
  }

  function overrideDeviceAction(method, request, action) {
    if (!backendOverride || typeof backendOverride[method] !== "function")
      return deviceActionResult(false, "unavailable",
        "Bluetooth action backend is unavailable", request, action)
    return normalizeDeviceActionResult(
      backendOverride[method](request), request, action)
  }

  function connectDevice(request) {
    return backendOverride !== null
      ? overrideDeviceAction("connectDevice", request, "connect")
      : runNativeDeviceAction(request, "connect", "connecting")
  }

  function disconnectDevice(request) {
    return backendOverride !== null
      ? overrideDeviceAction("disconnectDevice", request, "disconnect")
      : runNativeDeviceAction(request, "disconnect", "disconnecting")
  }

  function forgetDevice(request) {
    return backendOverride !== null
      ? overrideDeviceAction("forgetDevice", request, "forget")
      : runNativeDeviceAction(request, "forget", "forgetting")
  }

  function audioRouteRequest(device) {
    if (!device || !device.address) return null
    return {
      address: String(device.address).trim(),
      name: device.name ? String(device.name) : "",
      deviceName: device.deviceName ? String(device.deviceName) : ""
    }
  }

  function audioRouteResult(ok, code, message, entityId, generation) {
    return {
      ok: ok === true,
      code: String(code || (ok ? "ok" : "unavailable")),
      message: String(message || ""),
      entityId: String(entityId || ""),
      generation: Number(generation || 0)
    }
  }

  function normalizeAudioRouteResult(value) {
    if (value && typeof value === "object"
        && typeof value.ok === "boolean")
      return value
    if (value === true) return audioRouteResult(true, "ok", "", "", 0)
    return audioRouteResult(
      false, "unavailable", "Bluetooth audio route is unavailable", "", 0)
  }

  function requestBluetoothAudioRoute(device) {
    const request = audioRouteRequest(device)
    if (!request || !audioRoute
        || typeof audioRoute.routeBluetoothDevice !== "function")
      return audioRouteResult(
        false, "unavailable", "Bluetooth audio route is unavailable", "", 0)
    return normalizeAudioRouteResult(
      audioRoute.routeBluetoothDevice(request))
  }

  function scheduleAudioOutputSwitch(device) {
    if (!device || !device.address) return
    pendingAudioOutputDevice = {
      address: String(device.address),
      name: device.name ? String(device.name) : "",
      deviceName: device.deviceName ? String(device.deviceName) : "",
      entityId: String(device.entityId || ""),
      generation: Number(device.generation || 0),
      adapterId: String(device.adapterId || ""),
      adapterEntityId: String(device.adapterEntityId || ""),
      adapterGeneration: Number(device.adapterGeneration || 0)
    }
    pendingAudioOutputAttempts = 0
    audioIntentTimeout.restart()
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
    if (!pendingAudioOutputDevice) return null
    const resolved = resolveNativeDevice(pendingAudioOutputDevice, "audio-route")
    const device = resolved.entity
    if (resolved.result || !device || !device.connected
        || !deviceUsesCurrentAdapter(device)) {
      cancelPendingAudioOutput("")
      return null
    }
    return device
  }

  function switchPendingAudioOutput() {
    const device = validatePendingAudioOutput()
    if (!device) return
    const routeResult = requestBluetoothAudioRoute(device)
    if (routeResult.ok) {
      pendingAudioOutputDevice = null
      audioSwitchTimer.stop()
      audioIntentTimeout.stop()
      return
    }
    // Retry only transient route unavailability. The handoff timeout bounds
    // the wait while allowing slow BlueZ/PipeWire graph creation to settle.
    if (routeResult.code !== "unavailable") {
      pendingAudioOutputDevice = null
      audioSwitchTimer.stop()
      audioIntentTimeout.stop()
      return
    }
    pendingAudioOutputAttempts++
    audioSwitchTimer.restart()
  }

  function syncNativeAudioHandoffIntents() {
    if (backendOverride !== null) return
    const intent = audioHandoffIntent
    if (intent) {
      const resolved = resolveNativeDevice(intent, "audio-route")
      const device = resolved.entity
      if (resolved.result) clearAudioHandoffIntent(intent.address)
      else if (device && device.connected && deviceUsesCurrentAdapter(device)) {
        scheduleAudioOutputSwitch(intent)
        audioHandoffIntent = null
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
    reconcileNativeEntities()
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
    observeNativeAdapter()
    reconcileNativeEntities()
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
  Component.onCompleted: reconcileNativeEntities()
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
    onTriggered: {
      root.audioHandoffIntent = null
      root.cancelPendingAudioOutput("")
    }
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
