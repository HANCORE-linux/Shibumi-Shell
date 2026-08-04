import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property int consumers: 0
  property int detailsConsumers: 0
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
  property var topProcesses: []
  property bool detailsReady: false
  property bool detailsFailed: false
  property bool probeFailed: false
  property var previousProcessCounters: ({})
  property double previousProcessEpoch: 0
  property bool probeDetails: false
  property bool pendingRefresh: false
  readonly property bool available: backend !== ""
  readonly property int intervalMs: 1500
  readonly property int detailsIntervalMs: 2500
  readonly property int probeTimeoutSeconds: 2

  function acquire() {
    consumers++
    if (consumers === 1) refresh()
  }

  function release() {
    consumers = Math.max(0, consumers - 1)
    if (consumers === 0) {
      pendingRefresh = false
      probe.running = false
    }
  }

  function acquireDetails() {
    detailsConsumers++
    if (detailsConsumers === 1) {
      detailsReady = false
      detailsFailed = false
    }
    refresh()
  }

  function releaseDetails() {
    detailsConsumers = Math.max(0, detailsConsumers - 1)
    if (detailsConsumers === 0) {
      topProcesses = []
      detailsReady = false
      detailsFailed = false
      previousProcessCounters = ({})
      previousProcessEpoch = 0
      pendingRefresh = false
      if (probe.running && probeDetails) probe.running = false
    }
  }

  function refresh() {
    if (consumers <= 0) return
    if (probe.running) {
      if (detailsConsumers > 0 && !probeDetails) pendingRefresh = true
      return
    }
    probeDetails = detailsConsumers > 0
    pendingRefresh = false
    probe.running = true
  }

  function parse(line, includeDetails) {
    const parseDetails = includeDetails === undefined
      ? true : includeDetails === true
    const lines = String(line || "").trim().split("\n").filter(
      function(value) { return String(value || "").trim() !== "" })
    const completed = lines.some(function(value) {
      const parts = String(value || "").split("|")
      return parts[0] === "status" && parts[1] === "ok"
    })
    if (lines.length === 0) {
      probeFailed = true
      if (parseDetails) {
        detailsReady = true
        detailsFailed = true
      }
      return
    }
    const fields = lines.length > 0 ? lines[0].split("|") : []
    if (fields.length < 5) {
      probeFailed = true
      if (parseDetails) {
        detailsReady = true
        detailsFailed = true
      }
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
      topProcesses = []
      detailsReady = parseDetails
      detailsFailed = !completed && parseDetails
      probeFailed = !completed
      previousProcessCounters = ({})
      previousProcessEpoch = 0
      return
    }

    probeFailed = !completed
    backend = String(fields[0] || "").trim()
    utilization = Math.max(0, Math.min(100, parseInt(fields[1]) || 0))
    temperatureC = Math.max(0, parseInt(fields[2]) || 0)
    memoryUsedMiB = Math.max(0, parseInt(fields[3]) || 0)
    memoryTotalMiB = Math.max(0, parseInt(fields[4]) || 0)

    const now = Date.now()
    const elapsedMs = previousProcessEpoch > 0
      ? Math.max(1, now - previousProcessEpoch) : 0
    const counters = ({})
    const processes = []
    for (let i = 1; i < lines.length; i++) {
      const parts = lines[i].split("|")
      const kind = String(parts[0] || "").trim()
      if (kind === "meta" && parts.length >= 4) {
        name = String(parts[1] || "").trim()
        driverName = String(parts[2] || "").trim()
        driverVersion = String(parts[3] || "").trim()
      } else if (parseDetails && kind === "proc" && parts.length >= 5) {
        const percent = parseInt(parts[2])
        processes.push({
          pid: Math.max(0, parseInt(parts[1]) || 0),
          percent: Number.isFinite(percent) && percent >= 0
            ? Math.min(100, percent) : -1,
          memoryMiB: Math.max(0, parseInt(parts[3]) || 0),
          name: String(parts.slice(4).join("|") || "GPU process").trim()
        })
      } else if (parseDetails && kind === "counter" && parts.length >= 5) {
        const pid = Math.max(0, parseInt(parts[1]) || 0)
        const ticks = Math.max(0, Number(parts[2]) || 0)
        const key = String(pid)
        const previous = Number(previousProcessCounters[key])
        const percent = elapsedMs > 0 && Number.isFinite(previous)
          && ticks >= previous
          ? Math.min(100, Math.round((ticks - previous) / elapsedMs / 10000))
          : -1
        counters[key] = ticks
        processes.push({
          pid: pid,
          percent: percent,
          memoryMiB: Math.max(0, parseInt(parts[3]) || 0),
          name: String(parts.slice(4).join("|") || "GPU process").trim()
        })
      }
    }
    processes.sort(function(left, right) {
      const leftKnown = left.percent >= 0 ? 1 : 0
      const rightKnown = right.percent >= 0 ? 1 : 0
      if (leftKnown !== rightKnown) return rightKnown - leftKnown
      if (left.percent !== right.percent) return right.percent - left.percent
      if (left.memoryMiB !== right.memoryMiB)
        return right.memoryMiB - left.memoryMiB
      return left.name.localeCompare(right.name)
    })
    if (parseDetails && completed) {
      topProcesses = processes.slice(0, 3)
      detailsReady = true
      detailsFailed = false
      previousProcessCounters = counters
      previousProcessEpoch = Object.keys(counters).length > 0 ? now : 0
    } else if (parseDetails) {
      detailsReady = true
      detailsFailed = true
    }
  }

  Process {
    id: probe
    command: ["timeout", "--signal=TERM",
      String(root.probeTimeoutSeconds), root.helperPath,
      root.probeDetails ? "1" : "0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text,
        root.probeDetails && root.detailsConsumers > 0)
    }
    onExited: if (root.pendingRefresh && root.consumers > 0)
      Qt.callLater(root.refresh)
  }

  Timer {
    interval: root.detailsConsumers > 0
      ? root.detailsIntervalMs : root.intervalMs
    running: root.consumers > 0
    repeat: true
    onTriggered: root.refresh()
  }
}
