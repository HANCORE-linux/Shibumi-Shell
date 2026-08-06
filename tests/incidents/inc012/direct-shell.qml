import QtQuick
import Quickshell

ShellRoot {
  SectionHost {
    id: host

    onFinished: result => {
      if (result !== "passed") {
        console.error("INC012_HARNESS_ERROR direct result=" + result)
        Qt.exit(1)
        return
      }
      console.log("INC012_COMPLETE direct")
      Qt.callLater(function() { Qt.exit(0) })
    }
  }

  Timer {
    interval: 30000
    running: true
    onTriggered: {
      console.error("INC012_HARNESS_ERROR direct watchdog")
      Qt.exit(1)
    }
  }
}
