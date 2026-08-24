pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "NetworkModel.js" as NetworkModel
import "NetworkProfileCatalogModel.js" as CatalogModel
import "NetworkProfileCatalogAuthority.js" as Authority

// Demand-driven, process-wide catalog of persisted NetworkManager profiles.
// The helper reads GetSettings but projects only bounded non-secret metadata;
// backend paths, settings maps, identities, certificates, and secrets remain
// private and never enter this QML object.
Item {
  id: root

  property bool active: false
  property var nativeLiveness: null
  property var commandOverride: null
  property int refreshTimeoutMs: 25000

  property real generation: 0
  property string phase: "inactive"
  property bool launchRequested: false

  readonly property int schemaVersion: CatalogModel.SchemaVersion
  readonly property bool authorized: implementation.authorized
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
  readonly property int clientCount: implementation.records.length
  readonly property string errorCode: implementation.lastError
  readonly property var profileSnapshots: implementation.publicRows()
  readonly property bool workerRunning: catalogProcess.running
  readonly property bool workerOutputComplete:
    implementation.runState === "complete"
  readonly property bool available: root.active && root.authorized
    && root.nativeServiceAvailable && root.phase === "live"
  readonly property var catalogSnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.available,
    phase: root.phase,
    count: root.profileSnapshots.length,
    errorCode: root.errorCode,
    generation: root.generation
  })
  property QtObject authorityGuard: QtObject {
    property bool authorityAlive: true
    property int claim: 0
    Component.onDestruction: Authority.release(claim)
  }

  visible: false
  width: 0
  height: 0

  function acquire(owner) { return implementation.acquire(owner) }
  function release(owner) { return implementation.release(owner) }
  function requestRefresh() { return implementation.refresh() }

  onActiveChanged: {
    if (active) implementation.claimAuthority()
    else implementation.shutdown()
  }
  onNativeLivenessChanged: implementation.livenessChanged()
  onNativeServiceAvailableChanged: implementation.livenessChanged()
  onNativeServiceEpochChanged: implementation.livenessChanged()

  Timer {
    interval: 250
    repeat: true
    running: root.active && !root.authorized
    onTriggered: implementation.claimAuthority()
  }

  Timer {
    id: refreshTimeout
    interval: Math.max(100, root.refreshTimeoutMs)
    repeat: false
    onTriggered: implementation.failRun("timeout")
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

  QtObject {
    id: implementation

    property bool authorized: false
    property int authorityClaim: 0
    property int nextLeaseToken: 1
    property var records: []
    property var publishedRows: []
    property string runState: "idle"
    property bool pendingRefresh: false
    property string lastError: ""
    property int expectedCount: 0
    property int lastSequence: 0
    property var pendingRows: []

    function bumpGeneration() {
      if (root.generation < CatalogModel.MaxSafeInteger) root.generation++
    }

    function publicRows() {
      const rows = publishedRows
      const result = []
      for (let index = 0; index < rows.length; index++) {
        const source = rows[index]
        const row = ({})
        for (const key in source) row[key] = source[key]
        result.push(row)
      }
      return result
    }

    function clearPublished(nextPhase) {
      publishedRows = []
      root.phase = String(nextPhase || "unavailable")
      bumpGeneration()
    }

    function resetPending() {
      expectedCount = 0
      lastSequence = 0
      pendingRows = []
    }

    function claimAuthority() {
      if (!root.active || authorized) return authorized
      authorityClaim = Authority.claim(root.authorityGuard)
      root.authorityGuard.claim = authorityClaim
      authorized = authorityClaim > 0
      root.phase = authorized ? "idle" : "standby"
      if (authorized && root.clientCount > 0) refresh()
      return authorized
    }

    function acquire(owner) {
      if (!owner || !root.active || !authorized) return false
      for (let index = 0; index < records.length; index++) {
        if (records[index].owner === owner) return true
      }
      const token = nextLeaseToken++
      if (nextLeaseToken > CatalogModel.MaxSafeInteger) nextLeaseToken = 1
      const tokenObject = leaseTokenComponent.createObject(owner, {
        leaseToken: token
      })
      if (!tokenObject) return false
      const next = records.slice()
      next.push({ token: token, owner: owner, tokenObject: tokenObject })
      records = next
      if (records.length === 1) refresh()
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
      let tokenObject = null
      const next = []
      for (let index = 0; index < records.length; index++) {
        if (records[index].token === token) tokenObject = records[index].tokenObject
        else next.push(records[index])
      }
      if (!tokenObject) return false
      records = next
      tokenObject.armed = false
      tokenObject.destroy()
      if (records.length === 0) {
        cancelRun("idle")
        clearPublished("idle")
      }
      return true
    }

    function livenessChanged() {
      if (!root.nativeServiceAvailable) {
        cancelRun("unavailable")
        clearPublished("unavailable")
      } else if (root.active && authorized && root.clientCount > 0) {
        refresh()
      }
    }

    function refresh() {
      if (!root.active || !authorized || root.clientCount < 1
          || !root.nativeServiceAvailable)
        return false
      if (catalogProcess.running || launchRequested) {
        pendingRefresh = true
        return true
      }
      pendingRefresh = false
      lastError = ""
      resetPending()
      runState = "loading"
      root.phase = "loading"
      bumpGeneration()
      root.launchRequested = true
      return true
    }

    function cancelRun(nextPhase) {
      refreshTimeout.stop()
      pendingRefresh = false
      if (catalogProcess.running) catalogProcess.signal(15)
      root.launchRequested = false
      if (runState === "loading" || runState === "complete")
        runState = "cancelled"
      resetPending()
      root.phase = String(nextPhase || "idle")
    }

    function failRun(reason) {
      refreshTimeout.stop()
      pendingRefresh = false
      lastError = String(reason || "invalid")
      if (catalogProcess.running) catalogProcess.signal(15)
      root.launchRequested = false
      runState = "failed"
      resetPending()
      clearPublished(root.nativeServiceAvailable ? "error" : "unavailable")
      return false
    }

    function ingestLine(line) {
      if (runState === "failed" || runState === "cancelled") return false
      if (runState !== "loading") return failRun("unexpected-output")
      const record = CatalogModel.parseLine(line)
      if (!record.ok) return failRun(record.code)

      if (record.event === "begin") {
        if (lastSequence !== 0 || record.sequence !== 1)
          return failRun("invalid-begin")
        expectedCount = record.count
        lastSequence = record.sequence
        return true
      }

      if (lastSequence < 1) return failRun("missing-begin")
      if (record.event === "profile") {
        if (pendingRows.length >= expectedCount
            || record.index !== pendingRows.length
            || record.sequence !== lastSequence + 1)
          return failRun("invalid-profile-order")
        const profile = record.profile
        const id = NetworkModel.catalogProfileId(profile.uuid)
        if (!id) return failRun("invalid-profile-id")
        if (pendingRows.length > 0
            && pendingRows[pendingRows.length - 1].uuid >= profile.uuid)
          return failRun("unsorted-profile")
        pendingRows.push({
          schemaVersion: root.schemaVersion,
          id: id,
          uuid: profile.uuid,
          name: profile.name,
          profileType: profile.profileType,
          ssid: profile.ssid,
          ssidHex: profile.ssidHex,
          security: profile.security,
          enterprise: profile.enterprise,
          hidden: profile.hidden,
          autoconnect: profile.autoconnect,
          timestamp: profile.timestamp
        })
        lastSequence = record.sequence
        return true
      }

      if (record.event !== "end" || record.count !== expectedCount
          || pendingRows.length !== expectedCount
          || record.sequence !== lastSequence + 1
          || record.sequence !== expectedCount + 2)
        return failRun("invalid-end")
      lastSequence = record.sequence
      runState = "complete"
      return true
    }

    function processStarted() {
      if (runState !== "loading") return
      refreshTimeout.restart()
    }

    function processExited(exitCode) {
      refreshTimeout.stop()
      root.launchRequested = false
      if (runState === "cancelled" || runState === "failed") {
        const retry = runState === "cancelled" && pendingRefresh
        pendingRefresh = false
        runState = "idle"
        if (retry && root.active && authorized && root.clientCount > 0
            && root.nativeServiceAvailable)
          refresh()
        return
      }
      if (exitCode !== 0 || runState !== "complete") {
        failRun("process-exited")
        return
      }
      const rows = pendingRows.slice()
      const retry = pendingRefresh
      pendingRefresh = false
      resetPending()
      runState = "idle"
      if (!root.nativeServiceAvailable || root.clientCount < 1) {
        clearPublished(root.nativeServiceAvailable ? "idle" : "unavailable")
        return
      }
      publishedRows = rows
      root.phase = "live"
      bumpGeneration()
      if (retry) refresh()
    }

    function shutdown() {
      cancelRun("inactive")
      const oldRecords = records.slice()
      records = []
      for (let index = 0; index < oldRecords.length; index++) {
        const tokenObject = oldRecords[index].tokenObject
        if (!tokenObject) continue
        tokenObject.armed = false
        tokenObject.destroy()
      }
      Authority.release(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
      clearPublished("inactive")
    }
  }

  Process {
    id: catalogProcess
    running: root.launchRequested && root.active && root.authorized
    command: Array.isArray(root.commandOverride)
      ? root.commandOverride
      : [Qt.resolvedUrl("scripts/network-profile-catalog")]
    stdout: SplitParser {
      onRead: data => implementation.ingestLine(data)
    }
    stderr: StdioCollector {}
    onStarted: implementation.processStarted()
    onExited: (exitCode, _exitStatus) => implementation.processExited(exitCode)
    onRunningChanged: {
      if (root.launchRequested && !catalogProcess.running)
        implementation.failRun("start-failed")
    }
  }

  Component.onCompleted: if (root.active)
    implementation.claimAuthority()
  Component.onDestruction: implementation.shutdown()
}
