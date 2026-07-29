import QtQuick

Item {
  id: root

  property var bar: null

  visible: false
  width: 0
  height: 0

  function focusWorkspace(value) {
    const id = Number(value)
    if (!Number.isInteger(id) || id <= 0 || id > 9999) return false
    if (!bar || typeof bar.run !== "function") return false
    bar.run("hyprctl dispatch 'hl.dsp.focus({ workspace = \"" + id + "\" })'")
    return true
  }
}
