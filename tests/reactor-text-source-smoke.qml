import QtQuick
import Quickshell
import Quickshell.Io
import "reactor" as Reactor

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property double destroyedAt: 0
  readonly property string scenario: Quickshell.env("REACTOR_FIXTURE_SCENARIO")
  function check(value, message) {
    if (value) return
    console.error("reactor-text-source:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  property bool recreated: false
  readonly property var source: sourceLoader.item
  Loader {
    id: sourceLoader
    active: true
    sourceComponent: Reactor.BoundedTextSource {
      kind: root.recreated || root.scenario === "valid" ? "event" : "theme"
    }
  }
  FileView {
    id: barrier
    path: ["stale-success", "cancel", "destroy"].indexOf(root.scenario) >= 0
      ? Quickshell.env("HOME") + "/barrier" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  Connections {
    target: source
    function onUpdated() {
      root.check(!(root.scenario === "stale-success" && root.phase >= 3
        && source.available && source.text === "theme-old"), "stale successful read published")
    }
  }
  Timer {
    interval: 30; running: true; repeat: true
    onTriggered: {
      root.check(++root.ticks < 230, "source deadline " + root.phase)
      if (root.phase === 10) {
        root.check(source === null, "source Loader retained destroyed item")
        root.recreated = true
        sourceLoader.active = true
        root.phase = 2
        return
      }
      root.check(source !== null && !source.watchContentLoaded, "watcher buffered file contents")
      if (root.phase === 0) {
        root.check(!source.available && !source.busy && source.text === "", "inactive source read")
        source.active = true
      } else if (root.phase === 1) {
        if (root.scenario === "stale-success") {
          if (!barrier.loaded || barrier.text() !== "ready") return
          root.check(source.busy, "stale-success control was not in flight")
          root.phase = 3
          source.kind = "event"
          return
        }
        if (root.scenario === "cancel" || root.scenario === "destroy") {
          if (!barrier.loaded || barrier.text() !== "ready") return
          root.check(source.busy, "cancellation control was not in flight")
          if (root.scenario === "destroy") {
            root.phase = 10
            root.destroyedAt = Date.now()
            sourceLoader.active = false
            return
          }
          source.active = false
        } else {
          if (source.busy) return
          root.check(source.available === (root.scenario === "valid"), "initial read result")
          if (root.scenario === "valid") root.check(source.text === "event-ok", "wrong initial bytes")
          source.active = false
        }
      } else if (root.phase === 2) {
        if (source.busy) return
        root.check(!source.available && source.text === "", "cancelled publication retained")
        source.kind = "event"
        source.active = true
      } else if (root.phase === 3) {
        if (source.busy) return
        root.check(source.available && source.text === "event-ok", "failed read/cancel recovery latched")
        source.reload(); source.reload(); source.reload()
        source.kind = "quotes"
      } else if (root.phase === 4) {
        if (source.busy) return
        root.check(source.available && source.text === "quote-ok", "coalescing published stale input")
        source.active = false
      } else {
        if (source.busy) return
        root.check(!source.available && source.text === "", "final cancellation")
        if (root.scenario === "destroy") {
          root.check(barrier.text() !== "survived", "destroyed source left helper active")
          if (Date.now() - root.destroyedAt < 1600) return
          root.check(barrier.text() === "ready", "destruction barrier lost")
        }
        console.log("reactor text source smoke passed", root.scenario)
        Qt.exit(0)
        return
      }
      root.phase++
    }
  }
}
