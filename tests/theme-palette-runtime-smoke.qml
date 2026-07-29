pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as StatePlugin

ShellRoot {
  id: root

  property int polls: 0
  property bool swapStarted: false

  QtObject {
    id: fakeShell
    property var shellConfig: ({
      version: 1,
      bar: { shibumi: { version: 1, presentation: { accent: "color06" } } }
    })
  }

  StatePlugin.Service {
    id: state
    shell: fakeShell
  }

  function colorText(value) {
    return String(value || "").toLowerCase()
  }

  function fail(message) {
    console.error("theme-palette-runtime-smoke:", message)
    Qt.exit(1)
  }

  function paletteMatches(values) {
    return root.colorText(state.color01) === values[0]
      && root.colorText(state.color02) === values[1]
      && root.colorText(state.color03) === values[2]
      && root.colorText(state.color04) === values[3]
      && root.colorText(state.color05) === values[4]
      && root.colorText(state.color06) === values[5]
      && root.colorText(state.color07) === values[6]
      && root.colorText(state.color08) === values[7]
      && root.colorText(state.selectedColor) === values[5]
  }

  Process {
    id: themeSwap
    command: [Quickshell.env("SHIBUMI_THEME_SWAP_SCRIPT")]
    onExited: function(exitCode) {
      if (exitCode !== 0) root.fail("theme swap fixture exited " + exitCode)
    }
  }

  Timer {
    interval: 20
    running: true
    repeat: true
    onTriggered: {
      root.polls++

      if (!root.swapStarted) {
        if (!root.paletteMatches([
              "#112233", "#223344", "#334455", "#445566",
              "#556677", "#667788", "#778899", "#8899aa"
            ])) {
          if (root.polls < 100) return
          return root.fail("initial palette did not load")
        }
        root.swapStarted = true
        root.polls = 0
        themeSwap.running = true
        return
      }

      if (root.paletteMatches([
            "#8899aa", "#99aabb", "#aabbcc", "#bbccdd",
            "#ccddee", "#ddeeff", "#eeffcc", "#223344"
          ])) {
        stop()
        console.log("theme palette runtime smoke passed")
        Qt.quit()
        return
      }

      if (root.polls >= 100)
        root.fail("palette did not reload after atomic theme-directory swap")
    }
  }
}
