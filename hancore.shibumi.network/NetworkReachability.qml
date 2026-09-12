pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "NetworkReachabilityModel.js" as Model
import "NetworkReachabilityAuthority.js" as Authority

// Demand-driven, process-wide ICMP reachability history. It consumes only the
// primitive NetworkTelemetry connection snapshot and publishes primitive rows.
// Service.qml owns one demand-driven instance process-wide.
Item {
  id: root

  property bool active: false
  property var networkTelemetry: null
  property var commandOverride: null
  property int pollIntervalMs: 2500
  property int refreshTimeoutMs: 5000
  property int drainTimeoutMs: 1000
  readonly property string helperPath:
    String(Qt.resolvedUrl("scripts/network-reachability-probe"))
      .replace(/^file:\/\//, "")

  property real generation: 0
  property string phase: "inactive"
  property bool launchRequested: false

  readonly property int schemaVersion: Model.SchemaVersion
  readonly property bool authorized: implementation.authorized
  readonly property int clientCount: implementation.records.length
  readonly property bool workerRunning: probeProcess.running
  readonly property bool draining: implementation.shutdownRequested
  readonly property bool workerOutputComplete:
    implementation.runState === "complete"
  readonly property string errorCode: implementation.lastError
  readonly property var routeInput: Model.routeInput(
    root.networkTelemetry !== null
      && root.networkTelemetry.available === true
      ? root.networkTelemetry.connectionSnapshot : null)
  readonly property string routeFingerprint:
    Model.routeFingerprint(root.routeInput)
  readonly property bool available: root.active && root.authorized
    && root.routeInput !== null
    && (root.phase === "live" || root.phase === "refreshing")
    && implementation.publishedHistory !== null
  readonly property var reachabilitySnapshot:
    implementation.publicSnapshot()
  readonly property real routerPingLatency:
    root.reachabilitySnapshot !== null
      ? root.reachabilitySnapshot.routerLatencyMs : -1
  readonly property real internetPingLatency:
    root.reachabilitySnapshot !== null
      ? root.reachabilitySnapshot.internetLatencyMs : -1
  readonly property int internetPingPacketLoss:
    root.reachabilitySnapshot !== null
      ? root.reachabilitySnapshot.internetPacketLossPercent : 0
  readonly property var statusSnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.available,
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
  onNetworkTelemetryChanged: implementation.inputChanged()
  onRouteFingerprintChanged: implementation.inputChanged()

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
      if (!probeProcess.running) return
      if (implementation.canSignalProcess()) probeProcess.signal(9)
      probeProcess.running = false
      if (probeProcess.running && !implementation.canSignalProcess())
        drainWatchdog.restart()
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
    property var publishedHistory: null
    property var pendingRoute: null
    property string pendingFingerprint: ""
    property var pendingSnapshot: null
    property string runState: "idle"
    property bool pendingRefresh: false
    property string lastError: ""
    property bool shutdownRequested: false
    property bool processStarted: false
    property string stdoutBuffer: ""

    function canSignalProcess() {
      const pid = Number(probeProcess.processId)
      return processStarted && isFinite(pid) && pid > 0
        && Math.floor(pid) === pid
    }

    function bumpGeneration() {
      if (root.generation < Model.MaxSafeInteger) root.generation++
    }

    function publicSnapshot() {
      if (!root.available) return null
      const snapshot = Model.cloneHistory(publishedHistory)
      if (!snapshot) return null
      snapshot.schemaVersion = root.schemaVersion
      snapshot.generation = root.generation
      return snapshot
    }

    function clearPublished(nextPhase) {
      publishedHistory = null
      root.phase = String(nextPhase || "unavailable")
      bumpGeneration()
    }

    function resetPending() {
      pendingRoute = null
      pendingFingerprint = ""
      pendingSnapshot = null
      stdoutBuffer = ""
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
      if (nextLeaseToken > Model.MaxSafeInteger) nextLeaseToken = 1
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
        if (records[index].token === token)
          tokenObject = records[index].tokenObject
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

    function inputChanged() {
      cancelRun(root.routeInput ? "waiting" : "unavailable")
      clearPublished(root.routeInput ? "waiting" : "unavailable")
      if (root.active && authorized && root.clientCount > 0
          && root.routeInput !== null)
        restartDelay.restart()
    }

    function workerCommand(route) {
      const base = Array.isArray(root.commandOverride)
        ? root.commandOverride.slice()
        : ["/usr/bin/python3", "-I", root.helperPath]
      return base.concat([
        "--interface", route.interfaceName,
        "--gateway", route.gateway === "" ? "none" : route.gateway
      ])
    }

    function refresh() {
      pollTimer.stop()
      if (!root.active || shutdownRequested || !authorized
          || root.clientCount < 1 || root.routeInput === null)
        return false
      if (probeProcess.running || root.launchRequested
          || runState === "cancelled") {
        pendingRefresh = true
        return true
      }
      pendingRefresh = false
      lastError = ""
      resetPending()
      pendingRoute = {
        connectionId: root.routeInput.connectionId,
        deviceId: root.routeInput.deviceId,
        interfaceName: root.routeInput.interfaceName,
        gateway: root.routeInput.gateway,
        internetTarget: root.routeInput.internetTarget
      }
      pendingFingerprint = Model.routeFingerprint(pendingRoute)
      runState = "loading"
      root.phase = publishedHistory === null ? "loading" : "refreshing"
      processStarted = false
      root.launchRequested = true
      probeProcess.command = workerCommand(pendingRoute)
      probeProcess.running = true
      return true
    }

    function scheduleNext() {
      if (root.active && !shutdownRequested && authorized
          && root.clientCount > 0 && root.routeInput !== null)
        pollTimer.restart()
    }

    function cancelRun(nextPhase) {
      const hadWorker = probeProcess.running
      restartDelay.stop()
      pollTimer.stop()
      refreshTimeout.stop()
      pendingRefresh = false
      if (hadWorker) {
        if (canSignalProcess()) probeProcess.signal(15)
        drainWatchdog.restart()
      } else {
        drainWatchdog.stop()
      }
      probeProcess.running = false
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
      if (probeProcess.running) {
        if (canSignalProcess()) probeProcess.signal(15)
        drainWatchdog.restart()
      } else {
        drainWatchdog.stop()
      }
      probeProcess.running = false
      root.launchRequested = false
      runState = "failed"
      resetPending()
      clearPublished(root.routeInput ? "error" : "unavailable")
      scheduleNext()
      return false
    }

    function ingestChunk(chunk) {
      if (runState === "failed" || runState === "cancelled") return false
      if (runState !== "loading" || pendingSnapshot !== null
          || typeof chunk !== "string")
        return failRun("unexpected-output")
      const remainingCharacters = Model.MaxProtocolLine + 1
        - stdoutBuffer.length
      if (chunk.length > remainingCharacters)
        return failRun("invalid-line")
      const combined = stdoutBuffer + chunk
      const bytes = Model.utf8Bytes(combined)
      if (bytes === null || bytes.length > Model.MaxProtocolLine + 1)
        return failRun("invalid-line")
      const newline = combined.indexOf("\n")
      if (newline < 0) {
        stdoutBuffer = combined
        return true
      }
      if (newline !== combined.length - 1
          || combined.indexOf("\n", newline + 1) >= 0)
        return failRun("unexpected-output")
      const line = combined.slice(0, -1)
      stdoutBuffer = ""
      const record = Model.parseLine(line)
      if (!record.ok) return failRun(record.code)
      pendingSnapshot = record.snapshot
      runState = "complete"
      return true
    }

    function processStartedEvent() {
      processStarted = true
      if (runState !== "loading") {
        if (probeProcess.running) {
          if (canSignalProcess()) probeProcess.signal(15)
          probeProcess.running = false
          drainWatchdog.restart()
        }
        return
      }
      refreshTimeout.restart()
    }

    function settleCancelledRun() {
      const retry = pendingRefresh
      pendingRefresh = false
      runState = "idle"
      if (retry && root.active && authorized && root.clientCount > 0
          && root.routeInput !== null)
        refresh()
      else scheduleNext()
    }

    function processExited(exitCode) {
      processStarted = false
      drainWatchdog.stop()
      refreshTimeout.stop()
      probeProcess.running = false
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
        const retry = pendingRefresh
        pendingRefresh = false
        runState = "idle"
        if (retry) refresh()
        else scheduleNext()
        return
      }
      if (exitCode !== 0 || runState !== "complete"
          || pendingSnapshot === null || pendingRoute === null
          || pendingFingerprint === "") {
        failRun("process-exited")
        return
      }
      if (root.routeFingerprint !== pendingFingerprint) {
        const retry = root.routeInput !== null && root.clientCount > 0
        resetPending()
        runState = "idle"
        clearPublished(root.routeInput ? "waiting" : "unavailable")
        if (retry) refresh()
        return
      }
      const next = Model.nextHistory(
        publishedHistory, pendingRoute, pendingSnapshot)
      const retry = pendingRefresh
      pendingRefresh = false
      resetPending()
      runState = "idle"
      if (!next) {
        failRun("invalid-probe")
        return
      }
      if (root.clientCount < 1 || root.routeInput === null) {
        clearPublished(root.routeInput ? "idle" : "unavailable")
        return
      }
      publishedHistory = next
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
      clearPublished(probeProcess.running ? "draining" : "inactive")
      if (!probeProcess.running) finishShutdown()
    }

    function destroying() {
      const hadWorker = probeProcess.running
      restartDelay.stop()
      pollTimer.stop()
      refreshTimeout.stop()
      drainWatchdog.stop()
      destroyLeases()
      if (hadWorker) {
        if (canSignalProcess()) probeProcess.signal(9)
        probeProcess.running = false
        Authority.block(authorityClaim)
      } else {
        probeProcess.running = false
        Authority.release(authorityClaim)
      }
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
    }
  }

  Process {
    id: probeProcess
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => implementation.ingestChunk(data)
    }
    onStarted: implementation.processStartedEvent()
    onExited: (exitCode, _exitStatus) => implementation.processExited(exitCode)
    onRunningChanged: {
      if (probeProcess.running) return
      implementation.processStarted = false
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
