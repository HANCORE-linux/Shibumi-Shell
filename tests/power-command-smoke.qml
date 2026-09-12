pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "powerState" as PowerState

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property int completions: 0
  property bool lastOk: false
  property string lastOutput: ""
  property double waitSince: 0
  property bool revokeOnIdle: false
  property bool cancelOnBusy: false
  FileView {
    id: marker
    path: Quickshell.env("SHIBUMI_POWER_SCOPE_DIR") + "/startup"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
  }
  QtObject { id: scope }
  PowerState.PowerCommand {
    id: command
    admitted: true
    lease: scope
    timeoutMs: 150
    onBusyChanged: {
      if (!busy && root.revokeOnIdle) { root.revokeOnIdle = false; generation++ }
      if (busy && root.cancelOnBusy) { root.cancelOnBusy = false; cancel() }
    }
    onCompleted: function(output, ok) {
      root.completions++; root.lastOk = ok; root.lastOutput = output
    }
  }
  function check(value, message) {
    if (value) return
    console.error("power-command:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  function simulatedRun() {
    command.operation = { lease: scope, generation: command.generation, cancelled: false,
      started: true, exited: false, collected: false, output: "old", ok: true, failed: false }
  }
  Timer {
    interval: 30; repeat: true; running: true
    onTriggered: {
      root.check(++root.ticks < 150, "deadline phase " + root.phase)
      if (root.phase === 0) {
        root.simulatedRun()
        command.cancel()
      } else if (root.phase === 1) {
        root.check(command.busy && !command.start(["/usr/bin/true"]), "cancel drained before exit")
        command.operation.exited = true
        command.finish()
      } else if (root.phase === 2) {
        root.check(command.busy && root.completions === 0, "cancel drained before collector")
        command.operation.collected = true
        command.finish()
      } else if (root.phase === 3) {
        root.check(!command.busy && root.completions === 0, "cancel published")
        root.simulatedRun()
        command.failOperation()
      } else if (root.phase === 4) {
        root.check(command.busy, "timeout drained before callbacks")
        command.operation.collected = true
        command.finish()
      } else if (root.phase === 5) {
        root.check(command.busy, "timeout drained before exit")
        command.operation.exited = true
        command.finish()
      } else if (root.phase === 6) {
        root.check(!command.busy && root.completions === 1 && !root.lastOk, "timeout result")
        root.check(command.start(["/usr/bin/printf", "new"]), "replacement launch")
      } else if (root.phase === 7) {
        if (command.busy) return
        root.check(root.completions === 2 && root.lastOk && root.lastOutput === "new", "replacement contaminated")
        root.check(command.start([decodeURIComponent(String(Qt.resolvedUrl("missing-helper")).substring(7))]), "failed-start queue")
      } else if (root.phase === 8) {
        if (command.busy) return
        root.check(root.completions === 3 && !root.lastOk, "failed start latched")
        root.check(command.start(["/usr/bin/python3", "-I", "-c", "import time; time.sleep(10)"]), "timeout queue")
      } else if (root.phase === 9) {
        if (command.busy) return
        root.check(root.completions === 4 && !root.lastOk && !command.processRunning, "owned timeout failed")
        root.check(command.start(["/usr/bin/printf", "restored"]), "restored queue")
      } else if (root.phase === 10) {
        if (command.busy) return
        root.check(root.completions === 5 && root.lastOk && root.lastOutput === "restored", "restored result")
        command.timeoutMs = 1500
        root.check(command.start(["/usr/bin/python3", "-I", "-c",
          "import pathlib,sys,time; time.sleep(.4); pathlib.Path(sys.argv[1]).write_text('survived')",
          marker.path]), "startup cancel launch")
        root.check(!command.operation.started, "startup cancel missed starting window")
        command.cancel()
        root.waitSince = Date.now()
      } else if (root.phase === 11) {
        if (Date.now() - root.waitSince < 800) return
        marker.reload()
        root.check(!command.busy && marker.text() === "" && root.completions === 5,
          "cancel during startup left helper active")
        root.check(command.start(["/usr/bin/python3", "-I", "-c",
          "import pathlib,sys,time; time.sleep(.4); pathlib.Path(sys.argv[1]).write_text('survived')",
          marker.path]), "startup timeout launch")
        root.check(!command.operation.started, "startup timeout missed starting window")
        command.failOperation()
        root.waitSince = Date.now()
      } else if (root.phase === 12) {
        if (Date.now() - root.waitSince < 800) return
        marker.reload()
        root.check(!command.busy && marker.text() === "" && root.completions === 6 && !root.lastOk,
          "timeout during startup left helper active")
        root.simulatedRun()
        command.operation.exited = true
        command.operation.collected = true
        root.revokeOnIdle = true
        command.finish()
        root.check(!command.busy && root.completions === 6,
          "revoked idle transition published old completion")
      } else if (root.phase === 13) {
        root.cancelOnBusy = true
        var accepted = command.start(["/usr/bin/python3", "-I", "-c",
          "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text('survived')", marker.path])
        root.check(!accepted && !command.processRunning,
          "pre-dispatch cancellation still started helper")
        root.waitSince = Date.now()
      } else {
        if (Date.now() - root.waitSince < 350) return
        marker.reload()
        root.check(!command.busy && marker.text() === "" && root.completions === 6,
          "pre-dispatch cancellation left side effect")
        console.log("power command smoke passed")
        Qt.exit(0)
        return
      }
      root.phase++
    }
  }
}
