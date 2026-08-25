pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "NetworkQrSecretModel.js" as Model
import "NetworkQrSecretAuthority.js" as Authority

// Process-wide, click-triggered reader for one exact active saved Wi-Fi PSK.
// The secret exists only in one complete-line callback and the QR encoder call.
// The resulting matrix stays staged until a clean worker exit; neither value is
// a secret property, snapshot, command argument, environment value, or log.
Item {
  id: root

  property bool active: false
  property var networkService: null
  property var nativeLiveness: null
  property var commandOverride: null
  property int workerTimeoutMs: 5000
  property int drainTimeoutMs: 1000
  readonly property string helperPath:
    String(Qt.resolvedUrl("scripts/network-qr-secret"))
      .replace(/^file:\/\//, "")

  readonly property bool authorized: implementation.authorized
  readonly property bool busy: implementation.phase === "pending"
    || secretProcess.running || root.launchRequested
  readonly property string phase: implementation.phase
  readonly property string errorCode: implementation.errorCode
  readonly property bool workerRunning: secretProcess.running
  property bool launchRequested: false

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

  function request(owner, descriptor) {
    return implementation.request(owner, descriptor)
  }
  function cancel(owner, requestToken) {
    return implementation.cancel(owner, requestToken)
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
    interval: Math.max(500, Math.min(15000, root.workerTimeoutMs))
    onTriggered: implementation.fail("timeout")
  }

  Timer {
    id: drainWatchdog
    interval: Math.max(100, Math.min(5000, root.drainTimeoutMs))
    onTriggered: {
      if (!secretProcess.running) return
      if (implementation.canSignal()) secretProcess.signal(9)
      secretProcess.running = false
      if (secretProcess.running && !implementation.canSignal()) restart()
    }
  }

  QtObject {
    id: implementation

    property bool authorized: false
    property int authorityClaim: 0
    property int sequence: 1
    property bool processStarted: false
    property bool shutdownRequested: false
    property bool completionDelivered: false
    property string phase: "idle"
    property string errorCode: ""
    property string inputLine: ""
    property string requestToken: ""
    property var pendingOwner: null
    property var pendingDescriptor: null

    function canSignal() {
      const pid = Number(secretProcess.processId)
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

    function nextToken() {
      const token = "shibumi-qr-secret-v1:" + JSON.stringify([
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
      return ["/usr/bin/python3", "-I", root.helperPath]
    }

    function publicResult(accepted, code, token) {
      return {
        accepted: accepted === true,
        code: String(code || "unavailable"),
        requestToken: accepted ? String(token || "") : ""
      }
    }

    function request(owner, descriptor) {
      const safe = Model.descriptor(descriptor)
      const workerCommand = command()
      if (!safe || !owner || typeof owner.stageSavedSecret !== "function"
          || typeof owner.commitSavedSecret !== "function"
          || typeof owner.rejectSavedSecret !== "function"
          || !root.active || !authorized || root.busy || !workerCommand
          || !root.nativeLiveness
          || root.nativeLiveness.serviceUsable !== true)
        return publicResult(false, safe ? "unavailable" : "invalid", "")
      const token = nextToken()
      const line = Model.requestLine(safe, token)
      if (line === "") return publicResult(false, "invalid", "")
      pendingOwner = owner
      pendingDescriptor = safe
      requestToken = token
      inputLine = line
      completionDelivered = false
      processStarted = false
      phase = "pending"
      errorCode = ""
      root.launchRequested = true
      root.authorityGuard.workerUnsettled = true
      secretProcess.stdinEnabled = true
      secretProcess.command = workerCommand
      secretProcess.running = true
      workerTimeout.restart()
      return publicResult(true, "accepted", token)
    }

    function started() {
      processStarted = true
      if (!root.launchRequested || inputLine === "") {
        fail("start-race")
        return
      }
      const line = inputLine
      inputLine = ""
      root.launchRequested = false
      secretProcess.write(line + "\n")
      secretProcess.stdinEnabled = false
    }

    function ingestLine(line) {
      if (typeof line !== "string" || completionDelivered) {
        fail("protocol")
        return false
      }
      let completion = Model.parseCompletion(line)
      if (!completion
          || !Model.completionMatches(
            completion, pendingDescriptor, requestToken)
          || !root.networkService
          || typeof root.networkService.qrSecretRequestCurrent !== "function"
          || root.networkService.qrSecretRequestCurrent(
            pendingDescriptor) !== true) {
        if (completion) completion.psk = ""
        fail("stale")
        return false
      }
      let psk = completion.psk
      completion.psk = ""
      const evidence = {
        requestToken: completion.requestToken,
        networkId: completion.networkId,
        profileUuid: completion.profileUuid,
        deviceId: completion.deviceId,
        interfaceName: completion.interfaceName,
        hardwareAddress: completion.hardwareAddress,
        ssidHex: completion.ssidHex,
        security: completion.security,
        generation: completion.generation
      }
      let accepted = false
      try {
        accepted = pendingOwner.stageSavedSecret(evidence, psk) === true
      } catch (error) {
        accepted = false
      }
      psk = ""
      completion = null
      if (!accepted) {
        fail("consumer-rejected")
        return false
      }
      completionDelivered = true
      phase = "staged"
      errorCode = ""
      return true
    }

    function notifyFailure(code) {
      const owner = pendingOwner
      const token = requestToken
      pendingOwner = null
      pendingDescriptor = null
      requestToken = ""
      if (!owner || typeof owner.rejectSavedSecret !== "function") return
      try { owner.rejectSavedSecret(token, String(code || "unavailable")) }
      catch (error) {}
    }

    function fail(code) {
      if (phase !== "pending" && phase !== "staged") return
      workerTimeout.stop()
      notifyFailure(code)
      phase = "failed"
      errorCode = String(code || "unavailable")
      inputLine = ""
      stopWorker()
      if (!secretProcess.running && !processStarted)
        root.authorityGuard.workerUnsettled = false
    }

    function exited(exitCode) {
      processStarted = false
      root.authorityGuard.workerUnsettled = false
      root.launchRequested = false
      workerTimeout.stop()
      drainWatchdog.stop()
      secretProcess.running = false
      if (shutdownRequested) {
        finishShutdown()
        return
      }
      if (exitCode === 0 && completionDelivered) {
        let committed = false
        try {
          committed = root.networkService
            && root.networkService.qrSecretRequestCurrent(
              pendingDescriptor) === true
            && pendingOwner
            && pendingOwner.commitSavedSecret(requestToken) === true
        } catch (error) {
          committed = false
        }
        if (committed) {
          pendingOwner = null
          pendingDescriptor = null
          requestToken = ""
          phase = "succeeded"
          errorCode = ""
        } else {
          notifyFailure("consumer-rejected")
          phase = "failed"
          errorCode = "consumer-rejected"
        }
      } else if (phase === "pending" || phase === "staged") {
        notifyFailure("unavailable")
        phase = "failed"
        errorCode = "unavailable"
      }
      inputLine = ""
      completionDelivered = false
    }

    function cancel(owner, token) {
      if (owner !== pendingOwner || token !== requestToken) return false
      notifyFailure("cancelled")
      phase = "cancelled"
      errorCode = ""
      inputLine = ""
      stopWorker()
      return true
    }

    function stopWorker() {
      if (secretProcess.running) {
        if (canSignal()) secretProcess.signal(15)
        secretProcess.running = false
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
      notifyFailure("cancelled")
      const hadWorker = secretProcess.running || root.launchRequested
      stopWorker()
      phase = "inactive"
      if (!hadWorker && !secretProcess.running) finishShutdown()
    }

    function destroying() {
      const unsettled = secretProcess.running
        || root.authorityGuard.workerUnsettled
      workerTimeout.stop()
      drainWatchdog.stop()
      notifyFailure("cancelled")
      if (secretProcess.running && canSignal()) secretProcess.signal(9)
      secretProcess.running = false
      if (unsettled) Authority.block(authorityClaim)
      else Authority.release(authorityClaim)
      authorityClaim = 0
      root.authorityGuard.claim = 0
      authorized = false
    }
  }

  Process {
    id: secretProcess
    command: []
    clearEnvironment: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: data => implementation.ingestLine(data)
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: _data => {}
    }
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
        implementation.fail("start-failed")
    }
  }

  Component.onCompleted: if (root.active) implementation.claimAuthority()
  Component.onDestruction: implementation.destroying()
}
