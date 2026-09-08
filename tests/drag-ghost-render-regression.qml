import QtQuick
import Quickshell
import "core" as Core

ShellRoot {
  id: test
  property int phase: 0
  property int ticks: 0
  property int oldGeneration: -1
  property var oldGrab: null
  property bool savedVisual: false
  property var tokens: null
  property bool frameSeen: false
  Component {
    id: transientSource
    Rectangle { x: 10; y: 45; width: 40; height: 20; color: "green" }
  }

  QtObject {
    id: bar
    property string position: "top"
    readonly property var visualTokens: test.tokens
    readonly property color foreground: "white"
    readonly property color urgent: "yellow"
  }
  QtObject {
    id: controller
    function groupLocation(id) { return id === "G4" ? { region: "left", index: 3 } : null }
  }
  Core.DragSession { id: session; layoutController: controller }
  Window {
    id: window
    width: 640
    height: 360
    visible: true
    color: "transparent"
    onFrameSwapped: test.frameSeen = true
    Rectangle {
      id: source
      x: 40
      y: bar.position === "bottom" ? window.height - 38 : 12
      width: 96
      height: 24
      color: bar.position === "bottom" ? "blue" : "red"
      opacity: session.active ? 0.28 : 1
    }
    Core.DragGhostVisual { id: ghost; bar: bar; layoutSession: session }
  }
  Window {
    id: otherWindow
    width: 320
    height: 180
    visible: true
    color: "transparent"
  }
  function fail(message) {
    console.error("drag-ghost-render-regression:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  function expectRejected(item, reason) {
    if (session.begin("G4", item, 10, 10) || session.active || session.returning
        || session.sourceItem !== null || session.sourceGroupId !== ""
        || session.ghostImageGrab !== null || String(session.ghostImageUrl) !== "")
      fail("invalid source activated drag: " + reason)
  }
  function verifyInitialSourceGuards() {
    window.visible = false
    expectRejected(source, "Window already hidden")
    window.visible = true
    expectRejected(null, "missing Item")
    const detached = transientSource.createObject(null)
    expectRejected(detached, "Item without Window")
    detached.destroy()
    // Qt's offscreen QWindow clamps width/height=0 to 1. Do not pretend it
    // produced a zero-sized native window; test the shared size guard below.
    source.width = 0
    expectRejected(source, "zero-width Item")
    source.width = 96
    source.height = 0
    expectRejected(source, "zero-height Item")
    source.height = 24
    source.visible = false
    expectRejected(source, "hidden Item")
    source.visible = true
    for (const bad of [NaN, Infinity, -Infinity, -1, 0]) {
      if (session.positiveSize({ width: bad, height: 24 })
          || session.positiveSize({ width: 96, height: bad }))
        fail("nonpositive/nonfinite dimension accepted")
    }
  }
  function begin() {
    return session.begin("G4", source, source.x + source.width / 2,
      source.y + source.height / 2)
  }
  Timer {
    interval: 30
    running: true
    repeat: true
    onTriggered: {
      if (++test.ticks > 150) return test.fail("phase " + test.phase + " timed out")
      if (test.phase === 0) {
        if (!test.frameSeen) return
        if (ghost.active || source.Window.window !== window)
          return test.fail("cold tokens or attached Window API")
        test.verifyInitialSourceGuards()
        test.tokens = { pillRadius: 12, invalidDropDuration: 230, returnCleanupDuration: 240 }
        if (!test.begin()) return test.fail("top drag begin")
        test.phase = 1
        return
      }
      if (test.phase === 1) {
        if (!ghost.imageReady) return
        if (!session.ghostImageGrab || ghost.x !== source.x || ghost.y !== source.y)
          return test.fail("top capture or coordinates")
        if (!session.ghostImageGrab.saveToFile("testOutput/capture-top.png"))
          return test.fail("save top fixture capture")
        session.move(300, 120)
        if (ghost.x !== 252 || ghost.y !== 108) return test.fail("pointer coordinates")
        ghost.grabToImage(function(result) {
          if (!result.saveToFile("testOutput/visual-top.png")) return test.fail("save rendered ghost")
          test.savedVisual = true
        })
        test.oldGeneration = session.captureGeneration
        test.oldGrab = session.ghostImageGrab
        test.phase = 2
        return
      }
      if (test.phase === 2) {
        if (!test.savedVisual) return
        bar.position = "bottom"
        if (!test.begin() || session.ghostImageGrab !== null
            || session.acceptGhostCapture(test.oldGeneration, source, test.oldGrab))
          return test.fail("old capture accepted for new drag on same Item")
        test.phase = 3
        return
      }
      if (test.phase === 3) {
        if (!ghost.imageReady) return
        if (ghost.y !== window.height - 38 || ghost.x !== 40
            || !session.ghostImageGrab.saveToFile("testOutput/capture-bottom.png"))
          return test.fail("bottom double-offset or missing capture")
        session.move(300, 150)
        if (session.drop() || !session.returning) return test.fail("invalid drop return")
        test.phase = 4
        return
      }
      if (test.phase === 4) {
        if (session.returning) return
        if (session.active || session.ghostImageGrab !== null || String(session.ghostImageUrl) !== "")
          return test.fail("return did not release capture")
        if (session.acceptGhostCapture(test.oldGeneration, source, test.oldGrab))
          return test.fail("capture resurrected cancelled drag")
        test.oldGrab = null
        if (!test.begin()) return test.fail("pending capture begin")
        window.visible = false
        if (session.active || session.sourceItem !== null || ghost.active)
          return test.fail("window loss did not cancel pending drag")
        test.phase = 5
        return
      }
      if (test.phase === 5) {
        if (session.ghostImageGrab !== null || String(session.ghostImageUrl) !== "")
          return test.fail("late callback resurrected hidden-window drag")
        test.frameSeen = false
        window.visible = true
        test.phase = 6
        return
      }
      if (test.phase === 6) {
        if (!test.frameSeen) return
        if (session.active || session.ghostImageGrab !== null)
          return test.fail("window return revived cancelled capture")
        if (!test.begin()) return test.fail("reparent source begin")
        source.parent = otherWindow.contentItem
        if (session.active || session.sourceItem !== null || session.ghostImageGrab !== null)
          return test.fail("Window replacement did not cancel drag")
        source.parent = window.contentItem
        const temporary = transientSource.createObject(window.contentItem)
        if (!session.begin("G4", temporary, 30, 55)) return test.fail("temporary source begin")
        temporary.destroy()
        test.phase = 7
        return
      }
      if (test.phase === 7) {
        if (session.sourceItem !== null) return
        if (session.active || session.returning || session.ghostImageGrab !== null)
          return test.fail("destroyed source left active drag/capture")
        test.tokens = null
        stop()
        console.log("drag ghost render regression passed")
        Qt.quit()
      }
    }
  }
}
