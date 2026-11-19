pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "NetworkTailscaleModel.js" as Model

// Process-wide Tailscale owner. Status is read from the local tailscale CLI
// only; panels lease a faster refresh cadence while they are open.
Item {
  id: root

  property bool active: true
  property var owners: []
  readonly property bool sessionActive: owners.length > 0
  property var snapshot: Model.emptySnapshot("loading")
  readonly property bool installed: snapshot.reason !== "missing"
  property string actionKind: ""
  property string errorText: ""
  readonly property bool busy: actionProcess.running
  property bool statusStarted: false
  property bool actionStarted: false

  visible: false
  width: 0
  height: 0

  function acquire(owner) {
    if (!owner || !root.active) return false
    if (owners.indexOf(owner) < 0) owners = owners.concat([owner])
    refresh()
    return true
  }

  function release(owner) {
    owners = owners.filter(function(candidate) { return candidate !== owner })
  }

  function refresh() {
    if (!root.active || statusProbe.running) return false
    statusStarted = false
    statusProbe.running = true
    return true
  }

  function runAction(kind, command) {
    if (!root.active || root.busy || snapshot.available !== true) return false
    errorText = ""
    actionKind = kind
    actionStarted = false
    actionProcess.command = command
    actionProcess.running = true
    actionDeadline.restart()
    return true
  }

  function setEnabled(enabled) {
    if (enabled && snapshot.needsLogin) {
      errorText = "Log in with 'tailscale up' in a terminal first."
      return false
    }
    return runAction(enabled ? "up" : "down",
      ["tailscale", enabled ? "up" : "down"])
  }

  function setExitNode(ip) {
    const target = Model.exitNodeTarget(snapshot, ip)
    if (target === null) return false
    return runAction("exit-node", ["tailscale", "set", "--exit-node=" + target])
  }

  function copyText(value) {
    const text = Model.copyableText(value)
    if (text === "") return false
    Quickshell.execDetached(["wl-copy", "--", text])
    return true
  }

  onActiveChanged: {
    if (!active) {
      owners = []
      actionDeadline.stop()
      if (actionProcess.running) actionProcess.running = false
    } else Qt.callLater(refresh)
  }
  Component.onCompleted: if (root.active) Qt.callLater(refresh)

  Timer {
    interval: root.sessionActive ? 5000 : 30000
    running: root.active && (root.installed || root.sessionActive)
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: actionDeadline
    interval: 20000
    onTriggered: if (actionProcess.running) {
      root.errorText = "Tailscale did not respond in time"
      actionProcess.running = false
    }
  }

  Process {
    id: statusProbe
    command: ["tailscale", "status", "--json"]
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onStarted: root.statusStarted = true
    onExited: function(exitCode) {
      root.snapshot = exitCode === 0
        ? Model.parseStatus(statusStdout.text)
        : Model.emptySnapshot(Model.probeFailure(statusStderr.text))
    }
    onRunningChanged: if (!running && !root.statusStarted)
      root.snapshot = Model.emptySnapshot("missing")
  }

  Process {
    id: actionProcess
    command: []
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onStarted: root.actionStarted = true
    onExited: function(exitCode) {
      actionDeadline.stop()
      if (exitCode !== 0 && root.errorText === "")
        root.errorText = Model.actionError(actionStderr.text)
      root.actionKind = ""
      root.refresh()
    }
    onRunningChanged: if (!running && !root.actionStarted) {
      actionDeadline.stop()
      root.errorText = "Tailscale CLI not found"
      root.actionKind = ""
    }
  }
}
