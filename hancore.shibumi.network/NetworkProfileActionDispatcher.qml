pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "NetworkProfileActionModel.js" as Model
import "NetworkProfileActionAuthority.js" as Authority

// Exact catalog-only saved-profile actions. The helper receives no settings
// map or secret and binds every D-Bus operation to one NetworkManager owner.
Item {
  id: root

  property bool active: false
  property var networkAdapter: null
  property var savedProfileCatalog: null
  property var networkTelemetry: null
  property var commandOverride: null
  property int workerTimeoutMs: 25000
  property int evidenceTimeoutMs: 30000
  property int drainTimeoutMs: 1000
  readonly property string helperPath:
    String(Qt.resolvedUrl("scripts/network-profile-action"))
      .replace(/^file:\/\//, "")

  readonly property bool authorized: implementation.authorized
  readonly property bool busy: implementation.state.phase === "pending"
    || actionProcess.running || root.launchRequested
  readonly property string phase: implementation.state.phase
  readonly property string actionKind: implementation.state.kind
  readonly property string actionEntityId: implementation.state.entityId
  readonly property string failureMessage: implementation.state.phase === "failed"
    ? implementation.state.message : ""
  readonly property var actionSnapshot: implementation.publicSnapshot()
  readonly property bool workerRunning: actionProcess.running
  readonly property bool workerStarted: implementation.processStarted
  property bool launchRequested: false
  property real generation: 0

  property QtObject authorityGuard: QtObject {
    property bool alive: true
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

  function connectProfile(request, deviceId) {
    return implementation.dispatch("connect", request, deviceId)
  }
  function forgetProfile(request) {
    return implementation.dispatch("forget", request, "")
  }
  function clearResult() {
    if (root.busy) return false
    implementation.state = implementation.idleState()
    implementation.bump()
    return true
  }

  onActiveChanged: {
    if (active) implementation.claimAuthority()
    else implementation.shutdown()
  }

  Timer {
    interval: 250
    repeat: true
    running: root.active && !root.authorized
    onTriggered: implementation.claimAuthority()
  }

  Timer {
    id: workerTimeout
    interval: Math.max(1000, Math.min(120000, root.workerTimeoutMs))
    onTriggered: implementation.timeoutAction("Saved profile worker timed out.")
  }

  Timer {
    id: evidenceTimeout
    interval: Math.max(1000, Math.min(120000, root.evidenceTimeoutMs))
    onTriggered: implementation.timeoutAction(
      "Saved profile completion evidence timed out.")
  }

  Timer {
    id: drainWatchdog
    interval: Math.max(100, Math.min(5000, root.drainTimeoutMs))
    onTriggered: {
      if (!actionProcess.running) return
      if (implementation.canSignal()) actionProcess.signal(9)
      actionProcess.running = false
      if (actionProcess.running && !implementation.canSignal()) restart()
    }
  }

  Connections {
    target: root.networkAdapter
    ignoreUnknownSignals: true
    function onGenerationChanged() { implementation.reconcile() }
  }
  Connections {
    target: root.savedProfileCatalog
    ignoreUnknownSignals: true
    function onGenerationChanged() { implementation.reconcile() }
  }

  QtObject {
    id: implementation

    property bool authorized: false
    property int authorityClaim: 0
    property int sequence: 1
    property bool processStarted: false
    property bool mutationPossible: false
    property bool shutdownRequested: false
    property string inputLine: ""
    property string stdoutBuffer: ""
    property var completion: null
    property var state: idleState()

    function idleState() {
      return {
        phase: "idle", kind: "", entityId: "", uuid: "", deviceId: "",
        interfaceName: "", hardwareAddress: "", dispatchGeneration: 0,
        requestToken: "", message: ""
      }
    }

    function publicSnapshot() {
      return {
        schemaVersion: 1,
        phase: state.phase,
        kind: state.kind === "connect" ? "connect-catalog-profile"
          : state.kind === "forget" ? "forget-catalog-profile" : "",
        entityId: state.entityId,
        uuid: state.uuid,
        deviceId: state.deviceId,
        dispatchGeneration: state.dispatchGeneration,
        message: state.message,
        generation: root.generation
      }
    }

    function bump() { root.generation++ }

    function canSignal() {
      const pid = Number(actionProcess.processId)
      return processStarted && isFinite(pid) && pid > 0
        && Math.floor(pid) === pid
    }

    function claimAuthority() {
      if (!root.active || shutdownRequested || authorized) return authorized
      authorityClaim = Authority.claim(root.authorityGuard)
      root.authorityGuard.claim = authorityClaim
      authorized = authorityClaim > 0
      return authorized
    }

    function requestData(request) {
      try {
        if (!request || typeof request !== "object" || Array.isArray(request)
            || Reflect.ownKeys(request).length !== 2) return null
        const entityId = request.entityId
        const generation = request.generation
        return typeof entityId === "string" && entityId !== ""
            && typeof generation === "number" && isFinite(generation)
            && generation >= 0 && Math.floor(generation) === generation
          ? { entityId: entityId, generation: generation } : null
      } catch (error) { return null }
    }

    function result(accepted, code, request, message) {
      return {
        accepted: accepted === true,
        code: String(code || "invalid"),
        message: String(message || ""),
        actionId: accepted ? state.requestToken : "",
        entityId: request ? request.entityId : "",
        generation: root.networkAdapter
          && typeof root.networkAdapter.generation === "number"
          ? root.networkAdapter.generation : 0
      }
    }

    function profile(entityId) {
      try {
        if (!root.savedProfileCatalog
            || root.savedProfileCatalog.available !== true
            || !root.networkAdapter
            || root.networkAdapter.savedProfileCatalogAvailable !== true)
          return null
        const rows = root.networkAdapter.savedProfileSnapshots
        let found = null
        let count = 0
        for (let index = 0; index < rows.length; index++) {
          if (rows[index] && rows[index].id === entityId) {
            found = rows[index]
            count++
          }
        }
        return count === 1 && found.profileType === "wifi" ? found : null
      } catch (error) { return null }
    }

    function device(entityId) {
      try {
        const rows = root.networkAdapter.deviceSnapshots
        let found = null
        let count = 0
        for (let index = 0; index < rows.length; index++) {
          if (rows[index] && rows[index].id === entityId) {
            found = rows[index]
            count++
          }
        }
        return count === 1 && found.type === "wifi" && found.managed === true
            && found.ambiguous === false
            && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,14}$/.test(found.name)
            && /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(found.address)
          ? found : null
      } catch (error) { return null }
    }

    function nextToken() {
      const token = "shibumi-profile-action-v1:" + JSON.stringify([
        authorityClaim, sequence
      ])
      sequence++
      if (sequence > 2147483646) sequence = 1
      return token
    }

    function command() {
      if (root.commandOverride !== null)
        return Array.isArray(root.commandOverride)
          && root.commandOverride.length > 0
          ? root.commandOverride.slice() : null
      try {
        return root.networkAdapter
            && root.networkAdapter.backendOverride === null
          ? ["/usr/bin/python3", "-I", root.helperPath] : null
      } catch (error) { return null }
    }

    function acquireEvidence() {
      if (!root.networkTelemetry || !root.savedProfileCatalog
          || root.networkTelemetry.acquire(root) !== true) return false
      if (root.savedProfileCatalog.acquire(root) === true) return true
      root.networkTelemetry.release(root)
      return false
    }

    function releaseEvidence() {
      if (root.savedProfileCatalog) root.savedProfileCatalog.release(root)
      if (root.networkTelemetry) root.networkTelemetry.release(root)
    }

    function dispatch(action, request, deviceId) {
      const safeRequest = requestData(request)
      if (!safeRequest || !root.active || !authorized || root.busy)
        return result(false, safeRequest ? "busy" : "invalid", safeRequest,
          "Saved profile action is unavailable.")
      const adapter = root.networkAdapter
      if (!adapter || adapter.backendAvailable !== true
          || safeRequest.generation !== adapter.generation)
        return result(false, "stale-generation", safeRequest,
          "Network state changed before dispatch.")
      const saved = profile(safeRequest.entityId)
      const target = action === "connect" ? device(deviceId) : null
      const workerCommand = command()
      if (!saved || action === "connect" && !target || !workerCommand
          || !acquireEvidence())
        return result(false, "unavailable", safeRequest,
          "Exact saved profile action is unavailable.")
      const descriptor = {
        action: action, uuid: saved.uuid,
        deviceId: target ? target.id : "",
        interfaceName: target ? target.name : "",
        hardwareAddress: target ? target.address : "",
        generation: safeRequest.generation
      }
      const token = nextToken()
      const line = Model.payloadLine(descriptor, token)
      if (line === "") {
        releaseEvidence()
        return result(false, "invalid", safeRequest, "Saved profile is invalid.")
      }
      state = {
        phase: "pending", kind: action, entityId: safeRequest.entityId,
        uuid: saved.uuid, deviceId: descriptor.deviceId,
        interfaceName: descriptor.interfaceName,
        hardwareAddress: descriptor.hardwareAddress,
        dispatchGeneration: safeRequest.generation,
        requestToken: token, message: ""
      }
      inputLine = line
      stdoutBuffer = ""
      completion = null
      processStarted = false
      mutationPossible = false
      root.launchRequested = true
      root.authorityGuard.workerUnsettled = true
      actionProcess.stdinEnabled = true
      actionProcess.command = workerCommand
      actionProcess.running = true
      workerTimeout.restart()
      bump()
      return result(true, "accepted", safeRequest, "")
    }

    function ingest(chunk) {
      if (typeof chunk !== "string" || completion !== null
          || stdoutBuffer.length + chunk.length > Model.MaxLine + 1)
        return false
      const combined = stdoutBuffer + chunk
      const newline = combined.indexOf("\n")
      if (newline < 0) { stdoutBuffer = combined; return true }
      if (newline !== combined.length - 1
          || combined.indexOf("\n", newline + 1) >= 0) return false
      completion = Model.parseCompletion(combined.slice(0, -1))
      stdoutBuffer = ""
      return completion !== null
    }

    function started() {
      processStarted = true
      if (!root.launchRequested || inputLine === "") { stopWorker(); return }
      const line = inputLine
      inputLine = ""
      root.launchRequested = false
      mutationPossible = true
      actionProcess.write(line + "\n")
      actionProcess.stdinEnabled = false
    }

    function exited(exitCode) {
      processStarted = false
      root.authorityGuard.workerUnsettled = false
      drainWatchdog.stop()
      workerTimeout.stop()
      actionProcess.running = false
      root.launchRequested = false
      if (shutdownRequested) {
        if (state.phase === "pending")
          terminal(false, "Saved profile action stopped.")
        finishShutdown()
        return
      }
      const descriptor = {
        action: state.kind, uuid: state.uuid, deviceId: state.deviceId,
        interfaceName: state.interfaceName,
        hardwareAddress: state.hardwareAddress,
        generation: state.dispatchGeneration
      }
      if (exitCode === 0
          && Model.completionMatches(completion, descriptor, state.requestToken)) {
        evidenceTimeout.restart()
        if (state.kind === "forget") root.savedProfileCatalog.requestRefresh()
        reconcile()
      } else if (!mutationPossible) {
        terminal(false, "Could not start saved profile action.")
      } else {
        evidenceTimeout.restart()
        if (state.kind === "forget") root.savedProfileCatalog.requestRefresh()
        reconcile()
      }
    }

    function reconcile() {
      if (state.phase !== "pending" || actionProcess.running
          || root.launchRequested) return false
      if (state.kind === "connect") {
        if (!root.networkAdapter
            || root.networkAdapter.generation <= state.dispatchGeneration
            || root.networkAdapter.activeConnectionUuidForDevice(state.deviceId)
              !== state.uuid) return false
        terminal(true, "")
        return true
      }
      if (!root.savedProfileCatalog
          || root.savedProfileCatalog.available !== true) return false
      const rows = root.savedProfileCatalog.profileSnapshots
      for (let index = 0; index < rows.length; index++)
        if (rows[index] && rows[index].uuid === state.uuid) return false
      terminal(true, "")
      return true
    }

    function timeoutAction(message) {
      stopWorker()
      terminal(false, message)
    }

    function terminal(success, message) {
      workerTimeout.stop()
      evidenceTimeout.stop()
      if (!actionProcess.running && !processStarted)
        root.authorityGuard.workerUnsettled = false
      releaseEvidence()
      state = Object.assign({}, state, {
        phase: success ? "succeeded" : "failed",
        message: String(message || "")
      })
      completion = null
      inputLine = ""
      stdoutBuffer = ""
      bump()
    }

    function stopWorker() {
      if (actionProcess.running) {
        if (canSignal()) actionProcess.signal(15)
        actionProcess.running = false
        drainWatchdog.restart()
      }
      root.launchRequested = false
      inputLine = ""
    }

    function blockShutdown() {
      Authority.block(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
      shutdownRequested = false
    }

    function finishShutdown() {
      Authority.release(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
      shutdownRequested = false
      if (root.active) claimAuthority()
    }

    function shutdown() {
      if (shutdownRequested) return
      shutdownRequested = true
      workerTimeout.stop()
      evidenceTimeout.stop()
      const hadWorker = actionProcess.running || root.launchRequested
      stopWorker()
      if (state.phase === "pending") terminal(false, "Saved profile action stopped.")
      if (!hadWorker && !actionProcess.running) finishShutdown()
    }

    function destroying() {
      const unsettled = actionProcess.running
        || root.authorityGuard.workerUnsettled
      workerTimeout.stop()
      evidenceTimeout.stop()
      drainWatchdog.stop()
      if (actionProcess.running && canSignal()) actionProcess.signal(9)
      actionProcess.running = false
      releaseEvidence()
      if (unsettled) Authority.block(authorityClaim)
      else Authority.release(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
    }
  }

  Process {
    id: actionProcess
    command: []
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => implementation.ingest(data)
    }
    stderr: StdioCollector {}
    onStarted: implementation.started()
    onExited: (code, _status) => implementation.exited(code)
    onRunningChanged: {
      if (running) return
      if (implementation.shutdownRequested) {
        if (!root.authorityGuard.workerUnsettled)
          implementation.finishShutdown()
        else if (!implementation.processStarted)
          implementation.blockShutdown()
        return
      }
      if (root.launchRequested && !implementation.processStarted)
        implementation.terminal(false, "Could not start saved profile action.")
    }
  }

  Component.onCompleted: if (root.active) implementation.claimAuthority()
  Component.onDestruction: implementation.destroying()
}
