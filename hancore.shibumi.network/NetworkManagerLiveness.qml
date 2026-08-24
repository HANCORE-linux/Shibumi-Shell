pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "NetworkLivenessModel.js" as Model
import "NetworkLivenessAuthority.js" as Authority

// Process-wide, read-only NetworkManager owner watcher. It never calls a
// NetworkManager feature method. A monitoring gap or owner loss after this
// Quickshell backend generation became usable is terminal for that generation:
// reacquisition remains fail-closed until the complete Quickshell/QML engine
// process is restarted. Soft QML reloads and same-process component handoffs
// stay blocked because Quickshell Networking is a process-lifetime singleton.
Item {
  id: root

  property bool active: false
  property var watcherOverride: null
  property var commandOverride: null
  property var continuityState: null
  property int startupTimeoutMs: 3000
  property int restartDelayMs: 1000

  property real generation: 0
  property bool helperReady: false
  property bool servicePresent: false
  property bool recoveryBlocked: false
  property bool everUsable: false
  property bool monitorEstablished: false
  property int lastSequence: 0
  property string phase: "inactive"
  property bool launchRequested: false

  readonly property bool authorized: root.watcherOverride !== null
    ? root.active : implementation.authorized
  readonly property int schemaVersion: Model.SchemaVersion
  readonly property bool serviceUsable: root.active && root.helperReady
    && root.servicePresent && !root.recoveryBlocked
  readonly property bool workerRunning: watcherProcess.running
  readonly property bool processRestartRequired:
    root.continuityState !== null
      && root.continuityState.processRestartRequired === true
  readonly property var livenessSnapshot: ({
    schemaVersion: root.schemaVersion,
    available: root.serviceUsable,
    present: root.servicePresent,
    recoveryBlocked: root.recoveryBlocked,
    processRestartRequired: root.processRestartRequired,
    phase: root.phase,
    generation: root.generation
  })
  property QtObject authorityGuard: QtObject {
    property bool authorityAlive: true
    property int claim: 0
    property bool continuityTainted: false
    Component.onDestruction: Authority.retire(claim, continuityTainted)
  }

  visible: false
  width: 0
  height: 0

  onActiveChanged: {
    if (active) implementation.startTransport()
    else implementation.stopTransport()
  }

  onWatcherOverrideChanged: {
    if (!root.active) return
    implementation.releaseAuthority()
    implementation.transportFailure("watcher-replaced")
  }

  onServiceUsableChanged: {
    if (serviceUsable) {
      everUsable = true
      root.authorityGuard.continuityTainted = true
    }
  }

  function ingestProtocolLine(line) {
    return implementation.ingestProtocolLine(line)
  }

  Timer {
    interval: 250
    repeat: true
    running: root.active && root.watcherOverride === null
      && !implementation.authorized
    onTriggered: implementation.claimAuthority()
  }

  QtObject {
    id: implementation

    property bool authorized: false
    property int authorityClaim: 0

    function bumpGeneration() {
      if (root.generation < Model.MaxSequence) root.generation++
    }

    function blockRecovery() {
      root.recoveryBlocked = true
      root.authorityGuard.continuityTainted = true
      if (root.continuityState !== null
          && "processRestartRequired" in root.continuityState)
        root.continuityState.processRestartRequired = true
      setPhase()
      bumpGeneration()
    }

    function setPhase() {
      if (!root.active) root.phase = "inactive"
      else if (root.recoveryBlocked && root.servicePresent)
        root.phase = "recovery-blocked"
      else if (!root.helperReady) root.phase = "starting"
      else if (!root.servicePresent) root.phase = "absent"
      else root.phase = "available"
    }

    function beginRun() {
      root.helperReady = false
      root.servicePresent = false
      root.lastSequence = 0
      setPhase()
      startupTimer.restart()
      bumpGeneration()
    }

    function claimAuthority() {
      if (!root.active || root.watcherOverride !== null || authorized) return
      if (root.continuityState === null
          || typeof root.continuityState.processRestartRequired !== "boolean") {
        root.phase = "continuity-unavailable"
        return
      }
      const result = Authority.claim(root.authorityGuard)
      if (!result || typeof result.token !== "number" || result.token <= 0) {
        root.phase = "standby"
        return
      }
      authorized = true
      authorityClaim = result.token
      root.authorityGuard.claim = result.token
      if (result.continuityBlocked === true
          || root.continuityState.processRestartRequired === true)
        blockRecovery()
      root.launchRequested = true
      setPhase()
      bumpGeneration()
    }

    function releaseAuthority() {
      if (!authorized) return
      const token = authorityClaim
      authorized = false
      authorityClaim = 0
      root.authorityGuard.claim = 0
      Authority.retire(token, root.monitorEstablished)
    }

    function startTransport() {
      retryTimer.stop()
      if (root.watcherOverride !== null) {
        root.launchRequested = false
        beginRun()
      } else {
        claimAuthority()
      }
    }

    function stopTransport() {
      startupTimer.stop()
      retryTimer.stop()
      root.launchRequested = false
      if (root.monitorEstablished) blockRecovery()
      root.helperReady = false
      root.servicePresent = false
      root.lastSequence = 0
      releaseAuthority()
      setPhase()
      bumpGeneration()
    }

    function scheduleRestart() {
      if (!root.active) return
      if (root.watcherOverride !== null) {
        beginRun()
        return
      }
      retryTimer.restart()
    }

    function transportFailure(_reason) {
      startupTimer.stop()
      root.launchRequested = false
      if (root.monitorEstablished) blockRecovery()
      root.helperReady = false
      root.servicePresent = false
      root.lastSequence = 0
      root.phase = "failed"
      bumpGeneration()
      scheduleRestart()
    }

    function rejectProtocol() {
      transportFailure("invalid-protocol")
      return false
    }

    function ingestProtocolLine(line) {
      if (!root.active) return false
      const record = Model.parseLine(line)
      if (!record.ok) return rejectProtocol()

      if (!root.helperReady) {
        if (record.event !== "snapshot" || record.sequence !== 1)
          return rejectProtocol()
        startupTimer.stop()
        root.lastSequence = record.sequence
        root.servicePresent = record.present
        root.helperReady = true
        root.monitorEstablished = true
        root.authorityGuard.continuityTainted = true
        setPhase()
        bumpGeneration()
        return true
      }

      if (record.event !== "owner"
          || record.sequence !== root.lastSequence + 1)
        return rejectProtocol()
      if (record.replacement) {
        if (!root.servicePresent || !record.present)
          return rejectProtocol()
      } else if (record.present === root.servicePresent) {
        return rejectProtocol()
      }

      root.lastSequence = record.sequence
      if (root.everUsable
          && (!record.present || record.replacement))
        blockRecovery()
      root.servicePresent = record.present
      setPhase()
      bumpGeneration()
      return true
    }
  }

  Connections {
    target: root.continuityState
    ignoreUnknownSignals: true

    function onProcessRestartRequiredChanged() {
      if (root.processRestartRequired)
        implementation.blockRecovery()
    }
  }

  Connections {
    target: root.watcherOverride
    enabled: root.active && root.watcherOverride !== null
    ignoreUnknownSignals: true

    function onProtocolLine(line) {
      implementation.ingestProtocolLine(line)
    }

    function onTransportFailed() {
      implementation.transportFailure("override-failed")
    }
  }

  Process {
    id: watcherProcess
    running: root.launchRequested && root.active && root.authorized
      && root.watcherOverride === null
    command: Array.isArray(root.commandOverride)
      ? root.commandOverride
      : [Qt.resolvedUrl("scripts/network-manager-owner-watch")]

    stdout: SplitParser {
      onRead: data => implementation.ingestProtocolLine(data)
    }

    stderr: StdioCollector {}

    onStarted: implementation.beginRun()
    onExited: (_exitCode, _exitStatus) => {
      if (root.active && root.authorized
          && root.watcherOverride === null && root.launchRequested)
        implementation.transportFailure("watcher-exited")
    }
    onRunningChanged: {
      // Process has no failed-to-start signal in its QML API. A requested
      // worker that is still absent is therefore a transport failure too.
      if (root.active && root.authorized
          && root.watcherOverride === null && root.launchRequested
          && !watcherProcess.running)
        implementation.transportFailure("watcher-start-failed")
    }
  }

  Timer {
    id: startupTimer
    interval: Math.max(100, root.startupTimeoutMs)
    repeat: false
    onTriggered: implementation.transportFailure("startup-timeout")
  }

  Timer {
    id: retryTimer
    interval: Math.max(100, root.restartDelayMs)
    repeat: false
    onTriggered: {
      if (root.active && root.watcherOverride === null)
        root.launchRequested = true
    }
  }

  Component.onCompleted: if (root.active)
    implementation.startTransport()
  Component.onDestruction: implementation.stopTransport()
}
