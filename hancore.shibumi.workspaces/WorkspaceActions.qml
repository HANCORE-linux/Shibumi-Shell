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
    return dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  function focusSlot(value, connector) {
    const slot = Number(value)
    const name = String(connector || "")
    if (!Number.isInteger(slot) || slot < 1 || slot > 10
        || !/^[A-Za-z0-9_.:-]+$/.test(name)) return false
    return dispatch("o.workspaces.focus(" + slot + ", \"" + name + "\")")
  }

  function dispatch(expression) {
    const command = ["hyprctl", "dispatch", expression]
    if (commandRunner !== null)
      return commandRunner && typeof commandRunner.run === "function"
        ? commandRunner.run(command) !== false : false
    launcher.command = command
    launcher.startDetached()
    return true
  }

  Process { id: launcher }
}
