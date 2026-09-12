import QtQuick
import Quickshell

ShellRoot {
  id: root

  property int waits: 0

  Bar {
    id: bar
    outputWindowsEnabled: false
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (bar.shutdownPrepared) {
        if (bar.hostReady || bar.outputWindowsEnabled)
          return Qt.exit(1)
        console.log("bar shutdown IPC smoke passed")
        Qt.exit(0)
        return
      }
      if (++root.waits > 150) {
        console.error("bar shutdown IPC smoke timed out")
        Qt.exit(1)
      }
    }
  }
}
