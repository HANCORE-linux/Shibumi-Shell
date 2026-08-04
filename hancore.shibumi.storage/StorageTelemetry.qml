import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property int consumers: 0
  property bool runtimeProbesEnabled: true
  property bool available: false
  property bool inventoryAvailable: false
  property string inventoryError: ""
  property string rootDevice: ""
  property int percent: 0
  property real totalBytes: 0
  property real usedBytes: 0
  property real freeBytes: 0
  property var drives: []
  readonly property bool inventoryLoading:
    inventoryProbe.running && !inventoryAvailable
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
    if (consumers <= 0 || !runtimeProbesEnabled) return
    if (!usageProbe.running) usageProbe.running = true
    if (!inventoryProbe.running) inventoryProbe.running = true
  }

  function parseUsage(text) {
    const lines = String(text || "").trim().split("\n")
    const fields = lines.length > 0
      ? lines[lines.length - 1].trim().split(/\s+/) : []
    if (fields.length < 4) {
      available = false
      return
    }
    const offset = fields.length >= 5 ? 1 : 0
    rootDevice = offset > 0 ? String(fields[0]) : ""
    const total = Number(fields[offset])
    const used = Number(fields[offset + 1])
    const free = Number(fields[offset + 2])
    const value = Number(String(fields[offset + 3]).replace("%", ""))
    available = Number.isFinite(total) && total > 0
    if (!available) return
    totalBytes = total
    usedBytes = Math.max(0, used)
    freeBytes = Math.max(0, free)
    percent = Math.max(0, Math.min(100, Math.round(value)))
  }

  function boolValue(value) {
    return value === true || value === 1 || String(value) === "1"
  }

  function mountPoints(device) {
    const values = device && Array.isArray(device.mountpoints)
      ? device.mountpoints : []
    const result = []
    for (let index = 0; index < values.length; index++) {
      const value = String(values[index] || "").trim()
      if (value !== "" && value !== "[SWAP]") result.push(value)
    }
    return result
  }

  function parsePercent(value, used, free) {
    const parsed = Number(String(value === null || value === undefined
      ? "" : value).replace("%", ""))
    if (Number.isFinite(parsed))
      return Math.max(0, Math.min(100, Math.round(parsed)))
    const total = used + free
    return total > 0 ? Math.round(used * 100 / total) : -1
  }

  function volumeFrom(device, removable) {
    const mounts = mountPoints(device)
    const fileSystem = String(device.fstype || "")
    const used = Number(device.fsused)
    const free = Number(device.fsavail)
    const usedBytes = Number.isFinite(used) && used >= 0 ? used : -1
    const freeBytes = Number.isFinite(free) && free >= 0 ? free : -1
    const total = usedBytes >= 0 && freeBytes >= 0
      ? usedBytes + freeBytes : -1
    return {
      name: String(device.name || ""),
      path: String(device.path || ""),
      type: String(device.type || ""),
      sizeBytes: Math.max(0, Number(device.size) || 0),
      fileSystem: fileSystem,
      mountPoints: mounts,
      mountPoint: mounts.length > 0 ? mounts[0] : "",
      mounted: mounts.length > 0,
      usedBytes: usedBytes,
      freeBytes: freeBytes,
      totalBytes: total,
      percent: parsePercent(device["fsuse%"],
        Math.max(0, usedBytes), Math.max(0, freeBytes))
    }
  }

  function collectVolumes(device, removable, rows) {
    if (!device || typeof device !== "object") return
    if (String(device.fstype || "") !== "")
      rows.push(volumeFrom(device, removable))
    const children = Array.isArray(device.children) ? device.children : []
    for (let index = 0; index < children.length; index++)
      collectVolumes(children[index], removable, rows)
  }

  function uniqueValues(values) {
    const result = []
    for (let index = 0; index < values.length; index++) {
      const value = String(values[index] || "")
      if (value !== "" && result.indexOf(value) < 0) result.push(value)
    }
    return result
  }

  function driveType(device, removable) {
    const transport = String(device.tran || "").toLowerCase()
    const name = String(device.name || "").toLowerCase()
    if (removable || transport === "usb") return "usb"
    if (transport === "nvme" || name.indexOf("nvme") === 0) return "nvme"
    return boolValue(device.rota) ? "hdd" : "ssd"
  }

  function driveFrom(device) {
    const transport = String(device.tran || "").toLowerCase()
    const removable = boolValue(device.rm) || boolValue(device.hotplug)
      || transport === "usb"
    const volumes = []
    collectVolumes(device, removable, volumes)
    let used = 0
    let free = 0
    let measured = 0
    let mounted = 0
    let fileSystems = []
    let mounts = []
    for (let index = 0; index < volumes.length; index++) {
      const volume = volumes[index]
      if (volume.mounted) mounted++
      if (volume.totalBytes > 0) {
        used += volume.usedBytes
        free += volume.freeBytes
        measured += volume.totalBytes
      }
      fileSystems.push(volume.fileSystem)
      mounts = mounts.concat(volume.mountPoints)
    }
    fileSystems = uniqueValues(fileSystems)
    mounts = uniqueValues(mounts)
    const kind = driveType(device, removable)
    const primaryMount = mounts.indexOf("/") >= 0 ? "/"
      : mounts.length > 0 ? mounts[0] : ""
    return {
      name: String(device.name || ""),
      path: String(device.path || ""),
      model: String(device.model || "").trim()
        || String(device.name || ""),
      sizeBytes: Math.max(0, Number(device.size) || 0),
      transport: transport,
      removable: removable,
      driveType: kind,
      media: kind === "usb" ? "USB DRIVE"
        : kind === "nvme" ? "NVME SSD"
          : kind === "hdd" ? "HDD" : "SSD",
      volumes: volumes,
      fileSystems: fileSystems.join(" · "),
      mountPoints: mounts,
      mountSummary: primaryMount !== ""
        ? primaryMount + (mounts.length > 1 ? " +" + (mounts.length - 1) : "")
        : volumes.length > 0 ? "Not mounted" : "No filesystem",
      mountedVolumes: mounted,
      usedBytes: measured > 0 ? used : -1,
      freeBytes: measured > 0 ? free : -1,
      totalBytes: measured > 0 ? measured : -1,
      percent: measured > 0 ? Math.max(0, Math.min(100,
        Math.round(used * 100 / measured))) : -1
    }
  }

  function parseInventory(text) {
    let payload = null
    try { payload = JSON.parse(String(text || "")) } catch (error) {}
    if (!payload || !Array.isArray(payload.blockdevices)) {
      inventoryError = "Drive inventory unavailable"
      inventoryAvailable = false
      return false
    }
    const rows = []
    for (let index = 0; index < payload.blockdevices.length; index++) {
      const device = payload.blockdevices[index]
      const name = String(device && device.name || "").toLowerCase()
      if (!device || device.type !== "disk"
          || /^(loop|ram|zram)/.test(name)) continue
      rows.push(driveFrom(device))
    }
    drives = rows
    inventoryAvailable = true
    inventoryError = ""
    return true
  }

  function cleanProbeError(value, fallback) {
    const lines = String(value || "").trim().split("\n")
    let message = lines.length > 0 ? lines[lines.length - 1].trim() : ""
    if (message === "") message = fallback
    return message.length > 180 ? message.slice(0, 177) + "…" : message
  }

  Process {
    id: usageProbe
    command: ["df", "-B1", "--output=source,size,used,avail,pcent", "/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseUsage(text)
    }
  }

  Process {
    id: inventoryProbe
    command: [
      "lsblk", "-J", "-b", "-o",
      "NAME,PATH,TYPE,SIZE,FSTYPE,FSUSED,FSAVAIL,FSUSE%,MOUNTPOINTS,MODEL,TRAN,ROTA,RM,HOTPLUG"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseInventory(text)
    }
    stderr: StdioCollector {
      id: inventoryStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) return
      root.inventoryError = root.cleanProbeError(
        inventoryStderr.text, "Drive inventory unavailable")
      if (root.drives.length === 0) root.inventoryAvailable = false
    }
  }

  Timer {
    interval: 30000
    running: root.consumers > 0
    repeat: true
    onTriggered: root.refresh()
  }
}
