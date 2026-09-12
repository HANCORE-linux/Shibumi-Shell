pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "SearchEngine.js" as SearchEngine

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool motionActive: false
  property bool favoritesOnly: false
  property string selectedProvider: "All"
  property string pluginQuery: ""
  property bool activeExpanded: false
  property bool availableExpanded: false
  property bool feedbackVisible: false
  property string feedbackTitle: ""
  property string feedbackDetail: ""
  property string undoMode: ""
  property string undoPluginId: ""
  property bool undoPluginValue: false
  property string undoGroup: ""
  property var undoGroups: []
  property var undoGroupStates: ({})
  property var undoProviderSnapshot: null
  property var undoPluginIds: []
  property var pendingPluginMutation: null
  property var pendingUndoRestore: null
  property bool pageComplete: false
  readonly property bool transitionPending:
    pendingPluginMutation !== null || pendingUndoRestore !== null
  property real feedbackProgress: 0
  readonly property real boundedFeedbackProgress:
    Math.max(0, Math.min(1, feedbackProgress))
  readonly property real feedbackProgressInset: Math.max(
    Commons.Style.space(4), Number(controller.controlRadius || 0))
  readonly property real feedbackProgressAvailableWidth: Math.max(0,
    statusSlot.width - 2 * feedbackProgressInset)
  readonly property real feedbackProgressRenderedWidth:
    feedbackProgressBar.width
  property bool removalConfirmationVisible: false
  property string pendingRemovalId: ""
  property string pendingRemovalName: ""
  property string removingPluginId: ""
  property string removingPluginName: ""
  property bool pluginUpdateConsumerActive: false
  property var leasedPluginUpdateService: null
  property var catalogConsumerService: null
  property var catalogConsumerToken: null
  readonly property var catalogServiceCandidate: {
    const service = controller.effectivePluginUpdateService || null
    try {
      return service && service.scopedHost === true
          && typeof service.acquireCatalogConsumer === "function"
          && typeof service.releaseCatalogConsumer === "function"
          && typeof service.hasCatalogConsumer === "function"
          && typeof service.catalogObservation === "function"
          && typeof service.isCatalogObservationCurrent === "function"
        ? service : null
    } catch (error) { return null }
  }
  readonly property bool catalogConsumerActive: {
    try {
      return catalogConsumerService !== null && catalogConsumerToken !== null
        && catalogConsumerService === catalogServiceCandidate
        && catalogConsumerService.hasCatalogConsumer(catalogConsumerToken)
    } catch (error) { return false }
  }
  readonly property var catalogObservation: {
    const service = catalogConsumerService
    const token = catalogConsumerToken
    if (!catalogConsumerActive || !service || !token) return null
    try {
      if ("catalogReady" in service) void(service.catalogReady)
      if ("catalogReadSerial" in service) void(service.catalogReadSerial)
      if ("catalogGeneration" in service) void(service.catalogGeneration)
      const observation = service.catalogObservation(token)
      return observation
          && service.isCatalogObservationCurrent(token, observation)
        ? observation : null
    } catch (error) { return null }
  }

  readonly property var allEntries: (controller.pluginEntries || [])
    .filter(function(entry) {
      return entry.userToggleable === true
        && entry.styleAvailable !== false
    })
  readonly property var providerEntries: allEntries.filter(function(entry) {
    const providerMatch = root.selectedProvider === "All"
      || (root.selectedProvider === "Active"
        ? entry.installedInBar === true || entry.replaced === true
        : entry.provider === root.selectedProvider)
    return providerMatch
  })
  readonly property var scopedEntries: favoritesOnly
    ? providerEntries.filter(function(entry) {
        return controller.pluginFavorite(entry.id)
      })
    : providerEntries
  readonly property var filteredEntries:
    SearchEngine.filterAndRank(scopedEntries, pluginQuery)
  readonly property var searchSuggestions: pluginSearch.suggestions
  readonly property int activeSearchSuggestion:
    pluginSearch.activeSuggestionIndex
  readonly property string searchGhostText: pluginSearch.ghostText
  readonly property bool searchInputActiveFocus:
    pluginSearch.inputActiveFocus
  readonly property var providerSwitchEntries: filteredEntries.filter(
    function(entry) {
      return entry.replacementInEffect === true || entry.replaced === true
    }).sort(function(left, right) {
      const leftFamily = String(
        left.replacementGroup || left.group || "")
      const rightFamily = String(
        right.replacementGroup || right.group || "")
      const familyOrder = leftFamily.localeCompare(rightFamily)
      if (familyOrder !== 0) return familyOrder
      if (left.replacementInEffect === right.replacementInEffect) return 0
      return left.replacementInEffect === true ? -1 : 1
    })
  readonly property var activeEntries: filteredEntries.filter(function(entry) {
    return entry.installedInBar === true
      && entry.replacementInEffect !== true
  })
  readonly property var availableEntries: filteredEntries.filter(
    function(entry) {
      return entry.installedInBar !== true && entry.replaced !== true
    })
  readonly property var displayedActiveEntries:
    activeExpanded || pluginQuery.trim() !== "" ? activeEntries : []
  readonly property var displayedAvailableEntries:
    availableExpanded || pluginQuery.trim() !== "" ? availableEntries : []
  readonly property int activeCount: allEntries.filter(function(entry) {
    return entry.installedInBar === true
  }).length
  readonly property int availableCount: allEntries.length - activeCount
  readonly property int shibumiProviderCount:
    providerCatalogCount("Shibumi")
  readonly property int omarchyProviderCount:
    providerCatalogCount("Omarchy Quattro")
  readonly property int thirdPartyProviderCount:
    providerCatalogCount("Third-party")
  readonly property int favoriteCount: allEntries.filter(function(entry) {
    return controller.pluginFavorite(entry.id)
  }).length
  readonly property color undoColor:
    typeof controller.accentColor === "function"
      ? controller.accentColor("color01") : accent
  readonly property color activeCountColor:
    typeof controller.accentColor === "function"
      ? controller.accentColor("color03") : accent
  readonly property color availableCountColor:
    typeof controller.accentColor === "function"
      ? controller.accentColor("color02") : accent
  readonly property color pluginUpdateStatusColor:
    controller.pluginUpdateCheckError !== ""
      || controller.pluginUpdateFailedCount > 0
      ? (typeof controller.accentColor === "function"
        ? controller.accentColor("color01") : Commons.Color.urgent)
      : controller.pluginUpdateCount > 0 ? accent : foreground
  readonly property bool feedbackCountdownRunning:
    feedbackCountdown.running
  readonly property bool feedbackCountdownPaused:
    feedbackCountdown.paused
  readonly property bool ready:
    providerSwitchRepeater.count === providerSwitchEntries.length
    && activeRepeater.count === displayedActiveEntries.length
    && availableRepeater.count === displayedAvailableEntries.length
    && (!motionActive || favoritesOnly || pluginUpdateConsumerActive)
    && (catalogServiceCandidate === null
      || (catalogConsumerActive && catalogObservation !== null))

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  function entryById(pluginId) {
    const id = String(pluginId || "")
    for (let index = 0; index < root.allEntries.length; index++) {
      if (String(root.allEntries[index].id || "") === id)
        return root.allEntries[index]
    }
    return null
  }

  function providerCatalogCount(provider) {
    const requested = String(provider || "")
    return allEntries.filter(function(entry) {
      return String(entry.provider || "") === requested
    }).length
  }

  function acceptSearchSuggestion(index) {
    return pluginSearch.acceptSuggestion(index)
  }

  function moveSearchSuggestion(offset) {
    return pluginSearch.moveSuggestion(offset)
  }

  function focusPluginSearch() {
    pluginSearch.forceInputFocus()
    return true
  }

  function setPluginSearchQuery(value) {
    pluginSearch.suggestionsSuppressed = false
    pluginSearch.activeSuggestionIndex = -1
    pluginSearch.text = String(value || "")
    applyPluginSearchQuery(pluginSearch.text)
    return true
  }

  function applyPluginSearchQuery(value) {
    const next = String(value || "")
    if (!favoritesOnly && next.trim() !== ""
        && selectedProvider === "Active")
      selectedProvider = "All"
    pluginQuery = next
  }

  function dismissPluginSearch() {
    return pluginSearch.handleEscape()
  }

  function blurPluginSearch() {
    return pluginSearch.blur()
  }

  function searchContainsPoint(sourceItem, x, y) {
    const local = pluginSearch.mapFromItem(sourceItem, x, y)
    return local.x >= 0 && local.x <= pluginSearch.width
      && local.y >= 0
      && local.y <= pluginSearch.height + pluginSearch.reservedPopupHeight
  }

  function transitionSucceeded(result) {
    return ["confirmed", "unchanged"].indexOf(String(result || "")) >= 0
  }

  function transitionFailureDetail(result) {
    const value = String(result || "")
    if (value === "state-refused")
      return "The saved widget state was refused or could not be confirmed."
    if (value === "revoked")
      return "The active bar changed before the widget request completed."
    if (value === "native-indeterminate")
      return "Omarchy did not confirm the final native bar layout."
    if (value.indexOf("timeout") >= 0)
      return "The widget request timed out before it could be confirmed."
    if (value === "conflict")
      return "A newer bar-layout change replaced this widget request."
    if (value === "compensated")
      return "The native layout refused the request; saved widget state was restored."
    return "The widget request did not reach a confirmed layout."
  }

  function feedbackRecord(title, detail, mode, pluginId, value, group, ids,
      groupValues, groupStates, providerSnapshot) {
    return {
      title: String(title || ""), detail: String(detail || ""),
      mode: String(mode || ""), pluginId: String(pluginId || ""),
      pluginValue: value === true, group: String(group || ""),
      ids: Array.isArray(ids) ? ids.slice() : [],
      groups: Array.isArray(groupValues) ? groupValues.slice() : [],
      groupStates: groupStates && typeof groupStates === "object"
        ? JSON.parse(JSON.stringify(groupStates)) : ({}),
      providerSnapshot: providerSnapshot
          && typeof providerSnapshot === "object"
        ? JSON.parse(JSON.stringify(providerSnapshot)) : null
    }
  }

  function publishFeedbackRecord(record) {
    showFeedback(record.title, record.detail, record.mode,
      record.pluginId, record.pluginValue, record.group, record.ids,
      record.groups, record.groupStates, record.providerSnapshot)
  }

  function beginAcceptedPluginRequest(beforeLayoutSerial, beforeStateSerial,
      name, record) {
    const layoutSerial = Number(controller.pluginLayoutTransitionSerial || 0)
    const stateSerial = Number(controller.pluginStateTransitionSerial || 0)
    const channel = layoutSerial > beforeLayoutSerial ? "layout"
      : stateSerial > beforeStateSerial ? "state" : ""
    if (channel === "") {
      publishFeedbackRecord(record)
      return true
    }
    const serial = channel === "layout" ? layoutSerial : stateSerial
    const busy = channel === "layout"
      ? controller.pluginLayoutTransitionBusy === true
      : controller.pluginStateTransitionBusy === true
    if (!busy) {
      showFeedback(name + " could not be changed",
        "The bar did not retain the accepted request.",
        "", "", false, "", [])
      return false
    }
    pendingPluginMutation = {
      owner: controller,
      serial: serial,
      channel: channel,
      name: String(name || "Plugin"),
      feedback: record
    }
    feedbackTimer.stop()
    feedbackCountdown.stop()
    feedbackVisible = true
    feedbackTitle = "Updating " + String(name || "plugin") + " …"
    feedbackDetail = channel === "layout"
      ? "Waiting for saved state and the native bar layout."
      : "Waiting for the saved widget state."
    clearUndoState()
    return true
  }

  function settlePluginMutation(serial, result, channel) {
    const pending = pendingPluginMutation
    if (!pending || pending.serial !== serial
        || pending.channel !== channel) return false
    pendingPluginMutation = null
    if (pending.owner !== controller) return false
    if (transitionSucceeded(result)) {
      if (pending.feedback.mode === "provider-snapshot") {
        const snapshot = typeof controller.confirmedProviderUndoSnapshot
          === "function"
          ? controller.confirmedProviderUndoSnapshot(serial) : null
        if (!snapshot) {
          showFeedback(pending.feedback.title,
            "The change completed, but its exact previous layout was not retained for Undo.",
            "", "", false, "", [])
          return false
        }
        pending.feedback.providerSnapshot = snapshot
      }
      publishFeedbackRecord(pending.feedback)
      return true
    }
    showFeedback(pending.name + " could not be changed",
      transitionFailureDetail(result), "", "", false, "", [])
    return false
  }

  function settleUndoRestore(serial, result, channel) {
    const pending = pendingUndoRestore
    if (!pending || pending.serial !== serial
        || pending.channel !== channel) return false
    pendingUndoRestore = null
    if (pending.owner !== controller) return false
    if (transitionSucceeded(result)) {
      feedbackVisible = false
      clearUndoState()
      return true
    }
    // Keep the exact Undo payload for an explicit retry after a failed async
    // restore. Acceptance is never presented as persistence completion.
    feedbackVisible = true
    feedbackTitle = "Undo could not be completed"
    feedbackDetail = transitionFailureDetail(result)
    feedbackProgress = 1
    feedbackCountdown.start()
    return false
  }

  function showFeedback(title, detail, mode, pluginId, value, group, ids,
      groupValues, groupStates, providerSnapshot) {
    feedbackTimer.stop()
    feedbackCountdown.stop()
    removalConfirmationVisible = false
    feedbackTitle = String(title || "")
    feedbackDetail = String(detail || "")
    undoMode = String(mode || "")
    undoPluginId = String(pluginId || "")
    undoPluginValue = value === true
    undoGroup = String(group || "")
    undoGroups = Array.isArray(groupValues) ? groupValues.slice()
      : undoGroup !== "" ? [undoGroup] : []
    undoGroupStates = groupStates && typeof groupStates === "object"
      ? JSON.parse(JSON.stringify(groupStates)) : ({})
    undoProviderSnapshot = providerSnapshot
      && typeof providerSnapshot === "object"
      ? JSON.parse(JSON.stringify(providerSnapshot)) : null
    undoPluginIds = Array.isArray(ids) ? ids.slice() : []
    feedbackVisible = true
    feedbackProgress = 1
    if (undoMode !== "") feedbackCountdown.start()
    else feedbackTimer.restart()
  }

  function clearUndoState() {
    undoMode = ""
    undoPluginId = ""
    undoPluginValue = false
    undoGroup = ""
    undoGroups = []
    undoGroupStates = ({})
    undoProviderSnapshot = null
    undoPluginIds = []
    feedbackProgress = 0
  }

  function expireFeedback() {
    feedbackTimer.stop()
    feedbackCountdown.stop()
    feedbackVisible = false
    clearUndoState()
  }

  function requestPluginRemoval(entry) {
    if (!entry || entry.removable !== true || transitionPending
        || controller.pluginRemovalRunning === true) return false
    feedbackTimer.stop()
    feedbackCountdown.stop()
    feedbackVisible = false
    clearUndoState()
    pendingRemovalId = String(entry.id || "")
    pendingRemovalName = String(entry.name || pendingRemovalId)
    removalConfirmationVisible = pendingRemovalId !== ""
    return removalConfirmationVisible
  }

  function requestPluginRemovalById(pluginId) {
    return requestPluginRemoval(entryById(pluginId))
  }

  function cancelPluginRemoval() {
    removalConfirmationVisible = false
    pendingRemovalId = ""
    pendingRemovalName = ""
  }

  function confirmPluginRemoval() {
    if (!removalConfirmationVisible || pendingRemovalId === ""
        || controller.pluginRemovalRunning === true) return false
    const id = pendingRemovalId
    removingPluginId = id
    removingPluginName = pendingRemovalName
    removalConfirmationVisible = false
    feedbackTitle = "Removing " + pendingRemovalName + " …"
    feedbackDetail = "Disabling and deleting the installed plugin."
    feedbackVisible = true
    clearUndoState()
    if (controller.removePlugin(id)) {
      pendingRemovalId = ""
      pendingRemovalName = ""
      return true
    }
    removingPluginId = ""
    feedbackTitle = "Plugin could not be removed"
    feedbackDetail = String(controller.pluginActionError
      || "The provider rejected the remove request.")
    feedbackTimer.restart()
    return false
  }

  function togglePlugin(entry) {
    if (!entry || transitionPending) return false
    if (typeof controller.pluginActivationAvailable === "function"
        && !controller.pluginActivationAvailable(entry)) {
      showFeedback("Action unavailable",
        "Omarchy has not published a current component authority for this widget.",
        "", "", false, "", [])
      return false
    }
    const id = String(entry.id || "")
    const name = String(entry.name || id)
    const providerSnapshot = typeof controller.providerUndoSnapshot
      === "function" ? controller.providerUndoSnapshot(id) : null
    const transitionSerial = Number(
      controller.pluginLayoutTransitionSerial || 0)
    const stateTransitionSerial = Number(
      controller.pluginStateTransitionSerial || 0)

    if (entry.replaced === true) {
      const alternatives = Array.isArray(entry.replacedByIds)
        ? entry.replacedByIds.slice() : []
      const replacementName = String(entry.replacedBy || "alternative")
      if (controller.nativeCatalogRequired === true && !providerSnapshot) {
        showFeedback(name + " could not be restored",
          "The current provider layout could not be captured safely.",
          "", "", false, "", [])
        return false
      }
      if (!controller.setPluginEnabled(id, true)) {
        showFeedback(
          name + " could not be restored",
          String(controller.pluginActionError
            || "The provider rejected the request."),
          "", "", false, "", [])
        return false
      }
      return beginAcceptedPluginRequest(
        transitionSerial, stateTransitionSerial, name,
        feedbackRecord(name + " restored",
          replacementName + " was removed to avoid duplicates.",
          providerSnapshot ? "provider-snapshot" : "plugins",
          "", false, "", alternatives, [], ({}), providerSnapshot))
    }

    const wasEnabled = entry.installedInBar === true
    const enable = !wasEnabled
    const group = String(entry.replacementGroup || "")
    const groups = Array.isArray(entry.replacementGroups)
      ? entry.replacementGroups.slice()
      : group !== "" ? [group] : []
    const target = String(entry.replacementTarget || "Shibumi widget")
    const targetStates = entry.replacementTargetStates || ({})
    const targetWasEnabled = entry.replacementTargetEnabled === true
    const displacedProviderIds = Array.isArray(entry.conflictingProviderIds)
      ? entry.conflictingProviderIds.slice() : []
    const displacedProviderStates = entry.conflictingProviderStates || ({})
    const providerChange = enable && (displacedProviderIds.length > 0
      || group !== "" && targetWasEnabled)
    if (controller.nativeCatalogRequired === true && providerChange
        && !providerSnapshot) {
      showFeedback(name + " could not be activated",
        "The current provider layout could not be captured safely.",
        "", "", false, "", [])
      return false
    }
    if (!controller.setPluginEnabled(id, enable)) {
      showFeedback(
        name + (enable ? " could not be activated"
          : " could not be deactivated"),
        String(controller.pluginActionError
          || "The provider rejected the request."),
        "", "", false, "", [])
      return false
    }

    let record = null
    if (enable && displacedProviderIds.length > 0) {
      record = feedbackRecord(name + " activated",
        displacedProviderIds.length === 1
          ? displacedProviderIds[0] + " was replaced to avoid duplicates."
          : displacedProviderIds.length
            + " conflicting providers were replaced to avoid duplicates.",
        providerSnapshot ? "provider-snapshot" : "plugins",
        "", false, "", displacedProviderIds, [],
        displacedProviderStates, providerSnapshot)
    } else if (enable && group !== "" && targetWasEnabled) {
      record = feedbackRecord(name + " activated",
        target + " was hidden to avoid duplicates.",
        providerSnapshot ? "provider-snapshot" : "restore-group",
        "", false, group, [], groups, targetStates, providerSnapshot)
    } else {
      record = feedbackRecord(
        name + (enable ? " activated" : " deactivated"),
        enable ? "The plugin is now visible in the active bar."
          : "The plugin was removed from the active bar.",
        "plugin-value", id, wasEnabled, "", [])
    }
    return beginAcceptedPluginRequest(
      transitionSerial, stateTransitionSerial, name, record)
  }

  function togglePluginById(pluginId) {
    return togglePlugin(entryById(pluginId))
  }

  function toggleFavorite(entry) {
    if (!entry) return false
    const id = String(entry.id || "")
    return controller.setPluginFavorite(
      id, !controller.pluginFavorite(id))
  }

  function toggleFavoriteById(pluginId) {
    return toggleFavorite(entryById(pluginId))
  }

  function undoLastChange() {
    if (transitionPending) return false
    feedbackTimer.stop()
    feedbackCountdown.stop()
    const beforeLayoutSerial = Number(
      controller.pluginLayoutTransitionSerial || 0)
    const beforeProviderSerial = Number(
      controller.providerSnapshotTransitionSerial || 0)
    const beforeStateSerial = Number(
      controller.pluginStateTransitionSerial || 0)
    let restored = false
    if (undoMode === "provider-snapshot") {
      restored = typeof controller.restoreProviderUndoSnapshot === "function"
        && controller.restoreProviderUndoSnapshot(undoProviderSnapshot)
    } else if (undoMode === "restore-group") {
      restored = Object.keys(undoGroupStates).length > 0
        && typeof controller.restoreShibumiProviderStates === "function"
        ? controller.restoreShibumiProviderStates(undoGroupStates)
        : typeof controller.restoreShibumiProviders === "function"
          ? controller.restoreShibumiProviders(undoGroups)
          : controller.restoreShibumiProvider(undoGroup)
    } else if (undoMode === "plugins") {
      restored = true
      for (let index = 0; index < undoPluginIds.length; index++)
        restored = controller.setPluginEnabled(undoPluginIds[index], true)
          && restored
      if (restored && Object.keys(undoGroupStates).length > 0)
        restored = typeof controller.setProviderGroupStates === "function"
          && controller.setProviderGroupStates(undoGroupStates)
    } else if (undoMode === "plugin-value") {
      restored = controller.setPluginEnabled(
        undoPluginId, undoPluginValue)
    }
    if (!restored) {
      feedbackVisible = true
      feedbackTitle = "Undo could not be completed"
      feedbackDetail = String(controller.pluginActionError
        || "The previous provider layout was not restored.")
      feedbackProgress = 1
      feedbackCountdown.start()
      return false
    }
    const providerSerial = Number(
      controller.providerSnapshotTransitionSerial || 0)
    const layoutSerial = Number(
      controller.pluginLayoutTransitionSerial || 0)
    const stateSerial = Number(
      controller.pluginStateTransitionSerial || 0)
    const channel = providerSerial > beforeProviderSerial
      ? "provider" : layoutSerial > beforeLayoutSerial ? "layout"
        : stateSerial > beforeStateSerial ? "state" : ""
    const serial = channel === "provider" ? providerSerial
      : channel === "layout" ? layoutSerial : stateSerial
    const busy = channel === "provider"
      ? controller.providerSnapshotTransitionBusy === true
      : channel === "layout"
        ? controller.pluginLayoutTransitionBusy === true
        : channel === "state"
          ? controller.pluginStateTransitionBusy === true : false
    if (channel !== "") {
      if (!busy) {
        feedbackVisible = true
        feedbackTitle = "Undo could not be completed"
        feedbackDetail = "The bar did not retain the accepted restore request."
        feedbackProgress = 1
        feedbackCountdown.start()
        return false
      }
      pendingUndoRestore = {
        owner: controller, serial: serial, channel: channel
      }
      feedbackVisible = true
      feedbackTitle = "Restoring previous provider …"
      feedbackDetail = "Waiting for saved state and the native bar layout."
      feedbackProgress = 1
      return true
    }
    feedbackVisible = false
    clearUndoState()
    return true
  }

  function releaseCatalogConsumer() {
    const service = catalogConsumerService
    const token = catalogConsumerToken
    catalogConsumerService = null
    catalogConsumerToken = null
    if (!service || !token) return false
    try { return service.releaseCatalogConsumer(token) === true }
    catch (error) { return false }
  }

  function syncCatalogConsumer() {
    const next = catalogServiceCandidate
    if (catalogConsumerService === next && catalogConsumerToken) {
      try {
        if (next && next.hasCatalogConsumer(catalogConsumerToken)) return true
      } catch (error) {}
    }
    releaseCatalogConsumer()
    if (!next) return false
    let token = null
    try { token = next.acquireCatalogConsumer(root) }
    catch (error) { token = null }
    if (!token) return false
    if (next !== catalogServiceCandidate) {
      try { next.releaseCatalogConsumer(token) }
      catch (error) {}
      catalogConsumerSync.restart()
      return false
    }
    try {
      if (!next.hasCatalogConsumer(token)) {
        next.releaseCatalogConsumer(token)
        return false
      }
    } catch (error) {
      try { next.releaseCatalogConsumer(token) }
      catch (releaseError) {}
      return false
    }
    catalogConsumerService = next
    catalogConsumerToken = token
    return true
  }

  function requestCatalogRefresh() {
    const service = catalogConsumerService
    const token = catalogConsumerToken
    if (!catalogConsumerActive || !service || !token
        || typeof service.requestCatalogRefresh !== "function") return false
    try { return service.requestCatalogRefresh(token) === true }
    catch (error) { return false }
  }

  function syncPluginUpdateConsumer() {
    const next = motionActive && !favoritesOnly
      ? (controller.effectivePluginUpdateService || null) : null
    if (leasedPluginUpdateService === next) return false
    if (leasedPluginUpdateService)
      leasedPluginUpdateService.releaseConsumer()
    leasedPluginUpdateService = next
    pluginUpdateConsumerActive = next !== null
    if (next) next.acquireConsumer()
    return true
  }

  onMotionActiveChanged: pluginUpdateConsumerSync.restart()
  onFavoritesOnlyChanged: pluginUpdateConsumerSync.restart()
  onCatalogServiceCandidateChanged: catalogConsumerSync.restart()
  onControllerChanged: {
    if (!pageComplete) return
    pendingPluginMutation = null
    pendingUndoRestore = null
    feedbackVisible = false
    clearUndoState()
    if (leasedPluginUpdateService)
      leasedPluginUpdateService.releaseConsumer()
    leasedPluginUpdateService = null
    pluginUpdateConsumerActive = false
    pluginUpdateConsumerSync.restart()
  }
  Component.onCompleted: {
    pageComplete = true
    pluginUpdateConsumerSync.restart()
    catalogConsumerSync.restart()
  }
  Component.onDestruction: {
    pendingPluginMutation = null
    pendingUndoRestore = null
    if (leasedPluginUpdateService) leasedPluginUpdateService.releaseConsumer()
    leasedPluginUpdateService = null
    pluginUpdateConsumerActive = false
    releaseCatalogConsumer()
  }

  Timer {
    id: catalogConsumerSync
    interval: 0
    repeat: false
    onTriggered: root.syncCatalogConsumer()
  }

  Timer {
    id: pluginUpdateConsumerSync
    interval: 0
    repeat: false
    onTriggered: root.syncPluginUpdateConsumer()
  }

  Connections {
    target: root.controller
    ignoreUnknownSignals: true

    function onEffectivePluginUpdateServiceChanged() {
      pluginUpdateConsumerSync.restart()
      catalogConsumerSync.restart()
    }

    function onPluginLayoutTransitionSettled(serial, result) {
      if (!root.settleUndoRestore(serial, result, "layout"))
        root.settlePluginMutation(serial, result, "layout")
    }

    function onProviderSnapshotTransitionSettled(serial, result) {
      root.settleUndoRestore(serial, result, "provider")
    }

    function onPluginStateTransitionSettled(serial, result) {
      if (!root.settleUndoRestore(serial, result, "state"))
        root.settlePluginMutation(serial, result, "state")
    }

    function onPluginRemovalFinished(pluginId, success, detail) {
      if (String(pluginId || "") !== root.removingPluginId) return
      const removedName = root.removingPluginName !== ""
        ? root.removingPluginName : String(pluginId || "")
      root.removingPluginId = ""
      root.removingPluginName = ""
      feedbackCountdown.stop()
      root.clearUndoState()
      root.feedbackVisible = true
      root.feedbackTitle = success
        ? removedName + " removed" : "Removal failed"
      root.feedbackDetail = success
        ? (String(detail || "") || "The plugin is no longer installed.")
        : (String(detail || "") || "The installed plugin was left untouched.")
      feedbackTimer.restart()
    }
  }

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "plugins"
    eyebrow: "BAR PLUGINS"
    title: root.favoritesOnly ? "Favorites" : "Plugins"
    description: root.favoritesOnly
      ? root.favoriteCount + " saved plugins" : ""
    descriptionComponent: root.favoritesOnly ? null : providerSummary
    preferredHeight: root.favoritesOnly
      ? Commons.Style.space(80) : Commons.Style.space(110)
    actionWidth: Commons.Style.space(132)
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    actionLabel: "Add plugin"
    actionGlyph: "add"
    secondaryActionLabel: root.favoritesOnly ? "" : "Check plugins"
    secondaryActionGlyph: "refresh"
    secondaryActionEnabled: !root.controller.pluginUpdateCheckRunning
    secondaryActionStatusText: root.favoritesOnly ? ""
      : root.controller.pluginUpdateShortStatusText
    secondaryActionDescription: root.favoritesOnly ? ""
      : root.controller.pluginUpdateStatusText
    secondaryActionStatusColor: root.pluginUpdateStatusColor
    onActionRequested: root.controller.openPluginInstaller()
    onSecondaryActionRequested: root.controller.openPluginUpdater()
  }

  Component {
    id: providerSummary

    PluginProviderSummary {
      controller: root.controller
      shibumiCount: root.shibumiProviderCount
      omarchyCount: root.omarchyProviderCount
      thirdPartyCount: root.thirdPartyProviderCount
      active: root.motionActive
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
    }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: root.controller.dividerColor
  }

  ProviderFilter {
    width: parent.width
    controller: root.controller
    title: "FILTER"
    options: ["All", "Active", "Shibumi", "Omarchy Quattro", "Third-party"]
    selectedProvider: root.selectedProvider
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onSelected: function(provider) { root.selectedProvider = provider }
  }

  Rectangle {
    id: statusSlot
    z: pluginSearch.suggestionsVisible ? 60 : 0
    width: parent.width
    height: Commons.Style.space(42) + pluginSearch.reservedPopupHeight
    radius: root.controller.controlRadius
    color: root.feedbackVisible || root.removalConfirmationVisible
      ? Commons.Util.alpha(root.accent, 0.08) : "transparent"
    border.width: root.feedbackVisible
      || root.removalConfirmationVisible ? 1 : 0
    border.color: root.removalConfirmationVisible
      ? Commons.Util.alpha(Commons.Color.urgent, 0.62)
      : root.feedbackVisible
        ? Commons.Util.alpha(root.accent, 0.52)
        : root.controller.controlBorderColor

    HoverHandler {
      id: feedbackHover
      enabled: root.feedbackVisible && root.undoMode !== ""
        && !root.transitionPending
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: Commons.Style.space(4)
      visible: !root.feedbackVisible && !root.removalConfirmationVisible
      height: Commons.Style.space(34)
      radius: root.controller.controlRadius
      color: "transparent"
      border.width: 1
      border.color: root.controller.controlBorderColor

      PredictiveSearchInput {
        id: pluginSearch
        anchors.fill: parent
        controller: root.controller
        entries: root.scopedEntries
        text: root.pluginQuery
        placeholder: "Find plugins, tags, authors, or providers…"
        popupStyle: "catalog"
        suggestionLimit: 4
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onEdited: function(value) { root.applyPluginSearchQuery(value) }
        onCompletionAccepted: function(_completion) {
          root.pluginQuery = pluginSearch.text
        }
      }
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(10)
      anchors.rightMargin: Commons.Style.space(8)
      spacing: Commons.Style.space(8)
      visible: root.feedbackVisible && !root.removalConfirmationVisible

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.removingPluginId !== ""
          ? "hourglass_top" : "swap_horiz"
        color: root.accent
        font.pixelSize: Commons.Style.space(17) * root.uiScale
        fill: 0
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - undoButton.width - parent.spacing
        spacing: Commons.Style.space(1)

        Text {
          width: parent.width
          text: root.feedbackTitle
          color: root.foreground
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: root.feedbackDetail
          color: root.foreground
          opacity: 0.56
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
        }
      }

      Rectangle {
        id: undoButton
        visible: root.undoMode !== "" && !root.transitionPending
        activeFocusOnTab: visible
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? Commons.Style.space(54) : 0
        height: Commons.Style.space(26)
        radius: root.controller.controlRadius
        color: undoPointer.containsMouse
            || activeFocus
          ? Commons.Util.alpha(root.undoColor, 0.18) : "transparent"
        border.width: undoPointer.containsMouse || activeFocus ? 1 : 0
        border.color: Commons.Util.alpha(root.undoColor, 0.62)

        Text {
          anchors.centerIn: parent
          text: "UNDO"
          color: root.undoColor
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
          font.letterSpacing: 0.6
        }

        MouseArea {
          id: undoPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.undoLastChange()
        }

        Keys.onReturnPressed: function(event) {
          root.undoLastChange()
          event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
          root.undoLastChange()
          event.accepted = true
        }
      }
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(10)
      anchors.rightMargin: Commons.Style.space(8)
      spacing: Commons.Style.space(7)
      visible: root.removalConfirmationVisible

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: "delete"
        color: Commons.Color.urgent
        font.pixelSize: Commons.Style.space(17) * root.uiScale
        fill: 0
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - cancelRemoval.width
          - confirmRemoval.width - parent.spacing * 2
        text: "Remove " + root.pendingRemovalName + "?"
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        font.weight: Font.DemiBold
      }

      Rectangle {
        id: cancelRemoval
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(58)
        height: Commons.Style.space(26)
        radius: root.controller.controlRadius
        color: cancelRemovalPointer.containsMouse
          ? root.controller.controlHoverFillColor : "transparent"
        border.width: 1
        border.color: root.controller.controlBorderColor

        Text {
          anchors.centerIn: parent
          text: "CANCEL"
          color: root.foreground
          opacity: 0.72
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: cancelRemovalPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cancelPluginRemoval()
        }
      }

      Rectangle {
        id: confirmRemoval
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(62)
        height: Commons.Style.space(26)
        radius: root.controller.controlRadius
        color: confirmRemovalPointer.containsMouse
          ? Commons.Util.alpha(Commons.Color.urgent, 0.22)
          : Commons.Util.alpha(Commons.Color.urgent, 0.10)
        border.width: 1
        border.color: Commons.Util.alpha(Commons.Color.urgent, 0.68)

        Text {
          anchors.centerIn: parent
          text: "REMOVE"
          color: Commons.Color.urgent
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: confirmRemovalPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.confirmPluginRemoval()
        }
      }
    }

    Rectangle {
      id: feedbackProgressBar
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: root.feedbackProgressInset
      anchors.bottomMargin: Commons.Style.space(2)
      visible: root.feedbackVisible && root.undoMode !== ""
        && !root.transitionPending
      width: root.feedbackProgressAvailableWidth
        * root.boundedFeedbackProgress
      height: 2
      radius: 1
      color: root.undoColor
    }
  }

  Timer {
    id: feedbackTimer
    interval: 7000
    onTriggered: root.expireFeedback()
  }

  NumberAnimation {
    id: feedbackCountdown
    target: root
    property: "feedbackProgress"
    from: 1
    to: 0
    duration: 7000
    paused: feedbackHover.hovered || undoButton.activeFocus
    easing.type: Easing.Linear
    onFinished: {
      if (root.feedbackVisible && root.undoMode !== "")
        root.expireFeedback()
    }
  }

  Text {
    visible: root.filteredEntries.length === 0
    width: parent.width
    text: root.controller.pluginsScanning
      ? "Scanning plugins …"
      : root.favoritesOnly && root.favoriteCount === 0
        ? "No favorites yet. Star any plugin to keep it here."
        : "No matching bar plugins."
    color: root.foreground
    opacity: 0.62
    horizontalAlignment: Text.AlignHCenter
    font.family: Commons.Style.font.menuFamily
    font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
  }

  PluginSectionHeader {
    visible: root.providerSwitchEntries.length > 0
    width: parent.width
    controller: root.controller
    title: "PROVIDER SWITCHES"
    count: root.providerSwitchEntries.length
    countColor: root.accent
    collapsible: false
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  Flow {
    id: providerSwitchDeck
    visible: root.providerSwitchEntries.length > 0
    width: parent.width
    spacing: Commons.Style.space(8)

    Repeater {
      id: providerSwitchRepeater
      model: root.providerSwitchEntries

      delegate: WidgetModuleTile {
        required property var modelData
        width: (providerSwitchDeck.width - providerSwitchDeck.spacing) / 2
        controller: root.controller
        glyph: modelData.glyph
        label: modelData.name
        provider: modelData.provider
        relationship: modelData.replacementLabel || ""
        inserted: modelData.installedInBar === true
        replaced: modelData.replaced === true
        replacedBy: modelData.replacedBy || ""
        removable: modelData.removable === true
        removalBusy: root.removingPluginId === modelData.id
        favorite: root.controller.pluginFavorite(modelData.id)
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onToggled: root.togglePlugin(modelData)
        onFavoriteToggled: root.toggleFavorite(modelData)
        onRemoveRequested: root.requestPluginRemoval(modelData)
      }
    }
  }

  PluginSectionHeader {
    visible: root.activeEntries.length > 0
    width: parent.width
    controller: root.controller
    title: "ACTIVE"
    count: root.activeEntries.length
    countColor: root.activeCountColor
    expanded: root.activeExpanded || root.pluginQuery.trim() !== ""
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onToggled: root.activeExpanded = !root.activeExpanded
  }

  Flow {
    id: activeDeck
    visible: root.displayedActiveEntries.length > 0
    width: parent.width
    spacing: Commons.Style.space(8)

    Repeater {
      id: activeRepeater
      model: root.displayedActiveEntries

      delegate: WidgetModuleTile {
        required property var modelData
        width: (activeDeck.width - activeDeck.spacing) / 2
        controller: root.controller
        glyph: modelData.glyph
        label: modelData.name
        provider: modelData.provider
        relationship: modelData.replacementLabel || ""
        inserted: true
        removable: modelData.removable === true
        removalBusy: root.removingPluginId === modelData.id
        favorite: root.controller.pluginFavorite(modelData.id)
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onToggled: root.togglePlugin(modelData)
        onFavoriteToggled: root.toggleFavorite(modelData)
        onRemoveRequested: root.requestPluginRemoval(modelData)
      }
    }
  }

  PluginSectionHeader {
    visible: root.availableEntries.length > 0
    width: parent.width
    controller: root.controller
    title: "AVAILABLE"
    count: root.availableEntries.length
    countColor: root.availableCountColor
    expanded: root.availableExpanded || root.pluginQuery.trim() !== ""
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onToggled: root.availableExpanded = !root.availableExpanded
  }

  Flow {
    id: availableDeck
    visible: root.displayedAvailableEntries.length > 0
    width: parent.width
    spacing: Commons.Style.space(8)

    Repeater {
      id: availableRepeater
      model: root.displayedAvailableEntries

      delegate: WidgetModuleTile {
        required property var modelData
        width: (availableDeck.width - availableDeck.spacing) / 2
        controller: root.controller
        glyph: modelData.glyph
        label: modelData.name
        provider: modelData.provider
        relationship: modelData.replacementLabel || ""
        inserted: false
        removable: modelData.removable === true
        removalBusy: root.removingPluginId === modelData.id
        favorite: root.controller.pluginFavorite(modelData.id)
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onToggled: root.togglePlugin(modelData)
        onFavoriteToggled: root.toggleFavorite(modelData)
        onRemoveRequested: root.requestPluginRemoval(modelData)
      }
    }
  }
}
