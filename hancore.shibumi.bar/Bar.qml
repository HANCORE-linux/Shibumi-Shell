pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "core" as Core
import "core/GroupRegistry.js" as GroupRegistry
import "core/PanelRouting.js" as PanelRouting
import "core/LayoutModel.js" as LayoutModel
import "core/V2LayoutModel.js" as V2LayoutModel
import "core/WidgetFamilies.js" as WidgetFamilies
import "services" as Services
import "styles" as Styles
import "../hancore.shibumi.state/runtime" as SuiteRuntime

Item {
  id: root

  // Third-party bars are loaded asynchronously and wired after construction.
  // Keep host-injected properties optional at creation time.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  SuiteRuntime.HostShell { id: suiteHostShell }
  SuiteRuntime.Provider {
    id: barRuntimeProvider
    pluginId: "hancore.shibumi.bar"
    implementationVersion: "0.1.1-beta.15.1"
    owner: root
    host: suiteHostShell.host
    manifest: root.manifest
  }
  onShellChanged: {
    if (shell === suiteHostShell) return
    suiteHostShell.host = shell
    // Preserve the explicit legacy injection, including native widget APIs.
    // A scoped facade is adapted, never replaced by a legacy fallback.
    if (shell && "pluginId" in shell) shell = suiteHostShell
  }
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property var barConfig: ({})
  readonly property int shibumiHostContractVersion: 1
  // The marker belongs to this loaded entry point, not to private host
  // manifest metadata (which scoped hosts deliberately do not expose).
  readonly property string suiteMarkerPath: {
    const url = String(Qt.resolvedUrl(".shibumi-managed.json"))
    if (url.indexOf("file:///") !== 0) return ""
    // FileView takes a filesystem path, not a percent-encoded QML URL.
    try { return decodeURIComponent(url.substring(7)) } catch (error) { return "" }
  }
  property string suitePayloadDigest: ""
  property bool suitePayloadLoaded: false
  property bool hostReady: false
  readonly property bool mutationAdmissionReady:
    hostReady && startupAdmissionSatisfied && !shutdownPrepared
  // Consumed only by the process-singleton runtime IPC handler. A handler is
  // admitted after complete host injection and startup, and is revoked before
  // this Bar begins shutdown or whenever Bar ownership overlaps.
  readonly property bool visibilityIpcReady: barRuntimeProvider.registered
    && SuiteRuntime.Runtime.isActiveBar(root)
    && injectionComplete && hostReady && !shutdownPrepared
    && barConfig && barConfig.id === "hancore.shibumi.bar"
  property bool outputWindowsEnabled: true
  // No-output fixtures can opt out while the deployed scoped Bar performs
  // the one process-bound native registry prime before becoming visible.
  property bool nativeRegistryPrimeEnabled: outputWindowsEnabled
  property bool shutdownPrepared: false
  readonly property bool suiteRuntimeReady: SuiteRuntime.Runtime.contractVersion === 1
    && SuiteRuntime.Runtime.ready
    && SuiteRuntime.Runtime.isActiveBar(root)
    && SuiteRuntime.Runtime.publishedBarConfig !== null
    && SuiteRuntime.Runtime.payloadDigest === suitePayloadDigest
    && SuiteRuntime.Runtime.serviceFor("hancore.shibumi.state") !== null
  readonly property bool nativeRegistryPrimeRequired:
    nativeRegistryPrimeEnabled && suiteHostShell.scoped
  readonly property bool nativeRegistryPrimeReady: {
    void(SuiteRuntime.Runtime.hostRegistryPrimeRevision)
    return !nativeRegistryPrimeRequired
      || SuiteRuntime.Runtime.hostRegistryPrimeReadyFor(
        root, Quickshell.processId)
  }
  readonly property bool startupAdmissionSatisfied: injectionComplete
    && (!suiteHostShell.scoped || suiteRuntimeReady)
    && nativeRegistryPrimeReady
  readonly property int validHostOutputCount: countValidHostOutputs()
  property bool hostOutputPresenceObserved: false
  property bool hostOutputLossObserved: false
  property bool hostOutputReturnObserved: false
  property var hostOutputPreviouslyReadyWidgetIds: ({})
  property var hostOutputLossReadyWidgetIds: ({})

  property string home: Quickshell.env("HOME")
  property var fallbackBarConfig: ({
    position: "top",
    style: "shibumi",
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property string position: "top"
  // Quattro keeps this facade surface for stock-widget compatibility, but
  // barConfig.transparent belongs exclusively to the stock Omarchy bar.
  readonly property bool requestedTransparent: false
  readonly property bool transparent: false
  property bool barToggledOff: false
  property bool barToggleStateLoaded: false
  property bool barHiddenProbeQueued: false
  readonly property bool barHiddenProbeBusy:
    barHiddenProbe.running || barHiddenProbeQueued
  readonly property var idleService: root.shell
    && typeof root.shell.firstPartyServiceFor === "function"
    ? root.shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property bool screensaverPreHidden: !!(idleService
    && idleService.screensaverStartedThisCycle)
  readonly property bool barHidden: barToggledOff || screensaverPreHidden
  property bool foregroundAnimationEnabled: true
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property string requestedStyleId: "shibumi"
  property bool styleReady: false
  readonly property var activeStyle: styleLoader.item
  readonly property var visualTokens: styleReady ? activeStyle.visualTokens : null
  readonly property var hostWidgetResolver: hostWidgetResolverService
  readonly property var layoutController: layoutStateController
  property int providerRegistryRevision: 0
  readonly property var catalogConsumerCandidate: {
    void(SuiteRuntime.Runtime.revision)
    if (!root.hostReady || !suiteHostShell.scoped
        || !barRuntimeProvider.registered) return null
    const candidate = suiteHostShell.serviceFor(
      "hancore.shibumi.control-center")
    try {
      return candidate
          && typeof candidate.acquireCatalogConsumer === "function"
          && typeof candidate.releaseCatalogConsumer === "function"
          && typeof candidate.hasCatalogConsumer === "function"
          && typeof candidate.catalogObservation === "function"
          && typeof candidate.isCatalogObservationCurrent === "function"
        ? candidate : null
    } catch (error) { return null }
  }
  property var catalogConsumerService: null
  property var catalogConsumerToken: null
  property int catalogConsumerRevision: 0
  readonly property var catalogObservation: {
    void(catalogConsumerRevision)
    const service = catalogConsumerService
    const token = catalogConsumerToken
    if (!suiteHostShell.scoped || !service || service !== catalogConsumerCandidate
        || !token) return null
    try {
      // Read reactivity comes only from the public primitive facade. Never
      // retain or inspect the catalog backend or its snapshot property.
      void(service.catalogReady)
      void(service.catalogReadSerial)
      void(service.catalogGeneration)
      if (service.catalogReady !== true || !service.hasCatalogConsumer(token))
        return null
      const observation = service.catalogObservation(token)
      if (!observation) return null
      return service.isCatalogObservationCurrent(token, observation)
        ? observation : null
    } catch (error) { return null }
  }
  readonly property var v1FamilySlotBindings: {
    void(layoutConfig)
    void(layoutStateController.v1Slots)
    void(providerRegistryRevision)
    void(pluginRegistry ? pluginRegistry.installedPlugins : null)
    void(catalogObservation)
    return WidgetFamilies.v1SlotBindings(v1PluginSpecs(),
      layoutStateController.v1Slots, pluginRegistry, catalogObservation,
      suiteHostShell.scoped)
  }
  readonly property string styleId: styleRegistry.resolvedId
  readonly property var availableStyleIds: styleRegistry.availableIds
  property color foreground: styleReady ? activeStyle.foreground : Color.bar.text
  property color barForeground: styleReady ? activeStyle.barForeground : Color.bar.text
  property color background: styleReady ? activeStyle.background : Color.bar.background
  property color urgent: styleReady ? activeStyle.urgent : Color.bar.active
  property string fontFamily: styleReady ? activeStyle.fontFamily : Style.font.family
  readonly property bool injectionComplete: omarchyPath !== ""
    && shell !== null
    && manifest !== null
    && pluginRegistry !== null
    && barWidgetRegistry !== null
    && Util.isPlainObject(barConfig)
  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: styleReady
    ? (vertical ? activeStyle.sizeVertical : activeStyle.sizeHorizontal)
    : (vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
  readonly property int barExclusiveSize: styleReady && !vertical
    ? activeStyle.exclusiveSizeHorizontal : barSize

  // Popout ownership is output-local. `activePopout` remains a compatibility
  // view of the most recently touched owner for host panels that do not yet
  // pass an output identity explicitly.
  property var activePopouts: ({})
  property var activePopout: null
  // V2 panels publish their connector geometry per output. The scalar fields
  // remain a compatibility view of the most recently updated record.
  property var connectedPanels: ({})
  property var connectedPanelOwner: null
  property string connectedPanelScreenName: ""
  property real connectedPanelX: 0
  property real connectedPanelReveal: 0
  property bool connectedPanelHostCaret: false
  property real connectedPanelCardX: 0
  property real connectedPanelCardY: 0
  property real connectedPanelCardWidth: 0
  property real connectedPanelCardHeight: 0
  property var moduleSlots: []
  property var loadedOwners: []
  property Component loadedOwnerSentinel: Component {
    QtObject {
      id: sentinel
      required property Item slot
      required property string screenName
      Component.onCompleted: root.loadedOwners = root.loadedOwners.concat([sentinel])
      Component.onDestruction: root.loadedOwners = root.loadedOwners.filter(candidate => candidate !== sentinel)
    }
  }
  property var clickTargets: []
  property bool tearingDown: false
  property var layoutSessions: []
  property var tooltipTarget: null
  property string tooltipText: ""
  property var pendingTooltipTarget: null
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  // Restore records are output-local. A V1/V2 owner handoff on one output
  // must not suppress or overwrite a value-only mutation on another output.
  property var pendingWidgetRestores: []
  property int nextWidgetRestoreId: 0
  readonly property var restoreStateService: layoutStateController.stateService
  readonly property bool restoreAdmitted: mutationAdmissionReady
    && (!suiteHostShell.scoped || suiteRuntimeReady)
  property var activeRestoreCalls: []
  property var lastProviderUndoReceipt: null
  property var lastCatalogTransitionSnapshot: null
  readonly property alias layoutTransitionBusy: layoutTransition.busy
  readonly property alias layoutTransitionSerial: layoutTransition.requestSerial
  readonly property alias layoutTransitionResult: layoutTransition.lastResult
  readonly property alias providerSnapshotTransitionBusy:
    providerSnapshotTransition.busy
  readonly property alias providerSnapshotTransitionSerial:
    providerSnapshotTransition.requestSerial
  readonly property alias providerSnapshotTransitionResult:
    providerSnapshotTransition.lastResult
  readonly property alias stateTransitionBusy: stateTransition.busy
  readonly property alias stateTransitionSerial: stateTransition.requestSerial
  readonly property alias stateTransitionResult: stateTransition.lastResult
  readonly property bool layoutTransitionsSupported: layoutTransition.supported
    && providerSnapshotTransition.supported && stateTransition.supported
  readonly property bool legacyLayoutMutationAllowed: !suiteHostShell.scoped
  signal layoutTransitionSettled(int serial, string result)
  signal providerSnapshotTransitionSettled(int serial, string result)
  signal stateTransitionSettled(int serial, string result)
  onRestoreStateServiceChanged: revokeStateRestores()
  onRestoreAdmittedChanged: revokeStateRestores()
  property string controlCenterWidgetDetailGroup: ""
  property string controlCenterWidgetDetailPlugin: ""

  function countValidHostOutputs() {
    let count = 0
    const values = Quickshell.screens || []
    for (let index = 0; index < values.length; index++) {
      const screen = values[index]
      if (screen && String(screen.name || "") !== ""
          && Number(screen.width) > 0 && Number(screen.height) > 0) count++
    }
    return count
  }

  function copyWidgetIdSet(value) {
    const source = value && typeof value === "object" ? value : ({})
    const result = Object.create(null)
    for (const id in source) {
      if (Object.prototype.hasOwnProperty.call(source, id)
          && source[id] === true) result[id] = true
    }
    return result
  }

  function observeHostOutputCount(countValue) {
    if (shutdownPrepared || !suiteHostShell.scoped
        || screensaverPreHidden) return false
    const count = Number(countValue)
    if (!Number.isInteger(count) || count < 0) return false
    if (count > 0) {
      hostOutputPresenceObserved = true
      if (hostOutputLossObserved) hostOutputReturnObserved = true
      return true
    }
    if (!hostOutputPresenceObserved || hostOutputLossObserved
        || !nativeRegistryPrimeReady) return false
    hostOutputLossObserved = true
    hostOutputLossReadyWidgetIds = copyWidgetIdSet(
      hostOutputPreviouslyReadyWidgetIds)
    return true
  }

  function syncHostOutputLifecycleState() {
    return observeHostOutputCount(validHostOutputCount)
  }

  function validDiagnosticPluginId(value) {
    const id = String(value || "")
    return id.length > 0 && id.length <= 160
      && /^[a-z0-9][a-z0-9._-]*$/.test(id) ? id : ""
  }

  function sanitizedDiagnosticScreenLabel(value) {
    const label = String(value || "")
    return label.length > 0 && label.length <= 64
        && /^[A-Za-z0-9_.:-]+$/.test(label) ? label : "unknown"
  }

  function hostWidgetResolutionWarningCandidate(slot, outputCountValue) {
    if (!slot || moduleSlots.indexOf(slot) < 0 || shutdownPrepared
        || screensaverPreHidden || !mutationAdmissionReady
        || !suiteHostShell.scoped || !hostWidgetResolverService.scoped
        || hostWidgetResolverService.widgetRegistry === null
        || !nativeRegistryPrimeReady
        || !hostOutputPresenceObserved || !hostOutputLossObserved
        || !hostOutputReturnObserved) return false
    const outputCount = Number(outputCountValue)
    if (!Number.isInteger(outputCount) || outputCount < 1) return false
    const id = validDiagnosticPluginId(slot.moduleName)
    if (id === "" || slot.moduleEnabled !== true
        || Number(slot.resolutionAttempts) !== 10
        || slot.resolvedComponent !== null
        || !Object.prototype.hasOwnProperty.call(
          hostOutputLossReadyWidgetIds, id)
        || hostOutputLossReadyWidgetIds[id] !== true
        || !hostWidgetConfiguredEnabled(id)) return false
    try { return hostWidgetResolverService.configured(id) === true }
    catch (error) { return false }
  }

  function hostWidgetResolutionWarningEvidence(slot, outputCountValue) {
    if (!hostWidgetResolutionWarningCandidate(slot, outputCountValue))
      return null
    return {
      pluginId: validDiagnosticPluginId(slot.moduleName),
      screenLabel: sanitizedDiagnosticScreenLabel(slot.screenName),
      retryCount: 10,
      facadeScoped: true,
      facadeRegistryPresent: true,
      facadeConfigured: true,
      facadeEnabled: true,
      previouslyResolved: true,
      outputSequence: true,
      shutdown: false
    }
  }

  function hostWidgetConfiguredEnabled(pluginId) {
    const id = validDiagnosticPluginId(pluginId)
    const layout = barConfig && barConfig.layout
    if (id === "" || !layout) return false
    for (const region of ["left", "center", "right"]) {
      const entries = layout[region]
      if (!Array.isArray(entries)) return false
      for (let index = 0; index < entries.length; index++) {
        const entry = entries[index]
        if (entryId(entry) === id
            && (!Util.isPlainObject(entry) || entry.enabled !== false))
          return true
      }
    }
    return false
  }

  function hostWidgetSlotLoadedCurrent(slot, pluginId) {
    const id = validDiagnosticPluginId(pluginId)
    if (id === "" || !slot || moduleSlots.indexOf(slot) < 0
        || String(slot.moduleName || "") !== id
        || slot.moduleEnabled !== true
        || !hostWidgetConfiguredEnabled(id)) return false
    try {
      return typeof slot.currentLoadReady === "function"
        && slot.currentLoadReady() === true
    } catch (error) { return false }
  }

  function hostWidgetResolutionWarningCurrent(pluginId) {
    const id = validDiagnosticPluginId(pluginId)
    if (id === "") return false
    for (let index = 0; index < moduleSlots.length; index++) {
      const slot = moduleSlots[index]
      if (slot && String(slot.moduleName || "") === id
          && hostWidgetResolutionWarningCandidate(
            slot, validHostOutputCount)) return true
    }
    return false
  }

  function noteHostWidgetResolution(slot, ready) {
    if (!slot || moduleSlots.indexOf(slot) < 0 || shutdownPrepared
        || !suiteHostShell.scoped || !nativeRegistryPrimeReady) return false
    const id = validDiagnosticPluginId(slot.moduleName)
    if (id === "") return false
    if (ready === true) {
      // Account only an onLoaded-confirmed item for the exact current registry
      // handle. Older Beta.13 slots have no method and fail closed.
      if (!hostWidgetSlotLoadedCurrent(slot, id)) return false
      if (validHostOutputCount < 1 || hostOutputLossObserved) return false
      if (hostOutputPreviouslyReadyWidgetIds[id] === true) return true
      if (Object.keys(hostOutputPreviouslyReadyWidgetIds).length >= 256)
        return false
      const next = copyWidgetIdSet(hostOutputPreviouslyReadyWidgetIds)
      next[id] = true
      hostOutputPreviouslyReadyWidgetIds = next
      return true
    }
    if (ready !== false) return false
    const evidence = hostWidgetResolutionWarningEvidence(
      slot, validHostOutputCount)
    return evidence !== null
      && SuiteRuntime.Runtime.noteHostWidgetResolutionExhausted(
        root, Quickshell.processId, evidence)
  }

  function releaseCatalogConsumer() {
    const service = catalogConsumerService
    const token = catalogConsumerToken
    catalogConsumerService = null
    catalogConsumerToken = null
    catalogConsumerRevision++
    if (!service || !token) return false
    try { return service.releaseCatalogConsumer(token) === true }
    catch (error) { return false }
  }

  function rebindCatalogConsumer() {
    if (shutdownPrepared) return false
    const candidate = catalogConsumerCandidate
    if (catalogConsumerService === candidate && catalogConsumerToken) {
      try {
        if (candidate && candidate.hasCatalogConsumer(catalogConsumerToken))
          return true
      } catch (error) {}
    }
    releaseCatalogConsumer()
    if (!candidate) return false
    let token = null
    try { token = candidate.acquireCatalogConsumer(root) }
    catch (error) { token = null }
    // Acquisition can synchronously replace/revoke the provider. Retain only
    // the exact token from the still-selected service.
    if (!token) return false
    if (candidate !== catalogConsumerCandidate) {
      try { candidate.releaseCatalogConsumer(token) }
      catch (error) {}
      Qt.callLater(root.rebindCatalogConsumer)
      return false
    }
    try {
      if (!candidate.hasCatalogConsumer(token)) {
        candidate.releaseCatalogConsumer(token)
        return false
      }
    } catch (error) {
      try { candidate.releaseCatalogConsumer(token) }
      catch (releaseError) {}
      return false
    }
    catalogConsumerService = candidate
    catalogConsumerToken = token
    catalogConsumerRevision++
    return true
  }

  function normalizePosition(value) {
    const candidate = String(value || "").trim()
    return /^(top|bottom|left|right)$/.test(candidate) ? candidate : "top"
  }

  function captureSuiteMarker(raw) {
    suitePayloadDigest = ""
    suitePayloadLoaded = false
    try {
      const marker = JSON.parse(String(raw || ""))
      const digest = String(marker.suitePayloadDigest || "")
      if (marker.suiteId === "hancore.shibumi" && /^[0-9a-f]{64}$/.test(digest)) {
        suitePayloadDigest = digest
        suitePayloadLoaded = true
      }
    } catch (error) {}
  }

  function registeredWidgetComponent(widgetId) {
    return hostWidgetResolverService.componentFor(widgetId)
  }

  function registeredEmbeddedWidgetComponent(ownerId, widgetId) {
    return hostWidgetResolverService.embeddedComponentFor(ownerId, widgetId)
  }

  function registeredWidgetSource(widgetId) {
    return hostWidgetResolverService.entryPointUrl(widgetId)
  }

  function pluginService(pluginId) {
    const id = String(pluginId || "")
    return id && shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor(id) : null
  }

  function setWidgetAppearance(groupId, key, valueJson) {
    if (!mutationAdmissionReady) return "not-ready"
    const name = String(key || "")
    // The legacy endpoint only owns appearance shared by both variants.
    // Variant-scoped values must never report success after writing a
    // top-level fallback that the active renderer may ignore.
    if (name !== "separator") return "variant-required"
    const state = pluginService("hancore.shibumi.state")
    if (!state || typeof state.setGroupSetting !== "function")
      return "not-ready"
    let value = String(valueJson || "")
    try {
      value = JSON.parse(value)
    } catch (error) {
      return "invalid-value"
    }
    if (typeof value !== "boolean") return "invalid-value"
    return state.setGroupSetting(String(groupId || ""), name, value)
      ? "ok" : "rejected"
  }

  function setWidgetAppearanceForVariant(groupId, variantValue, key,
      valueJson) {
    if (!mutationAdmissionReady) return "not-ready"
    const variant = String(variantValue || "").toLowerCase()
    if (["v1", "v2"].indexOf(variant) < 0) return "invalid-variant"
    const state = pluginService("hancore.shibumi.state")
    if (!state
        || typeof state.setGroupAppearanceSettingForVariant !== "function")
      return "not-ready"
    const name = String(key || "")
    if (Array.isArray(state.appearanceKeys)
        && state.appearanceKeys.indexOf(name) < 0) return "invalid-key"
    let value = String(valueJson || "")
    try {
      value = JSON.parse(value)
    } catch (error) {
      // Plain strings remain convenient for CLI callers.
    }
    return state.setGroupAppearanceSettingForVariant(
      String(groupId || ""), variant, name, value) ? "ok" : "rejected"
  }

  function inlineSettingsDelta(current, next) {
    if (!Util.isPlainObject(current) || !Util.isPlainObject(next)) return null
    const regions = ["left", "center", "right"]
    const counts = Object.create(null)
    for (let regionIndex = 0; regionIndex < regions.length; regionIndex++) {
      const entries = Array.isArray(next[regions[regionIndex]])
        ? next[regions[regionIndex]] : []
      for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        const id = entryId(entries[entryIndex])
        counts[id] = (counts[id] || 0) + 1
      }
    }

    const changes = []
    for (let regionIndex = 0; regionIndex < regions.length; regionIndex++) {
      const region = regions[regionIndex]
      const currentEntries = Array.isArray(current[region])
        ? current[region] : []
      const nextEntries = Array.isArray(next[region]) ? next[region] : []
      if (currentEntries.length !== nextEntries.length) return null
      for (let entryIndex = 0; entryIndex < currentEntries.length;
          entryIndex++) {
        const currentId = entryId(currentEntries[entryIndex])
        const nextId = entryId(nextEntries[entryIndex])
        if (currentId !== nextId) return null
        if (JSON.stringify(currentEntries[entryIndex])
            === JSON.stringify(nextEntries[entryIndex])) continue
        const currentEntry = Util.isPlainObject(currentEntries[entryIndex])
          ? currentEntries[entryIndex] : ({})
        const nextEntry = Util.isPlainObject(nextEntries[entryIndex])
          ? nextEntries[entryIndex] : ({})
        // These values determine slot ownership or Loader activation rather
        // than provider state. They require the structural reconciliation path.
        if ((currentEntry.shibumiModule === true)
              !== (nextEntry.shibumiModule === true)
            || (currentEntry.enabled !== false)
              !== (nextEntry.enabled !== false)) return null
        // Without stable per-entry identities, repeated providers cannot be
        // patched safely. Fall back to the normal structural rebuild.
        if (counts[nextId] > 1) return null
        changes.push({
          region: region,
          index: entryIndex,
          entry: nextEntries[entryIndex]
        })
      }
    }
    return changes
  }

  function applyInlineSettingsDelta(changes) {
    // Composite-consumed entries (clock, weather, tray, and similar) have no
    // same-ID WidgetSlot to invalidate. If any changed entry lacks a live slot,
    // use the structural path rather than leaving that consumer stale.
    for (let changeIndex = 0; changeIndex < changes.length; changeIndex++) {
      const id = entryId(changes[changeIndex].entry)
      let found = false
      for (let slotIndex = 0; slotIndex < moduleSlots.length; slotIndex++) {
        const slot = moduleSlots[slotIndex]
        if (slot && slot.moduleName === id
            && typeof slot.applyInlineSettings === "function") {
          found = true
          break
        }
      }
      if (!found) return false
    }

    for (let changeIndex = 0; changeIndex < changes.length; changeIndex++) {
      const change = changes[changeIndex]
      layoutConfig[change.region][change.index] = change.entry
      const id = entryId(change.entry)
      // One logical slot may be rendered on multiple outputs or as a
      // zero-size anchor placeholder. Patch every live copy in place so
      // state persistence cannot destroy an open third-party panel. Keep the
      // delegate-owned entry binding intact; later group updates still need it.
      for (let slotIndex = 0; slotIndex < moduleSlots.length; slotIndex++) {
        const slot = moduleSlots[slotIndex]
        if (slot && slot.moduleName === id
            && typeof slot.applyInlineSettings === "function")
          slot.applyInlineSettings(change.entry)
      }
    }
    return true
  }

  function applyBarConfig() {
    const config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig
    position = normalizePosition(config.position)
    requestedStyleId = String(config.style || "shibumi")
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")
    const nextLayout = Util.normalizeLayout(config.layout)
    // QML cannot diff reassigned JavaScript layout arrays: replacing one for
    // an inline setting (for example a saved game score) recreates every
    // widget and closes its panel. Match Omarchy's stock host by updating
    // shape-stable, uniquely identified entries and their live slots in place.
    const delta = inlineSettingsDelta(layoutConfig, nextLayout)
    if (delta !== null && applyInlineSettingsDelta(delta)) return
    for (let slotIndex = 0; slotIndex < moduleSlots.length; slotIndex++) {
      const slot = moduleSlots[slotIndex]
      if (slot && typeof slot.clearInlineSettings === "function")
        slot.clearInlineSettings()
    }
    layoutConfig = nextLayout
  }

  function setBarPosition(value, ownerValue, screenName) {
    if (!mutationAdmissionReady || layoutTransitionBusy) return false
    const next = String(value || "")
    if (["top", "bottom"].indexOf(next) < 0 || !shell
        || typeof shell.mutateShellConfig !== "function") return false
    root.scheduleOpenControlCenterRestores(
      "bars", false, ownerValue, screenName)
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.position = next
    })
    return true
  }

  function setAllSplits(value) {
    if (!mutationAdmissionReady) return false
    return typeof value === "boolean"
      ? layoutStateController.setAllSplits(value) : false
  }

  function toggleGroupSeparator(groupId, editingValue) {
    const state = pluginService("hancore.shibumi.state")
    return layoutStateController.v2Mode
      && layoutStateController.interactiveMutationAllowed(editingValue)
      && state && typeof state.toggleGroupSeparator === "function"
      ? state.toggleGroupSeparator(String(groupId || "")) : false
  }

  function resetBarLayout() {
    const reset = layoutStateController.resetLayout()
    if (reset && !layoutStateController.v2Mode)
      v1PluginReconcileTimer.restart()
    return reset
  }

  function addV2Slot(region) {
    return layoutStateController.addV2Slot(region)
  }

  function removeV2Slot(region) {
    return layoutStateController.removeV2Slot(region)
  }

  function addV1Slot(region) {
    return layoutStateController.addV1Slot(region)
  }

  function removeV1Slot(region) {
    return layoutStateController.removeV1Slot(region)
  }

  function widgetSettings(groupId, moduleId) {
    const state = pluginService("hancore.shibumi.state")
    const config = state && state.config ? state.config : ({})
    const group = config.widgets
      ? config.widgets[String(groupId || "")] || ({}) : ({})
    return GroupRegistry.childSettingsFor(group, layoutConfig,
      String(moduleId || ""))
  }

  function validateStyle(item) {
    if (!item) return false
    if (!("bar" in item) || Number(item.contractVersion) !== 1) return false
    if (String(item.styleId || "") !== styleRegistry.resolvedId) return false
    if (Number(item.sizeHorizontal) <= 0 || Number(item.sizeVertical) <= 0) return false
    if (Number(item.exclusiveSizeHorizontal) < Number(item.sizeHorizontal)) return false
    if (!item.visualTokens) return false
    if (!item.barSurfaceComponent || !item.tooltipSurfaceComponent) return false
    return true
  }

  function setStyle(value) {
    if (!mutationAdmissionReady) return false
    const next = styleRegistry.normalizeId(value)
    if (!styleRegistry.hasStyle(next)) return false

    if (shell && typeof shell.mutateShellConfig === "function") {
      shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.style = next
      })
    } else {
      requestedStyleId = next
    }
    return true
  }

  function setRequestedTransparency(value) {
    // Compatibility no-op: Shibumi V1/V2 are always opaque and must neither
    // apply nor rewrite the stock Omarchy bar's saved preference.
    return false
  }

  function layoutEntries(region) {
    const entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  function isV1AdditionalSuiteWidget(widgetId) {
    return [
      "hancore.shibumi.temperature",
      "hancore.shibumi.gpu",
      "hancore.shibumi.storage"
    ].indexOf(String(widgetId || "")) >= 0
  }

  function deduplicatedUnassignedEntries(entries) {
    const seen = Object.create(null)
    return entries.filter(function(entry) {
      const id = entryId(entry)
      if (widgetAllowsMultiple(id)) return true
      if (seen[id] === true) return false
      seen[id] = true
      return true
    })
  }

  function unassignedLayoutEntries(region) {
    const entries = GroupRegistry.unassignedEntries(layoutConfig, region)
    const removing = layoutTransitionBusy && layoutTransition.operation
      && layoutTransition.operation.intent
      && Array.isArray(layoutTransition.operation.intent.removeIds)
      ? layoutTransition.operation.intent.removeIds : []
    if (layoutStateController.v2Mode) {
      // G16-G18 use V1 extension slots but remain native fixed groups in V2.
      // Keep their persisted V1 provider entries out of V2's unassigned deck,
      // otherwise the same widget would be rendered twice after a switch.
      return deduplicatedUnassignedEntries(entries.filter(function(entry) {
        const id = entryId(entry)
        if (isV1AdditionalSuiteWidget(id) || removing.indexOf(id) >= 0) return false
        const groupId = GroupRegistry.dynamicGroupIdForModule(id)
        return groupId === "" || !layoutStateController.groupLocation(groupId)
      }))
    }
    const familyProviders = Object.values(v1FamilySlotBindings)
    return deduplicatedUnassignedEntries(entries.filter(function(entry) {
      const id = entryId(entry)
      if (familyProviders.indexOf(id) >= 0 || removing.indexOf(id) >= 0) return false
      const groupId = GroupRegistry.dynamicGroupIdForModule(id)
      return groupId === "" || !layoutStateController.groupLocation(groupId)
    }))
  }

  function pluginSpecsForLayout(layoutValue, excludeValue, includeSpec,
      v2Value) {
    const excluded = Array.isArray(excludeValue)
      ? excludeValue.map(function(value) { return String(value || "") })
      : [String(excludeValue || "")]
    const source = Util.isPlainObject(layoutValue) ? layoutValue : ({})
    const specs = []
    const seen = Object.create(null)
    for (const region of ["left", "center", "right"]) {
      const entries = Array.isArray(source[region]) ? source[region] : []
      for (let index = 0; index < entries.length; index++) {
        const entry = entries[index]
        const id = entryId(entry)
        const hasBarWidget = hasBarWidgetEntryPoint(id)
        const shibumiModule = Util.isPlainObject(entry)
          && entry.shibumiModule === true && hasBarWidget
        const dynamicV2Provider = v2Value === true && hasBarWidget
        if (id === "" || excluded.indexOf(id) >= 0 || seen[id]
            || !Util.isPlainObject(entry)
            || (!shibumiModule && !dynamicV2Provider)
            || (v2Value === true && GroupRegistry.isAssignedModule(id))
            || widgetAllowsMultiple(id)) continue
        seen[id] = true
        specs.push({ pluginId: id, region: region })
      }
    }
    if (includeSpec && Util.isPlainObject(includeSpec)) {
      const id = entryId(includeSpec)
      if (id !== "" && !seen[id] && !widgetAllowsMultiple(id)
          && (v2Value !== true || !GroupRegistry.isAssignedModule(id)))
        specs.push({
          pluginId: id,
          region: ["left", "center", "right"].indexOf(
            String(includeSpec.region || "")) >= 0
              ? String(includeSpec.region) : "right"
        })
    }
    return specs
  }

  function v1PluginSpecsForLayout(layoutValue, excludeValue, includeSpec) {
    return pluginSpecsForLayout(
      layoutValue, excludeValue, includeSpec, false)
  }

  function v2PluginSpecsForLayout(layoutValue, excludeValue, includeSpec) {
    return pluginSpecsForLayout(
      layoutValue, excludeValue, includeSpec, true)
  }

  function v1PluginSpecs(excludeValue, includeSpec) {
    return v1PluginSpecsForLayout(layoutConfig, excludeValue, includeSpec)
  }

  function v2PluginSpecs(excludeValue, includeSpec) {
    return v2PluginSpecsForLayout(layoutConfig, excludeValue, includeSpec)
  }

  function activePluginSpecsForLayout(layoutValue, excludeValue, includeSpec) {
    return layoutStateController.v2Mode
      ? v2PluginSpecsForLayout(layoutValue, excludeValue, includeSpec)
      : v1PluginSpecsForLayout(layoutValue, excludeValue, includeSpec)
  }

  function activePluginSpecs(excludeValue, includeSpec) {
    return activePluginSpecsForLayout(
      layoutConfig, excludeValue, includeSpec)
  }

  function reconcileActivePluginGroups(specs, syncValue, followRegionsValue, allowPartialValue) {
    if (layoutStateController.v2Mode)
      return layoutStateController.reconcileV2PluginGroups(
        specs, syncValue, followRegionsValue, allowPartialValue)
    if (!Array.isArray(specs)) return false
    const bindings = WidgetFamilies.v1SlotBindings(specs,
      layoutStateController.currentV1Order(), pluginRegistry,
      catalogObservation, suiteHostShell.scoped)
    const familyProviders = Object.values(bindings)
    return layoutStateController.reconcileV1PluginGroups(
      specs.filter(function(spec) {
        return !spec || familyProviders.indexOf(spec.pluginId) < 0
      }), allowPartialValue)
  }

  function reconcileV1PluginGroups() {
    if (layoutStateController.v2Mode) return true
    if (!reconcileActivePluginGroups(v1PluginSpecs()))
      return false
    return reconcileWidgetFamilyProviders()
  }

  function reconcileActivePluginGroupsAndProviders() {
    if (layoutTransitionBusy) return false
    // The shared host layout is also the V1 provider-region source. During a
    // background reconciliation, let it repair an existing V2 dynamic group
    // whose provider entry was moved outside the V2 editor. Explicit V2 drag
    // mutations update both stores first, so this does not undo an edit.
    if (!reconcileActivePluginGroups(
          activePluginSpecs(), true, layoutStateController.v2Mode, true))
      return false
    return reconcileWidgetFamilyProviders()
  }

  function layoutContains(widgetId) {
    const id = String(widgetId || "")
    if (!id) return false
    for (const region of ["left", "center", "right"]) {
      const entries = layoutEntries(region)
      for (let index = 0; index < entries.length; index++) {
        if (entryId(entries[index]) !== id) continue
        const entry = entries[index]
        if (!GroupRegistry.isAssignedModule(id)
            || GroupRegistry.isOptionalModule(id)
            || (Util.isPlainObject(entry) && entry.shibumiModule === true))
          return true
      }
    }
    return false
  }

  function hasBarWidgetEntryPoint(widgetId, selectionValue) {
    const selection = selectionValue === undefined
      ? hostWidgetResolverService.selectionFor(widgetId) : selectionValue
    if (hostWidgetResolverService.scoped)
      return !!(selection && selection.metadata)
    const candidate = selection ? selection.manifest : null
    if (!candidate || !pluginRegistry
        || typeof pluginRegistry.entryPointUrl !== "function") return false
    return String(pluginRegistry.entryPointUrl(
      candidate, "barWidget") || "") !== ""
  }

  function widgetAllowsMultiple(widgetId, selectionValue) {
    const selection = selectionValue === undefined
      ? hostWidgetResolverService.selectionFor(widgetId) : selectionValue
    if (hostWidgetResolverService.scoped)
      return !!(selection && selection.metadata && selection.metadata.allowMultiple === true)
    const candidate = selection ? selection.manifest : null
    return !!(candidate && candidate.barWidget
      && candidate.barWidget.allowMultiple === true)
  }

  function widgetFamilyGroups(widgetId) {
    return WidgetFamilies.familiesForPlugin(
      String(widgetId || ""), pluginRegistry, catalogObservation,
      suiteHostShell.scoped).map(function(family) {
        return String(family.group || "")
      }).filter(function(groupId, index, values) {
        return GroupRegistry.GroupIds.indexOf(groupId) >= 0
          && values.indexOf(groupId) === index
      })
  }

  function widgetCapabilities(widgetId) {
    return WidgetFamilies.capabilitiesForPlugin(
      String(widgetId || ""), pluginRegistry, catalogObservation,
      suiteHostShell.scoped)
  }

  function widgetsShareCapability(leftId, rightId) {
    const left = widgetCapabilities(leftId)
    if (left.length === 0) return false
    const right = widgetCapabilities(rightId)
    return left.some(function(capability) {
      return right.indexOf(capability) >= 0
    })
  }

  function renderedProviderEntries(layoutValue, region) {
    return GroupRegistry.unassignedEntries(layoutValue, region)
  }

  function providerFamilyGroupsInLayout(layoutValue) {
    const groups = []
    for (const region of ["left", "center", "right"]) {
      const entries = renderedProviderEntries(layoutValue, region)
      for (let index = 0; index < entries.length; index++) {
        const familyGroups = widgetFamilyGroups(entryId(entries[index]))
        for (let groupIndex = 0; groupIndex < familyGroups.length;
             groupIndex++) {
          const group = familyGroups[groupIndex]
          if (groups.indexOf(group) < 0) groups.push(group)
        }
      }
    }
    return groups
  }

  function conflictingLayoutProviderIds(widgetId) {
    const id = String(widgetId || "")
    const result = id !== "" ? [id] : []
    for (const region of ["left", "center", "right"]) {
      const entries = renderedProviderEntries(layoutConfig, region)
      for (let index = 0; index < entries.length; index++) {
        const candidateId = entryId(entries[index])
        if (candidateId === "" || result.indexOf(candidateId) >= 0)
          continue
        if (widgetsShareCapability(id, candidateId)) result.push(candidateId)
      }
    }
    return result
  }

  function conflictingProviderIdsInLayout(layoutValue) {
    const capabilityOwners = ({})
    const removed = []
    for (const region of ["left", "center", "right"]) {
      const entries = renderedProviderEntries(layoutValue, region)
      for (let index = 0; index < entries.length; index++) {
        const id = entryId(entries[index])
        if (id === "" || removed.indexOf(id) >= 0) continue
        const capabilities = widgetCapabilities(id)
        const conflict = capabilities.some(function(capability) {
          return Object.prototype.hasOwnProperty.call(
            capabilityOwners, capability)
            && capabilityOwners[capability] !== id
        })
        if (conflict) {
          removed.push(id)
          continue
        }
        for (let capabilityIndex = 0;
             capabilityIndex < capabilities.length; capabilityIndex++)
          capabilityOwners[capabilities[capabilityIndex]] = id
      }
    }
    return removed
  }

  function conflictingLayoutProviderGroups(widgetId) {
    const id = String(widgetId || "")
    const providerIds = conflictingLayoutProviderIds(id)
    const groups = []
    for (let index = 0; index < providerIds.length; index++) {
      if (providerIds[index] === id) continue
      const providerGroups = widgetFamilyGroups(providerIds[index])
      for (let groupIndex = 0; groupIndex < providerGroups.length;
           groupIndex++) {
        const group = providerGroups[groupIndex]
        if (groups.indexOf(group) < 0) groups.push(group)
      }
    }
    return groups
  }

  function currentLayoutSnapshot() {
    return JSON.parse(JSON.stringify({
      left: layoutEntries("left"),
      center: layoutEntries("center"),
      right: layoutEntries("right")
    }))
  }

  function planV2DynamicLayout(layoutValue, slotsValue) {
    if (!Util.isPlainObject(slotsValue) || !Util.isPlainObject(layoutValue)
        || !["left", "center", "right"].every(region =>
          Array.isArray(layoutValue[region]) && Array.isArray(slotsValue[region]))) return null
    const nextLayout = JSON.parse(JSON.stringify(layoutValue))
    const dynamicById = Object.create(null)
    const desiredByRegion = ({ left: [], center: [], right: [] })
    let changed = false
    const desiredIds = Object.create(null)
    for (const region of ["left", "center", "right"]) {
      const slots = Array.isArray(slotsValue[region])
        ? slotsValue[region] : []
      for (let slotIndex = 0; slotIndex < slots.length; slotIndex++) {
        const moduleId = GroupRegistry.dynamicModuleIdForGroup(
          String(slots[slotIndex] || ""))
        if (moduleId === "") continue
        if (Object.prototype.hasOwnProperty.call(desiredIds, moduleId))
          return false
        desiredIds[moduleId] = true
        desiredByRegion[region].push(moduleId)
      }
    }

    // A malformed host layout must not let one dynamic provider appear twice.
    // Count before moving or reordering so duplicates across regions also
    // fail closed without ever reaching shell-config persistence.
    const actualCounts = Object.create(null)
    for (const region of ["left", "center", "right"]) {
      const entries = nextLayout[region]
      for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        const moduleId = entryId(entries[entryIndex])
        if (!Object.prototype.hasOwnProperty.call(desiredIds, moduleId))
          continue
        actualCounts[moduleId] = (actualCounts[moduleId] || 0) + 1
      }
    }
    for (const moduleId in desiredIds) {
      if (actualCounts[moduleId] !== 1) return false
    }

    // First put every V2-assigned dynamic entry in its model-owned region.
    for (const region of ["left", "center", "right"]) {
      const desired = desiredByRegion[region]
      for (let index = 0; index < desired.length; index++) {
        const moduleId = desired[index]
        let sourceRegion = ""
        let sourceIndex = -1
        for (const candidateRegion of ["left", "center", "right"]) {
          const entries = nextLayout[candidateRegion]
          const candidateIndex = entries.findIndex(function(entry) {
            return entryId(entry) === moduleId
          })
          if (candidateIndex >= 0) {
            sourceRegion = candidateRegion
            sourceIndex = candidateIndex
            break
          }
        }
        if (sourceRegion === "") return false
        if (sourceRegion === region) continue
        const entry = nextLayout[sourceRegion].splice(sourceIndex, 1)[0]
        nextLayout[region].push(entry)
        changed = true
      }
    }

    // Then reorder only the dynamic entries inside each region. Native and
    // unassigned entries retain their relative positions and settings.
    for (const region of ["left", "center", "right"]) {
      const desired = desiredByRegion[region]
      const desiredSet = Object.create(null)
      for (let index = 0; index < desired.length; index++) {
        const moduleId = desired[index]
        desiredSet[moduleId] = true
        const entries = nextLayout[region]
        const entryIndex = entries.findIndex(function(entry) {
          return entryId(entry) === moduleId
        })
        if (entryIndex < 0) return false
        dynamicById[moduleId] = entries[entryIndex]
      }
      let dynamicIndex = 0
      for (let entryIndex = 0;
          entryIndex < nextLayout[region].length; entryIndex++) {
        const currentId = entryId(nextLayout[region][entryIndex])
        if (!desiredSet[currentId]) continue
        if (dynamicIndex >= desired.length) return false
        const desiredId = desired[dynamicIndex++]
        if (currentId === desiredId) continue
        nextLayout[region][entryIndex] = dynamicById[desiredId]
        changed = true
      }
    }
    return nextLayout
  }

  function planNativeTransition(layoutValue, intentValue) {
    const intent = intentValue || ({})
    if (intent.kind === "v2-layout")
      return planV2DynamicLayout(layoutValue, intent.slots)
    if (intent.kind === "provider-snapshot") {
      const snapshotLayout = intent.layout
      const expectedCurrent = intent.expectedCurrentLayout
      if (!Util.isPlainObject(layoutValue)
          || !Util.isPlainObject(snapshotLayout)
          || !Util.isPlainObject(expectedCurrent)
          || !["left", "center", "right"].every(function(region) {
            return Array.isArray(layoutValue[region])
              && Array.isArray(snapshotLayout[region])
              && Array.isArray(expectedCurrent[region])
          })
          || !providerSnapshotTransition.same(
            layoutValue, expectedCurrent)) return null
      return JSON.parse(JSON.stringify(snapshotLayout))
    }
    if (intent.kind !== "catalog-layout" || !Util.isPlainObject(layoutValue)
        || !["left", "center", "right"].every(function(region) {
          return Array.isArray(layoutValue[region])
        })) return null
    const id = String(intent.id || "")
    const region = String(intent.region || "")
    if (!LayoutModel.validPluginId(id)
        || ["left", "center", "right"].indexOf(region) < 0
        || typeof intent.installed !== "boolean"
        || !Array.isArray(intent.removeIds)
        || intent.removeIds.some(function(value) {
          return !LayoutModel.validPluginId(value)
        })) return null
    const next = JSON.parse(JSON.stringify(layoutValue))
    let retained = null
    for (const part of ["left", "center", "right"]) {
      next[part] = next[part].filter(function(entry) {
        const entryValue = entryId(entry)
        if (entryValue === id && retained === null) retained = entry
        return intent.removeIds.indexOf(entryValue) < 0
      })
    }
    if (intent.installed) {
      const entry = retained && Util.isPlainObject(retained)
        ? JSON.parse(JSON.stringify(retained)) : {id: id}
      entry.id = id
      entry.shibumiModule = true
      next[region].push(entry)
    } else if (intent.keepConfigured === true) {
      next[region].push({id: id})
    }
    return next
  }

  function requestV2LayoutTransition(patch) {
    if (!mutationAdmissionReady) return false
    return layoutTransition.request(patch, {
      kind: "v2-layout", slots: patch && patch.v2Layout
    })
  }

  function syncV2DynamicLayout(slotsValue) {
    if (!mutationAdmissionReady) return false
    if (layoutTransitionsSupported)
      return requestV2LayoutTransition({v2Layout: slotsValue})
    // Legacy presentation fixtures without the settlement API. Scoped hosts
    // never fall back to optimistic mutation through an incomplete State seam.
    if (suiteHostShell.scoped) return false
    const nextLayout = planV2DynamicLayout(currentLayoutSnapshot(), slotsValue)
    if (!nextLayout) return false
    if (JSON.stringify(nextLayout) === JSON.stringify(currentLayoutSnapshot())) return true
    if (!shell || typeof shell.mutateShellConfig !== "function") return false
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.layout = JSON.parse(JSON.stringify(nextLayout))
    })
    layoutConfig = nextLayout
    return true
  }

  function currentV2LayoutSnapshot() {
    return layoutStateController.v2Mode
      && layoutStateController.v2Slots
      ? JSON.parse(JSON.stringify(layoutStateController.v2Slots)) : null
  }

  function restoreV2LayoutSnapshot(snapshotValue) {
    return snapshotValue === null || snapshotValue === undefined
      || !layoutStateController.v2Mode
      ? true : layoutStateController.restoreV2Layout(snapshotValue)
  }

  function providerUndoSnapshotForTransition(serialValue) {
    const serial = Number(serialValue)
    const receipt = lastProviderUndoReceipt
    if (!receipt || receipt.serial !== serial) return null
    lastProviderUndoReceipt = null
    return JSON.parse(JSON.stringify(receipt.snapshot))
  }

  function observedLayoutSnapshot() {
    const config = Util.isPlainObject(barConfig) ? barConfig : null
    const layout = config && Util.isPlainObject(config.layout)
      ? config.layout : null
    if (!layout || !["left", "center", "right"].every(function(region) {
      return Array.isArray(layout[region])
    })) return null
    return JSON.parse(JSON.stringify(layout))
  }

  function providerLayoutSnapshot(groupValues) {
    const groups = normalizedProviderGroups(groupValues)
    const states = groups.length > 0 ? widgetGroupVariantStates(groups) : ({})
    if (groups.length > 0 && !states) return null
    const layout = suiteHostShell.scoped
      ? observedLayoutSnapshot() : currentLayoutSnapshot()
    if (!layout) return null
    const patch = catalogLayoutPatch(layout, states || ({}))
    if (suiteHostShell.scoped && (!layoutTransitionsSupported || !patch))
      return null
    return {
      layout: layout,
      groupStates: states || ({}),
      v2Layout: currentV2LayoutSnapshot(),
      variant: layoutStateController.v2Mode ? "v2" : "v1",
      transitionPatch: patch
    }
  }

  function validScopedProviderSnapshot(snapshotValue) {
    if (!Util.isPlainObject(snapshotValue)
        || !Util.isPlainObject(snapshotValue.groupStates)
        || !Util.isPlainObject(snapshotValue.transitionPatch)
        || !Util.isPlainObject(snapshotValue.expectedStatePatch)
        || !Util.isPlainObject(snapshotValue.expectedLayout)) return false
    const stateGroups = Object.keys(snapshotValue.groupStates)
    const groups = normalizedProviderGroups(stateGroups)
    if (groups.length === 0 || groups.length !== stateGroups.length)
      return false
    for (let index = 0; index < groups.length; index++) {
      const states = snapshotValue.groupStates[groups[index]]
      if (!Util.isPlainObject(states)
          || typeof states.v1 !== "boolean"
          || typeof states.v2 !== "boolean") return false
    }
    const variant = String(snapshotValue.variant || "")
    if (["v1", "v2"].indexOf(variant) < 0) return false
    const patch = snapshotValue.transitionPatch
    const keys = Object.keys(patch).sort()
    const expectedKeys = ["familyStates", variant + "Layout"].sort()
    if (!providerSnapshotTransition.same(keys, expectedKeys)
        || !providerSnapshotTransition.same(
          patch.familyStates, snapshotValue.groupStates)
        || !providerSnapshotTransition.same(
          Object.keys(snapshotValue.expectedStatePatch).sort(), expectedKeys))
      return false
    return variant !== "v2" || providerSnapshotTransition.same(
      patch.v2Layout, snapshotValue.v2Layout)
  }

  function legacyFamilyMutationAllowed() {
    // These multi-step provider/catalog flows still need native-authoritative
    // sequencing. Never run their synchronous chain with queued State setters.
    return mutationAdmissionReady && legacyLayoutMutationAllowed
      && !layoutTransitionsSupported && !layoutTransitionBusy
  }

  function restoreProviderLayoutSnapshot(snapshotValue) {
    if (!mutationAdmissionReady || !Util.isPlainObject(snapshotValue)
        || !Util.isPlainObject(snapshotValue.layout)
        || !Util.isPlainObject(snapshotValue.groupStates)) return false
    const layout = snapshotValue.layout
    for (const region of ["left", "center", "right"]) {
      if (!Array.isArray(layout[region])) return false
    }
    if (suiteHostShell.scoped) {
      if (!layoutTransitionsSupported || layoutTransitionBusy
          || providerSnapshotTransitionBusy || stateTransitionBusy
          || !validScopedProviderSnapshot(snapshotValue)
          || !providerSnapshotTransition.same(
            observedLayoutSnapshot(), snapshotValue.expectedLayout)) return false
      let expectedState = null
      let observedState = null
      try {
        expectedState = layoutStateController.stateService
          .normalizedLayoutFamilyPatch(snapshotValue.expectedStatePatch)
        observedState = layoutStateController.stateService
          .layoutFamilySnapshot(snapshotValue.expectedStatePatch)
      } catch (error) {
        return false
      }
      if (!expectedState || !observedState
          || !providerSnapshotTransition.same(
            observedState, expectedState)) return false
      const patch = JSON.parse(JSON.stringify(snapshotValue.transitionPatch))
      const intent = {
        kind: "provider-snapshot",
        layout: JSON.parse(JSON.stringify(layout)),
        expectedCurrentLayout: JSON.parse(JSON.stringify(
          snapshotValue.expectedLayout)),
        patch: patch
      }
      return providerSnapshotTransition.request(patch, intent)
    }
    if (!legacyFamilyMutationAllowed()) return false
    const previousV2Layout = currentV2LayoutSnapshot()
    if (!restoreV2LayoutSnapshot(snapshotValue.v2Layout)) return false
    if (!applyProviderLayoutTransaction(
          JSON.parse(JSON.stringify(layout)),
          activePluginSpecsForLayout(layout),
          JSON.parse(JSON.stringify(snapshotValue.groupStates)))) {
      if (!restoreV2LayoutSnapshot(previousV2Layout))
        console.warn("provider snapshot V2 rollback was incomplete")
      return false
    }
    return true
  }

  function layoutWithoutProviderIds(layoutValue, providerIds) {
    const source = Util.isPlainObject(layoutValue) ? layoutValue : ({})
    const ids = Array.isArray(providerIds) ? providerIds : []
    const result = { left: [], center: [], right: [] }
    for (const region of ["left", "center", "right"]) {
      const entries = Array.isArray(source[region]) ? source[region] : []
      result[region] = entries.filter(function(entry) {
        return ids.indexOf(entryId(entry)) < 0
      })
    }
    return result
  }

  function normalizedProviderGroups(groupValues) {
    const source = Array.isArray(groupValues) ? groupValues : []
    const result = []
    for (let index = 0; index < source.length; index++) {
      const group = String(source[index] || "")
      if (GroupRegistry.GroupIds.indexOf(group) >= 0
          && result.indexOf(group) < 0) result.push(group)
    }
    return result
  }

  function widgetGroupVariantStates(groupValues) {
    const groups = normalizedProviderGroups(groupValues)
    const stateService = shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor("hancore.shibumi.state") : null
    if (groups.length === 0 || !stateService
        || typeof stateService.groupEnabledForVariant !== "function")
      return null
    const states = ({})
    for (let index = 0; index < groups.length; index++) {
      const group = groups[index]
      states[group] = {
        v1: stateService.groupEnabledForVariant(group, "v1"),
        v2: stateService.groupEnabledForVariant(group, "v2")
      }
    }
    return states
  }

  function setWidgetGroupVariantStates(stateValues) {
    if (!mutationAdmissionReady || layoutTransitionBusy) return false
    if (!Util.isPlainObject(stateValues)) return false
    const sourceGroups = Object.keys(stateValues)
    const groups = normalizedProviderGroups(sourceGroups)
    if (groups.length === 0 || groups.length !== sourceGroups.length)
      return false
    for (let index = 0; index < groups.length; index++) {
      const states = stateValues[groups[index]]
      if (!Util.isPlainObject(states)
          || typeof states.v1 !== "boolean"
          || typeof states.v2 !== "boolean") return false
    }
    const stateService = shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor("hancore.shibumi.state") : null
    if (!stateService || ("ready" in stateService && !stateService.ready)) return false
    let called = false
    if (typeof stateService.setGroupVariantStates === "function") {
      called = true
      // Request acceptance, not synchronous persistence. Published config and
      // persistenceSettled carry completion; never roll back from an old read.
      if (stateService.setGroupVariantStates(stateValues)) return true
    } else if (typeof stateService.setGroupEnabledForVariant === "function") {
      called = true
      for (let index = 0; index < groups.length; index++) {
        const group = groups[index]
        stateService.setGroupEnabledForVariant(
          group, "v1", stateValues[group].v1)
        stateService.setGroupEnabledForVariant(
          group, "v2", stateValues[group].v2)
      }
    } else if (typeof stateService.setGroupSetting === "function") {
      called = true
      for (let index = 0; index < groups.length; index++) {
        const group = groups[index]
        stateService.setGroupSetting(
          group, "enabledV1", stateValues[group].v1)
        stateService.setGroupSetting(
          group, "enabledV2", stateValues[group].v2)
      }
    }
    if (!called) return false
    if (typeof stateService.groupEnabledForVariant !== "function") return true
    return groups.every(function(group) {
      return stateService.groupEnabledForVariant(group, "v1")
          === stateValues[group].v1
        && stateService.groupEnabledForVariant(group, "v2")
          === stateValues[group].v2
    })
  }

  function setWidgetGroupsEnabledForAllVariants(groupValues, enabled) {
    const groups = normalizedProviderGroups(groupValues)
    if (groups.length === 0 || typeof enabled !== "boolean") return false
    const states = ({})
    for (let index = 0; index < groups.length; index++)
      states[groups[index]] = { v1: enabled, v2: enabled }
    return setWidgetGroupVariantStates(states)
  }

  function requestWidgetGroupStateTransition(groupId, variantValue, enabled) {
    if (!mutationAdmissionReady) return false
    const group = String(groupId || "")
    const variant = String(variantValue || "").toLowerCase()
    if (!layoutTransitionsSupported
        || layoutTransitionBusy || providerSnapshotTransitionBusy
        || stateTransitionBusy || GroupRegistry.GroupIds.indexOf(group) < 0
        || ["v1", "v2"].indexOf(variant) < 0
        || typeof enabled !== "boolean") return false
    const states = widgetGroupVariantStates([group])
    const stateService = layoutStateController.stateService
    if (!states || !stateService || stateService.ready !== true
        || stateService.writePending !== false
        || !Number.isInteger(stateService.writeSerial)
        || states[group][variant] === enabled) return false
    states[group][variant] = enabled
    return stateTransition.request({familyStates: states}, {
      kind: "state-only", group: group, variant: variant, enabled: enabled
    })
  }

  function reconcileWidgetFamilyProviders() {
    if (!legacyFamilyMutationAllowed()) return false
    const currentLayout = currentLayoutSnapshot()
    const removedProviderIds = conflictingProviderIdsInLayout(currentLayout)
    const nextLayout = layoutWithoutProviderIds(
      currentLayout, removedProviderIds)
    const ownedGroups = providerFamilyGroupsInLayout(nextLayout)
    const displacedGroups = []
    for (let index = 0; index < removedProviderIds.length; index++) {
      const groups = widgetFamilyGroups(removedProviderIds[index])
      for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        if (displacedGroups.indexOf(groups[groupIndex]) < 0)
          displacedGroups.push(groups[groupIndex])
      }
    }
    const stateValues = ({})
    for (let index = 0; index < ownedGroups.length; index++)
      stateValues[ownedGroups[index]] = { v1: false, v2: false }
    for (let index = 0; index < displacedGroups.length; index++) {
      const group = displacedGroups[index]
      if (ownedGroups.indexOf(group) < 0)
        stateValues[group] = { v1: true, v2: true }
    }
    if (removedProviderIds.length > 0)
      return applyProviderLayoutTransaction(nextLayout,
        activePluginSpecsForLayout(nextLayout), stateValues)
    const groups = Object.keys(stateValues)
    return groups.length === 0 || setWidgetGroupVariantStates(stateValues)
  }

  function catalogLayoutPatch(nextLayout, stateValues) {
    if (!Util.isPlainObject(nextLayout)) return null
    const specs = activePluginSpecsForLayout(nextLayout)
    const patch = ({})
    if (layoutStateController.v2Mode) {
      const planned = V2LayoutModel.reconcilePluginGroups(
        layoutStateController.v2Slots, specs, true)
      if (!planned || planned.unplaced.length > 0) return null
      patch.v2Layout = planned.layout
    } else {
      const order = layoutStateController.currentV1Order()
      const splits = layoutStateController.currentV1Splits(order)
      const bindings = WidgetFamilies.v1SlotBindings(specs, order,
        pluginRegistry, catalogObservation, suiteHostShell.scoped)
      const providers = Object.values(bindings)
      const planned = LayoutModel.reconcilePluginGroups(order, splits,
        specs.filter(function(spec) {
          return spec && providers.indexOf(spec.pluginId) < 0
        }))
      if (!planned || planned.unplaced.length > 0) return null
      patch.v1Layout = {order: planned.order, splits: planned.splits}
    }
    if (stateValues && Object.keys(stateValues).length > 0)
      patch.familyStates = JSON.parse(JSON.stringify(stateValues))
    return patch
  }

  function catalogTransitionIntent(widgetId, installed, region) {
    const id = String(widgetId || "")
    if (suiteHostShell.scoped) {
      const snapshot = catalogObservation ? catalogObservation.snapshot : null
      const row = snapshot && snapshot.byId
        && Object.prototype.hasOwnProperty.call(snapshot.byId, id)
        ? snapshot.byId[id] : null
      if (!row || row.id !== id || !Array.isArray(row.kinds)
          || row.kinds.indexOf("bar-widget") < 0) return null
    }
    const targetRegion = WidgetFamilies.targetRegion(id, region,
      pluginRegistry, catalogObservation, suiteHostShell.scoped)
    const removeIds = installed === true
      ? conflictingLayoutProviderIds(id) : [id]
    const affectedGroups = widgetFamilyGroups(id)
    for (const removedId of removeIds) {
      for (const group of widgetFamilyGroups(removedId))
        if (affectedGroups.indexOf(group) < 0) affectedGroups.push(group)
    }
    const current = currentLayoutSnapshot()
    const intent = {kind: "catalog-layout", id: id,
      installed: installed === true, region: targetRegion,
      removeIds: removeIds, keepConfigured: installed !== true
        && isV1AdditionalSuiteWidget(id),
      providerGroups: affectedGroups.slice()}
    const next = planNativeTransition(current, intent)
    if (!next) return null
    const owned = providerFamilyGroupsInLayout(next)
    const states = ({})
    for (const group of affectedGroups)
      states[group] = {v1: owned.indexOf(group) < 0,
        v2: owned.indexOf(group) < 0}
    const patch = catalogLayoutPatch(next, states)
    return patch ? {patch: patch, intent: intent} : null
  }

  function validateNativeTransition(layoutValue, intentValue, patchValue) {
    if (intentValue && intentValue.kind === "provider-snapshot")
      return Util.isPlainObject(intentValue.patch)
        && providerSnapshotTransition.same(intentValue.patch, patchValue)
        && providerSnapshotTransition.same(
          planNativeTransition(layoutValue, intentValue), intentValue.layout)
    if (!intentValue || intentValue.kind !== "catalog-layout") return true
    const planned = planNativeTransition(layoutValue, intentValue)
    const expected = planned ? catalogLayoutPatch(planned,
      patchValue && patchValue.familyStates) : null
    return !!expected && layoutTransition.same(expected, patchValue)
  }

  function canSetBarWidgetInstalled(widgetId, installed) {
    if (!mutationAdmissionReady) return false
    const id = String(widgetId || "")
    if (!suiteHostShell.scoped || !layoutTransitionsSupported
        || layoutTransitionBusy || providerSnapshotTransitionBusy
        || stateTransitionBusy || !catalogObservation
        || !LayoutModel.validPluginId(id)) return false
    if (installed !== true) return layoutContains(id)
    const snapshot = catalogObservation.snapshot
    const row = snapshot && snapshot.byId
      && Object.prototype.hasOwnProperty.call(snapshot.byId, id)
      ? snapshot.byId[id] : null
    return !!(row && row.id === id
      && (row.enabled === false || (row.enabled === true
        && !layoutStateController.v2Mode
        && isV1AdditionalSuiteWidget(id) && !layoutContains(id)
        && registeredWidgetComponent(id) !== null))
      && Array.isArray(row.kinds) && row.kinds.indexOf("bar-widget") >= 0)
  }

  function requestCatalogLayoutTransition(widgetId, installed, region,
      observationValue) {
    const id = String(widgetId || "")
    if (!canSetBarWidgetInstalled(id, installed)
        || observationValue !== catalogObservation) return false
    const request = catalogTransitionIntent(id, installed, region)
    if (!request) return false
    const groups = Array.isArray(request.intent.providerGroups)
      ? request.intent.providerGroups : []
    lastCatalogTransitionSnapshot = groups.length > 0
      ? providerLayoutSnapshot(groups) : null
    const accepted = layoutTransition.request(request.patch, request.intent)
    if (!accepted) lastCatalogTransitionSnapshot = null
    return accepted
  }

  function setBarWidgetInstalled(widgetId, installed, region,
      observationValue) {
    if (!mutationAdmissionReady) return false
    if (suiteHostShell.scoped)
      return requestCatalogLayoutTransition(
        widgetId, installed, region, observationValue)
    if (!legacyFamilyMutationAllowed()) return false
    const requestedId = String(widgetId || "")
    const selection = installed === true
      ? hostWidgetResolverService.selectionFor(requestedId) : null
    if (installed === true && !hasBarWidgetEntryPoint(requestedId, selection))
      return false
    const id = selection ? selection.id : requestedId
    const effectiveSelection = selection
      ? hostWidgetResolverService.selectionFor(id) : null
    if (selection && (!effectiveSelection || effectiveSelection.id !== id
        || effectiveSelection.manifest !== selection.manifest)) return false
    // A host-selected clone retains its own activation identity. Enabling the
    // original would tell Omarchy to restore the source and remove the clone.
    if (id !== requestedId && JSON.stringify(widgetFamilyGroups(id).sort())
        !== JSON.stringify(widgetFamilyGroups(requestedId).sort())) return false
    const targetRegion = WidgetFamilies.targetRegion(
      id, region, pluginRegistry, catalogObservation, suiteHostShell.scoped)
    const familyGroups = widgetFamilyGroups(id)
    if (!id || !shell || typeof shell.mutateShellConfig !== "function")
      return false
    // V1's fixed family slot has one provider identity, not instance keys.
    // Refuse an ambiguous multi-instance replacement before changing layout,
    // registry enablement or either generation's family state. Existing
    // layouts and unrelated allowMultiple entries keep their old semantics.
    if (installed === true && !layoutStateController.v2Mode
        && familyGroups.length > 0 && widgetAllowsMultiple(id, selection))
      return false

    const previousSpecs = activePluginSpecs()
    const previousLayout = currentLayoutSnapshot()
    const existingEntries = ["left", "center", "right"].reduce(
      (entries, part) => entries.concat(previousLayout[part].filter(
        entry => entryId(entry) === id)), [])
    if (installed === true && !widgetAllowsMultiple(id, selection)
        && existingEntries.length > 1) return false
    const previousV2Layout = currentV2LayoutSnapshot()
    const previousV1Order = !layoutStateController.v2Mode
      ? layoutStateController.currentV1Order() : null
    const previousV1Splits = previousV1Order
      ? layoutStateController.currentV1Splits(previousV1Order) : null
    const replacedProviderIds = installed === true
      ? conflictingLayoutProviderIds(id) : [id]
    const displacedGroups = []
    for (let index = 0; index < replacedProviderIds.length; index++) {
      const replacedId = replacedProviderIds[index]
      if (replacedId === id) continue
      const groups = widgetFamilyGroups(replacedId)
      for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        if (displacedGroups.indexOf(groups[groupIndex]) < 0)
          displacedGroups.push(groups[groupIndex])
      }
    }
    const nextLayout = layoutWithoutProviderIds(
      previousLayout, replacedProviderIds)
    if (installed === true) {
      const entry = existingEntries.length === 1 && Util.isPlainObject(existingEntries[0])
        ? JSON.parse(JSON.stringify(existingEntries[0])) : { id: id }
      entry.shibumiModule = true
      nextLayout[targetRegion].push(entry)
    } else if (isV1AdditionalSuiteWidget(id))
      nextLayout[targetRegion].push({ id: id })
    const nextOwnedGroups = providerFamilyGroupsInLayout(nextLayout)
    const stateValues = ({})
    if (installed === true) {
      for (let index = 0; index < familyGroups.length; index++)
        stateValues[familyGroups[index]] = { v1: false, v2: false }
      for (let index = 0; index < displacedGroups.length; index++) {
        const group = displacedGroups[index]
        if (nextOwnedGroups.indexOf(group) < 0)
          stateValues[group] = { v1: true, v2: true }
      }
    }
    const stateGroups = Object.keys(stateValues)
    const stateService = stateGroups.length > 0 && shell
      && typeof shell.serviceFor === "function"
      ? shell.serviceFor("hancore.shibumi.state") : null
    const canSetFamilyState = stateService
      && (typeof stateService.setGroupVariantStates === "function"
        || typeof stateService.setGroupEnabledForVariant === "function"
        || typeof stateService.setGroupSetting === "function")
    if (stateGroups.length > 0 && !canSetFamilyState) return false
    const previousFamilyStates = stateGroups.length > 0
      ? widgetGroupVariantStates(stateGroups) : null
    const registryWasEnabled = pluginRegistry
      && typeof pluginRegistry.isEnabled === "function"
      ? pluginRegistry.isEnabled(id) : null
    if (installed === true && registryWasEnabled !== true
        && (!pluginRegistry || typeof pluginRegistry.setEnabled !== "function"))
      return false
    const desiredSpecs = activePluginSpecs(replacedProviderIds,
      installed === true ? { id: id, region: targetRegion } : null)
    if (!reconcileActivePluginGroups(
          desiredSpecs, false, layoutStateController.v2Mode))
      return false

    if (installed === true && registryWasEnabled !== true
        && pluginRegistry.setEnabled(id, true) !== true) {
      const restoredGroups = previousV1Order
        ? layoutStateController.restoreV1Layout(previousV1Order, previousV1Splits)
        : reconcileActivePluginGroups(previousSpecs, false)
      const restoredV2 = restoreV2LayoutSnapshot(previousV2Layout)
      if (!restoredGroups || !restoredV2)
        console.warn("provider enable rollback was incomplete")
      return false
    }
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.layout = JSON.parse(JSON.stringify(nextLayout))
    })
    // Persist the provider choice last. mutateShellConfig may publish its
    // snapshot asynchronously, so writing this state before the layout would
    // let that older snapshot re-enable the Shibumi provider.
    if (stateGroups.length > 0 && canSetFamilyState
        && !setWidgetGroupVariantStates(stateValues)) {
      shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.layout = JSON.parse(JSON.stringify(previousLayout))
      })
      const restoredGroups = previousV1Order
        ? layoutStateController.restoreV1Layout(
            previousV1Order, previousV1Splits)
        : reconcileActivePluginGroups(previousSpecs, false)
      const restoredV2 = restoreV2LayoutSnapshot(previousV2Layout)
      if (registryWasEnabled === false && pluginRegistry
          && typeof pluginRegistry.setEnabled === "function")
        pluginRegistry.setEnabled(id, false)
      const restoredFamilies = !previousFamilyStates
        || setWidgetGroupVariantStates(previousFamilyStates)
      if (!restoredGroups || !restoredV2 || !restoredFamilies)
        console.warn("provider transaction rollback was incomplete")
      return false
    }
    return true
  }

  function applyProviderLayoutTransaction(nextLayout, desiredSpecs,
      stateValues) {
    if (!legacyFamilyMutationAllowed()) return false
    if (!shell || typeof shell.mutateShellConfig !== "function") return false
    const previousSpecs = activePluginSpecs()
    const previousLayout = currentLayoutSnapshot()
    const previousV2Layout = currentV2LayoutSnapshot()
    const previousV1Order = !layoutStateController.v2Mode
      ? layoutStateController.currentV1Order() : null
    const previousV1Splits = previousV1Order
      ? layoutStateController.currentV1Splits(previousV1Order) : null
    const groups = Util.isPlainObject(stateValues)
      ? Object.keys(stateValues) : []
    const previousStates = groups.length > 0
      ? widgetGroupVariantStates(groups) : null
    if (!reconcileActivePluginGroups(desiredSpecs, false))
      return false
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.layout = JSON.parse(JSON.stringify(nextLayout))
    })
    if (groups.length === 0 || setWidgetGroupVariantStates(stateValues))
      return true
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.layout = JSON.parse(JSON.stringify(previousLayout))
    })
    const restoredGroups = previousV1Order
      ? layoutStateController.restoreV1Layout(
          previousV1Order, previousV1Splits)
      : reconcileActivePluginGroups(previousSpecs, false)
    const restoredV2 = restoreV2LayoutSnapshot(previousV2Layout)
    const restoredStates = !previousStates
      || setWidgetGroupVariantStates(previousStates)
    if (!restoredGroups || !restoredV2 || !restoredStates)
      console.warn("provider layout rollback was incomplete")
    return false
  }

  function widgetFamilyAlternativeIds(groupValues) {
    const groups = normalizedProviderGroups(groupValues)
    const result = []
    for (let index = 0; index < groups.length; index++) {
      const family = WidgetFamilies.familyForGroup(
        groups[index], pluginRegistry, catalogObservation,
        suiteHostShell.scoped)
      if (!family) continue
      for (let alternativeIndex = 0;
           alternativeIndex < family.alternatives.length;
           alternativeIndex++) {
        const id = String(family.alternatives[alternativeIndex] || "")
        if (id !== "" && result.indexOf(id) < 0) result.push(id)
      }
    }
    return result
  }

  function widgetFamilyAlternativesInstalled(groupId) {
    const group = String(groupId || "")
    if (GroupRegistry.GroupIds.indexOf(group) < 0) return false
    for (const region of ["left", "center", "right"]) {
      const entries = renderedProviderEntries(layoutConfig, region)
      for (let index = 0; index < entries.length; index++) {
        if (widgetFamilyGroups(entryId(entries[index])).indexOf(group) >= 0)
          return true
      }
    }
    return false
  }

  function restoreWidgetFamilyProviderStates(stateValues) {
    if (!mutationAdmissionReady || !Util.isPlainObject(stateValues)) return false
    if (suiteHostShell.scoped) {
      if (!layoutTransitionsSupported || layoutTransitionBusy
          || providerSnapshotTransitionBusy || stateTransitionBusy
          || !catalogObservation) return false
      const sourceGroups = Object.keys(stateValues)
      const groups = normalizedProviderGroups(sourceGroups)
      if (groups.length === 0 || groups.length !== sourceGroups.length)
        return false
      for (let index = 0; index < groups.length; index++) {
        const states = stateValues[groups[index]]
        if (!Util.isPlainObject(states)
            || typeof states.v1 !== "boolean"
            || typeof states.v2 !== "boolean") return false
      }
      const alternatives = widgetFamilyAlternativeIds(groups).filter(function(id) {
        return layoutContains(id)
      })
      if (alternatives.length === 0) return false
      const affectedGroups = groups.slice()
      for (let index = 0; index < alternatives.length; index++) {
        const alternativeGroups = widgetFamilyGroups(alternatives[index])
        for (let groupIndex = 0; groupIndex < alternativeGroups.length;
             groupIndex++) {
          if (affectedGroups.indexOf(alternativeGroups[groupIndex]) < 0)
            affectedGroups.push(alternativeGroups[groupIndex])
        }
      }
      const intent = {kind: "catalog-layout", id: alternatives[0],
        installed: false, region: "right", removeIds: alternatives,
        keepConfigured: false, providerGroups: affectedGroups.slice()}
      const next = planNativeTransition(currentLayoutSnapshot(), intent)
      if (!next) return false
      const ownedGroups = providerFamilyGroupsInLayout(next)
      const effectiveStates = JSON.parse(JSON.stringify(stateValues))
      for (let index = 0; index < affectedGroups.length; index++) {
        const group = affectedGroups[index]
        if (ownedGroups.indexOf(group) < 0
            && !Object.prototype.hasOwnProperty.call(effectiveStates, group))
          effectiveStates[group] = {v1: true, v2: true}
      }
      const patch = catalogLayoutPatch(next, effectiveStates)
      const snapshot = patch ? providerLayoutSnapshot(affectedGroups) : null
      if (!patch || !snapshot) return false
      lastCatalogTransitionSnapshot = snapshot
      const accepted = layoutTransition.request(patch, intent)
      if (!accepted) lastCatalogTransitionSnapshot = null
      return accepted
    }
    if (!legacyFamilyMutationAllowed()) return false
    const groups = normalizedProviderGroups(Object.keys(stateValues))
    if (groups.length === 0
        || groups.length !== Object.keys(stateValues).length) return false
    const alternatives = widgetFamilyAlternativeIds(groups)
    const nextLayout = layoutWithoutProviderIds(
      currentLayoutSnapshot(), alternatives)
    const ownedGroups = providerFamilyGroupsInLayout(nextLayout)
    const effectiveStates = JSON.parse(JSON.stringify(stateValues))
    for (let index = 0; index < alternatives.length; index++) {
      const alternativeGroups = widgetFamilyGroups(alternatives[index])
      for (let groupIndex = 0; groupIndex < alternativeGroups.length;
           groupIndex++) {
        const group = alternativeGroups[groupIndex]
        if (ownedGroups.indexOf(group) < 0
            && !Object.prototype.hasOwnProperty.call(effectiveStates, group))
          effectiveStates[group] = { v1: true, v2: true }
      }
    }
    return applyProviderLayoutTransaction(
      nextLayout, activePluginSpecs(alternatives), effectiveStates)
  }

  function restoreWidgetFamilyProviders(groupValues) {
    const groups = normalizedProviderGroups(groupValues)
    if (groups.length === 0) return false
    const states = ({})
    for (let index = 0; index < groups.length; index++)
      states[groups[index]] = { v1: true, v2: true }
    return restoreWidgetFamilyProviderStates(states)
  }

  function canRemoveBarWidget(widgetId) {
    const id = String(widgetId || "")
    return id !== "" && (layoutStateController.v2Mode
      || layoutStateController.canRemoveV1PluginGroup(id))
  }

  function removeBarWidgetAndRestoreFamilies(widgetId, groupValues) {
    if (!legacyFamilyMutationAllowed()) return false
    const id = String(widgetId || "")
    if (id === "") return false
    const groups = normalizedProviderGroups(groupValues)
    const nextLayout = layoutWithoutProviderIds(
      currentLayoutSnapshot(), [id])
    const states = ({})
    const ownedGroups = providerFamilyGroupsInLayout(nextLayout)
    for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      const group = groups[groupIndex]
      if (ownedGroups.indexOf(group) < 0)
        states[group] = { v1: true, v2: true }
    }
    return applyProviderLayoutTransaction(
      nextLayout, activePluginSpecs([id]), states)
  }

  function removeWidgetFamilyAlternatives(groupId) {
    if (!mutationAdmissionReady) return false
    const family = WidgetFamilies.familyForGroup(
      groupId, pluginRegistry, catalogObservation, suiteHostShell.scoped)
    if (!family || !shell || typeof shell.mutateShellConfig !== "function")
      return false
    let changed = false
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)
          || !Util.isPlainObject(config.bar.layout)) return
      for (const section of ["left", "center", "right"]) {
        const source = Array.isArray(config.bar.layout[section])
          ? config.bar.layout[section] : []
        const filtered = source.filter(function(entry) {
          const entryValue = Util.isPlainObject(entry) ? entry.id : entry
          return family.alternatives.indexOf(
            Util.canonicalWidgetId(entryValue || "")) < 0
        })
        if (filtered.length !== source.length) changed = true
        config.bar.layout[section] = filtered
      }
    })
    return changed
  }

  function widgetReplacementLabel(widgetId) {
    return WidgetFamilies.replacementLabel(
      widgetId, pluginRegistry, catalogObservation, suiteHostShell.scoped)
  }

  function widgetReplacementGroups(widgetId) {
    return widgetFamilyGroups(widgetId)
  }

  function widgetReplacementGroup(widgetId) {
    const groups = widgetReplacementGroups(widgetId)
    return groups.length > 0 ? groups[0] : ""
  }

  function widgetReplacementTarget(widgetId) {
    return WidgetFamilies.joinedLabels(
      WidgetFamilies.replacementTargets(
        String(widgetId || ""), pluginRegistry, catalogObservation,
        suiteHostShell.scoped))
  }

  function entryId(entry) {
    if (typeof entry === "string") return Util.canonicalWidgetId(entry)
    if (Util.isPlainObject(entry)) return Util.canonicalWidgetId(entry.id || "")
    return ""
  }

  function entrySettings(entry) {
    if (!Util.isPlainObject(entry)) return ({})
    const settings = ({})
    for (const key in entry) {
      if (key !== "id") settings[key] = entry[key]
    }
    return settings
  }

  function entryIndex(entries, id) {
    if (!Array.isArray(entries)) return -1
    for (let i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return i
    }
    return -1
  }

  function run(command) {
    const text = String(command || "").trim()
    if (!text) return
    if (typeof Util.execDetached === "function") Util.execDetached(text)
    else Quickshell.execDetached(["bash", "-lc", text])
  }

  function resolvedPopoutScreenName(owner, screenName) {
    const explicitName = String(screenName || "").trim()
    if (explicitName) return explicitName
    if (owner && "popoutScreenName" in owner) {
      const ownerName = String(owner.popoutScreenName || "").trim()
      if (ownerName) return ownerName
    }
    const ownerWindow = owner && owner.QsWindow
      ? owner.QsWindow.window : null
    const ownerScreen = ownerWindow ? ownerWindow.screen : null
    return ownerScreen ? String(ownerScreen.name || "").trim() : ""
  }

  function popoutScreenKey(screenName) {
    const value = String(screenName || "").trim()
    return value || "__global__"
  }

  function activePopoutForScreen(screenName) {
    return activePopouts[popoutScreenKey(screenName)] || null
  }

  function remainingPopout(next) {
    let result = null
    for (const key in next) result = next[key]
    return result
  }

  function requestPopout(owner, screenName) {
    if (!owner) return
    const key = popoutScreenKey(resolvedPopoutScreenName(owner, screenName))
    const previous = activePopouts[key] || null
    if (previous === owner) {
      activePopout = owner
      return
    }
    const next = ({})
    for (const existingKey in activePopouts)
      next[existingKey] = activePopouts[existingKey]
    next[key] = owner
    activePopouts = next
    activePopout = owner
    if (!previous) return
    if (typeof previous.closeForPopoutSwitch === "function")
      previous.closeForPopoutSwitch()
    else if (typeof previous.close === "function") previous.close()
  }

  function releasePopout(owner, screenName) {
    if (!owner) return
    const resolvedScreenName = resolvedPopoutScreenName(owner, screenName)
    const constrained = resolvedScreenName !== ""
    const requestedKey = popoutScreenKey(resolvedScreenName)
    const next = ({})
    let removed = false
    for (const key in activePopouts) {
      if (activePopouts[key] === owner && (!constrained || key === requestedKey))
        removed = true
      else
        next[key] = activePopouts[key]
    }
    if (!removed) return
    activePopouts = next
    if (activePopout === owner) activePopout = remainingPopout(next)
  }

  function releasePopoutsForScreen(screenName) {
    const key = popoutScreenKey(screenName)
    const owner = activePopouts[key] || null
    if (!owner) return false
    const next = ({})
    for (const existingKey in activePopouts) {
      if (existingKey !== key) next[existingKey] = activePopouts[existingKey]
    }
    activePopouts = next
    if (activePopout === owner) activePopout = remainingPopout(next)
    clearConnectedPanel(owner)
    if (typeof owner.close === "function") owner.close()
    return true
  }

  function dismissActivePopout(screenName) {
    const constrained = String(screenName || "").trim() !== ""
    if (constrained) return releasePopoutsForScreen(screenName)
    const owners = []
    for (const key in activePopouts) {
      const owner = activePopouts[key]
      if (owner && owners.indexOf(owner) < 0) owners.push(owner)
    }
    if (owners.length === 0) return false
    activePopouts = ({})
    activePopout = null
    for (const owner of owners) {
      clearConnectedPanel(owner)
      if (typeof owner.close === "function") owner.close()
    }
    return true
  }

  onBarHiddenChanged: {
    if (barHidden) dismissActivePopout()
  }

  function emptyConnectedPanel() {
    return ({
      owner: null,
      screenName: "",
      x: 0,
      reveal: 0,
      hostCaret: false,
      cardX: 0,
      cardY: 0,
      cardWidth: 0,
      cardHeight: 0
    })
  }

  function connectedPanelForScreen(screenName) {
    return connectedPanels[popoutScreenKey(screenName)] || emptyConnectedPanel()
  }

  function syncConnectedPanelCompatibility(record) {
    const value = record || emptyConnectedPanel()
    connectedPanelOwner = value.owner || null
    connectedPanelScreenName = String(value.screenName || "")
    connectedPanelX = Number(value.x) || 0
    connectedPanelReveal = Number(value.reveal) || 0
    connectedPanelHostCaret = value.hostCaret === true
    connectedPanelCardX = Number(value.cardX) || 0
    connectedPanelCardY = Number(value.cardY) || 0
    connectedPanelCardWidth = Math.max(0, Number(value.cardWidth) || 0)
    connectedPanelCardHeight = Math.max(0, Number(value.cardHeight) || 0)
  }

  function remainingConnectedPanel(next) {
    let result = null
    for (const key in next) result = next[key]
    return result
  }

  function publishConnectedPanel(owner, screenName, resolvedX, reveal,
      options) {
    if (!owner) return false
    const name = String(screenName || "").trim()
    const progress = Math.max(0, Math.min(1, Number(reveal) || 0))
    const x = Number(resolvedX) || 0
    if (progress <= 0.001)
      return clearConnectedPanel(owner, name)
    if (x <= 0 || !name) return false
    const key = popoutScreenKey(name)
    const current = connectedPanels[key] || null
    if (current && current.owner !== owner
        && activePopoutForScreen(name) !== owner) return false
    const geometry = options && typeof options === "object" ? options : null
    const record = {
      owner: owner,
      screenName: name,
      x: x,
      reveal: progress,
      hostCaret: !!(geometry && geometry.hostCaret === true),
      cardX: geometry ? Number(geometry.cardX) || 0 : 0,
      cardY: geometry ? Number(geometry.cardY) || 0 : 0,
      cardWidth: geometry
        ? Math.max(0, Number(geometry.cardWidth) || 0) : 0,
      cardHeight: geometry
        ? Math.max(0, Number(geometry.cardHeight) || 0) : 0
    }
    const next = ({})
    for (const existingKey in connectedPanels)
      next[existingKey] = connectedPanels[existingKey]
    next[key] = record
    connectedPanels = next
    syncConnectedPanelCompatibility(record)
    return true
  }

  function clearConnectedPanel(owner, screenName) {
    const constrained = String(screenName || "").trim() !== ""
    const requestedKey = popoutScreenKey(screenName)
    const next = ({})
    let removed = false
    for (const key in connectedPanels) {
      const record = connectedPanels[key]
      if ((!owner || record.owner === owner)
          && (!constrained || key === requestedKey))
        removed = true
      else
        next[key] = record
    }
    if (!removed) return false
    connectedPanels = next
    if (!connectedPanelOwner || !owner || connectedPanelOwner === owner
        || constrained && connectedPanelScreenName === String(screenName))
      syncConnectedPanelCompatibility(remainingConnectedPanel(next))
    return true
  }

  function showTooltip(target, text) {
    const nextText = String(text || "")
    if (!target || !nextText) {
      hideTooltip(target)
      return
    }
    pendingTooltipTarget = target
    pendingTooltipText = nextText
    tooltipDelay.restart()
  }

  function hideTooltip(target) {
    if (target && target !== tooltipTarget && target !== pendingTooltipTarget) return
    tooltipDelay.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    const next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    moduleSlots = moduleSlots.filter(item => item !== slot)
  }

  function widgetSlotLoadAdmitted(slot) {
    return widgetAllowsMultiple(slot.moduleName) || !loadedOwners.some(candidate =>
      candidate.objectName === slot.moduleName && candidate.screenName === slot.screenName && candidate.slot !== slot)
  }
  function claimLoadedOwner(slot, item) {
    if (!widgetSlotLoadAdmitted(slot)) return false
    return !!loadedOwnerSentinel.createObject(item, {slot, objectName: slot.moduleName, screenName: slot.screenName})
  }
  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    const next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    clickTargets = clickTargets.filter(item => item !== target)
  }

  function registerLayoutSession(session) {
    if (session && layoutSessions.indexOf(session) < 0)
      layoutSessions = layoutSessions.concat([session])
  }

  function unregisterLayoutSession(session) {
    layoutSessions = layoutSessions.filter(item => item !== session)
  }

  function setLayoutEditing(enabled, screenName) {
    if (!mutationAdmissionReady) return false
    const requested = String(screenName || "") || focusedOutputName()
    let changed = false
    for (let index = 0; index < layoutSessions.length; index++) {
      const session = layoutSessions[index]
      if (!session || (requested !== ""
          && String(session.screenName || "") !== requested)) continue
      if (typeof session.setEditing === "function")
        changed = session.setEditing(enabled === true) || changed
    }
    return changed
  }

  function panelSlotsFor(owner) {
    const ownerWindow = targetWindow(owner)
    return moduleSlots.filter(slot => {
      if (!slot || !slot.activeItem || !slot.visible) return false
      if (ownerWindow && targetWindow(slot.activeItem) !== ownerWindow) return false
      const item = slot.activeItem
      return typeof item.open === "function"
        && typeof item.close === "function"
        && item.opened !== undefined
    })
  }

  function switchPanelFrom(owner, direction) {
    const slots = panelSlotsFor(owner)
    if (slots.length < 2) return false
    const current = slots.findIndex(slot => slot.activeItem === owner)
    if (current < 0) return false
    const step = direction < 0 ? -1 : 1
    const next = slots[(current + step + slots.length) % slots.length]
    next.activeItem.open()
    return true
  }

  function focusedOutputName() {
    const monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function findPanelWidget(pluginId, screenName) {
    const requested = String(screenName || "") || focusedOutputName()
    return PanelRouting.findPanelWidgetForScreen(moduleSlots, pluginId, requested)
  }

  function findPanelWidgetOnScreen(pluginId, screenName) {
    const id = String(pluginId || "")
    const requested = String(screenName || "")
    if (requested === "") return findPanelWidget(id)
    for (let index = 0; index < moduleSlots.length; index++) {
      const slot = moduleSlots[index]
      if (!slot || String(slot.screenName || "") !== requested) continue
      const panel = PanelRouting.panelForSlot(slot, id)
      if (panel) return panel
    }
    return null
  }

  function panelWidgets(pluginId) {
    return PanelRouting.panelWidgets(moduleSlots, pluginId)
  }

  function screenForName(value) {
    const requested = String(value || "")
    let fallback = null
    for (let i = 0; i < moduleSlots.length; i++) {
      const slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      const window = targetWindow(slot.activeItem)
      const candidate = window && window.screen ? window.screen : null
      if (!candidate || String(candidate.name || "") === "") continue
      if (!fallback) fallback = candidate
      if (requested !== "" && String(candidate.name || "") === requested)
        return candidate
    }
    return fallback
  }

  function summonBarWidget(pluginId, screenName) {
    const item = findPanelWidget(pluginId, screenName)
    if (!item) return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    const items = panelWidgets(pluginId)
    if (items.length === 0) return false
    for (let i = 0; i < items.length; i++) {
      if (items[i].opened === true) items[i].close()
    }
    return true
  }

  function isBarWidgetOpen(pluginId) {
    const items = panelWidgets(pluginId)
    for (let i = 0; i < items.length; i++) {
      if (items[i].opened === true) return true
    }
    return false
  }

  function barWidgetPage(pluginId, fallbackPage) {
    const widget = findPanelWidget(pluginId)
    return widget && widget.panelLoaded === true && widget.panelItem
      && widget.panelItem.settingsPage !== undefined
      ? String(widget.panelItem.settingsPage || fallbackPage || "")
      : String(fallbackPage || "")
  }

  function scheduleOpenControlCenterRestores(page, needsReplacement,
      preferredOwner, preferredScreenName, includeExisting) {
    const id = "hancore.shibumi.control-center"
    const owners = panelWidgets(id).filter(function(owner) {
      return owner && owner.opened === true
    })
    if (preferredOwner && preferredOwner.opened === true) {
      const index = owners.indexOf(preferredOwner)
      if (index >= 0) owners.splice(index, 1)
      owners.unshift(preferredOwner)
    }
    const created = []
    const outputs = Object.create(null)
    for (let index = 0; index < owners.length; index++) {
      const owner = owners[index]
      const preferred = owner === preferredOwner
        ? String(preferredScreenName || "") : ""
      const screenName = restoreScreenName(owner, preferred)
      // Outgoing and replacement owners can overlap on one output. Enroll
      // that output once, preferring its explicit invoking owner.
      if (Object.prototype.hasOwnProperty.call(outputs, screenName)) continue
      outputs[screenName] = true
      const requestedPage = owner.panelLoaded === true && owner.panelItem
        ? String(owner.panelItem.settingsPage || page || "")
        : String(page || "")
      const capture = []
      if (!scheduleWidgetRestore(id, requestedPage, needsReplacement,
          owner, screenName, capture)) continue
      if (capture[0].created || includeExisting === true) created.push(capture[0])
    }
    return created
  }

  function cancelCreatedWidgetRestores(records) {
    const values = Array.isArray(records) ? records : []
    let changed = false
    for (let index = 0; index < values.length; index++) {
      const record = values[index]
      if (!record) continue
      const current = widgetRestoreIndex(record.id, record.owner, record.screenName)
      if (current < 0 || (record.restoreId !== undefined
          && pendingWidgetRestores[current].restoreId !== record.restoreId)) continue
      const live = pendingWidgetRestores[current]
      // Undo only our provisional update, never newer navigation, settlement,
      // cancellation/recreation or a timer turn entered by the callback.
      if (record.scheduled && live.restoreRevision !== record.restoreRevision) continue
      if (record.created === false) {
        if (!record.previous) continue
        const next = pendingWidgetRestores.slice()
        const navigationChanged = record.scheduled
          && live.navigationRevision !== record.scheduled.navigationRevision
        next[current] = Object.assign({}, record.previous, navigationChanged
          ? {page: live.page, navigationRevision: live.navigationRevision} : {})
        pendingWidgetRestores = next
        changed = true
      } else changed = removeWidgetRestoreAt(current) || changed
    }
    return changed
  }

  // Keep restoration in the persistent Bar, not in a panel which a published
  // style change can destroy. Queue acceptance is not persistence completion.
  function runWithControlCenterRestore(callback, page, needsReplacement,
      preferredOwner, preferredScreenName) {
    if (!mutationAdmissionReady
        || typeof callback !== "function" || !restoreAdmitted) return false
    const writer = restoreStateService
    const serial = writer && "writeSerial" in writer ? writer.writeSerial : -1
    const revision = writer && "revision" in writer ? writer.revision : -1
    const layoutSerial = layoutTransitionSerial
    const snapshotSerial = providerSnapshotTransitionSerial
    const records = scheduleOpenControlCenterRestores(page, needsReplacement,
      preferredOwner, preferredScreenName, true)
    if (!restoreAdmitted) { cancelCreatedWidgetRestores(records); return false }
    const call = {writer: writer, serial: serial, settlements: []}
    activeRestoreCalls.push(call)
    let accepted = false
    try { accepted = callback() === true }
    catch (error) { cancelCreatedWidgetRestores(records); throw error }
    finally { activeRestoreCalls = activeRestoreCalls.filter(item => item !== call) }
    if (!accepted) { cancelCreatedWidgetRestores(records); return false }
    if (!restoreAdmitted || (serial >= 0
        && (!writer || writer !== restoreStateService || !writer.ready))) {
      cancelCreatedWidgetRestores(records)
      return false
    }
    const stateQueued = serial >= 0 && writer.writeSerial > serial
    if (stateQueued && !writer.writePending
        && !call.settlements.some(item => item.serial >= writer.writeSerial)) {
      cancelCreatedWidgetRestores(records)
      return false
    }
    const hold = layoutTransitionBusy && layoutTransition.operation.id > layoutSerial
      ? layoutTransition.operation.id
      : providerSnapshotTransitionBusy
          && providerSnapshotTransition.operation.id > snapshotSerial
        ? -providerSnapshotTransition.operation.id : 0
    if (stateQueued || hold) {
      const next = pendingWidgetRestores.slice()
      for (let i = 0; i < records.length; i++) {
        const ref = records[i]
        const index = next.findIndex(function(record) { return record.restoreId === ref.restoreId })
        if (index < 0) continue // User cancellation is newer than the request.
        const record = next[index]
        next[index] = Object.assign({}, record, {
          restoreRevision: Number(record.restoreRevision || 0) + 1,
          stateBound: true, writeOwner: writer,
          waitingLayout: hold || record.waitingLayout || 0,
          waitingWrites: (record.waitingWrites || []).concat(stateQueued
            ? [{serial: writer.writeSerial, revision: revision}] : []),
          restoreConfirmed: ref.created ? false : record.restoreConfirmed !== false
        })
      }
      pendingWidgetRestores = next
      for (const event of call.settlements) {
        if (!restoreAdmitted || writer !== restoreStateService || !writer.ready) break
        settleStateRestores(event.serial, event.result, event.revision)
      }
    }
    return true
  }

  function settleLayoutRestores(serial, result) {
    if (!restoreAdmitted) { revokeStateRestores(); return }
    const next = []
    for (const record of pendingWidgetRestores) {
      if (record.waitingLayout !== serial) { next.push(record); continue }
      const confirmed = record.restoreConfirmed || result === "confirmed"
      if (!confirmed && !(record.waitingWrites || []).length) continue
      next.push(Object.assign({}, record, {waitingLayout: 0, restoreConfirmed: confirmed,
        restoreRevision: Number(record.restoreRevision || 0) + 1, attempts: 0}))
    }
    pendingWidgetRestores = next
    if (!next.length) widgetRestoreTimer.stop()
  }

  function observeStateSettlement(throughSerial, result) {
    const writer = restoreStateService
    for (const call of activeRestoreCalls) {
      if (call.writer === writer && throughSerial > call.serial)
        call.settlements.push({serial: throughSerial, result: result,
          revision: writer ? writer.revision : -1})
    }
    settleStateRestores(throughSerial, result)
  }

  function revokeStateRestores() {
    const writer = restoreStateService
    pendingWidgetRestores = pendingWidgetRestores.filter(function(record) {
      return root.restoreAdmitted && (!record.stateBound
        || (record.writeOwner === writer && writer && writer.ready))
    })
    if (!pendingWidgetRestores.length && widgetRestoreTimer) widgetRestoreTimer.stop()
  }

  function settleStateRestores(throughSerial, result, observedRevision) {
    const writer = restoreStateService
    if (!restoreAdmitted || !writer || !writer.ready) { revokeStateRestores(); return }
    const revision = observedRevision === undefined ? writer.revision : observedRevision
    const next = []
    for (const record of pendingWidgetRestores) {
      if (record.writeOwner !== writer || !record.waitingWrites || !record.waitingWrites.length) {
        next.push(record)
        continue
      }
      const completed = record.waitingWrites.filter(function(request) { return request.serial <= throughSerial })
      if (!completed.length) { next.push(record); continue }
      const changed = result === "confirmed" || (result === "unchanged"
        && completed.some(function(request) { return request.revision !== revision }))
      const waiting = record.waitingWrites.filter(function(request) { return request.serial > throughSerial })
      // A later refusal cannot undo an earlier applied write's restore. A pure
      // no-op or failed first write must not reopen a panel at all.
      const confirmed = record.restoreConfirmed || changed
      if (!confirmed && !waiting.length && !record.waitingLayout) continue
      next.push(Object.assign({}, record, {waitingWrites: waiting,
        restoreRevision: Number(record.restoreRevision || 0) + 1,
        restoreConfirmed: confirmed, attempts: 0}))
    }
    pendingWidgetRestores = next
    if (!next.length) widgetRestoreTimer.stop()
  }

  Connections {
    target: root.restoreStateService
    ignoreUnknownSignals: true
    function onPersistenceSettled(throughSerial, result) { root.observeStateSettlement(throughSerial, result) }
    function onReadyChanged() { root.revokeStateRestores() }
  }

  function openConfigPanel() {
    return summonBarWidget("hancore.shibumi.control-center")
  }

  function openConfigPage(page) {
    const widget = findPanelWidget("hancore.shibumi.control-center")
    return widget && typeof widget.openPage === "function"
      ? widget.openPage(String(page || "")) : false
  }

  function restoreScreenName(owner, screenName) {
    const explicit = String(screenName || "")
    if (explicit !== "") return explicit
    const window = targetWindow(owner)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  function widgetRestoreIndex(pluginId, owner, screenName) {
    const id = String(pluginId || "")
    const requestedScreen = restoreScreenName(owner, screenName)
    for (let index = 0; index < pendingWidgetRestores.length; index++) {
      const record = pendingWidgetRestores[index]
      if (record && record.id === id
          && String(record.screenName || "") === requestedScreen) return index
    }
    return -1
  }

  function widgetRestorePendingForOutput(pluginId, owner, screenName) {
    return widgetRestoreIndex(pluginId, owner, screenName) >= 0
  }

  function widgetRestorePendingForOwner(pluginId, owner, screenName) {
    const index = widgetRestoreIndex(pluginId, owner, screenName)
    if (index < 0) return false
    const record = pendingWidgetRestores[index]
    return record.owner === owner || record.activeOwner === owner
  }

  function scheduleWidgetRestore(pluginId, page, needsReplacement,
      ownerValue, screenName, capture) {
    const id = String(pluginId || "")
    if (id === "" || !restoreAdmitted) return false
    const owner = ownerValue || findPanelWidget(id, screenName)
    const outputName = restoreScreenName(owner, screenName)
    const index = widgetRestoreIndex(id, owner, outputName)
    const next = pendingWidgetRestores.slice()
    if (index >= 0) {
      const current = next[index]
      next[index] = Object.assign({}, current, {
        id: id,
        page: String(page || current.page || ""),
        attempts: 0,
        restoreRevision: Number(current.restoreRevision || 0) + 1,
        owner: current.owner || owner,
        activeOwner: current.activeOwner || null,
        needsReplacement: current.needsReplacement === true
          || needsReplacement === true,
        screenName: outputName
      })
    } else {
      next.push({
        restoreId: ++nextWidgetRestoreId,
        restoreRevision: 0,
        navigationRevision: 0,
        restoreConfirmed: true,
        id: id,
        page: String(page || ""),
        attempts: 0,
        owner: owner,
        activeOwner: null,
        needsReplacement: needsReplacement === true,
        screenName: outputName
      })
    }
    const scheduled = next[index >= 0 ? index : next.length - 1]
    if (Array.isArray(capture)) capture.push({id: id, owner: owner, screenName: outputName,
      restoreId: scheduled.restoreId, restoreRevision: scheduled.restoreRevision,
      created: index < 0, scheduled: scheduled,
      previous: index >= 0 ? Object.assign({}, pendingWidgetRestores[index]) : null})
    pendingWidgetRestores = next
    if (!restoreAdmitted || !pendingWidgetRestores.some(record => record.restoreId === scheduled.restoreId)) return false
    if (!widgetRestoreTimer.running) widgetRestoreTimer.start()
    return true
  }

  function removeWidgetRestoreAt(index) {
    if (index < 0 || index >= pendingWidgetRestores.length) return false
    const next = pendingWidgetRestores.slice()
    next.splice(index, 1)
    pendingWidgetRestores = next
    if (next.length === 0) widgetRestoreTimer.stop()
    return true
  }

  function trackWidgetRestorePage(pluginId, page, ownerValue, screenName) {
    const id = String(pluginId || "")
    const requestedPage = String(page || "")
    const owner = ownerValue || findPanelWidget(id, screenName)
    const index = widgetRestoreIndex(id, owner, screenName)
    if (id === "" || requestedPage === "" || index < 0) return false
    const next = pendingWidgetRestores.slice()
    const record = next[index]
    // Navigation issued while the layout is rebuilding is newer than the
    // page captured at mutation time. Preserve that intent even when the
    // click still lands on the outgoing owner.
    next[index] = Object.assign({}, record, {page: requestedPage,
      navigationRevision: Number(record.navigationRevision || 0) + 1})
    pendingWidgetRestores = next
    return true
  }

  function cancelWidgetRestore(pluginId, ownerValue, screenName) {
    const id = String(pluginId || "")
    const owner = ownerValue || findPanelWidget(id, screenName)
    return removeWidgetRestoreAt(widgetRestoreIndex(id, owner, screenName))
  }

  function trackControlCenterWidgetDetail(groupId, pluginId) {
    const group = String(groupId || "")
    if (group === "") return false
    controlCenterWidgetDetailGroup = group
    controlCenterWidgetDetailPlugin = String(pluginId || "")
    return true
  }

  function clearControlCenterWidgetDetail() {
    controlCenterWidgetDetailGroup = ""
    controlCenterWidgetDetailPlugin = ""
    return true
  }

  function widgetRestoreSatisfied(record, widget) {
    if (!record || !widget || widget.opened !== true) return false
    // Once an owner is established, navigation belongs to the
    // user. Follow its current page instead of forcing the page captured at
    // switch time; if this owner is replaced again, that latest page becomes
    // the handoff target for its successor.
    if (widget === record.activeOwner) {
      if (record.id === "hancore.shibumi.control-center") {
        if (widget.panelLoaded !== true || !widget.panelItem
            || widget.panelItem.settingsPageReady !== true) return false
        const currentPage = String(widget.panelItem.settingsPage || "")
        if (currentPage !== "") record.page = currentPage
      }
      return true
    }
    if (record.id !== "hancore.shibumi.control-center"
        || String(record.page || "") === "") {
      record.activeOwner = widget
      return true
    }
    const pageReady = widget.panelLoaded === true && widget.panelItem
      && widget.panelItem.settingsPageReady === true
      && String(widget.panelItem.settingsPage || "") === record.page
    if (pageReady) record.activeOwner = widget
    return pageReady
  }

  Timer {
    id: widgetRestoreTimer
    interval: 80
    repeat: true

    onTriggered: {
      if (!root.restoreAdmitted) { root.revokeStateRestores(); return }
      const records = root.pendingWidgetRestores.slice()
      for (let index = 0; index < records.length; index++) {
        const record = records[index]
        if (root.pendingWidgetRestores.indexOf(record) < 0) continue
        // Do not spend the 1.6s rebuild window or reopen an old owner while
        // native persistence is pending (its deadline is longer than 1.6s).
        if (record.waitingLayout) continue
        if (record.waitingWrites && record.waitingWrites.length) continue
        record.restoreRevision = Number(record.restoreRevision || 0) + 1
        record.attempts = Number(record.attempts || 0) + 1
        // Never let a missing owner fall back to another output.
        const widget = root.findPanelWidgetOnScreen(
          record.id, record.screenName)
        const satisfied = root.widgetRestoreSatisfied(record, widget)
        if (!root.restoreAdmitted || root.pendingWidgetRestores.indexOf(record) < 0) continue
        if (!satisfied && record.id
            === "hancore.shibumi.control-center"
            && String(record.page || "") !== "") {
          if (widget && typeof widget.openPage === "function")
            widget.openPage(record.page)
        } else if (!satisfied) {
          root.summonBarWidget(record.id, record.screenName)
        }
        // Filesystem-backed config publication and the layout delegate rebuild
        // can replace the panel owner more than once. Keep each output-local
        // handoff alive for its full 1.6 s window.
        const current = root.pendingWidgetRestores.findIndex(item =>
          item.restoreId === record.restoreId
            && item.restoreRevision === record.restoreRevision)
        if (current >= 0 && record.attempts >= 20) root.removeWidgetRestoreAt(current)
      }
      // openPage()/open() can synchronously cancel or schedule another restore.
      // Never replace that newer intent with the timer's old snapshot.
      if (root.pendingWidgetRestores.length === 0) stop()
    }
  }

  function debugWidgetPipeline() {
    // This is an evidence-only current-state census. Never project registry
    // keys, metadata, source URLs, backend objects, or object references.
    const expectedLimit = 64
    const outputLimit = 16
    const slotLimit = 128
    const snapshotCountLimit = 256

    function safeId(value) {
      const id = String(value || "")
      return id.length > 0 && id.length <= 160
          && /^[a-z0-9][a-z0-9._-]*$/.test(id) ? id : ""
    }
    function safeScreen(value) {
      const name = String(value || "")
      return name.length > 0 && name.length <= 64
          && /^[A-Za-z0-9_.:-]+$/.test(name) ? name : ""
    }
    function boundedInt(value, minimum, maximum, fallback) {
      const number = Number(value)
      return Number.isFinite(number)
        ? Math.max(minimum, Math.min(maximum, Math.floor(number))) : fallback
    }
    function componentObservation(component, accessAvailable) {
      if (accessAvailable === false) return {
        present: false, statusKind: "unavailable", status: -1
      }
      if (component === null || component === undefined) return {
        present: false, statusKind: "missing", status: -1
      }
      try {
        const status = component.status
        if (status === undefined) return {
          present: true, statusKind: "undefined", status: -1
        }
        if (typeof status === "number") return {
          present: true,
          statusKind: "number",
          status: boundedInt(status, 0, 3, -1)
        }
        return { present: true, statusKind: "other", status: -1 }
      } catch (error) {
        return { present: true, statusKind: "unavailable", status: -1 }
      }
    }
    function outputSequence() {
      if (hostOutputReturnObserved) return "positive-zero-positive"
      if (hostOutputLossObserved) return "positive-zero"
      if (hostOutputPresenceObserved) return "positive"
      return "none"
    }
    let observedValidOutputCount = 0
    const observedScreens = Quickshell.screens || []
    for (let index = 0; index < observedScreens.length; index++) {
      const screen = observedScreens[index]
      if (screen && String(screen.name || "") !== ""
          && Number(screen.width) > 0 && Number(screen.height) > 0)
        observedValidOutputCount++
    }

    const snapshot = barWidgetRegistry && barWidgetRegistry.widgets
      && typeof barWidgetRegistry.widgets === "object"
      ? barWidgetRegistry.widgets : null
    let snapshotKeyCount = 0
    let snapshotKeyCountTruncated = false
    if (snapshot) {
      for (const key in snapshot) {
        if (!Object.prototype.hasOwnProperty.call(snapshot, key)) continue
        if (snapshotKeyCount >= snapshotCountLimit) {
          snapshotKeyCountTruncated = true
          break
        }
        snapshotKeyCount++
      }
    }

    const expected = []
    const seenExpected = Object.create(null)
    const configuredLayout = layoutConfig && typeof layoutConfig === "object"
      ? layoutConfig : ({})
    let expectedTruncated = false
    let inspectedEntries = 0
    for (const region of ["left", "center", "right"]) {
      const entries = Array.isArray(configuredLayout[region])
        ? configuredLayout[region] : []
      for (let index = 0; index < entries.length; index++) {
        if (inspectedEntries >= expectedLimit) {
          expectedTruncated = true
          break
        }
        inspectedEntries++
        let id = ""
        try { id = safeId(entryId(entries[index])) } catch (error) {}
        if (id === "" || seenExpected[id]) continue
        seenExpected[id] = true
        let configured = false
        let selection = null
        let component = null
        let componentAccessAvailable = true
        try {
          configured = hostWidgetResolverService.configured(id) === true
          selection = hostWidgetResolverService.selectionFor(id)
          component = selection ? selection.component : null
        } catch (error) {
          configured = false
          selection = null
          componentAccessAvailable = false
        }
        const componentState = componentObservation(
          component, componentAccessAvailable)
        expected.push({
          id: id,
          configured: configured,
          selection: selection !== null,
          componentPresent: componentState.present,
          componentStatusKind: componentState.statusKind,
          componentStatus: componentState.status
        })
      }
      if (expectedTruncated) break
    }

    const sessions = []
    const outputCount = Math.min(1000000,
      Array.isArray(layoutSessions) ? layoutSessions.length : 0)
    for (let index = 0;
         index < outputCount && index < outputLimit; index++) {
      const session = layoutSessions[index]
      if (!session) continue
      sessions.push({
        screen: safeScreen(session.screenName),
        barPanel: true,
        layoutSession: true
      })
    }

    const slots = []
    const slotCount = Math.min(1000000,
      Array.isArray(moduleSlots) ? moduleSlots.length : 0)
    for (let index = 0; index < slotCount && index < slotLimit; index++) {
      const slot = moduleSlots[index]
      if (!slot) continue
      let resolved = null
      let resolvedAccessAvailable = true
      try { resolved = slot.resolvedComponent }
      catch (error) { resolvedAccessAvailable = false }
      const resolvedState = componentObservation(
        resolved, resolvedAccessAvailable)
      let currentLoadReady = false
      try {
        currentLoadReady = typeof slot.currentLoadReady === "function"
          && slot.currentLoadReady() === true
      } catch (error) { currentLoadReady = false }
      slots.push({
        id: safeId(slot.moduleName),
        screen: safeScreen(slot.screenName),
        moduleEnabled: slot.moduleEnabled === true,
        resolutionAttempts: boundedInt(
          slot.resolutionAttempts, 0, 10, 0),
        resolvedComponentPresent: resolvedState.present,
        resolvedComponentStatusKind: resolvedState.statusKind,
        resolvedStatus: resolvedState.status,
        currentLoadReady: currentLoadReady,
        loaderActive: slot.loaderActive === true,
        loaderStatus: boundedInt(slot.loaderStatus, 0, 3, 0),
        loaderItem: slot.loaderHasItem === true
      })
    }

    return {
      version: 2,
      facades: {
        shellScoped: suiteHostShell.scoped === true,
        pluginRegistryScoped: hostWidgetResolverService.scoped === true,
        widgetRegistryPresent: hostWidgetResolverService.widgetRegistry !== null
      },
      outputs: {
        validOutputCount: boundedInt(
          observedValidOutputCount, 0, 256, 0),
        barPanelCount: outputCount,
        layoutSessionCount: outputCount,
        truncated: outputCount > outputLimit,
        sessions: sessions
      },
      outputLifecycle: {
        presenceObserved: hostOutputPresenceObserved === true,
        lossObserved: hostOutputLossObserved === true,
        returnObserved: hostOutputReturnObserved === true,
        sequence: outputSequence(),
        previouslyReadyWidgetCount: boundedInt(Object.keys(
          hostOutputPreviouslyReadyWidgetIds || {}).length, 0, 256, 0),
        lossReadyWidgetCount: boundedInt(Object.keys(
          hostOutputLossReadyWidgetIds || {}).length, 0, 256, 0),
        warningEmitted: SuiteRuntime.Runtime.hostWidgetResolutionWarningEmitted
          === true
      },
      registry: {
        snapshotKeyCount: snapshotKeyCount,
        snapshotKeyCountTruncated: snapshotKeyCountTruncated,
        revision: boundedInt(barWidgetRegistry
          ? barWidgetRegistry.revision : 0, 0, 2147483647, 0)
      },
      expected: {
        truncated: expectedTruncated,
        entries: expected
      },
      widgetSlots: {
        count: slotCount,
        truncated: slotCount > slotLimit,
        entries: slots
      }
    }
  }

  function debugBarGeometry() {
    const geometry = []
    const focused = focusedOutputName()
    for (let i = 0; i < moduleSlots.length; i++) {
      const slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      let point = { x: slot.x, y: slot.y }
      try { point = slot.mapToItem(null, 0, 0) } catch (error) {}
      const window = targetWindow(slot.activeItem)
      let groupSection = slot
      for (let depth = 0; groupSection && depth < 16; depth++) {
        if ("separatorGeometry" in groupSection
            && "groupGeometry" in groupSection
            && "separatorHitTargetCount" in groupSection) break
        groupSection = groupSection.parent || null
      }
      let groupLayout = ({})
      if (groupSection && "separatorHitTargetCount" in groupSection) {
        let sectionPoint = { x: 0, y: 0 }
        try { sectionPoint = groupSection.mapToItem(null, 0, 0) }
        catch (error) {}
        groupLayout = {
          region: String(groupSection.region || ""),
          x: Math.round(sectionPoint.x),
          y: Math.round(sectionPoint.y),
          width: Math.round(Number(groupSection.width) || 0),
          height: Math.round(Number(groupSection.height) || 0),
          hitTargets: Number(groupSection.separatorHitTargetCount) || 0,
          groups: (groupSection.groupGeometry || []).map(function(entry) {
            return {
              groupId: String(entry.groupId || ""),
              index: Number(entry.index),
              left: Math.round(sectionPoint.x + Number(entry.left || 0)),
              right: Math.round(sectionPoint.x + Number(entry.right || 0))
            }
          }),
          separators: (groupSection.separatorGeometry || []).map(
            function(entry) {
              const center = sectionPoint.x + Number(entry.markerCenter || 0)
              return {
                groupId: String(entry.groupId || ""),
                index: Number(entry.index),
                center: Math.round(center),
                hitLeft: Math.round(center - 7),
                hitRight: Math.round(center + 7)
              }
            })
        }
      }
      geometry.push({
        id: slot.moduleName,
        section: slot.region,
        screen: window && window.screen ? window.screen.name : "",
        slotScreen: String(slot.screenName || ""),
        focusedScreen: focused,
        selectedForFocus: findPanelWidget(slot.moduleName, focused)
          === slot.activeItem,
        windowWidth: window ? Math.round(Number(window.width) || 0) : 0,
        surfaceWidth: window && "surfaceWidth" in window
          ? Math.round(Number(window.surfaceWidth) || 0) : 0,
        responsiveStage: window && "responsiveStage" in window
          ? Number(window.responsiveStage) || 0 : 0,
        responsiveProbe: window && "responsiveProbe" in window
          ? window.responsiveProbe : ({}),
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        opened: slot.activeItem.opened === true,
        panelLoaded: slot.activeItem.panelLoaded === true,
        groupLayout: groupLayout
      })
    }
    return geometry
  }

  function requestBarHiddenProbe() {
    if (!hostReady || shutdownPrepared) return false
    if (barHiddenProbe.running) {
      // A later marker mutation arrived while an earlier sample was running.
      // Drain one coalesced follow-up so the final published state is current.
      barHiddenProbeQueued = true
      return true
    }
    barHiddenProbe.running = true
    return true
  }

  function syncHidden() {
    return visibilityIpcReady && requestBarHiddenProbe()
  }

  function prepareForShutdown() {
    if (shutdownPrepared) return true
    shutdownPrepared = true
    startupAdmissionTimer.stop()
    hostReadyDelay.stop()
    v1PluginReconcileTimer.stop()
    tooltipDelay.stop()
    barHiddenProbeQueued = false
    barHiddenProbe.running = false
    hideTooltip(null)
    hostReady = false
    outputWindowsEnabled = false
    releaseCatalogConsumer()
    return true
  }

  onBarConfigChanged: {
    if (!shutdownPrepared) applyBarConfig()
  }
  onLayoutConfigChanged: {
    if (!shutdownPrepared) v1PluginReconcileTimer.restart()
  }
  function scheduleStartupAdmission() {
    if (shutdownPrepared) return
    startupAdmissionTimer.restart()
  }

  function advanceStartupAdmission() {
    if (shutdownPrepared) return
    if (!injectionComplete
        || (suiteHostShell.scoped && !suiteRuntimeReady)) {
      hostReadyDelay.stop()
      hostReady = false
      return
    }
    if (nativeRegistryPrimeRequired && !nativeRegistryPrimeReady) {
      SuiteRuntime.Runtime.requestHostRegistryPrime(
        root, Quickshell.processId)
      hostReadyDelay.stop()
      hostReady = false
      return
    }
    hostReadyDelay.restart()
  }

  onInjectionCompleteChanged: scheduleStartupAdmission()
  onSuiteRuntimeReadyChanged: scheduleStartupAdmission()
  onNativeRegistryPrimeReadyChanged: scheduleStartupAdmission()
  // Host injection can become scoped after Component.onCompleted, without a
  // screen-count change. Start passive chronology when admission actually opens.
  onHostReadyChanged: if (hostReady) syncHostOutputLifecycleState()
  onValidHostOutputCountChanged: syncHostOutputLifecycleState()
  onCatalogConsumerCandidateChanged: {
    if (!shutdownPrepared) rebindCatalogConsumer()
  }
  Component.onCompleted: {
    applyBarConfig()
    rebindCatalogConsumer()
    syncHostOutputLifecycleState()
    scheduleStartupAdmission()
  }
  Component.onDestruction: {
    tearingDown = true
    prepareForShutdown()
    releaseCatalogConsumer()
  }

  Timer {
    id: startupAdmissionTimer
    interval: 0
    repeat: false
    onTriggered: root.advanceStartupAdmission()
  }

  Timer {
    id: v1PluginReconcileTimer
    interval: 1
    repeat: false
    onTriggered: {
      if (!root.shutdownPrepared && root.hostReady)
        root.reconcileActivePluginGroupsAndProviders()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() { root.syncHostOutputLifecycleState() }
  }

  Connections {
    target: layoutStateController
    ignoreUnknownSignals: true

    function onV2ModeChanged() {
      if (!root.shutdownPrepared) v1PluginReconcileTimer.restart()
    }
  }

  Connections {
    target: root.pluginRegistry
    ignoreUnknownSignals: true

    function onPluginsChanged() {
      if (root.shutdownPrepared) return
      // Family classification follows the host/catalog domains, not the
      // separately activated legacy Component cache.
      root.providerRegistryRevision++
      v1PluginReconcileTimer.restart()
    }
  }

  Behavior on barForeground {
    enabled: root.foregroundAnimationEnabled
    ColorAnimation {
      duration: root.styleReady ? root.activeStyle.colorTransitionDuration : 160
      easing.type: Easing.OutCubic
    }
  }

  Behavior on background {
    ColorAnimation {
      duration: root.styleReady ? root.activeStyle.colorTransitionDuration : 160
      easing.type: Easing.OutCubic
    }
  }

  Styles.StyleRegistry {
    id: styleRegistry
    requestedId: root.requestedStyleId
  }

  Services.HostWidgetResolver {
    id: hostWidgetResolverService
    bar: root
  }

  Core.LayoutTransition {
    id: layoutTransition
    stateService: layoutStateController.stateService
    nativeWriter: suiteHostShell.scoped ? suiteHostShell.host : root.shell
    observedBarConfig: root.barConfig
    planNativeLayout: root.planNativeTransition
    validateNativeLayout: root.validateNativeTransition
    admitted: root.restoreAdmitted && !providerSnapshotTransition.busy
      && !stateTransition.busy
    onSettledContext: function(serial, result, context) {
      root.lastProviderUndoReceipt = null
      const intent = context && context.intent ? context.intent : null
      const saved = root.lastCatalogTransitionSnapshot
      root.lastCatalogTransitionSnapshot = null
      const groups = intent && Array.isArray(intent.providerGroups)
        ? root.normalizedProviderGroups(intent.providerGroups) : []
      const savedGroups = saved && Util.isPlainObject(saved.groupStates)
        ? root.normalizedProviderGroups(Object.keys(saved.groupStates)) : []
      if (["confirmed", "unchanged"].indexOf(result) < 0
          || !context || !context.nativeBefore || !context.nativeAfter
          || !Util.isPlainObject(context.patch)
          || !saved || groups.length === 0
          || groups.length !== intent.providerGroups.length
          || !providerSnapshotTransition.same(groups, savedGroups)
          || ["v1", "v2"].indexOf(saved.variant) < 0
          || !Util.isPlainObject(saved.transitionPatch)) return
      let expectedStatePatch = JSON.parse(JSON.stringify(context.patch))
      if (saved.variant === "v2") {
        const specs = root.activePluginSpecsForLayout(context.nativeAfter)
        const planned = V2LayoutModel.reconcilePluginGroups(
          saved.v2Layout, specs, true)
        if (!planned || planned.unplaced.length > 0) return
        expectedStatePatch.v2Layout = planned.layout
      }
      root.lastProviderUndoReceipt = {
        serial: serial,
        snapshot: {
          layout: JSON.parse(JSON.stringify(context.nativeBefore)),
          expectedLayout: JSON.parse(JSON.stringify(context.nativeAfter)),
          expectedStatePatch: JSON.parse(JSON.stringify(expectedStatePatch)),
          groupStates: JSON.parse(JSON.stringify(saved.groupStates)),
          v2Layout: saved.v2Layout === null ? null
            : JSON.parse(JSON.stringify(saved.v2Layout)),
          variant: saved.variant,
          transitionPatch: JSON.parse(JSON.stringify(saved.transitionPatch))
        }
      }
    }
    onSettled: function(serial, result) {
      root.settleLayoutRestores(serial, result)
      root.layoutTransitionSettled(serial, result)
    }
  }

  Core.LayoutTransition {
    id: providerSnapshotTransition
    stateService: layoutStateController.stateService
    nativeWriter: suiteHostShell.scoped ? suiteHostShell.host : root.shell
    observedBarConfig: root.barConfig
    planNativeLayout: root.planNativeTransition
    validateNativeLayout: root.validateNativeTransition
    admitted: root.restoreAdmitted && !layoutTransition.busy
      && !stateTransition.busy
    onSettled: function(serial, result) {
      root.settleLayoutRestores(-serial, result)
      root.providerSnapshotTransitionSettled(serial, result)
    }
  }

  Core.LayoutTransition {
    id: stateTransition
    stateService: layoutStateController.stateService
    nativeWriter: null
    observedBarConfig: null
    planNativeLayout: null
    admitted: root.restoreAdmitted && !layoutTransition.busy
      && !providerSnapshotTransition.busy
    onSettled: function(serial, result) {
      root.stateTransitionSettled(serial, result)
    }
  }

  Core.LayoutController {
    id: layoutStateController
    bar: root
    stateService: root.pluginService("hancore.shibumi.state")
  }

  Loader {
    id: styleLoader

    active: true
    visible: false
    source: styleRegistry.source

    onSourceChanged: root.styleReady = false
    onLoaded: {
      if (item && "bar" in item) item.bar = root
      root.styleReady = root.validateStyle(item)
      if (!root.styleReady)
        console.warn("Shibumi rejected invalid bar style:", styleRegistry.resolvedId)
      else if (styleRegistry.fallbackUsed)
        console.warn("Shibumi unknown bar style; using shibumi:", root.requestedStyleId)
    }
    onStatusChanged: {
      if (status === Loader.Error) {
        root.styleReady = false
        console.warn("Shibumi could not load bar style:", styleRegistry.resolvedId)
      }
    }
  }

  IpcHandler {
    target: "shibumi-suite"

    function prepareShutdown(): string {
      return root.prepareForShutdown() ? "ok" : "failed"
    }

    function openControlCenter(): string {
      return root.openConfigPanel() ? "ok" : "not-ready"
    }

    function closeControlCenter(): string {
      return root.hideBarWidget("hancore.shibumi.control-center")
        ? "ok" : "not-ready"
    }

    function openWidgetPanel(pluginId: string, screenName: string): string {
      return root.summonBarWidget(String(pluginId || ""), screenName)
        ? "ok" : "not-ready"
    }

    function closeWidgetPanel(pluginId: string): string {
      return root.hideBarWidget(String(pluginId || ""))
        ? "ok" : "not-ready"
    }

    function openStatusTray(screenName: string): string {
      const widget = root.findPanelWidget(
        "hancore.shibumi.status", String(screenName || ""))
      return widget && typeof widget.openTrayDrawer === "function"
          && widget.openTrayDrawer()
        ? "ok" : "not-ready"
    }

    function openStatusNotifications(screenName: string): string {
      const widget = root.findPanelWidget(
        "hancore.shibumi.status", String(screenName || ""))
      return widget && typeof widget.open === "function" && widget.open()
        ? "ok" : "not-ready"
    }

    function debugWidgetPipeline(): string {
      return JSON.stringify(root.debugWidgetPipeline())
    }

    function connectedPanelState(): string {
      return JSON.stringify({
        active: root.connectedPanelOwner !== null
          && root.connectedPanelReveal > 0.001,
        screen: root.connectedPanelScreenName,
        x: Math.round(root.connectedPanelX * 100) / 100,
        reveal: Math.round(root.connectedPanelReveal * 1000) / 1000
      })
    }

    function openControlCenterPage(page: string): string {
      return root.openConfigPage(page) ? "ok" : "not-ready"
    }

    function setWidgetModule(widgetId: string, enabled: string): string {
      const value = String(enabled || "").toLowerCase()
      if (value !== "true" && value !== "false") return "invalid-enabled"
      return root.setBarWidgetInstalled(widgetId, value === "true", "right")
        ? "ok" : "rejected"
    }

    function setWidgetAppearance(groupId: string, key: string,
        valueJson: string): string {
      return root.setWidgetAppearance(groupId, key, valueJson)
    }

    function setWidgetAppearanceForVariant(groupId: string, variant: string,
        key: string, valueJson: string): string {
      return root.setWidgetAppearanceForVariant(
        groupId, variant, key, valueJson)
    }

    function setBarAppearance(key: string, valueJson: string): string {
      const name = String(key || "")
      const allowed = [
        "accent", "border", "panelBorder", "frost", "shadow",
        "radius", "shellStyle"
      ]
      if (allowed.indexOf(name) < 0) return "invalid-key"
      const state = root.pluginService("hancore.shibumi.state")
      if (!state || typeof state.setPresentationSetting !== "function")
        return "not-ready"
      let value = String(valueJson || "")
      try {
        value = JSON.parse(value)
      } catch (error) {
        // Plain strings remain convenient for CLI callers.
      }
      const changed = root.runWithControlCenterRestore(function() {
        return state.setPresentationSetting(name, value)
      }, "bars", name === "shellStyle", null, "")
      return changed ? "ok" : "rejected"
    }

    function setBarEditing(enabled: string, screenName: string): string {
      const value = String(enabled || "").toLowerCase()
      if (value !== "true" && value !== "false") return "invalid-enabled"
      return root.setLayoutEditing(value === "true", screenName)
        ? "ok" : "unchanged"
    }

    function addV1Slot(region: string): string {
      if (layoutStateController.v2Mode) return "wrong-style"
      return root.addV1Slot(String(region || "")) ? "ok" : "rejected"
    }

    function removeV1Slot(region: string): string {
      if (layoutStateController.v2Mode) return "wrong-style"
      return root.removeV1Slot(String(region || "")) ? "ok" : "rejected"
    }

    function moveV1GroupToSlot(groupId: string, region: string,
        index: string): string {
      if (layoutStateController.v2Mode) return "wrong-style"
      const targetIndex = Number(index)
      if (!Number.isInteger(targetIndex)) return "invalid-index"
      return layoutStateController.moveGroupToSlot(
          String(groupId || ""), String(region || ""), targetIndex)
        ? "ok" : "rejected"
    }

    function setAllSplits(enabled: string): string {
      const value = String(enabled || "").toLowerCase()
      if (value !== "true" && value !== "false") return "invalid-enabled"
      return root.setAllSplits(value === "true") ? "ok" : "rejected"
    }

    function setShellStyle(style: string): string {
      const value = String(style || "")
      const state = root.pluginService("hancore.shibumi.state")
      const changed = root.runWithControlCenterRestore(function() {
        return state && typeof state.setPresentationSetting === "function"
          && state.setPresentationSetting("shellStyle", value)
      }, "bars", true, null, "")
      return changed ? "ok" : "rejected"
    }

    function setBarPosition(position: string): string {
      return root.setBarPosition(String(position || ""))
        ? "ok" : "rejected"
    }

    function verifyPayload(expectedDigest: string): string {
      const expected = String(expectedDigest || "")
      return root.hostReady
          && root.styleReady
          && root.suiteRuntimeReady
          && root.suitePayloadLoaded
          && expected.length === 64
          && expected === root.suitePayloadDigest
        ? "ok" : "not-ready"
    }

    function reloadPayload(): string {
      // Quattro's plugin rescan can recreate a Loader from a still-cached QML
      // component when its URL did not change. Reload the shell configuration
      // after the transactional payload swap so the accepted code is the code
      // currently executing, not merely the files currently on disk.
      Qt.callLater(function() { Quickshell.reload(false) })
      return "ok"
    }
  }


  FileView {
    id: suiteMarker
    path: root.suiteMarkerPath
    watchChanges: false
    printErrors: false
    onLoaded: root.captureSuiteMarker(text())
    onLoadFailed: {
      root.suitePayloadDigest = ""
      root.suitePayloadLoaded = false
    }
  }

  Process {
    id: barHiddenProbe
    running: root.hostReady
    command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: line => {
        root.barToggledOff = String(line).trim() === "yes"
        root.barToggleStateLoaded = true
      }
    }
    onExited: {
      if (!root.barHiddenProbeQueued) return
      root.barHiddenProbeQueued = false
      Qt.callLater(function() { root.requestBarHiddenProbe() })
    }
  }

  FileView {
    path: root.hostReady ? root.home + "/.local/state/omarchy/toggles" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: root.requestBarHiddenProbe()
  }

  Timer {
    id: tooltipDelay
    interval: 350
    onTriggered: {
      root.tooltipTarget = root.pendingTooltipTarget
      root.tooltipText = root.pendingTooltipText
      root.tooltipShown = root.tooltipTarget !== null && root.tooltipText !== ""
    }
  }

  Timer {
    id: hostReadyDelay
    interval: 0
    onTriggered: {
      if (!root.shutdownPrepared) {
        root.hostReady = root.startupAdmissionSatisfied
        if (root.hostReady) v1PluginReconcileTimer.restart()
      }
    }
  }

  Variants {
    // Keep the host-native screen model so Variants receives output lifecycle
    // changes directly. BarPanel rejects incomplete placeholder screens.
    model: root.outputWindowsEnabled && !root.shutdownPrepared
      ? Quickshell.screens : []

    delegate: Component {
      Core.BarPanel {
        required property var modelData
        bar: root
        screen: modelData
      }
    }
  }
}
