import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property int cpuConsumers: 0
  property int memoryConsumers: 0
  property int cpuPanelConsumers: 0
  property string cpuModel: ""
  property var loadAverage: []
  property bool cpuModelRead: false
  readonly property bool active: cpuConsumers > 0 || memoryConsumers > 0 || cpuPanelConsumers > 0
  readonly property int intervalMs: 2000

  property int cpuPercent: 0
  property var cpuHistory: []
  readonly property int cpuMaxSamples: 30
  property real previousCpuIdle: -1
  property real previousCpuTotal: -1

  property int memTotalMiB: 0
  property int memAvailableMiB: 0
  property int memFreeMiB: 0
  property int memBuffersMiB: 0
  property int memCachedMiB: 0
  readonly property int memUsedMiB: Math.max(0, memTotalMiB - memAvailableMiB)
  readonly property int memPercent: memTotalMiB > 0
    ? Math.max(0, Math.min(100, Math.round(memUsedMiB / memTotalMiB * 100)))
    : 0
  readonly property real memUsedGiB: memUsedMiB / 1024
  readonly property real memTotalGiB: memTotalMiB / 1024

  function acquire(kind) {
    if (kind === "cpu") {
      cpuConsumers++
      if (cpuConsumers === 1) cpuFile.reload()
    } else if (kind === "memory") {
      memoryConsumers++
      if (memoryConsumers === 1) memoryFile.reload()
    } else if (kind === "cpuPanel") {
      if (++cpuPanelConsumers === 1) {
        // Lazy FileViews start async reads on text(), not on reload() alone.
        if (!cpuModelRead) { cpuModelRead = true; modelFile.text() }
        loadFile.reload()
        loadFile.text()
      }
    }
  }

  function release(kind) {
    if (kind === "cpu") cpuConsumers = Math.max(0, cpuConsumers - 1)
    else if (kind === "memory") memoryConsumers = Math.max(0, memoryConsumers - 1)
    else if (kind === "cpuPanel") cpuPanelConsumers = Math.max(0, cpuPanelConsumers - 1)
  }

  function parseCpu(text) {
    const lines = String(text || "").split("\n")
    if (lines.length === 0 || lines[0].indexOf("cpu ") !== 0) return
    const parts = lines[0].trim().split(/\s+/)
    if (parts.length < 8) return

    const idle = parseFloat(parts[4]) + parseFloat(parts[5])
    let total = 0
    for (let i = 1; i < parts.length; i++) {
      const value = parseFloat(parts[i])
      if (!isNaN(value)) total += value
    }
    if (isNaN(idle) || isNaN(total) || total <= 0) return

    if (previousCpuTotal >= 0 && total > previousCpuTotal) {
      const totalDelta = total - previousCpuTotal
      const idleDelta = idle - previousCpuIdle
      const busy = totalDelta > 0
        ? Math.round((totalDelta - idleDelta) / totalDelta * 100)
        : 0
      cpuPercent = Math.max(0, Math.min(100, busy))

      const history = cpuHistory.slice()
      history.push(cpuPercent / 100)
      if (history.length > cpuMaxSamples) history.shift()
      cpuHistory = history
    }

    previousCpuIdle = idle
    previousCpuTotal = total
  }

  function parseMemory(text) {
    let total = 0
    let available = 0
    let free = 0
    let buffers = 0
    let cached = 0
    const lines = String(text || "").split("\n")
    for (let i = 0; i < lines.length; i++) {
      const parts = lines[i].trim().split(/\s+/)
      if (parts.length < 2) continue
      const value = parseInt(parts[1])
      if (isNaN(value)) continue
      if (parts[0] === "MemTotal:") total = value
      else if (parts[0] === "MemAvailable:") available = value
      else if (parts[0] === "MemFree:") free = value
      else if (parts[0] === "Buffers:") buffers = value
      else if (parts[0] === "Cached:") cached = value
    }
    if (total <= 0) return

    memTotalMiB = Math.round(total / 1024)
    memAvailableMiB = Math.round(available / 1024)
    memFreeMiB = Math.round(free / 1024)
    memBuffersMiB = Math.round(buffers / 1024)
    memCachedMiB = Math.round(cached / 1024)
  }

  function parseCpuModel(text) {
    const match = /^(?:model name|Hardware)\s*:\s*([^\r\n]{1,256})/m.exec(String(text || "").slice(0, 8192))
    cpuModel = match ? match[1].trim() : ""
  }

  function parseLoad(text) {
    const values = String(text || "").slice(0, 256).trim().split(/\s+/).slice(0, 3).map(Number)
    loadAverage = values.length === 3 && values.every(value => isFinite(value) && value >= 0) ? values : []
  }

  function refresh() {
    if (cpuPanelConsumers > 0) { loadFile.reload(); loadFile.text() }
    if (cpuConsumers > 0) cpuFile.reload()
    if (memoryConsumers > 0) memoryFile.reload()
  }

  FileView {
    id: cpuFile
    path: "/proc/stat"
    printErrors: false
    onLoaded: root.parseCpu(text())
  }

  FileView {
    id: memoryFile
    path: "/proc/meminfo"
    printErrors: false
    onLoaded: root.parseMemory(text())
  }

  FileView {
    id: modelFile
    path: "/proc/cpuinfo"
    preload: false
    printErrors: false
    onLoaded: root.parseCpuModel(text())
  }
  FileView {
    id: loadFile
    path: "/proc/loadavg"
    preload: false
    printErrors: false
    onLoaded: if (root.cpuPanelConsumers > 0) root.parseLoad(text())
    onLoadFailed: root.loadAverage = []
  }

  Timer {
    interval: root.intervalMs
    running: root.active
    repeat: true
    onTriggered: root.refresh()
  }
}
