import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property int consumers: 0
  property string helperPath: String(Qt.resolvedUrl(
    "../scripts/shibumi-gpu-probe")).replace("file://", "")
  property var devices: []
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
  readonly property int deviceCount: Array.isArray(devices) ? devices.length : 0
  readonly property var defaultDevice: deviceCount > 0 ? devices[0] : null
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

  function boundedPercent(value) {
    return Math.max(0, Math.min(100, parseInt(value) || 0))
  }

  function nonNegativeInteger(value) {
    return Math.max(0, parseInt(value) || 0)
  }

  function deviceForId(deviceId) {
    const target = String(deviceId || "").trim()
    if (target === "" || target === "auto") return defaultDevice
    const rows = Array.isArray(devices) ? devices : []
    for (let index = 0; index < rows.length; index++) {
      if (String(rows[index].id || "") === target) return rows[index]
    }
    return null
  }

  function applySummary(device) {
    const value = device || null
    backend = value ? String(value.backend || "") : ""
    name = value ? String(value.name || "") : ""
    driverName = value ? String(value.driverName || "") : ""
    driverVersion = value ? String(value.driverVersion || "") : ""
    utilization = value ? boundedPercent(value.utilization) : 0
    temperatureC = value ? nonNegativeInteger(value.temperatureC) : 0
    memoryUsedMiB = value ? nonNegativeInteger(value.memoryUsedMiB) : 0
    memoryTotalMiB = value ? nonNegativeInteger(value.memoryTotalMiB) : 0
  }

  function publishDevices(rows) {
    devices = rows
    applySummary(rows.length > 0 ? rows[0] : null)
  }

  function parse(output) {
    const lines = String(output || "").trim().split("\n").filter(
      function(value) { return String(value || "").trim() !== "" })
    const completed = lines.some(function(value) {
      const parts = String(value || "").split("|")
      return parts[0] === "status" && parts[1] === "ok"
    })
    if (lines.length === 0 || !completed) {
      probeFailed = true
      return
    }

    const rows = []
    let noneReported = false
    let deviceRecordSeen = false
    for (let index = 0; index < lines.length; index++) {
      const fields = lines[index].split("|")
      if (fields[0] === "none") {
        noneReported = true
        continue
      }
      if (fields[0] !== "device") continue
      deviceRecordSeen = true
      if (fields.length < 11) continue
      const deviceId = String(fields[1] || "").trim()
      const deviceBackend = String(fields[2] || "").trim()
      if (deviceId === "" || deviceBackend === "") continue
      let duplicate = false
      for (let existing = 0; existing < rows.length; existing++) {
        if (rows[existing].id === deviceId) {
          duplicate = true
          break
        }
      }
      if (duplicate) continue
      rows.push({
        id: deviceId,
        backend: deviceBackend,
        utilization: boundedPercent(fields[3]),
        temperatureC: nonNegativeInteger(fields[4]),
        memoryUsedMiB: nonNegativeInteger(fields[5]),
        memoryTotalMiB: nonNegativeInteger(fields[6]),
        name: String(fields[7] || "").trim(),
        driverName: String(fields[8] || "").trim(),
        driverVersion: String(fields[9] || "").trim(),
        drmNode: String(fields[10] || "").trim(),
        available: true
      })
    }

    if (rows.length > 0) {
      publishDevices(rows)
      probeFailed = false
      return
    }
    if (deviceRecordSeen) {
      probeFailed = true
      return
    }
    if (noneReported) {
      publishDevices([])
      probeFailed = false
      return
    }

    // Accept the original single-device protocol for compatibility with
    // staged older helpers during transactional upgrades.
    const fields = lines[0].split("|")
    if (fields.length < 5 || fields[0] === "status") {
      probeFailed = true
      return
    }
    let legacyName = ""
    let legacyDriver = ""
    let legacyVersion = ""
    for (let index = 1; index < lines.length; index++) {
      const parts = lines[index].split("|")
      if (parts[0] !== "meta" || parts.length < 4) continue
      legacyName = String(parts[1] || "").trim()
      legacyDriver = String(parts[2] || "").trim()
      legacyVersion = String(parts[3] || "").trim()
    }
    const legacyBackend = String(fields[0] || "").trim()
    if (legacyBackend === "") {
      probeFailed = true
      return
    }
    publishDevices([{
      id: "legacy:" + legacyBackend,
      backend: legacyBackend,
      utilization: boundedPercent(fields[1]),
      temperatureC: nonNegativeInteger(fields[2]),
      memoryUsedMiB: nonNegativeInteger(fields[3]),
      memoryTotalMiB: nonNegativeInteger(fields[4]),
      name: legacyName,
      driverName: legacyDriver,
      driverVersion: legacyVersion,
      drmNode: "",
      available: true
    }])
    probeFailed = false
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
