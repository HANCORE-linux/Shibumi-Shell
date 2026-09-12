pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// One bounded read-only helper. Its child is IPC-only, not another shell.
Item {
  id: root
  required property bool admitted
  required property var sourceToken
  required property string shellDirectory
  property var operation: null
  property bool _busy: false
  readonly property alias busy: root._busy
  signal completed(int serial, string output, bool ok)
  signal drained(int serial)

  function helperPath() {
    var url = String(Qt.resolvedUrl("manager/shibumi-native-catalog"))
    if (url.indexOf("file:///") !== 0) return ""
    try { return decodeURIComponent(url.slice(7)) } catch (_) { return "" }
  }

  function current(op) {
    return operation === op && !op.cancelled && admitted && sourceToken !== null
      && op.owner === sourceToken && op.directory === shellDirectory
      && op.shellProcessId === Number(Quickshell.processId)
  }

  function start(serial) {
    if (!admitted || sourceToken === null || busy || operation || worker.running
        || !Number.isInteger(serial) || serial <= 0 || shellDirectory === "") return false
    var helper = helperPath()
    if (!helper) return false
    var processId = Number(Quickshell.processId)
    if (!Number.isInteger(processId) || processId <= 1) return false
    var op = { serial: serial, owner: sourceToken, directory: shellDirectory,
      shellProcessId: processId,
      started: false, exited: false, collected: false, cancelled: false,
      hardCancel: false, output: "", ok: false }
    operation = op
    _busy = true
    if (!current(op)) { cancel(); return false }
    worker.command = ["/usr/bin/python3", "-I", "-S", helper,
      "--shell", shellDirectory, "--pid", String(processId)]
    if (!current(op)) { cancel(); return false }
    deadline.restart()
    if (!current(op)) { cancel(); return false }
    worker.running = true
    Qt.callLater(finish)
    return true
  }

  function stopWorker() {
    if (worker.running && Number(worker.processId) > 0)
      worker.signal(operation && operation.hardCancel ? 9 : 15)
  }

  function forceStop() {
    if (operation) operation.hardCancel = true
    if (worker.running && Number(worker.processId) > 0) worker.signal(9)
  }

  function cancel() {
    if (operation) {
      var first = !operation.cancelled
      operation.cancelled = true
      operation.output = ""
      deadline.stop()
      if (first) cancellationDeadline.restart()
    }
    stopWorker()
    Qt.callLater(finish)
  }

  function finish() {
    var op = operation
    if (!op || worker.running || (op.started && (!op.exited || !op.collected))) return
    var publish = current(op)
    deadline.stop()
    cancellationDeadline.stop()
    operation = null
    _busy = false
    // Busy notifications can replace the owner or request before completion.
    if (publish && admitted && op.owner === sourceToken && op.directory === shellDirectory)
      completed(op.serial, op.output, op.started && op.ok)
    drained(op.serial)
  }

  onAdmittedChanged: if (!admitted) cancel()
  onSourceTokenChanged: cancel()
  onShellDirectoryChanged: cancel()
  // Destruction can force QProcess SIGKILL. The helper's separate custodian
  // retains and kills the entire owned group even when its launcher disappears.
  Component.onDestruction: forceStop()

  Process {
    id: worker
    onStarted: {
      var op = root.operation
      if (op) op.started = true
      if (!op || !root.current(op)) root.stopWorker()
    }
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
        // Acquisition is already bounded to 256 KiB in the trusted helper.
        root.operation.output = text.length <= 262144 ? text : ""
        root.operation.collected = true
        Qt.callLater(root.finish)
      }
    }
  }
  Timer {
    id: deadline
    interval: 5000
    onTriggered: root.cancel()
  }
  Timer {
    id: cancellationDeadline
    interval: 1500
    onTriggered: root.forceStop()
  }
}
