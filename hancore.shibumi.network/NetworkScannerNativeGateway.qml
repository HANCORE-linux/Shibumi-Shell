pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Networking
import "NetworkModel.js" as Model

// Private scanner mutation gateway for the exclusive NetworkScannerLease.
// Raw WifiDevice objects and removal tombstones never leave this component.
Item {
  id: root

  // Overrides are for the isolated lifecycle regression only. Production
  // leaves them null and consumes the public Quickshell singleton/model.
  property var deviceObjectsOverride: null
  property var backendInitializedOverride: null
  property var radioEnabledOverride: null
  property int topologyRevision: 0
  property var ownedDevices: []
  property var tombstonedDevices: []

  readonly property bool backendInitialized:
    backendInitializedOverride !== null
      ? backendInitializedOverride === true
      : Networking.backend === NetworkBackendType.NetworkManager
  readonly property bool radioEnabled: radioEnabledOverride !== null
    ? radioEnabledOverride === true
    : root.backendInitialized && Networking.wifiEnabled === true
      && Networking.wifiHardwareEnabled === true
  readonly property var nativeDeviceModel: Networking.devices
  readonly property var deviceObjects: deviceObjectsOverride !== null
    ? deviceObjectsOverride
    : root.backendInitialized && nativeDeviceModel
      ? nativeDeviceModel.values : []
  readonly property var snapshotProjection: buildDeviceProjection()
  readonly property bool snapshotDegraded: snapshotProjection.degraded
  readonly property var deviceSnapshots: snapshotProjection.rows

  visible: false
  width: 0
  height: 0

  function bumpTopology() { topologyRevision++ }

  function objectSequence(value) {
    const result = []
    if (value === null || value === undefined) return result
    try {
      const length = value.length
      if (typeof length !== "number" || !isFinite(length) || length < 0
          || Math.floor(length) !== length
          || length > Model.MaxSnapshotRows) return null
      for (let index = 0; index < length; index++) result.push(value[index])
    } catch (error) {
      return null
    }
    return result
  }

  function isTombstoned(device) {
    return device && tombstonedDevices.indexOf(device) >= 0
  }

  function wifiDevice(device) {
    if (!device) return false
    return deviceObjectsOverride !== null
      ? device.typeToken === "wifi" : device.type === DeviceType.Wifi
  }

  function deviceName(device) {
    if (deviceObjectsOverride !== null
        && device && typeof device.snapshotName === "function")
      return device.snapshotName()
    return device && device.name
  }

  function deviceAddress(device) {
    if (deviceObjectsOverride !== null
        && device && typeof device.snapshotAddress === "function")
      return device.snapshotAddress()
    return device && device.address
  }

  function deviceId(device) {
    if (!wifiDevice(device)) return ""
    return Model.deviceId("wifi", deviceAddress(device), deviceName(device))
  }

  function stationDevice(device) {
    if (!wifiDevice(device)) return false
    return deviceObjectsOverride !== null
      ? device.modeToken === "station"
      : device.mode === WifiDeviceMode.Station
  }

  function managedDevice(device) {
    if (!device) return false
    return deviceObjectsOverride !== null
      ? device.managed === true : device.nmManaged !== false
  }

  function scannerState(device) {
    try {
      if (!device) return { ok: false, value: false }
      if (deviceObjectsOverride !== null
          && typeof device.getScannerEnabled === "function")
        return { ok: true, value: device.getScannerEnabled() === true }
      return { ok: true, value: device.scannerEnabled === true }
    } catch (error) {
      return { ok: false, value: false }
    }
  }

  function writeScannerState(device, enabled) {
    if (!device) return false
    if (deviceObjectsOverride !== null
        && typeof device.setScannerEnabled === "function")
      return device.setScannerEnabled(enabled) !== false
    device.scannerEnabled = enabled === true
    return true
  }

  function buildDeviceProjection() {
    try {
      const revision = root.topologyRevision
      void revision
      const devices = objectSequence(deviceObjects)
      if (devices === null) return { rows: [], degraded: true }
      const rows = []
      const idCounts = ({})
      for (let index = 0; index < devices.length; index++) {
        const device = devices[index]
        if (!device || isTombstoned(device)) continue
        if (!wifiDevice(device) || !stationDevice(device)) continue
        const id = deviceId(device)
        if (!id) return { rows: [], degraded: true }
        idCounts[id] = Number(idCounts[id] || 0) + 1
        rows.push({
          schemaVersion: Model.SchemaVersion,
          id: id,
          type: "wifi",
          managed: managedDevice(device),
          mode: "station",
          eligible: false,
          ambiguous: false
        })
      }
      for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        const row = rows[rowIndex]
        row.ambiguous = idCounts[row.id] !== 1
        row.eligible = root.backendInitialized && root.radioEnabled
          && row.managed && !row.ambiguous
      }
      return { rows: rows, degraded: false }
    } catch (error) {
      return { rows: [], degraded: true }
    }
  }

  function resolution(entityId) {
    try {
      const key = typeof entityId === "string" ? entityId : ""
      const devices = objectSequence(deviceObjects)
      if (!key || devices === null)
        return { target: null, count: 0, overflow: devices === null }
      let target = null
      let count = 0
      for (let index = 0; index < devices.length; index++) {
        const device = devices[index]
        if (!device || isTombstoned(device) || !stationDevice(device)
            || deviceId(device) !== key) continue
        target = device
        count++
      }
      return { target: target, count: count, overflow: false }
    } catch (error) {
      return { target: null, count: 0, overflow: true }
    }
  }

  function closeScanner() {
    const previous = ownedDevices.slice()
    const remaining = []
    for (let index = 0; index < previous.length; index++) {
      const device = previous[index]
      if (!device) continue
      try {
        const written = writeScannerState(device, false)
        const state = scannerState(device)
        if (!written || !state.ok || state.value) remaining.push(device)
      } catch (error) {
        remaining.push(device)
      }
    }
    ownedDevices = remaining
    const complete = remaining.length === 0
    return {
      ok: complete,
      code: complete ? "accepted" : "unavailable",
      message: complete ? "Scanner lease closed."
        : "One or more scanner devices could not be closed.",
      entityIds: []
    }
  }

  function enableScannerIds(entityIds) {
    if (!root.backendInitialized || !root.radioEnabled)
      return {
        ok: false,
        code: "unavailable",
        message: "Wi-Fi scanner backend is unavailable.",
        entityIds: []
      }
    if (!Array.isArray(entityIds)
        || entityIds.length > Model.MaxSnapshotRows)
      return {
        ok: false,
        code: "invalid",
        message: "Scanner device request is malformed.",
        entityIds: []
      }

    const cleanup = closeScanner()
    if (!cleanup.ok)
      return {
        ok: false,
        code: "unavailable",
        message: "Previous scanner ownership could not be closed.",
        entityIds: []
      }

    const targets = []
    const acceptedIds = []
    const seen = ({})
    for (let index = 0; index < entityIds.length; index++) {
      const id = entityIds[index]
      if (typeof id !== "string" || id === "" || seen[id]) {
        closeScanner()
        return {
          ok: false,
          code: "invalid",
          message: "Scanner device identities are malformed.",
          entityIds: []
        }
      }
      seen[id] = true
      const resolved = resolution(id)
      if (resolved.overflow || resolved.count !== 1 || !resolved.target
          || !managedDevice(resolved.target)
          || !stationDevice(resolved.target)) {
        return {
          ok: false,
          code: resolved.count > 1 ? "ambiguous" : "stale-id",
          message: "Scanner device identity is unavailable.",
          entityIds: []
        }
      }
      const state = scannerState(resolved.target)
      if (!state.ok || state.value)
        return {
          ok: false,
          code: "unavailable",
          message: "Scanner device is owned by another provider.",
          entityIds: []
        }
      targets.push(resolved.target)
      acceptedIds.push(id)
    }

    // Mark ownership before writes so synchronous scannerEnabled notifications
    // cannot be mistaken for a foreign provider transition.
    ownedDevices = targets.slice()
    try {
      for (let targetIndex = 0; targetIndex < targets.length; targetIndex++) {
        const target = targets[targetIndex]
        if (isTombstoned(target) || !managedDevice(target)
            || !stationDevice(target)
            || !writeScannerState(target, true))
          throw new Error("device changed")
        const state = scannerState(target)
        if (!state.ok || !state.value) throw new Error("device changed")
      }
    } catch (error) {
      closeScanner()
      return {
        ok: false,
        code: "unavailable",
        message: "Wi-Fi scanner dispatch failed.",
        entityIds: []
      }
    }
    return {
      ok: true,
      code: "accepted",
      message: "Wi-Fi scanner dispatch accepted.",
      entityIds: acceptedIds
    }
  }

  function prepareRemoval(device) {
    if (!device || isTombstoned(device)) return
    const nextTombstones = tombstonedDevices.slice()
    nextTombstones.push(device)
    tombstonedDevices = nextTombstones

    const ownerIndex = ownedDevices.indexOf(device)
    if (ownerIndex >= 0) {
      let closed = false
      try {
        const written = writeScannerState(device, false)
        const state = scannerState(device)
        closed = written && state.ok && !state.value
      } catch (error) {}
      if (closed) {
        const nextOwned = ownedDevices.slice()
        nextOwned.splice(ownerIndex, 1)
        ownedDevices = nextOwned
      }
    }
    bumpTopology()
  }

  function finishRemoval(device) {
    // objectRemovedPost still runs before Quickshell deletes the backend
    // wrapper, so a failed pre-removal close gets one final bounded retry.
    if (ownedDevices.indexOf(device) >= 0) closeScanner()
    const ownerIndex = ownedDevices.indexOf(device)
    if (ownerIndex >= 0) {
      const nextOwned = ownedDevices.slice()
      nextOwned.splice(ownerIndex, 1)
      ownedDevices = nextOwned
    }
    const index = tombstonedDevices.indexOf(device)
    if (index >= 0) {
      const next = tombstonedDevices.slice()
      next.splice(index, 1)
      tombstonedDevices = next
    }
    bumpTopology()
  }

  Connections {
    target: root.deviceObjectsOverride === null
      ? root.nativeDeviceModel : null

    function onObjectInsertedPost(_object, _index) {
      root.bumpTopology()
    }
    function onObjectRemovedPre(object, _index) {
      root.prepareRemoval(object)
    }
    function onObjectRemovedPost(object, _index) {
      root.finishRemoval(object)
    }
  }

  Instantiator {
    model: root.deviceObjectsOverride === null
      ? root.nativeDeviceModel : null

    delegate: QtObject {
      id: observer
      required property var modelData

      property Connections deviceConnections: Connections {
        target: observer.modelData
        ignoreUnknownSignals: true
        function onNameChanged() { root.bumpTopology() }
        function onAddressChanged() { root.bumpTopology() }
        function onNmManagedChanged() { root.bumpTopology() }
        function onModeChanged() { root.bumpTopology() }
        function onScannerEnabledChanged() {
          if (root.ownedDevices.indexOf(observer.modelData) < 0
              && !root.isTombstoned(observer.modelData))
            root.bumpTopology()
        }
      }
    }
  }

  onBackendInitializedChanged: bumpTopology()
  onRadioEnabledChanged: bumpTopology()
  Component.onDestruction: closeScanner()
}
