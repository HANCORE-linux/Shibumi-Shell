pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Keep the one child and its busy guard alive across service replacement.
// An authorized pkexec may no longer accept our signal; only exit releases it.
Scope {
  id: root

  property QtObject owner: null
  property bool busy: false
  property bool started: false
  property bool finishing: false
  property string error: ""
  property real beforeMiB: -1
  property real afterMiB: -1

  function clearResult() {
    if (busy) return
    error = ""
    beforeMiB = -1
    afterMiB = -1
  }

  function start(source, command, before) {
    if (busy || !source || !source.sweepOwnerActive) return false
    clearResult()
    owner = source
    beforeMiB = before
    started = false
    busy = true
    // A synchronous observer may revoke admission while busy is published.
    if (owner !== source || !source.sweepOwnerActive) {
      release(source)
      busy = false
      return false
    }
    worker.command = command
    worker.running = true
    return true
  }

  function release(source) {
    if (owner === source) owner = null
  }

  onOwnerChanged: {
    if (owner || !busy || finishing) return
    error = "Sweep owner changed"
    if (worker.running) worker.signal(15)
  }

  function finish(source, exitCode, exitStatus) {
    if (!busy) return
    if (source) {
      error = exitStatus === 0 && exitCode === 126 ? "cancelled"
        : exitStatus !== 0 || exitCode !== 0
          ? "Sweep failed (exit " + exitCode + ")" : ""
      const fresh = source.readMemoryNow()
      if (owner === source) {
        if (fresh) afterMiB = source.memAvailableMiB
        else if (!error) error = "Could not read fresh memory data"
      }
    }
    finishing = true
    owner = null
    finishing = false
    // Publish availability last: an observer may immediately request a run.
    busy = false
  }

  Process {
    id: worker
    onStarted: {
      root.started = true
      if (!root.owner) worker.signal(15)
    }
    onRunningChanged: if (!running && root.busy && !root.started)
      root.finish(root.owner, -1, 1)
    onExited: function(exitCode, exitStatus) { root.finish(root.owner, exitCode, exitStatus) }
  }
}
