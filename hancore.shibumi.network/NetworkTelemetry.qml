pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "NetworkModel.js" as NetworkModel
import "NetworkTelemetryModel.js" as TelemetryModel
import "NetworkTelemetryAuthority.js" as Authority

// Demand-driven, process-wide active-connection telemetry. The helper exposes
// one bounded primitive snapshot; NetworkManager object paths and QObjects stay
// private. Service.qml owns one demand-driven instance process-wide.
Item {
  id: root

  property bool active: false
  property var nativeLiveness: null
  property var commandOverride: null
  property int pollIntervalMs: 2000
  property int refreshTimeoutMs: 15000
  property int drainTimeoutMs: 1000
  readonly property string helperPath:
    String(Qt.resolvedUrl("scripts/network-telemetry-snapshot"))
      .replace(/^file:\/\//, "")

  property real generation: 0
  property real identityGeneration: 0
  property string phase: "inactive"
  property bool launchRequested: false

  readonly property int schemaVersion: TelemetryModel.SchemaVersion
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
  readonly property bool workerRunning: telemetryProcess.running
  readonly property bool draining: implementation.shutdownRequested
  readonly property bool workerOutputComplete:
    implementation.runState === "complete"
  readonly property bool available: root.active && root.authorized
    && root.nativeServiceAvailable
    && (root.phase === "live" || root.phase === "refreshing")
    && implementation.publishedSnapshot !== null
  readonly property var telemetrySnapshot: implementation.publicSnapshot()
  readonly property bool connected: root.available
    && root.telemetrySnapshot !== null
    && root.telemetrySnapshot.connected === true
  readonly property var connectionSnapshot: root.connected
    ? root.telemetrySnapshot : null
  readonly property var dnsSnapshot: root.connected ? ({
    schemaVersion: root.schemaVersion,
    deviceId: root.telemetrySnapshot.deviceId,
    servers: TelemetryModel.cloneRows(root.telemetrySnapshot.dnsServers),
    domains: root.telemetrySnapshot.dnsDomains.slice(),
    generation: root.generation
  }) : null
  readonly property var throughputSnapshot: root.connected ? ({
    schemaVersion: root.schemaVersion,
    deviceId: root.telemetrySnapshot.deviceId,
    rxBytes: root.telemetrySnapshot.rxBytes,
    txBytes: root.telemetrySnapshot.txBytes,
    downloadBytesPerSecond: root.telemetrySnapshot.downloadBytesPerSecond,
    uploadBytesPerSecond: root.telemetrySnapshot.uploadBytesPerSecond,
    sampleMonotonicMs: root.telemetrySnapshot.sampleMonotonicMs,
    generation: root.generation
  }) : null
  readonly property string identityFingerprint:
    implementation.identityFingerprint()
  readonly property var statusSnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.available,
    connected: root.connected,
    phase: root.phase,
    errorCode: root.errorCode,
    generation: root.generation
  })
  property QtObject authorityGuard: QtObject {
    property bool authorityAlive: true
    property int claim: 0
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
  onIdentityFingerprintChanged: {
    if (root.identityGeneration < TelemetryModel.MaxSafeInteger)
      root.identityGeneration++
  }

  Timer {
    interval: 250
    repeat: true
    running: root.active && !root.authorized
    onTriggered: implementation.claimAuthority()
  }

  Timer {
    id: restartDelay
    interval: 100
    repeat: false
    onTriggered: implementation.refresh()
  }

  Timer {
    id: pollTimer
    interval: Math.max(100, root.pollIntervalMs)
    repeat: false
    onTriggered: implementation.refresh()
  }

  Timer {
    id: drainWatchdog
    interval: Math.max(100, root.drainTimeoutMs)
    repeat: false
    onTriggered: {
      if (telemetryProcess.running) {
        telemetryProcess.signal(9)
        telemetryProcess.running = false
      }
    }
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
    property var publishedSnapshot: null
    property var previousSample: null
    property var pendingSnapshot: null
    property string runState: "idle"
    property bool pendingRefresh: false
    property string lastError: ""
    property bool shutdownRequested: false

    function bumpGeneration() {
      if (root.generation < TelemetryModel.MaxSafeInteger) root.generation++
    }

    function clonePublic(source) {
      if (!source) return null
      const snapshot = TelemetryModel.cloneSnapshot(source)
      if (!snapshot) return null
      snapshot.id = source.id
      snapshot.deviceId = source.deviceId
      snapshot.downloadBytesPerSecond = source.downloadBytesPerSecond
      snapshot.uploadBytesPerSecond = source.uploadBytesPerSecond
      snapshot.generation = root.generation
      return snapshot
    }

    function publicSnapshot() {
      return root.available ? clonePublic(publishedSnapshot) : null
    }

    function identityFingerprint() {
      const source = publishedSnapshot
      return source ? JSON.stringify({
        connected: source.connected === true,
        id: String(source.id || ""),
        deviceId: String(source.deviceId || ""),
        kind: String(source.kind || "none"),
        activeConnections: Array.isArray(source.activeConnections)
          ? source.activeConnections : []
      }) : ""
    }

    function clearPublished(nextPhase) {
      publishedSnapshot = null
      previousSample = null
      root.phase = String(nextPhase || "unavailable")
      bumpGeneration()
    }

    function resetPending() {
      pendingSnapshot = null
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
      if (nextLeaseToken > TelemetryModel.MaxSafeInteger) nextLeaseToken = 1
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
        restartDelay.restart()
      }
    }

    function refresh() {
      pollTimer.stop()
      if (!root.active || shutdownRequested || !authorized
          || root.clientCount < 1
          || !root.nativeServiceAvailable)
        return false
      if (telemetryProcess.running || root.launchRequested
          || runState === "cancelled") {
        pendingRefresh = true
        return true
      }
      pendingRefresh = false
      lastError = ""
      resetPending()
      runState = "loading"
      root.phase = publishedSnapshot === null ? "loading" : "refreshing"
      root.launchRequested = true
      telemetryProcess.running = true
      return true
    }

    function scheduleNext() {
      if (root.active && !shutdownRequested && authorized
          && root.clientCount > 0
          && root.nativeServiceAvailable)
        pollTimer.restart()
    }

    function cancelRun(nextPhase) {
      const hadWorker = telemetryProcess.running
      restartDelay.stop()
      pollTimer.stop()
      refreshTimeout.stop()
      pendingRefresh = false
      if (hadWorker) {
        telemetryProcess.signal(15)
        drainWatchdog.restart()
      } else {
        drainWatchdog.stop()
      }
      telemetryProcess.running = false
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
      if (telemetryProcess.running) {
        telemetryProcess.signal(15)
        drainWatchdog.restart()
      } else {
        drainWatchdog.stop()
      }
      telemetryProcess.running = false
      root.launchRequested = false
      runState = "failed"
      resetPending()
      clearPublished(root.nativeServiceAvailable ? "error" : "unavailable")
      scheduleNext()
      return false
    }

    function ingestLine(line) {
      if (runState === "failed" || runState === "cancelled") return false
      if (runState !== "loading" || pendingSnapshot !== null)
        return failRun("unexpected-output")
      const record = TelemetryModel.parseLine(line)
      if (!record.ok) return failRun(record.code)
      pendingSnapshot = record.snapshot
      runState = "complete"
      return true
    }

    function processStarted() {
      if (runState !== "loading") {
        if (telemetryProcess.running) {
          telemetryProcess.signal(15)
          telemetryProcess.running = false
          drainWatchdog.restart()
        }
        return
      }
      refreshTimeout.restart()
    }

    function decoratedSnapshot(source) {
      const snapshot = TelemetryModel.cloneSnapshot(source)
      if (!snapshot) return null
      snapshot.id = snapshot.connected
        ? NetworkModel.connectionId(snapshot.connectionUuid) : ""
      snapshot.deviceId = snapshot.connected
        ? NetworkModel.deviceId(snapshot.kind, snapshot.hardwareAddress,
          snapshot.interfaceName) : ""
      if (snapshot.connected && (!snapshot.id || !snapshot.deviceId))
        return null
      let downloadRate = 0
      let uploadRate = 0
      const previous = previousSample
      if (snapshot.connected && previous && previous.connected
          && previous.connectionUuid === snapshot.connectionUuid
          && previous.deviceId === snapshot.deviceId
          && snapshot.sampleMonotonicMs > previous.sampleMonotonicMs
          && snapshot.rxBytes >= previous.rxBytes
          && snapshot.txBytes >= previous.txBytes) {
        const elapsed = snapshot.sampleMonotonicMs - previous.sampleMonotonicMs
        downloadRate = (snapshot.rxBytes - previous.rxBytes) * 1000 / elapsed
        uploadRate = (snapshot.txBytes - previous.txBytes) * 1000 / elapsed
        if (!isFinite(downloadRate) || downloadRate < 0
            || downloadRate > TelemetryModel.MaxSafeInteger) return null
        if (!isFinite(uploadRate) || uploadRate < 0
            || uploadRate > TelemetryModel.MaxSafeInteger) return null
      }
      snapshot.downloadBytesPerSecond = downloadRate
      snapshot.uploadBytesPerSecond = uploadRate
      return snapshot
    }

    function settleCancelledRun() {
      const retry = pendingRefresh
      pendingRefresh = false
      runState = "idle"
      if (retry && root.active && authorized && root.clientCount > 0
          && root.nativeServiceAvailable)
        refresh()
      else scheduleNext()
    }

    function processExited(exitCode) {
      drainWatchdog.stop()
      refreshTimeout.stop()
      telemetryProcess.running = false
      root.launchRequested = false
      if (shutdownRequested) {
        pendingRefresh = false
        runState = "idle"
        resetPending()
        finishShutdown()
        return
      }
      if (runState === "cancelled") {
        settleCancelledRun()
        return
      }
      if (runState === "failed") {
        pendingRefresh = false
        runState = "idle"
        scheduleNext()
        return
      }
      if (exitCode !== 0 || runState !== "complete"
          || pendingSnapshot === null) {
        failRun("process-exited")
        return
      }
      const next = decoratedSnapshot(pendingSnapshot)
      const retry = pendingRefresh
      pendingRefresh = false
      resetPending()
      runState = "idle"
      if (!next) {
        failRun("invalid-identity")
        return
      }
      if (!root.nativeServiceAvailable || root.clientCount < 1) {
        clearPublished(root.nativeServiceAvailable ? "idle" : "unavailable")
        return
      }
      previousSample = next
      publishedSnapshot = next
      root.phase = "live"
      bumpGeneration()
      if (retry) refresh()
      else scheduleNext()
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
      cancelRun("draining")
      destroyLeases()
      clearPublished(telemetryProcess.running ? "draining" : "inactive")
      if (!telemetryProcess.running) finishShutdown()
    }

    function destroying() {
      const hadWorker = telemetryProcess.running
      restartDelay.stop()
      pollTimer.stop()
      refreshTimeout.stop()
      drainWatchdog.stop()
      destroyLeases()
      if (hadWorker) {
        telemetryProcess.signal(9)
        telemetryProcess.running = false
        Authority.block(authorityClaim)
      } else {
        telemetryProcess.running = false
        Authority.release(authorityClaim)
      }
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
    }
  }

  Process {
    id: telemetryProcess
    command: Array.isArray(root.commandOverride)
      ? root.commandOverride
      : ["/usr/bin/python3", "-I", root.helperPath]
    stdout: SplitParser {
      onRead: data => implementation.ingestLine(data)
    }
    stderr: StdioCollector {}
    onStarted: implementation.processStarted()
    onExited: (exitCode, _exitStatus) => implementation.processExited(exitCode)
    onRunningChanged: {
      if (telemetryProcess.running) return
      drainWatchdog.stop()
      if (implementation.shutdownRequested)
        implementation.finishShutdown()
      else if (implementation.runState === "cancelled")
        implementation.settleCancelledRun()
      else if (root.launchRequested)
        implementation.failRun("start-failed")
    }
  }

  Component.onCompleted: if (root.active)
    implementation.claimAuthority()
  Component.onDestruction: implementation.destroying()
}
