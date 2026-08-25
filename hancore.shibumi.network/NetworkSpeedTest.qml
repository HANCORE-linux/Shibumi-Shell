pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "NetworkSpeedTestModel.js" as Model
import "NetworkSpeedTestAuthority.js" as Authority

// Process-wide, demand-driven speed-test action seam. It consumes only a
// validated primitive NetworkTelemetry connection snapshot and runs one
// bounded Shibumi worker at a time. Production Service.qml does not instantiate
// this source-only seam.
Item {
  id: root

  property bool active: false
  property var networkTelemetry: null
  property var commandOverride: null
  property int phaseDurationMs: 4000
  property int phaseTimeoutMs: 12000
  property int drainTimeoutMs: 2500
  property int interPhaseDelayMs: 1

  property real generation: 0
  property real runId: 0
  property string phase: "inactive"
  property bool launchRequested: false

  readonly property int schemaVersion: Model.SchemaVersion
  readonly property bool authorized: implementation.authorized
  readonly property bool workerRunning: speedProcess.running
  readonly property bool running: implementation.activeRecord !== null
  readonly property bool draining: implementation.shutdownRequested
    || implementation.runState === "cancelled" && speedProcess.running
  readonly property string errorCode: implementation.lastError
  readonly property var testInput: Model.testInput(
    root.networkTelemetry !== null
      && root.networkTelemetry.available === true
      && root.networkTelemetry.connected === true
      ? root.networkTelemetry.connectionSnapshot : null)
  readonly property string inputFingerprint: Model.inputFingerprint(root.testInput)
  readonly property bool available: root.active && root.authorized
    && !implementation.shutdownRequested && root.testInput !== null
  readonly property var speedTestResult: implementation.publicResult()
  readonly property real downloadMbps: root.speedTestResult !== null
    ? root.speedTestResult.downloadMbps : -1
  readonly property real uploadMbps: root.speedTestResult !== null
    ? root.speedTestResult.uploadMbps : -1
  readonly property var statusSnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.available,
    authorized: root.authorized,
    running: root.running,
    phase: root.phase,
    errorCode: root.errorCode,
    runId: root.runId,
    generation: root.generation
  })

  property QtObject authorityGuard: QtObject {
    property bool authorityAlive: true
    property int claim: 0
  }

  visible: false
  width: 0
  height: 0

  function requestRun(owner) { return implementation.requestRun(owner) }
  function cancel(owner) { return implementation.cancel(owner) }

  onActiveChanged: {
    if (active) implementation.claimAuthority()
    else implementation.shutdown()
  }
  onNetworkTelemetryChanged: implementation.inputChanged()
  onInputFingerprintChanged: implementation.inputChanged()

  Timer {
    interval: 250
    repeat: true
    running: root.active && !root.authorized
    onTriggered: implementation.claimAuthority()
  }

  Timer {
    id: uploadContinuation
    interval: Math.max(0, root.interPhaseDelayMs)
    repeat: false
    property real expectedRunId: 0
    onTriggered: implementation.continueUpload(expectedRunId)
  }

  Timer {
    id: phaseTimeout
    interval: Math.max(1000, root.phaseTimeoutMs)
    repeat: false
    onTriggered: implementation.abortRun("timeout")
  }

  Timer {
    id: drainWatchdog
    interval: Math.max(250, root.drainTimeoutMs)
    repeat: false
    onTriggered: {
      if (!speedProcess.running) return
      if (implementation.canSignalProcess()) speedProcess.signal(9)
      speedProcess.running = false
      if (speedProcess.running && !implementation.canSignalProcess())
        drainWatchdog.restart()
    }
  }

  Component {
    id: ownerTokenComponent
    QtObject {
      required property int ownerToken
      property bool armed: true
      Component.onDestruction: if (armed)
        implementation.ownerDestroyed(ownerToken)
    }
  }

  QtObject {
    id: implementation

    property bool authorized: false
    property int authorityClaim: 0
    property int nextOwnerToken: 1
    property var activeRecord: null
    property var pendingInput: null
    property string pendingFingerprint: ""
    property string pendingRunToken: ""
    property string pendingDirection: ""
    property var pendingMeasurement: null
    property var downloadMeasurement: null
    property var publishedResult: null
    property string publishedFingerprint: ""
    property string runState: "idle"
    property string lastError: ""
    property string abortError: ""
    property bool shutdownRequested: false
    property bool processStarted: false
    property string stdoutBuffer: ""

    function bumpGeneration() {
      if (root.generation < Model.MaxSafeInteger) root.generation++
    }

    function bumpRunId() {
      if (root.runId < Model.MaxSafeInteger) root.runId++
      else root.runId = 1
    }

    function canSignalProcess() {
      const pid = Number(speedProcess.processId)
      return processStarted && isFinite(pid) && pid > 0
        && Math.floor(pid) === pid
    }

    function publicResult() {
      if (!publishedResult || publishedFingerprint !== root.inputFingerprint)
        return null
      return Model.clonePublicResult(publishedResult)
    }

    function clearPublished() {
      if (publishedResult !== null || publishedFingerprint !== "") {
        publishedResult = null
        publishedFingerprint = ""
        bumpGeneration()
      }
    }

    function cloneInput(value) {
      return value ? {
        connectionId: value.connectionId,
        deviceId: value.deviceId,
        kind: value.kind,
        interfaceName: value.interfaceName,
        sourceAddress: value.sourceAddress,
        metered: value.metered
      } : null
    }

    function resetPhaseState() {
      pendingDirection = ""
      pendingMeasurement = null
      stdoutBuffer = ""
    }

    function resetRunState() {
      uploadContinuation.stop()
      uploadContinuation.expectedRunId = 0
      pendingInput = null
      pendingFingerprint = ""
      pendingRunToken = ""
      downloadMeasurement = null
      resetPhaseState()
    }

    function claimAuthority() {
      if (!root.active || shutdownRequested || authorized) return authorized
      authorityClaim = Authority.claim(root.authorityGuard)
      root.authorityGuard.claim = authorityClaim
      authorized = authorityClaim > 0
      root.phase = authorized ? "idle" : "standby"
      return authorized
    }

    function createOwnerRecord(owner) {
      if (!owner) return null
      const token = nextOwnerToken++
      if (nextOwnerToken > 2147483646) nextOwnerToken = 1
      const tokenObject = ownerTokenComponent.createObject(owner, {
        ownerToken: token
      })
      if (!tokenObject) return null
      return { token: token, owner: owner, tokenObject: tokenObject }
    }

    function clearOwnerRecord(destroyToken) {
      const record = activeRecord
      activeRecord = null
      if (!record || !record.tokenObject || !destroyToken) return
      record.tokenObject.armed = false
      record.tokenObject.destroy()
    }

    function requestRun(owner) {
      if (!owner || !root.available || activeRecord !== null
          || speedProcess.running || root.launchRequested) return false
      const record = createOwnerRecord(owner)
      if (!record) return false
      const input = cloneInput(root.testInput)
      const fingerprint = Model.inputFingerprint(input)
      if (!input || fingerprint === "") {
        record.tokenObject.armed = false
        record.tokenObject.destroy()
        return false
      }
      activeRecord = record
      pendingInput = input
      pendingFingerprint = fingerprint
      downloadMeasurement = null
      publishedResult = null
      publishedFingerprint = ""
      lastError = ""
      abortError = ""
      bumpRunId()
      bumpGeneration()
      pendingRunToken = String(authorityClaim) + ":" + String(root.runId)
        + ":" + String(root.generation)
      if (!Model.validRunToken(pendingRunToken)) {
        clearOwnerRecord(true)
        resetRunState()
        return false
      }
      return startPhase("down")
    }

    function cancel(owner) {
      if (!owner || !activeRecord || activeRecord.owner !== owner) return false
      clearOwnerRecord(true)
      abortRun("")
      return true
    }

    function ownerDestroyed(token) {
      if (!activeRecord || activeRecord.token !== token) return
      clearOwnerRecord(false)
      abortRun("")
    }

    function inputChanged() {
      if (publishedFingerprint !== ""
          && publishedFingerprint !== root.inputFingerprint)
        clearPublished()
      if (activeRecord !== null
          && pendingFingerprint !== root.inputFingerprint)
        abortRun("route-changed")
    }

    function workerCommand(direction) {
      const base = Array.isArray(root.commandOverride)
        ? root.commandOverride.slice()
        : [Qt.resolvedUrl("scripts/network-speed-test")]
      const expectedInterfaceIndex = direction === "up"
        && downloadMeasurement !== null
        ? String(downloadMeasurement.interfaceIndex) : "any"
      return base.concat([
        "--direction", direction,
        "--interface", pendingInput.interfaceName,
        "--source-address", pendingInput.sourceAddress,
        "--duration-ms", String(Math.max(1000,
          Math.min(8000, Math.floor(root.phaseDurationMs)))),
        "--run-token", pendingRunToken,
        "--expected-interface-index", expectedInterfaceIndex
      ])
    }

    function continueUpload(expectedRunId) {
      if (expectedRunId !== root.runId || activeRecord === null
          || runState !== "idle" || speedProcess.running
          || root.launchRequested || pendingDirection !== "") return false
      return startPhase("up")
    }

    function startPhase(direction) {
      if (!activeRecord || !pendingInput || pendingFingerprint === ""
          || !Model.validRunToken(pendingRunToken)
          || pendingFingerprint !== root.inputFingerprint
          || direction !== "down" && direction !== "up") {
        abortRun("route-changed")
        return false
      }
      resetPhaseState()
      pendingDirection = direction
      runState = "loading"
      processStarted = false
      root.phase = direction
      root.launchRequested = true
      speedProcess.command = workerCommand(direction)
      speedProcess.running = true
      return true
    }

    function ingestChunk(chunk) {
      if (runState === "cancelled" || runState === "failed") return false
      if (runState !== "loading" || pendingMeasurement !== null
          || typeof chunk !== "string") {
        abortRun("unexpected-output")
        return false
      }
      const remainingCharacters = Model.MaxProtocolLine + 1
        - stdoutBuffer.length
      if (chunk.length > remainingCharacters) {
        abortRun("invalid-line")
        return false
      }
      const combined = stdoutBuffer + chunk
      const bytes = Model.utf8Bytes(combined)
      if (bytes === null || bytes.length > Model.MaxProtocolLine + 1) {
        abortRun("invalid-line")
        return false
      }
      const newline = combined.indexOf("\n")
      if (newline < 0) {
        stdoutBuffer = combined
        return true
      }
      if (newline !== combined.length - 1
          || combined.indexOf("\n", newline + 1) >= 0) {
        abortRun("unexpected-output")
        return false
      }
      const line = combined.slice(0, -1)
      stdoutBuffer = ""
      const parsed = Model.parseLine(line)
      if (!parsed.ok) {
        abortRun(parsed.code)
        return false
      }
      pendingMeasurement = parsed.snapshot
      runState = "complete"
      return true
    }

    function processStartedEvent() {
      processStarted = true
      if (runState !== "loading" || activeRecord === null) {
        if (speedProcess.running) {
          if (canSignalProcess()) speedProcess.signal(15)
          speedProcess.running = false
          drainWatchdog.restart()
        }
        return
      }
      phaseTimeout.restart()
    }

    function abortRun(code) {
      uploadContinuation.stop()
      uploadContinuation.expectedRunId = 0
      phaseTimeout.stop()
      abortError = String(code || "")
      if (abortError !== "") lastError = abortError
      const hadWorker = speedProcess.running
      const hadLaunch = root.launchRequested
      runState = hadWorker || hadLaunch ? "cancelled" : "idle"
      if (speedProcess.running) {
        if (canSignalProcess()) speedProcess.signal(15)
        speedProcess.running = false
        drainWatchdog.restart()
      } else {
        drainWatchdog.stop()
      }
      root.launchRequested = false
      if (!hadWorker) finishAbort()
      return false
    }

    function finishAbort() {
      phaseTimeout.stop()
      drainWatchdog.stop()
      clearOwnerRecord(true)
      resetRunState()
      runState = "idle"
      root.launchRequested = false
      if (shutdownRequested) {
        finishShutdown()
        return
      }
      root.phase = abortError === "" ? "idle" : "error"
      abortError = ""
    }

    function processExited(exitCode) {
      processStarted = false
      phaseTimeout.stop()
      drainWatchdog.stop()
      speedProcess.running = false
      root.launchRequested = false
      if (shutdownRequested) {
        finishShutdown()
        return
      }
      if (runState === "cancelled") {
        finishAbort()
        return
      }
      if (exitCode !== 0 || runState !== "complete"
          || pendingMeasurement === null || pendingInput === null
          || pendingFingerprint === "" || pendingRunToken === "") {
        abortRun("process-exited")
        return
      }
      if (pendingFingerprint !== root.inputFingerprint) {
        abortRun("route-changed")
        return
      }
      if (!Model.measurementMatches(
          pendingInput, pendingDirection, pendingRunToken,
          pendingMeasurement)) {
        abortRun("invalid-result")
        return
      }
      if (pendingDirection === "down") {
        downloadMeasurement = pendingMeasurement
        resetPhaseState()
        runState = "idle"
        uploadContinuation.expectedRunId = root.runId
        uploadContinuation.restart()
        return
      }
      const next = Model.result(
        pendingInput, root.runId, pendingRunToken,
        downloadMeasurement, pendingMeasurement)
      if (!next) {
        abortRun("invalid-result")
        return
      }
      bumpGeneration()
      next.schemaVersion = root.schemaVersion
      next.generation = root.generation
      publishedResult = next
      publishedFingerprint = pendingFingerprint
      lastError = ""
      abortError = ""
      clearOwnerRecord(true)
      resetRunState()
      runState = "idle"
      root.phase = "succeeded"
    }

    function finishShutdown() {
      uploadContinuation.stop()
      uploadContinuation.expectedRunId = 0
      phaseTimeout.stop()
      drainWatchdog.stop()
      clearOwnerRecord(true)
      resetRunState()
      runState = "idle"
      root.launchRequested = false
      publishedResult = null
      publishedFingerprint = ""
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
      clearOwnerRecord(true)
      publishedResult = null
      publishedFingerprint = ""
      if (speedProcess.running || root.launchRequested) {
        root.phase = "draining"
        abortRun("")
      } else finishShutdown()
    }

    function destroying() {
      const hadWorker = speedProcess.running || root.launchRequested
      uploadContinuation.stop()
      uploadContinuation.expectedRunId = 0
      phaseTimeout.stop()
      drainWatchdog.stop()
      clearOwnerRecord(true)
      if (speedProcess.running && canSignalProcess()) speedProcess.signal(9)
      speedProcess.running = false
      if (hadWorker) Authority.block(authorityClaim)
      else Authority.release(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
    }
  }

  Process {
    id: speedProcess
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => implementation.ingestChunk(data)
    }
    onStarted: implementation.processStartedEvent()
    onExited: (exitCode, _exitStatus) => implementation.processExited(exitCode)
    onRunningChanged: {
      if (speedProcess.running) return
      implementation.processStarted = false
      drainWatchdog.stop()
      if (implementation.shutdownRequested)
        implementation.finishShutdown()
      else if (implementation.runState === "cancelled")
        implementation.finishAbort()
      else if (root.launchRequested)
        implementation.abortRun("start-failed")
    }
  }

  Component.onCompleted: if (root.active)
    implementation.claimAuthority()
  Component.onDestruction: implementation.destroying()
}
