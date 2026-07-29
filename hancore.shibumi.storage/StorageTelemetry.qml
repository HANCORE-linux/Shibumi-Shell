import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property int consumers: 0
  property bool available: false
  property int percent: 0
  property real totalBytes: 0
  property real usedBytes: 0
  property real freeBytes: 0
  property var drives: []
  readonly property real totalGiB: totalBytes / 1073741824
  readonly property real usedGiB: usedBytes / 1073741824
  readonly property real freeGiB: freeBytes / 1073741824

  function acquire() {
    consumers++
    if (consumers === 1) refresh()
  }

  function release() {
    consumers = Math.max(0, consumers - 1)
  }

  function refresh() {
    if (consumers <= 0) return
    if (!usageProbe.running) usageProbe.running = true
    if (!inventoryProbe.running) inventoryProbe.running = true
  }

  function parseUsage(text) {
    const fields = String(text || "").trim().split(/\s+/)
    if (fields.length < 4) {
      available = false
      return
    }
    const total = Number(fields[0])
    const used = Number(fields[1])
    const free = Number(fields[2])
    const value = Number(String(fields[3]).replace("%", ""))
    available = Number.isFinite(total) && total > 0
    if (!available) return
    totalBytes = total
    usedBytes = Math.max(0, used)
    freeBytes = Math.max(0, free)
    percent = Math.max(0, Math.min(100, Math.round(value)))
  }

  function parseInventory(text) {
    let payload = null
    try { payload = JSON.parse(String(text || "")) } catch (error) {}
    const rows = []

    function visit(device) {
      if (!device || typeof device !== "object") return
      const mounts = Array.isArray(device.mountpoints)
        ? device.mountpoints.filter(function(value) {
          return String(value || "") !== ""
        }) : []
      if (device.type === "disk" || mounts.length > 0) {
        rows.push({
          name: String(device.name || ""),
          type: String(device.type || ""),
          sizeBytes: Math.max(0, Number(device.size) || 0),
          fileSystem: String(device.fstype || ""),
          mountPoint: mounts.indexOf("/") >= 0
            ? "/"
            : (mounts.length > 0 ? String(mounts[0]) : ""),
          model: String(device.model || "").trim(),
          transport: String(device.tran || "")
        })
      }
      const children = Array.isArray(device.children) ? device.children : []
      for (let index = 0; index < children.length; index++)
        visit(children[index])
    }

    const devices = payload && Array.isArray(payload.blockdevices)
      ? payload.blockdevices : []
    for (let index = 0; index < devices.length; index++) visit(devices[index])
    drives = rows
  }

  Process {
    id: usageProbe
    command: [
      "bash", "-c",
      "df -B1 --output=size,used,avail,pcent / 2>/dev/null | tail -n1"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseUsage(text)
    }
  }

  Process {
    id: inventoryProbe
    command: [
      "lsblk", "-J", "-b",
      "-o", "NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,TRAN"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseInventory(text)
    }
  }

  Timer {
    interval: 30000
    running: root.consumers > 0
    repeat: true
    onTriggered: root.refresh()
  }
}
