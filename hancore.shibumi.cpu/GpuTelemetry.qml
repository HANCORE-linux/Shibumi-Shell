import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property int consumers: 0
  property string helperPath: String(Qt.resolvedUrl(
    "../scripts/shibumi-gpu-probe")).replace("file://", "")
  property string backend: ""
  property string name: ""
  property string driverName: ""
  property string driverVersion: ""
  property int utilization: 0
  property int temperatureC: 0
  property int memoryUsedMiB: 0
  property int memoryTotalMiB: 0
  property bool probeFailed: false
  readonly property bool available: backend !== ""
  readonly property int intervalMs: 1500
  readonly property int probeTimeoutSeconds: 2

  function acquire() {
    consumers++
    if (consumers === 1) refresh()
  }

  function release() {
    consumers = Math.max(0, consumers - 1)
    if (consumers === 0) probe.running = false
  }

  function refresh() {
    if (consumers <= 0 || probe.running) return
    probe.running = true
  }

  function parse(line) {
    const lines = String(line || "").trim().split("\n").filter(
      function(value) { return String(value || "").trim() !== "" })
    const completed = lines.some(function(value) {
      const parts = String(value || "").split("|")
      return parts[0] === "status" && parts[1] === "ok"
    })
    if (lines.length === 0) {
      probeFailed = true
      return
    }

    const fields = lines[0].split("|")
    if (fields.length < 5) {
      probeFailed = true
      return
    }
    if (fields[0] === "none") {
      backend = ""
      name = ""
      driverName = ""
      driverVersion = ""
      utilization = 0
      temperatureC = 0
      memoryUsedMiB = 0
      memoryTotalMiB = 0
      probeFailed = !completed
      return
    }

    probeFailed = !completed
    backend = String(fields[0] || "").trim()
    utilization = Math.max(0, Math.min(100, parseInt(fields[1]) || 0))
    temperatureC = Math.max(0, parseInt(fields[2]) || 0)
    memoryUsedMiB = Math.max(0, parseInt(fields[3]) || 0)
    memoryTotalMiB = Math.max(0, parseInt(fields[4]) || 0)

    for (let i = 1; i < lines.length; i++) {
      const parts = lines[i].split("|")
      if (parts[0] !== "meta" || parts.length < 4) continue
      name = String(parts[1] || "").trim()
      driverName = String(parts[2] || "").trim()
      driverVersion = String(parts[3] || "").trim()
    }
  }

  Process {
    id: probe
    command: ["timeout", "--signal=TERM",
      String(root.probeTimeoutSeconds), root.helperPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
  }

  Timer {
    interval: root.intervalMs
    running: root.consumers > 0
    repeat: true
    onTriggered: root.refresh()
  }
}
