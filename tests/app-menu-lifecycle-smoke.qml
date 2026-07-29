import QtQuick
import Quickshell
import "menu" as AppMenu

ShellRoot {
  id: root

  property int phase: 0
  property int attempts: 0

  function fail(message) {
    console.error("app menu lifecycle smoke failed: " + message)
    Qt.exit(1)
  }

  AppMenu.AppMenuService {
    id: service
    desktopEntrySource: []
  }

  AppMenu.Menu {
    id: menu
    service: service
    surfaceSource: Qt.resolvedUrl("MenuTestSurface.qml")
  }

  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: root.advance()
  }

  function advance() {
    attempts++
    if (attempts > 100) return fail("phase " + phase + " timed out")

    const state = JSON.parse(menu.debugState(""))
    if (phase === 0) {
      if (state.surfaceLoaded) return fail("surface loaded while menu was closed")
      if (menu.open('{"menu":"apps"}') !== "ok") return fail("open failed")
      phase = 1
      attempts = 0
      return
    }
    if (phase === 1) {
      if (!state.surfaceLoaded) return
      if (!service.menuOpen) return fail("shared menu state did not open")
      menu.close()
      phase = 2
      attempts = 0
      return
    }
    if (phase === 2) {
      if (state.surfaceLoaded) return
      if (state.opened) return fail("menu remained open after close")
      if (service.menuOpen) return fail("shared menu state did not close")
      if (menu.open('{"menu":"apps"}') !== "ok") return fail("warm reopen failed")
      phase = 3
      attempts = 0
      return
    }
    if (phase === 3) {
      if (!state.surfaceLoaded) return
      menu.close()
      phase = 4
      attempts = 0
      return
    }
    if (state.surfaceLoaded) return
    console.log("app menu lifecycle smoke passed")
    Qt.quit()
  }
}
