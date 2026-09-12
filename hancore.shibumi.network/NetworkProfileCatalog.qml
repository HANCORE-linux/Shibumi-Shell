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
  property int drainTimeoutMs: 1000
  readonly property string helperPath:
    String(Qt.resolvedUrl("scripts/network-profile-catalog"))
      .replace(/^file:\/\//, "")

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
    property bool workerUnsettled: false
    Component.onDestruction: {
      if (workerUnsettled) Authority.block(claim)
      else Authority.release(claim)
    }
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

  Timer {
    id: drainWatchdog
    interval: Math.max(100, root.drainTimeoutMs)
    repeat: false
    onTriggered: {
      if (!catalogProcess.running) return
      if (implementation.canSignalProcess()) catalogProcess.signal(9)
      catalogProcess.running = false
      if (catalogProcess.running && !implementation.canSignalProcess())
        drainWatchdog.restart()
    }
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
    property bool shutdownRequested: false
    property bool processStarted: false

    function canSignalProcess() {
      const pid = Number(catalogProcess.processId)
      return processStarted && isFinite(pid) && pid > 0
        && Math.floor(pid) === pid
    }

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
      if (!root.active || shutdownRequested || authorized) return authorized
      authorityClaim = Authority.claim(root.authorityGuard)
      root.authorityGuard.claim = authorityClaim
      authorized = authorityClaim > 0
      root.phase = authorized ? "idle" : "standby"
      if (authorized && root.clientCount > 0) refresh()
      return authorized
    }

    function acquire(owner) {
      if (!owner || !root.active || shutdownRequested || !authorized)
        return false
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
      processStarted = false
      root.launchRequested = true
      root.authorityGuard.workerUnsettled = true
      catalogProcess.command = workerCommand()
      catalogProcess.running = true
      return true
    }

    function cancelRun(nextPhase) {
      const hadWorker = catalogProcess.running
      refreshTimeout.stop()
      pendingRefresh = false
      if (hadWorker) {
        if (canSignalProcess()) catalogProcess.signal(15)
        drainWatchdog.restart()
      } else {
        drainWatchdog.stop()
      }
      catalogProcess.running = false
      root.launchRequested = false
      if (runState === "loading" || runState === "complete")
        runState = hadWorker ? "cancelled" : "idle"
      resetPending()
      root.phase = String(nextPhase || "idle")
    }

    function failRun(reason) {
      refreshTimeout.stop()
      pendingRefresh = false
      lastError = String(reason || "invalid")
      if (catalogProcess.running) {
        if (canSignalProcess()) catalogProcess.signal(15)
        drainWatchdog.restart()
      } else {
        drainWatchdog.stop()
        if (!processStarted) root.authorityGuard.workerUnsettled = false
      }
      catalogProcess.running = false
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

    function workerCommand() {
      return Array.isArray(root.commandOverride)
        ? root.commandOverride.slice()
        : ["/usr/bin/python3", "-I", root.helperPath]
    }

    function processStartedEvent() {
      processStarted = true
      if (runState !== "loading") {
        if (catalogProcess.running) {
          if (canSignalProcess()) catalogProcess.signal(15)
          catalogProcess.running = false
          drainWatchdog.restart()
        }
        return
      }
      refreshTimeout.restart()
    }

    function processExited(exitCode) {
      processStarted = false
      root.authorityGuard.workerUnsettled = false
      drainWatchdog.stop()
      refreshTimeout.stop()
      catalogProcess.running = false
      root.launchRequested = false
      if (shutdownRequested) {
        pendingRefresh = false
        runState = "idle"
        resetPending()
        finishShutdown()
        return
      }
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

    function destroyLeases() {
      const oldRecords = records.slice()
      records = []
      for (let index = 0; index < oldRecords.length; index++) {
        const tokenObject = oldRecords[index].tokenObject
        if (!tokenObject) continue
        tokenObject.armed = false
        tokenObject.destroy()
      }
    }

    function finishShutdown() {
      drainWatchdog.stop()
      pendingRefresh = false
      runState = "idle"
      resetPending()
      Authority.release(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
      shutdownRequested = false
      root.phase = "inactive"
      if (root.active) claimAuthority()
    }

    function shutdown() {
      if (shutdownRequested) return
      shutdownRequested = true
      const hadWorker = catalogProcess.running
      cancelRun("draining")
      destroyLeases()
      clearPublished(hadWorker ? "draining" : "inactive")
      if (!catalogProcess.running) finishShutdown()
    }

    function destroying() {
      const hadWorker = catalogProcess.running
        || root.authorityGuard.workerUnsettled
      refreshTimeout.stop()
      drainWatchdog.stop()
      destroyLeases()
      if (hadWorker) {
        if (canSignalProcess()) catalogProcess.signal(9)
        catalogProcess.running = false
        Authority.block(authorityClaim)
      } else {
        catalogProcess.running = false
        Authority.release(authorityClaim)
      }
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
    }
  }

  Process {
    id: catalogProcess
    command: []
    stdout: SplitParser {
      onRead: data => implementation.ingestLine(data)
    }
    stderr: StdioCollector {}
    onStarted: implementation.processStartedEvent()
    onExited: (exitCode, _exitStatus) => implementation.processExited(exitCode)
    onRunningChanged: {
      if (catalogProcess.running) return
      implementation.processStarted = false
      drainWatchdog.stop()
      if (implementation.shutdownRequested)
        implementation.finishShutdown()
      else if (implementation.runState === "cancelled")
        implementation.processExited(-1)
      else if (root.launchRequested)
        implementation.failRun("start-failed")
    }
  }

  Component.onCompleted: if (root.active)
    implementation.claimAuthority()
  Component.onDestruction: implementation.destroying()
}
