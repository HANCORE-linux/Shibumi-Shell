pragma ComponentBehavior: Bound

import QtQuick

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
    property bool historyReplayActive: false
    property var liveKeys: []
    property var lateLiveRows: []
    property var dismissedHistoryKeys: []
    property bool suppressReplay: false
    property double historyReplayCutoff: 0
    property double suppressionCutoff: 0
  }

  readonly property bool available: state.hostService !== null
  readonly property bool doNotDisturb: available
    && state.hostService.doNotDisturb === true
  readonly property int pendingCount: pendingRows.count
  readonly property int recentCount: pastRows.count
  readonly property bool historyAvailable: available
    && (historySourceModel() !== null
      || typeof state.hostService.showRecentHistory === "function"
      || typeof state.hostService.showHistory === "function")
  readonly property bool pastDismissAvailable: available
    && (typeof state.hostService.dismissPast === "function"
      || typeof state.hostService.dismissPopup === "function")
  property alias pendingModel: pendingRows
  property alias pastModel: pastRows

  ListModel { id: pendingRows }
  ListModel { id: pastRows }

  function attachShell(shellValue) {
    const service = shellValue
      && typeof shellValue.firstPartyServiceFor === "function"
      ? shellValue.firstPartyServiceFor("omarchy.notifications") : null
    state.hostService = service || null
    state.historyReplayActive = false
    state.liveKeys = []
    state.lateLiveRows = []
    state.dismissedHistoryKeys = []
    state.suppressReplay = false
    state.historyReplayCutoff = 0
    state.suppressionCutoff = 0
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

  function entryKey(entry) {
    const value = entry || ({})
    return String(Number(value.timestamp || 0)) + ":"
      + String(Number(value.originalId || value.id || 0))
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

  function rememberLateLiveRows(model) {
    if (!state.historyReplayActive || !model
        || typeof model.get !== "function") return
    for (let index = 0; index < model.count; index++) {
      const entry = model.get(index)
      if (!entry || Number(entry.originalId || entry.id || 0) < 0) continue
      const key = entryKey(entry)
      const timestamp = Number(entry.timestamp || 0)
      if (state.liveKeys.indexOf(key) >= 0
          || state.historyReplayCutoff <= 0
          || timestamp < state.historyReplayCutoff
          || state.lateLiveRows.some(row => entryKey(row) === key)) continue
      state.lateLiveRows.push(primitiveEntry(entry))
    }
  }

  function rebuildReplayModels(model) {
    pendingRows.clear()
    pastRows.clear()
    const lateKeys = []
    for (const entry of state.lateLiveRows) {
      lateKeys.push(entryKey(entry))
      pendingRows.append(entry)
    }
    if (!model || typeof model.get !== "function") return
    for (let index = 0; index < model.count; index++) {
      const entry = model.get(index)
      if (!entry || Number(entry.originalId || entry.id || 0) < 0
          || lateKeys.indexOf(entryKey(entry)) >= 0
          || state.dismissedHistoryKeys.indexOf(entryKey(entry)) >= 0)
        continue
      const timestamp = Number(entry.timestamp || 0)
      const isNewLive = state.historyReplayCutoff > 0
        && timestamp >= state.historyReplayCutoff
      const target = state.liveKeys.indexOf(entryKey(entry)) >= 0 || isNewLive
        ? pendingRows : pastRows
      target.append(primitiveEntry(entry))
    }
  }

  function rebuildSuppressedModels(model) {
    pendingRows.clear()
    pastRows.clear()
    if (!model || typeof model.get !== "function") return
    for (let index = 0; index < model.count; index++) {
      const entry = model.get(index)
      if (!entry || Number(entry.originalId || entry.id || 0) < 0) continue
      if (Number(entry.timestamp || 0) >= state.suppressionCutoff)
        pendingRows.append(primitiveEntry(entry))
    }
  }

  function syncModels() {
    const current = sourceModel()
    const archived = historySourceModel()
    rememberLateLiveRows(current)
    if (state.suppressReplay && !archived)
      rebuildSuppressedModels(current)
    else if (state.historyReplayActive && !archived)
      rebuildReplayModels(current)
    else {
      rebuild(pendingRows, current)
      // The current host intentionally exposes only live popupModel rows. Its
      // history is available through showRecentHistory(), not as a public
      // model; keep the recent model empty until that action is requested.
      rebuild(pastRows, archived)
    }
  }

  function removeBufferedEntry(entry) {
    const key = entryKey(entry)
    let removed = false
    for (let index = state.lateLiveRows.length - 1; index >= 0; index--) {
      if (entryKey(state.lateLiveRows[index]) !== key) continue
      state.lateLiveRows.splice(index, 1)
      removed = true
    }
    for (let index = state.liveKeys.length - 1; index >= 0; index--) {
      if (state.liveKeys[index] !== key) continue
      state.liveKeys.splice(index, 1)
      removed = true
    }
    return removed
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
    const buffered = removeBufferedEntry(entry)
    const source = sourceIndex(entry, sourceModel())
    if (source < 0) {
      if (!buffered) return false
      syncModels()
      return true
    }
    if (typeof service.dismissPopup !== "function") return false
    service.dismissPopup(source)
    return true
  }

  function dismissPast(index) {
    const service = state.hostService
    if (!service || index < 0 || index >= pastRows.count) return false
    const entry = pastRows.get(index)
    const key = entryKey(entry)
    if (typeof service.dismissPast === "function") {
      service.dismissPast(index)
      return true
    }
    const source = sourceIndex(entry, sourceModel())
    if (source < 0 || typeof service.dismissPopup !== "function") return false
    state.dismissedHistoryKeys = state.dismissedHistoryKeys.concat([key])
    service.dismissPopup(source)
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
      state.liveKeys = []
      state.lateLiveRows = []
      state.dismissedHistoryKeys = []
      state.historyReplayActive = false
      state.suppressReplay = true
      state.historyReplayCutoff = 0
      state.suppressionCutoff = Date.now()
      syncModels()
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

  function showHistory() {
    const service = state.hostService
    if (!service) return false
    const archived = historySourceModel()
    if (archived) {
      syncModels()
      return true
    }

    const current = sourceModel()
    state.liveKeys = []
    state.lateLiveRows = []
    state.dismissedHistoryKeys = []
    if (state.historyReplayActive) {
      for (let index = 0; index < pendingRows.count; index++)
        state.liveKeys.push(entryKey(pendingRows.get(index)))
    } else if (current && typeof current.get === "function") {
      for (let index = 0; index < current.count; index++)
        state.liveKeys.push(entryKey(current.get(index)))
    }
    state.suppressReplay = false
    state.suppressionCutoff = 0
    state.historyReplayCutoff = Date.now()
    state.historyReplayActive = true
    syncModels()
    if (typeof service.showRecentHistory === "function") {
      service.showRecentHistory()
      return true
    }
    if (typeof service.showHistory === "function") {
      service.showHistory()
      return true
    }
    state.historyReplayActive = false
    syncModels()
    return false
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
