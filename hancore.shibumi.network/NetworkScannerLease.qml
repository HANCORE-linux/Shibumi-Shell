pragma ComponentBehavior: Bound

import QtQuick
import "NetworkModel.js" as Model
import "NetworkScannerAuthority.js" as Authority

// Exclusive process-wide scanner owner. Client objects are private lease keys;
// the public surface contains only counts, phases, primitive device rows, and
// accepted device IDs. Service.qml owns the single process-wide lease authority.
Item {
  id: root

  property bool active: false
  property var backendOverride: null
  property var nativeLiveness: null
  readonly property bool nativeServiceAvailable:
    root.nativeLiveness !== null
      && root.nativeLiveness.serviceUsable === true
  readonly property real nativeServiceEpoch:
    root.nativeLiveness !== null
      && typeof root.nativeLiveness.generation === "number"
      && isFinite(root.nativeLiveness.generation)
      && root.nativeLiveness.generation >= 0
      && Math.floor(root.nativeLiveness.generation)
        === root.nativeLiveness.generation
      ? root.nativeLiveness.generation : 0
  property int scanDelayMs: 100
  property int scanWindowMs: 1500

  readonly property bool authorized: implementation.authorized
  readonly property bool nativeGatewayLoaded: nativeGateway.item !== null
  readonly property bool backendAvailable: implementation.backendAvailable()
  readonly property bool radioReady: implementation.radioReady()
  readonly property int clientCount: implementation.records.length
  readonly property string phase: implementation.phase
  readonly property bool scanning: phase === "delay-pending"
    || scanWindow.running
  readonly property bool scannerEnabled: phase === "enabled"
  readonly property var leasedDeviceIds: implementation.leasedIds.slice()
  readonly property var scannerProjection:
    implementation.deviceProjection()
  readonly property bool snapshotDegraded: scannerProjection.degraded
  readonly property var scannerDeviceSnapshots: scannerProjection.rows
  // The guard releases the numeric claim even if child destruction ordering
  // makes the root's final shutdown handler unable to reach implementation.
  property QtObject authorityGuard: QtObject {
    property bool authorityAlive: true
    property bool blockOnDestruction: false
    property int claim: 0
    Component.onDestruction: {
      if (blockOnDestruction) Authority.block(claim)
      else Authority.release(claim)
    }
  }

  readonly property string topologyFingerprint: JSON.stringify({
    available: root.backendAvailable,
    radioReady: root.radioReady,
    degraded: root.snapshotDegraded,
    devices: root.scannerDeviceSnapshots
  })

  visible: false
  width: 0
  height: 0

  function acquire(owner) { return implementation.acquire(owner) }
  function release(owner) { return implementation.release(owner) }
  function requestScan() { return implementation.requestScan() }
  function closeScanner() { return implementation.closeForCaller() }

  onActiveChanged: {
    if (active) implementation.claimAuthority()
    else implementation.shutdown(true, false)
  }
  onBackendOverrideChanged: implementation.reconcile()
  onNativeLivenessChanged: implementation.updateNativeAdmission()
  onNativeServiceAvailableChanged: implementation.updateNativeAdmission()
  onNativeServiceEpochChanged: implementation.reconcile()
  onTopologyFingerprintChanged: implementation.reconcile()

  Loader {
    id: nativeGateway
    // Keep the exact gateway instance alive for the full authority claim.
    // Deactivation may enter cleanup-pending and must retry against the same
    // private ownedDevices set before releasing authority.
    active: root.authorized && root.backendOverride === null
      && implementation.nativeGatewayAdmitted
    source: Qt.resolvedUrl("NetworkScannerNativeGateway.qml")
  }

  Component {
    id: leaseTokenComponent

    QtObject {
      required property int leaseToken
      property bool armed: true
      Component.onDestruction: if (armed)
        implementation.releaseToken(leaseToken)
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: root.active && !root.authorized
    onTriggered: implementation.claimAuthority()
  }

  Timer {
    interval: 250
    repeat: true
    running: root.authorized
      && implementation.phase === "cleanup-pending"
    onTriggered: {
      if (root.active) implementation.reconcile()
      else implementation.shutdown(true, false)
    }
  }

  Timer {
    id: scanDelay
    interval: Math.max(1, root.scanDelayMs)
    repeat: false
    onTriggered: implementation.enableEpoch(
      implementation.pendingEpoch)
  }

  Timer {
    id: scanWindow
    interval: Math.max(1, root.scanWindowMs)
    repeat: false
  }

  QtObject {
    id: implementation

    property bool authorized: false
    property bool nativeGatewayAdmitted: false
    property int authorityClaim: 0
    property string phase: "idle"
    property int epoch: 0
    property int pendingEpoch: 0
    property int nextLeaseToken: 1
    property var records: []
    property var leasedIds: []
    property var leaseBackend: null

    function updateNativeAdmission() {
      if (authorized && root.backendOverride === null
          && root.nativeServiceAvailable)
        nativeGatewayAdmitted = true
      reconcile()
    }

    function currentBackend() {
      return root.backendOverride !== null
        ? root.backendOverride : nativeGateway.item
    }

    function backendAvailable() {
      if (!root.active || !authorized) return false
      if (root.backendOverride !== null)
        return root.backendOverride.backendAvailable === true
      const gateway = nativeGateway.item
      return root.nativeServiceAvailable && gateway
        ? gateway.backendInitialized === true : false
    }

    function radioReady() {
      const backend = currentBackend()
      if (!backendAvailable() || !backend) return false
      if (root.backendOverride !== null)
        return backend.wifiEnabled === true
          && backend.wifiHardwareEnabled === true
      return backend.radioEnabled === true
    }

    function sequence(value) {
      const rows = []
      if (value === null || value === undefined)
        return { values: rows, overflow: false }
      try {
        const length = value.length
        if (typeof length !== "number" || !isFinite(length) || length < 0
            || Math.floor(length) !== length
            || length > Model.MaxSnapshotRows)
          return { values: [], overflow: true }
        for (let index = 0; index < length; index++) rows.push(value[index])
      } catch (error) {
        return { values: [], overflow: true }
      }
      return { values: rows, overflow: false }
    }

    function deviceProjection() {
      const backend = currentBackend()
      if (!backendAvailable() || !backend)
        return { rows: [], degraded: false }
      try {
        if (backend.snapshotDegraded === true)
          return { rows: [], degraded: true }
        const info = sequence(backend.deviceSnapshots)
        if (info.overflow) return { rows: [], degraded: true }
        const rows = []
        const ids = ({})
        for (let index = 0; index < info.values.length; index++) {
          const source = info.values[index]
          if (!source || typeof source !== "object" || Array.isArray(source)
              || source.schemaVersion !== Model.SchemaVersion
              || typeof source.id !== "string" || source.id.length < 1
              || source.id.length > 1024
              || source.id.indexOf(Model.IdPrefix) !== 0
              || /[\u0000-\u001f\u007f]/.test(source.id)
              || source.type !== "wifi"
              || typeof source.managed !== "boolean"
              || source.mode !== "station"
              || typeof source.eligible !== "boolean"
              || typeof source.ambiguous !== "boolean")
            return { rows: [], degraded: true }
          const row = {
            schemaVersion: Model.SchemaVersion,
            id: source.id,
            type: "wifi",
            managed: source.managed,
            mode: "station",
            eligible: source.eligible,
            ambiguous: source.ambiguous
          }
          ids[row.id] = Number(ids[row.id] || 0) + 1
          rows.push(row)
        }
        for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
          const row = rows[rowIndex]
          if (ids[row.id] !== 1) row.ambiguous = true
          row.eligible = root.radioReady && row.managed && !row.ambiguous
        }
        rows.sort(function(left, right) {
          return left.id < right.id ? -1 : left.id > right.id ? 1 : 0
        })
        return { rows: rows, degraded: false }
      } catch (error) {
        return { rows: [], degraded: true }
      }
    }

    function desiredIds() {
      const rows = root.scannerDeviceSnapshots
      const ids = []
      for (let index = 0; index < rows.length; index++) {
        if (rows[index].eligible) ids.push(rows[index].id)
      }
      return ids
    }

    function claimAuthority() {
      if (!root.active || authorized) return authorized
      authorityClaim = Authority.claim(root.authorityGuard)
      root.authorityGuard.claim = authorityClaim
      authorized = authorityClaim > 0
      if (authorized && root.backendOverride === null
          && root.nativeServiceAvailable)
        nativeGatewayAdmitted = true
      phase = authorized ? "idle" : "unauthorized"
      if (authorized) reconcile()
      return authorized
    }

    function acquire(owner) {
      if (!owner || !root.active || !authorized) return false
      for (let index = 0; index < records.length; index++) {
        if (records[index].owner === owner) return true
      }
      const token = nextLeaseToken++
      // Parenting the token to the client makes QObject destruction release
      // the lease even when the caller cannot run explicit teardown.
      const tokenObject = leaseTokenComponent.createObject(owner, {
        leaseToken: token
      })
      if (!tokenObject) return false
      const firstLease = records.length === 0
      const next = records.slice()
      next.push({ token: token, owner: owner, tokenObject: tokenObject })
      records = next
      if (firstLease) reconcile()
      return true
    }

    function release(owner) {
      if (!owner) return false
      for (let index = 0; index < records.length; index++) {
        if (records[index].owner === owner)
          return releaseToken(records[index].token)
      }
      return false
    }

    function releaseToken(token) {
      const next = []
      let tokenObject = null
      for (let index = 0; index < records.length; index++) {
        const record = records[index]
        if (record.token === token) tokenObject = record.tokenObject
        else next.push(record)
      }
      if (!tokenObject) return false
      // Remove first: destroying the token invokes this function again.
      records = next
      tokenObject.armed = false
      tokenObject.destroy()
      if (next.length === 0) reconcile()
      return true
    }

    function closeBackend(backend) {
      if (!backend || typeof backend.closeScanner !== "function") return false
      try {
        const value = backend.closeScanner()
        if (value === true) return true
        if (!value || typeof value !== "object" || value.ok !== true
            || value.code !== "accepted"
            || value.message !== undefined
              && typeof value.message !== "string") return false
        const info = sequence(value.entityIds)
        return !info.overflow && info.values.length === 0
      } catch (error) {
        return false
      }
    }

    function closeLeasedBackend() {
      const backend = leaseBackend
      if (!backend) {
        leasedIds = []
        return true
      }
      if (!closeBackend(backend)) return false
      leaseBackend = null
      leasedIds = []
      root.authorityGuard.blockOnDestruction = false
      return true
    }

    function cancelEpoch() {
      epoch++
      pendingEpoch = epoch
      scanDelay.stop()
      scanWindow.stop()
    }

    function reconcile() {
      if (!root.active && authorized) {
        shutdown(true, false)
        return
      }
      cancelEpoch()
      phase = "closing"
      const previous = leaseBackend
      if (!closeLeasedBackend()) {
        phase = "cleanup-pending"
        return
      }
      const current = currentBackend()
      // Close an unrecorded backend before a fresh epoch. This covers a
      // synchronous failure between dispatch and accepted-result validation.
      if (current && current !== previous && !closeBackend(current)) {
        leaseBackend = current
        leasedIds = []
        phase = "cleanup-pending"
        return
      }
      if (!root.active || !authorized) {
        phase = authorized ? "idle" : "unauthorized"
        return
      }
      if (root.clientCount <= 0) {
        phase = "idle"
        return
      }
      if (!backendAvailable() || !radioReady()
          || root.snapshotDegraded) {
        phase = "unavailable"
        return
      }
      const ids = desiredIds()
      if (ids.length === 0) {
        phase = "idle"
        return
      }
      pendingEpoch = epoch
      phase = "delay-pending"
      scanDelay.restart()
    }

    function acceptedResult(value, expectedIds) {
      try {
        if (!value || typeof value !== "object" || value.ok !== true
            || value.code !== "accepted"
            || value.message !== undefined
              && typeof value.message !== "string") return false
        const info = sequence(value.entityIds)
        if (info.overflow || info.values.length !== expectedIds.length)
          return false
        for (let index = 0; index < expectedIds.length; index++) {
          if (info.values[index] !== expectedIds[index]) return false
        }
        return true
      } catch (error) {
        return false
      }
    }

    function enableEpoch(requestEpoch) {
      if (requestEpoch !== epoch || phase !== "delay-pending"
          || root.clientCount <= 0 || !backendAvailable()
          || !radioReady()) return
      const backend = currentBackend()
      const ids = desiredIds()
      if (!backend || ids.length === 0
          || typeof backend.enableScannerIds !== "function") {
        phase = "unavailable"
        closeBackend(backend)
        return
      }
      leaseBackend = backend
      leasedIds = ids.slice()
      root.authorityGuard.blockOnDestruction = true
      let value = null
      try { value = backend.enableScannerIds(ids) } catch (error) {}
      if (requestEpoch !== epoch || !acceptedResult(value, ids)) {
        if (!closeLeasedBackend()) phase = "cleanup-pending"
        else phase = "unavailable"
        return
      }
      phase = "enabled"
      scanWindow.restart()
    }

    function requestScan() {
      if (root.clientCount <= 0 || !root.active || !authorized) return false
      reconcile()
      return phase === "delay-pending" || phase === "enabled"
    }

    function closeForCaller() {
      cancelEpoch()
      phase = "closing"
      const previous = leaseBackend
      let result = closeLeasedBackend()
      const current = currentBackend()
      if (result && current && current !== previous)
        result = closeBackend(current)
      if (!result && !leaseBackend && current) leaseBackend = current
      phase = result ? (root.clientCount > 0 ? "unavailable" : "idle")
        : "cleanup-pending"
      if (result && !root.active && authorized)
        return shutdown(true, false)
      return result
    }

    function shutdown(releaseAuthority, finalDestruction) {
      cancelEpoch()
      phase = "closing"
      const previous = leaseBackend
      let cleaned = closeLeasedBackend()
      const current = currentBackend()
      if (cleaned && current && current !== previous)
        cleaned = closeBackend(current)
      if (!cleaned) {
        if (!leaseBackend && current) leaseBackend = current
        phase = "cleanup-pending"
        if (finalDestruction === true && releaseAuthority === true) {
          // Owner-parented tokens may outlive this creation context. Disarm
          // them before blocking authority so later owner destruction cannot
          // call back into a dead implementation object.
          const abandonedRecords = records.slice()
          records = []
          for (let index = 0; index < abandonedRecords.length; index++) {
            const tokenObject = abandonedRecords[index].tokenObject
            if (!tokenObject) continue
            tokenObject.armed = false
            tokenObject.destroy()
          }
          root.authorityGuard.blockOnDestruction = true
          Authority.block(authorityClaim)
        }
        return false
      }

      const oldRecords = records.slice()
      records = []
      for (let index = 0; index < oldRecords.length; index++) {
        const tokenObject = oldRecords[index].tokenObject
        if (tokenObject) {
          tokenObject.armed = false
          tokenObject.destroy()
        }
      }
      if (releaseAuthority === true) {
        Authority.release(authorityClaim)
        authorityClaim = 0
        root.authorityGuard.blockOnDestruction = false
        root.authorityGuard.claim = 0
        authorized = false
        nativeGatewayAdmitted = false
      }
      phase = authorized ? "idle" : "unauthorized"
      return true
    }
  }

  Connections {
    target: implementation.currentBackend()
    ignoreUnknownSignals: true
    function onTopologyRevisionChanged() {
      implementation.reconcile()
    }
  }

  Component.onCompleted: if (active) implementation.claimAuthority()
  Component.onDestruction: implementation.shutdown(true, true)
}
