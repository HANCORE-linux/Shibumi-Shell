pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "NetworkEnterpriseModel.js" as Model
import "NetworkEnterpriseAuthority.js" as Authority

// Process-wide Enterprise Wi-Fi mutation seam. Credentials cross
// only one bounded stdin frame and are cleared when the worker starts. The
// helper creates a volatile PEAP/MSCHAPv2 NetworkManager activation; Shibumi
// does not persist, publish, or log credentials.
Item {
  id: root

  property bool active: false
  property var networkAdapter: null
  property var commandOverride: null
  property int workerTimeoutMs: 23000
  property int drainTimeoutMs: 1000

  readonly property int schemaVersion: Model.SchemaVersion
  readonly property string helperPath:
    String(Qt.resolvedUrl("scripts/network-enterprise-connect"))
      .replace(/^file:\/\//, "")
  readonly property bool authorized: implementation.authorized
  readonly property bool running: enterpriseProcess.running
    || root.launchRequested
  readonly property bool available: root.active && root.authorized
    && !implementation.shutdownRequested && !root.running
    && root.networkAdapter !== null
  readonly property string phase: implementation.phase
  readonly property string lastDispatchToken: implementation.lastDispatchToken
  readonly property string lastDispatchDeviceId: implementation.lastDispatchDeviceId
  readonly property string lastDispatchEntityId: implementation.lastDispatchEntityId
  readonly property real lastDispatchGeneration: implementation.lastDispatchGeneration
  readonly property string lastDispatchHardwareAddress:
    implementation.lastDispatchHardwareAddress
  readonly property string lastDispatchInterfaceName:
    implementation.lastDispatchInterfaceName
  readonly property string lastDispatchSecurity:
    implementation.lastDispatchSecurity
  readonly property string lastDispatchSsidHex: implementation.lastDispatchSsidHex
  readonly property var completionSnapshot: implementation.completionSnapshot
  readonly property real completionGeneration:
    implementation.completionGeneration
  property bool launchRequested: false

  signal launchFailed(string entityId, real generation)

  property QtObject authorityGuard: QtObject {
    property bool authorityAlive: true
    property int claim: 0
  }

  visible: false
  width: 0
  height: 0

  function connectNetworkEnterprise(request, credentials) {
    return implementation.dispatch(request, credentials)
  }
  function releaseCompletion(requestToken) {
    return implementation.releaseCompletion(requestToken)
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
    id: launchWatchdog
    interval: 2000
    repeat: false
    onTriggered: implementation.prestartTimedOut()
  }

  Timer {
    id: workerTimeout
    interval: Math.max(1000, Math.min(30000, root.workerTimeoutMs))
    repeat: false
    onTriggered: implementation.stopWorker()
  }

  Timer {
    id: drainWatchdog
    interval: Math.max(250, Math.min(5000, root.drainTimeoutMs))
    repeat: false
    onTriggered: {
      if (!enterpriseProcess.running) return
      if (implementation.canSignalProcess()) enterpriseProcess.signal(9)
      enterpriseProcess.running = false
      if (enterpriseProcess.running && !implementation.canSignalProcess())
        drainWatchdog.restart()
    }
  }

  QtObject {
    id: implementation

    property bool authorized: false
    property int authorityClaim: 0
    property int nextRequestSequence: 1
    property bool shutdownRequested: false
    property bool processStarted: false
    property bool mutationPossible: false
    property string inputLine: ""
    property string pendingEntityId: ""
    property real pendingGeneration: 0
    property string phase: "inactive"
    property string lastDispatchToken: ""
    property string lastDispatchDeviceId: ""
    property string lastDispatchEntityId: ""
    property real lastDispatchGeneration: 0
    property string lastDispatchHardwareAddress: ""
    property string lastDispatchInterfaceName: ""
    property string lastDispatchSecurity: ""
    property string lastDispatchSsidHex: ""
    property var completionSnapshot: null
    property real completionGeneration: 0
    property string stdoutBuffer: ""
    property var pendingCompletion: null
    property bool outputInvalid: false

    function bumpCompletionGeneration() {
      if (completionGeneration < Model.MaxSafeInteger) completionGeneration++
    }

    function clearCompletion() {
      if (completionSnapshot !== null) {
        completionSnapshot = null
        bumpCompletionGeneration()
      }
    }

    function releaseCompletion(requestToken) {
      if (!completionSnapshot
          || completionSnapshot.requestToken !== requestToken) return false
      clearCompletion()
      return true
    }

    function canSignalProcess() {
      const pid = Number(enterpriseProcess.processId)
      return processStarted && isFinite(pid) && pid > 0
        && Math.floor(pid) === pid
    }

    function requestData(request) {
      try {
        if (!request || typeof request !== "object" || Array.isArray(request))
          return null
        const keys = Reflect.ownKeys(request)
        if (keys.length !== 2 || keys.indexOf("entityId") < 0
            || keys.indexOf("generation") < 0) return null
        const entityDescriptor = Object.getOwnPropertyDescriptor(
          request, "entityId")
        const generationDescriptor = Object.getOwnPropertyDescriptor(
          request, "generation")
        if (!entityDescriptor || !generationDescriptor) return null
        const entityId = "value" in entityDescriptor
          ? entityDescriptor.value : entityDescriptor.get.call(request)
        const generation = "value" in generationDescriptor
          ? generationDescriptor.value : generationDescriptor.get.call(request)
        return typeof entityId === "string" && entityId !== ""
            && typeof generation === "number" && isFinite(generation)
            && generation >= 0 && Math.floor(generation) === generation
          ? { entityId: entityId, generation: generation } : null
      } catch (error) {
        return null
      }
    }

    function result(ok, code, request) {
      return Model.dispatchResult(ok, code,
        request ? request.entityId : "", request ? request.generation : 0)
    }

    function nextToken() {
      const value = "shibumi-enterprise-v1:" + JSON.stringify([
        authorityClaim, nextRequestSequence
      ])
      nextRequestSequence++
      if (nextRequestSequence > Model.MaxSafeInteger) nextRequestSequence = 1
      return Model.validRequestToken(value) ? value : ""
    }

    function workerCommand() {
      try {
        if (root.commandOverride !== null) {
          if (!Array.isArray(root.commandOverride)
              || root.commandOverride.length < 1
              || root.commandOverride.length > 8) return null
          const command = []
          for (let index = 0; index < root.commandOverride.length; index++) {
            const value = root.commandOverride[index]
            if (typeof value !== "string" || value === ""
                || value.indexOf("\u0000") >= 0
                || Model.utf8Length(value, 1024) < 1) return null
            command.push(value)
          }
          return command
        }
        const adapter = root.networkAdapter
        if (!adapter || !("backendOverride" in adapter)
            || adapter.backendOverride !== null) return null
        return ["/usr/bin/python3", "-I", root.helperPath]
      } catch (error) {
        return null
      }
    }

    function descriptor(request) {
      try {
        const adapter = root.networkAdapter
        if (!adapter || typeof adapter.enterpriseConnectionDescriptor
            !== "function") return null
        const value = adapter.enterpriseConnectionDescriptor({
          entityId: request.entityId,
          generation: request.generation
        })
        return Model.descriptorResult(
          value, request.entityId, request.generation) ? value.descriptor : null
      } catch (error) {
        return null
      }
    }

    function dispatch(request, credentials) {
      const safeRequest = requestData(request)
      if (!safeRequest) return result(false, "invalid", null)
      if (!root.available) return result(false, "unavailable", safeRequest)
      const command = workerCommand()
      if (!command) return result(false, "unavailable", safeRequest)
      const safeCredentials = Model.cloneCredentials(credentials)
      if (!safeCredentials) return result(false, "invalid", safeRequest)
      const safeDescriptor = descriptor(safeRequest)
      if (!safeDescriptor) return result(false, "unavailable", safeRequest)
      const token = nextToken()
      const line = Model.payloadLine(safeDescriptor, safeCredentials, token)
      if (line === "") return result(false, "invalid", safeRequest)
      clearCompletion()
      inputLine = line
      lastDispatchToken = token
      lastDispatchDeviceId = safeDescriptor.deviceId
      lastDispatchEntityId = safeDescriptor.entityId
      lastDispatchGeneration = safeDescriptor.generation
      lastDispatchHardwareAddress = safeDescriptor.hardwareAddress
      lastDispatchInterfaceName = safeDescriptor.interfaceName
      lastDispatchSecurity = safeDescriptor.security
      lastDispatchSsidHex = safeDescriptor.ssidHex
      pendingEntityId = safeRequest.entityId
      pendingGeneration = safeRequest.generation
      processStarted = false
      mutationPossible = false
      phase = "starting"
      root.launchRequested = true
      enterpriseProcess.stdinEnabled = true
      enterpriseProcess.command = command
      enterpriseProcess.running = true
      launchWatchdog.restart()
      return result(true, "accepted", safeRequest)
    }

    function ingestChunk(chunk) {
      if (outputInvalid || pendingCompletion !== null
          || typeof chunk !== "string") {
        outputInvalid = true
        return false
      }
      const remainingCharacters = Model.MaxCompletionBytes + 1
        - stdoutBuffer.length
      if (chunk.length > remainingCharacters) {
        outputInvalid = true
        stdoutBuffer = ""
        return false
      }
      const combined = stdoutBuffer + chunk
      if (Model.utf8Length(combined, Model.MaxCompletionBytes + 1) < 0) {
        outputInvalid = true
        stdoutBuffer = ""
        return false
      }
      const newline = combined.indexOf("\n")
      if (newline < 0) {
        stdoutBuffer = combined
        return true
      }
      if (newline !== combined.length - 1
          || combined.indexOf("\n", newline + 1) >= 0) {
        outputInvalid = true
        stdoutBuffer = ""
        return false
      }
      const parsed = Model.parseCompletionLine(combined.slice(0, -1))
      stdoutBuffer = ""
      if (!parsed.ok) {
        outputInvalid = true
        return false
      }
      pendingCompletion = parsed.snapshot
      return true
    }

    function processStartedEvent() {
      launchWatchdog.stop()
      processStarted = true
      if (!root.launchRequested || inputLine === "") {
        stopWorker()
        return
      }
      const line = inputLine
      inputLine = ""
      root.launchRequested = false
      mutationPossible = true
      phase = "dispatching"
      enterpriseProcess.write(line + "\n")
      enterpriseProcess.stdinEnabled = false
      workerTimeout.restart()
    }

    function prestartTimedOut() {
      if (!root.launchRequested || processStarted) return
      const entityId = pendingEntityId
      const generation = pendingGeneration
      inputLine = ""
      root.launchRequested = false
      enterpriseProcess.running = false
      resetPending()
      phase = root.active && authorized ? "idle" : "inactive"
      root.launchFailed(entityId, generation)
    }

    function emitLaunchFailure() {
      const entityId = pendingEntityId
      const generation = pendingGeneration
      resetPending()
      phase = root.active && authorized ? "idle" : "inactive"
      root.launchFailed(entityId, generation)
    }

    function resetPending() {
      launchWatchdog.stop()
      workerTimeout.stop()
      drainWatchdog.stop()
      inputLine = ""
      pendingEntityId = ""
      pendingGeneration = 0
      processStarted = false
      mutationPossible = false
      stdoutBuffer = ""
      pendingCompletion = null
      outputInvalid = false
      root.launchRequested = false
      enterpriseProcess.stdinEnabled = true
    }

    function processExited(exitCode) {
      const wasPossible = mutationPossible
      const entityId = pendingEntityId
      const generation = pendingGeneration
      const completion = pendingCompletion
      const completionValid = exitCode === 0 && !outputInvalid
        && Model.completionMatches(completion,
          lastDispatchToken, lastDispatchSsidHex, lastDispatchDeviceId,
          lastDispatchEntityId, lastDispatchGeneration,
          lastDispatchHardwareAddress, lastDispatchInterfaceName,
          lastDispatchSecurity)
      resetPending()
      if (shutdownRequested) {
        finishShutdown()
        return
      }
      phase = root.active && authorized ? "idle" : "inactive"
      if (completionValid) {
        completionSnapshot = completion
        bumpCompletionGeneration()
      }
      // Once stdin was written, any negative worker outcome is uncertain and
      // remains owned by NetworkActionCoordinator until snapshot completion or
      // timeout. Only a pre-start failure can safely release that action.
      if (!wasPossible) root.launchFailed(entityId, generation)
    }

    function startFailed() {
      if (!root.launchRequested || processStarted) return
      emitLaunchFailure()
      if (shutdownRequested) finishShutdown()
    }

    function stopWorker() {
      launchWatchdog.stop()
      workerTimeout.stop()
      if (enterpriseProcess.running) {
        if (canSignalProcess()) enterpriseProcess.signal(15)
        enterpriseProcess.running = false
        drainWatchdog.restart()
      }
      root.launchRequested = false
      inputLine = ""
      phase = shutdownRequested ? "draining" : "settling"
      if (!enterpriseProcess.running) {
        if (shutdownRequested) finishShutdown()
        else processExited()
      }
    }

    function claimAuthority() {
      if (!root.active || shutdownRequested || authorized) return authorized
      authorityClaim = Authority.claim(root.authorityGuard)
      root.authorityGuard.claim = authorityClaim
      authorized = authorityClaim > 0
      phase = authorized ? "idle" : "standby"
      return authorized
    }

    function finishShutdown() {
      resetPending()
      clearCompletion()
      lastDispatchToken = ""
      lastDispatchDeviceId = ""
      lastDispatchEntityId = ""
      lastDispatchGeneration = 0
      lastDispatchHardwareAddress = ""
      lastDispatchInterfaceName = ""
      lastDispatchSecurity = ""
      lastDispatchSsidHex = ""
      Authority.release(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
      shutdownRequested = false
      phase = "inactive"
      if (root.active) claimAuthority()
    }

    function shutdown() {
      if (shutdownRequested) return
      shutdownRequested = true
      phase = "draining"
      if (enterpriseProcess.running || root.launchRequested) stopWorker()
      else finishShutdown()
    }

    function destroying() {
      const hadWorker = enterpriseProcess.running || root.launchRequested
      launchWatchdog.stop()
      workerTimeout.stop()
      drainWatchdog.stop()
      inputLine = ""
      if (enterpriseProcess.running && canSignalProcess())
        enterpriseProcess.signal(9)
      enterpriseProcess.running = false
      if (hadWorker) Authority.block(authorityClaim)
      else Authority.release(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
    }
  }

  Process {
    id: enterpriseProcess
    command: []
    stdinEnabled: true
    clearEnvironment: true
    environment: ({ LANG: "C", LC_ALL: "C", PATH: "/usr/bin" })
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => implementation.ingestChunk(data)
    }
    onStarted: implementation.processStartedEvent()
    onExited: (exitCode, _exitStatus) => implementation.processExited(exitCode)
    onRunningChanged: {
      if (enterpriseProcess.running) return
      implementation.processStarted = false
      drainWatchdog.stop()
      if (root.launchRequested) implementation.startFailed()
      else if (implementation.shutdownRequested) implementation.finishShutdown()
    }
  }

  Component.onCompleted: if (root.active)
    implementation.claimAuthority()
  Component.onDestruction: implementation.destroying()
}
