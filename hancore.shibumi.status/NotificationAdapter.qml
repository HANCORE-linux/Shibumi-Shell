pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Compatibility adapter for the host-owned Omarchy Notifications service.
// The host service owns the notification daemon and all notification objects;
// this object copies only primitive rows into Shibumi-owned models.
Item {
  id: root

  width: 0
  height: 0
  visible: false

  // The host reference is deliberately kept in a private child object. The
  // public notificationService façade exposes only primitive models and
  // typed methods to Shibumi consumers.
  QtObject {
    id: state
    property var hostService: null
    property int hostGeneration: 0
    property var historyReadHost: null
    property int historyReadGeneration: -1
    property var queuedHistoryHost: null
    property int queuedHistoryGeneration: -1
    property string historyOutput: ""
  }

  readonly property bool available: state.hostService !== null
  readonly property bool doNotDisturb: available
    && state.hostService.doNotDisturb === true
  readonly property int pendingCount: pendingRows.count
  readonly property int recentCount: pastRows.count
  readonly property bool liveAvailable: sourceModel() !== null
  readonly property bool historyAvailable: available
  readonly property bool pastDismissAvailable: available
    && typeof state.hostService.dismissPast === "function"
  readonly property bool pastClearAvailable: available
    && (typeof state.hostService.clearPast === "function"
      || typeof state.hostService.clearHistory === "function")
  property alias pendingModel: pendingRows
  property alias pastModel: pastRows

  ListModel { id: pendingRows }
  ListModel { id: pastRows }

  function attachShell(shellValue) {
    const service = shellValue
      && typeof shellValue.firstPartyServiceFor === "function"
      ? shellValue.firstPartyServiceFor("omarchy.notifications") : null
    const nextService = service || null
    if (state.hostService === nextService) {
      syncModels()
      return
    }
    state.hostGeneration++
    state.hostService = nextService
    state.historyOutput = ""
    state.queuedHistoryHost = null
    state.queuedHistoryGeneration = -1
    pendingRows.clear()
    pastRows.clear()
    syncModels()
  }

  function sourceModel() {
    const service = state.hostService
    if (!service) return null
    // pendingModel is the legacy contract when present. popupModel is the
    // current Quattro contract and is used only when pendingModel is absent.
    return service.pendingModel || service.popupModel || null
  }

  function historySourceModel() {
    const service = state.hostService
    if (!service) return null
    const model = service.pastModel
    return model && model !== sourceModel() ? model : null
  }

  function primitiveEntry(entry) {
    const value = entry || ({})
    return {
      id: Number(value.id || value.originalId || 0),
      originalId: Number(value.originalId || value.id || 0),
      app: String(value.app || value.appName || ""),
      appIcon: String(value.appIcon || ""),
      summary: String(value.summary || ""),
      body: String(value.body || ""),
      image: String(value.image || ""),
      glyph: String(value.glyph || ""),
      exec: String(value.exec || ""),
      urgency: Number(value.urgency || 0),
      expireTimeout: Number(value.expireTimeout || 0),
      timestamp: Number(value.timestamp || 0)
    }
  }

  function rebuild(target, model) {
    target.clear()
    if (!model || typeof model.get !== "function") return
    for (let index = 0; index < model.count; index++) {
      const entry = model.get(index)
      if (!entry || Number(entry.originalId || entry.id || 0) < 0)
        continue
      target.append(primitiveEntry(entry))
    }
  }

  function syncModels() {
    rebuild(pendingRows, sourceModel())
    const archived = historySourceModel()
    if (archived) rebuild(pastRows, archived)
  }

  // Derived from MIT-licensed Omarchy v4.0.3 NotificationLogic.historyRows:
  // compact JSON lines, newest first, malformed lines skipped, at most ten.
  function applyHistory(raw) {
    const rows = []
    const lines = String(raw || "").split("\n")
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index].trim()
      if (!line) continue
      try {
        const value = JSON.parse(line)
        if (value && typeof value === "object")
          rows.push(primitiveEntry(value))
      } catch (_error) {
        // Match the host: one malformed persisted line does not hide the rest.
      }
    }
    rows.sort((a, b) => b.timestamp - a.timestamp)
    pastRows.clear()
    for (let index = 0; index < Math.min(10, rows.length); index++)
      pastRows.append(rows[index])
  }

  function sourceIndex(entry, model) {
    if (!entry || !model || typeof model.get !== "function") return -1
    const timestamp = Number(entry.timestamp || 0)
    const originalId = Number(entry.originalId || entry.id || 0)
    for (let index = 0; index < model.count; index++) {
      const candidate = model.get(index)
      if (!candidate) continue
      if (Number(candidate.timestamp || 0) === timestamp
          && Number(candidate.originalId || candidate.id || 0)
            === originalId)
        return index
    }
    return -1
  }

  function setDoNotDisturb(value) {
    const service = state.hostService
    if (!service) return false
    if (typeof service.setDoNotDisturb === "function") {
      service.setDoNotDisturb(value === true)
      return true
    }
    if (typeof service.setDnd === "function") {
      service.setDnd(value === true)
      return true
    }
    return false
  }

  function toggleDoNotDisturb() {
    return setDoNotDisturb(!doNotDisturb)
  }

  function dismissPending(index) {
    const service = state.hostService
    if (!service || index < 0 || index >= pendingRows.count) return false
    if (typeof service.dismissPending === "function") {
      service.dismissPending(index)
      return true
    }
    const entry = pendingRows.get(index)
    const source = sourceIndex(entry, sourceModel())
    if (source < 0) return false
    if (typeof service.dismissPopup !== "function") return false
    service.dismissPopup(source)
    return true
  }

  function dismissPast(index) {
    const service = state.hostService
    if (!service || index < 0 || index >= pastRows.count) return false
    if (typeof service.dismissPast !== "function") return false
    service.dismissPast(index)
    return true
  }

  function clearPending() {
    const service = state.hostService
    if (!service) return false
    if (typeof service.clearPending === "function") {
      service.clearPending()
      return true
    }
    if (typeof service.markAllSeen === "function") {
      service.markAllSeen()
      return true
    }
    if (typeof service.clearPopups === "function") {
      service.clearPopups()
      return true
    }
    return false
  }

  function clearPast() {
    const service = state.hostService
    if (!service) return false
    if (typeof service.clearPast === "function") {
      service.clearPast()
      return true
    }
    if (typeof service.clearHistory === "function") {
      service.clearHistory()
      return true
    }
    return false
  }

  function markAllSeen() {
    const service = state.hostService
    if (!service) return false
    if (typeof service.markAllSeen === "function") {
      service.markAllSeen()
      return true
    }
    return clearPending()
  }

  function focusApp(entry) {
    const service = state.hostService
    if (!service || !entry) return false
    if (typeof service.focusApp === "function") {
      service.focusApp(entry)
      return true
    }
    const source = sourceIndex(entry, sourceModel())
    if (source < 0 || typeof service.invokePopupDefault !== "function")
      return false
    service.invokePopupDefault(source)
    return true
  }

  function startHistoryRead() {
    state.historyOutput = ""
    state.historyReadHost = state.hostService
    state.historyReadGeneration = state.hostGeneration
    historyReader.running = true
  }

  function startQueuedHistoryRead() {
    if (historyReader.running
        || state.queuedHistoryHost !== state.hostService
        || state.queuedHistoryGeneration !== state.hostGeneration) return
    state.queuedHistoryHost = null
    state.queuedHistoryGeneration = -1
    startHistoryRead()
  }

  function showHistory() {
    if (!state.hostService) return false
    if (historySourceModel()) {
      syncModels()
      return true
    }
    if (historyReader.running) {
      state.queuedHistoryHost = state.hostService
      state.queuedHistoryGeneration = state.hostGeneration
    } else startHistoryRead()
    return true
  }

  Process {
    id: historyReader
    command: ["sh", "-c", "awk 1 \"$1\"/*.json", "--",
      Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: state.historyOutput = text
    }
    stderr: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running)
      Qt.callLater(root.startQueuedHistoryRead)
    onExited: function(exitCode, _exitStatus) {
      const current = state.hostService === state.historyReadHost
        && state.hostGeneration === state.historyReadGeneration
      state.historyReadHost = null
      state.historyReadGeneration = -1
      if (current)
        root.applyHistory(exitCode === 0 ? state.historyOutput : "")
    }
  }

  Connections {
    target: root.sourceModel()
    ignoreUnknownSignals: true
    function onRowsInserted() { root.syncModels() }
    function onRowsRemoved() { root.syncModels() }
    function onDataChanged() { root.syncModels() }
    function onModelReset() { root.syncModels() }
  }

  Connections {
    target: root.historySourceModel()
    ignoreUnknownSignals: true
    function onRowsInserted() { root.syncModels() }
    function onRowsRemoved() { root.syncModels() }
    function onDataChanged() { root.syncModels() }
    function onModelReset() { root.syncModels() }
  }

  Connections {
    target: state.hostService
    ignoreUnknownSignals: true
    function onPopupModelChanged() { root.syncModels() }
    function onPendingModelChanged() { root.syncModels() }
    function onPastModelChanged() { root.syncModels() }
    function onDoNotDisturbChanged() { root.syncModels() }
  }
}
