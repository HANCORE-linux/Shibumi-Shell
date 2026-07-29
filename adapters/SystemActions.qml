import QtQuick

QtObject {
  id: root

  property var bar: null

  function openSystemMonitor() {
    if (!bar || typeof bar.run !== "function") return false
    bar.run("omarchy-launch-floating-terminal-with-presentation 'btop'")
    return true
  }
}
