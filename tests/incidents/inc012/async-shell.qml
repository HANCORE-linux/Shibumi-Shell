import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property bool requestedVertical:
    Quickshell.env("SHIBUMI_TEST_VERTICAL") === "1"
  property int cycleMode: 0
  property int cycleIndex: 0
  property bool unloading: false

  function loadNext() {
    owner.source = "SectionHost.qml"
  }

  function finishCycle() {
    cycleIndex++
    if (cycleIndex >= 20) {
      console.log("INC012_EVENT async-cycle-mode v2=" + (cycleMode >= 2)
        + " editing=" + (cycleMode % 2 === 1) + " cycles=20")
      cycleIndex = 0
      cycleMode++
    }
    if (cycleMode >= 4) {
      console.log("INC012_COMPLETE async cycles=80")
      Qt.exit(0)
      return
    }
    loadNext()
  }

  Loader {
    id: owner
    asynchronous: true

    onLoaded: {
      item.externalMode = true
      item.requestedV2 = root.cycleMode >= 2
      item.requestedEditing = root.cycleMode % 2 === 1
      item.requestedVertical = root.requestedVertical
    }
  }

  Connections {
    target: owner.item
    ignoreUnknownSignals: true

    function onReady() {
      unloadTimer.restart()
    }
  }

  Timer {
    id: unloadTimer
    interval: 2
    onTriggered: {
      root.unloading = true
      owner.source = ""
      settleTimer.restart()
    }
  }

  Timer {
    id: settleTimer
    interval: 2
    repeat: true
    onTriggered: {
      if (owner.status !== Loader.Null || owner.item !== null) return
      stop()
      root.unloading = false
      root.finishCycle()
    }
  }

  Timer {
    interval: 30000
    running: true
    onTriggered: {
      console.error("INC012_HARNESS_ERROR async watchdog mode="
        + root.cycleMode + " cycle=" + root.cycleIndex
        + " status=" + owner.status)
      Qt.exit(1)
    }
  }

  Component.onCompleted: loadNext()
}
