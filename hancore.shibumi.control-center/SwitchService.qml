pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string statusPath: Quickshell.env("HOME")
    + "/.local/state/shibumi/switch-status.json"
  property var status: ({
    schemaVersion: 1,
    target: "",
    phase: "idle",
    detail: "",
    updatedEpoch: 0
  })
  readonly property string phase: String(status.phase || "idle")
  readonly property string target: String(status.target || "")
  readonly property string detail: String(status.detail || "")
  readonly property bool busy: ["queued", "snapshot", "apply", "verify"]
    .indexOf(phase) >= 0
  readonly property bool failed: phase === "error"

  width: 0
  height: 0
  visible: false

  function accept(raw) {
    try {
      const parsed = JSON.parse(String(raw || "{}"))
      if (Number(parsed.schemaVersion || 0) !== 1
          || typeof parsed.phase !== "string"
          || typeof parsed.target !== "string")
        return false
      const active = ["queued", "snapshot", "apply", "verify"]
        .indexOf(parsed.phase) >= 0
      const age = Math.max(0, Math.floor(Date.now() / 1000)
        - Number(parsed.updatedEpoch || 0))
      if (active && age > 120) {
        status = {
          schemaVersion: 1,
          target: String(parsed.target || ""),
          phase: "error",
          detail: "The previous bar transition did not finish.",
          updatedEpoch: Number(parsed.updatedEpoch || 0)
        }
      } else {
        status = parsed
      }
      return true
    } catch (_error) {
      return false
    }
  }

  function begin(targetId) {
    if (busy) return false
    status = {
      schemaVersion: 1,
      target: String(targetId || ""),
      phase: "queued",
      detail: "",
      updatedEpoch: Math.floor(Date.now() / 1000)
    }
    statusFile.reload()
    return true
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.accept(text())
    onFileChanged: reload()
  }

  Timer {
    interval: 250
    repeat: true
    running: root.busy
    onTriggered: statusFile.reload()
  }

  Component.onCompleted: statusFile.reload()
}
