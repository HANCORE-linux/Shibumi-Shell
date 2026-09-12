pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// One owned operation at a time. Admission is independent of command success.
// These are existing, trusted platform helpers; this collector is not a bounded
// acquisition interface for arbitrary files, network bodies or community code.
Item {
  id: root

  property bool admitted: false
  property var lease: null
  property int generation: 0
  property int timeoutMs: 10000
  readonly property bool busy: operation !== null
  readonly property bool processRunning: worker.running
  property var operation: null
  signal completed(string output, bool ok)
  signal settled()

  function start(command) {
    if (!admitted || lease === null || busy || !Array.isArray(command)
        || command.length === 0 || command.length > 32) return false
    for (var i = 0; i < command.length; i++) {
      if (typeof command[i] !== "string" || command[i].length > 8192
          || command[i].indexOf("\u0000") !== -1) return false
    }
    var current = { lease: lease, generation: generation, cancelled: false,
      started: false, exited: false, collected: false, output: "", ok: false, failed: false }
    operation = current
    // Busy notification is synchronous and can cancel/revoke before dispatch.
    if (operation !== current || current.cancelled || current.failed || !admitted
        || current.lease !== lease || current.generation !== generation) {
      current.cancelled = true
      Qt.callLater(finish)
      return false
    }
    worker.command = command.slice()
    deadline.restart()
    worker.running = true
    Qt.callLater(finish)
    return true // Queued launch, not an applied profile or successful probe.
  }

  function stopWorker() {
    // A starting QProcess can be running without a signalable PID yet.
    if (worker.running && Number(worker.processId) > 0) worker.signal(9)
  }

  function started() {
    var current = operation
    if (current) current.started = true
    if (!current || current.cancelled || current.failed || !admitted
        || current.lease !== lease || current.generation !== generation) stopWorker()
  }

  function cancel() {
    if (!operation) return
    operation.cancelled = true
    operation.output = ""
    stopWorker()
    Qt.callLater(finish)
  }

  function failOperation() {
    if (!operation) return
    operation.failed = true
    operation.output = ""
    stopWorker()
    Qt.callLater(finish)
  }

  function finish() {
    var current = operation
    if (!current || worker.running) return
    // Even cancelled operations retain their record until both old callbacks
    // have drained. Otherwise either callback could populate a replacement run.
    if (current.started && (!current.exited || !current.collected)) return
    var publish = !current.cancelled && admitted && current.lease === lease
      && current.generation === generation
    deadline.stop()
    operation = null
    // Clearing busy notifies consumers synchronously; it can revoke admission.
    if (publish && admitted && current.lease === lease && current.generation === generation)
      completed(current.output, current.started && current.ok && !current.failed)
    settled()
  }

  onAdmittedChanged: if (!admitted) cancel()
  onLeaseChanged: cancel()
  onGenerationChanged: cancel()
  Component.onDestruction: stopWorker()

  Process {
    id: worker
    onStarted: root.started()
    onRunningChanged: if (!running) Qt.callLater(root.finish)
    onExited: function(exitCode, exitStatus) {
      if (!root.operation) return
      root.operation.exited = true
      root.operation.ok = exitCode === 0 && exitStatus === 0
      Qt.callLater(root.finish)
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.operation) return
        // A schema/parse budget, not a pre-buffer acquisition bound.
        root.operation.output = text.length <= 65536 ? text : ""
        if (text.length > 65536) root.operation.failed = true
        root.operation.collected = true
        Qt.callLater(root.finish)
      }
    }
  }

  Timer {
    id: deadline
    interval: Math.max(100, Math.min(10000, root.timeoutMs))
    onTriggered: root.failOperation()
  }
}
