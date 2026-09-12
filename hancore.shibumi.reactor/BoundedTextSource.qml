pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Watch metadata without FileView content reads. One bounded, short-lived
// reader per input; changes coalesce and stale/cancelled reads never publish.
Item {
  id: root
  required property string kind
  property bool active: false
  readonly property string home: Quickshell.env("HOME")
  readonly property string relativePath: kind === "theme" ? ".local/state/omarchy/current/theme.name"
    : kind === "event" ? ".cache/qs-reactor-event"
    : kind === "quotes" ? ".config/shibumi/quotes.txt" : ""
  readonly property int maximum: kind === "quotes" ? 65536 : kind === "event" ? 4096 : 512
  readonly property string path: relativePath && home ? home + "/" + relativePath : ""
  readonly property string helperPath: {
    const url = String(Qt.resolvedUrl("scripts/read-reactor-text.py"))
    try { return url.indexOf("file:///") === 0 ? decodeURIComponent(url.substring(7)) : "" }
    catch (error) { return "" }
  }
  readonly property string text: storage.value
  readonly property bool available: storage.valid
  readonly property bool busy: storage.busy || storage.pending
  readonly property bool watchContentLoaded: watcher.loaded
  signal updated()
  visible: false
  width: 0; height: 0

  QtObject {
    id: storage
    property string value: ""
    property bool valid: false
    property bool busy: false
    property bool pending: false
    property int generation: 0
    property int startedGeneration: -1
    property bool exited: false
    property bool streamed: false
    property bool cleanExit: false
    property bool terminalRequested: false
  }
  function invalidate() {
    storage.generation++
    storage.value = ""
    storage.valid = false
  }
  function reload() {
    storage.pending = false
    invalidate()
    if (!active || !path || !helperPath) { updated(); return }
    storage.pending = true
    if (!storage.busy) beginRead()
  }
  function beginRead() {
    if (!active || !storage.pending || storage.busy) return
    storage.pending = false
    storage.busy = true
    storage.startedGeneration = storage.generation
    storage.exited = false
    storage.streamed = false
    storage.cleanExit = false
    storage.terminalRequested = false
    reader.command = ["/usr/bin/python3", "-I", "-S", helperPath, kind, home]
    deadline.restart()
    reader.running = true
  }
  function finishRead() {
    // running/processId describe this owned Process, not a cached PID. Never
    // reuse it until stopped; a failed start needs no collector completion.
    if (!storage.busy || reader.running || Number(reader.processId) > 0
        || (!storage.exited && !storage.terminalRequested)) return
    deadline.stop()
    storage.busy = false
    if (active && storage.startedGeneration === storage.generation) {
      let result = null
      if (storage.cleanExit && storage.streamed && !storage.terminalRequested) {
        try { result = JSON.parse(output.text) } catch (error) {}
      }
      if (result && result.ok === true && typeof result.text === "string"
          && result.text.length <= maximum) {
        storage.value = result.text
        storage.valid = true
      }
      updated()
    }
    if (storage.pending && active) Qt.callLater(beginRead)
  }
  function syncActive() {
    storage.pending = false
    invalidate()
    if (active) reload()
    else {
      storage.terminalRequested = true
      reader.running = false
      if (storage.busy) deadline.restart()
      else deadline.stop()
      Qt.callLater(finishRead)
      updated()
    }
  }
  onActiveChanged: syncActive()
  onPathChanged: if (active) reload()
  Component.onCompleted: syncActive()

  FileView {
    id: watcher
    preload: false
    path: root.active ? root.path : ""
    watchChanges: root.active
    printErrors: false
    onFileChanged: root.reload()
    // Never call text(), data() or FileView.reload(): acquisition is bounded
    // by the exact Python reader before anything reaches a QML collector.
  }
  Process {
    id: reader
    clearEnvironment: true
    environment: ({LANG: "C.UTF-8"})
    onRunningChanged: if (!running) Qt.callLater(root.finishRead)
    onProcessIdChanged: if (!(Number(processId) > 0)) Qt.callLater(root.finishRead)
    stdout: StdioCollector {
      id: output
      waitForEnd: true
      onStreamFinished: {
        storage.streamed = true
        Qt.callLater(root.finishRead)
      }
    }
    onExited: function(code, status) {
      storage.exited = true
      storage.cleanExit = code === 0 && status === 0
      Qt.callLater(root.finishRead)
    }
  }
  Timer {
    id: deadline
    interval: 2000
    onTriggered: {
      root.invalidate()
      root.updated()
      storage.pending = false
      storage.terminalRequested = true
      if (Number(reader.processId) > 0) reader.signal(9)
      reader.running = false
      Qt.callLater(root.finishRead)
    }
  }
}
