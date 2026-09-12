pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

Item {
  id: root

  property var commandRunner: null

  visible: false
  width: 0
  height: 0

  function focusWorkspace(value) {
    const id = Number(value)
    if (!Number.isInteger(id) || id <= 0 || id > 9999) return false
    const command = [
      "hyprctl",
      "dispatch",
      "hl.dsp.focus({ workspace = \"" + id + "\" })"
    ]
    if (commandRunner !== null)
      return commandRunner && typeof commandRunner.run === "function"
        ? commandRunner.run(command) !== false : false
    launcher.command = command
    launcher.startDetached()
    return true
  }

  Process { id: launcher }
}
