pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons as Commons

Item {
  id: root

  required property var bar
  required property var entry
  property string region: ""
  property string screenName: ""
  property real availableWidth: 0
  // The original V1 composes 28px widget roots inside a 32px slot row.
  // Keep this opt-in so direct/V2/vertical hosts retain provider geometry.
  property real horizontalHostHeight: 0
  readonly property string moduleName: bar.entryId(entry)
  property var hostEntry: entry
  property var settingsOverrides: ({})
  property var inlineHostEntry: null
  readonly property var moduleSettings: {
    const source = inlineHostEntry || hostEntry
    const result = bar.entrySettings(source)
    const overrides = settingsOverrides || ({})
    for (const key in overrides) result[key] = overrides[key]
    return result
  }
  readonly property bool moduleEnabled: moduleSettings.enabled !== false
  readonly property bool scopedHost: {
    const registry = bar ? bar.pluginRegistry : null
    return !!registry && "pluginId" in registry
  }
  // Bar.layoutConfig changes only for structural layout edits. A top-level
  // State write republishes barConfig but leaves this structure and every live
  // slot untouched.
  readonly property var structuralLayout: bar
    ? "layoutConfig" in bar ? bar.layoutConfig
      : bar.barConfig ? bar.barConfig.layout : null
    : null
  function configuredInStructuralLayout(widgetId) {
    const id = String(widgetId || "")
    const layout = structuralLayout
    if (id === "" || !layout) return false
    for (const section of ["left", "center", "right"]) {
      const entries = layout[section]
      if (!Array.isArray(entries)) return false
      for (let index = 0; index < entries.length; index++) {
        const candidate = bar.entryId(entries[index])
        if (candidate === id) return true
      }
    }
    return false
  }
  readonly property bool scopedConfigured:
    scopedHost && configuredInStructuralLayout(moduleName)
  // Omarchy 4.0.3 republishes a detached widgets object for every registration.
  // Bind the exact configured ID directly; equal Component handles do not emit
  // scopedComponentChanged and therefore do not touch the Loader.
  readonly property var scopedEntry: {
    const registry = bar ? bar.barWidgetRegistry : null
    const widgets = registry ? registry.widgets : null
    return widgets && Object.prototype.hasOwnProperty.call(widgets, moduleName)
      ? widgets[moduleName] : null
  }
  readonly property var scopedMetadata: scopedEntry && scopedEntry.metadata
    && scopedEntry.metadata.pluginId === moduleName
      ? scopedEntry.metadata : null
  readonly property var scopedComponent: {
    if (!scopedConfigured || !scopedMetadata || !scopedEntry) return null
    const candidate = scopedEntry.component
    // A valid native QQmlComponent may not expose a JavaScript status value.
    try { return candidate && candidate instanceof Component ? candidate : null }
    catch (error) { return null }
  }
  property var legacyComponent: null
  readonly property var resolvedComponent:
    scopedHost ? scopedComponent : legacyComponent
  // Only the separately activated legacy URL resolver publishes revisions.
  readonly property int resolverRevision: !scopedHost && bar
    && "hostWidgetResolver" in bar && bar.hostWidgetResolver
      ? bar.hostWidgetResolver.revision : 0
  property bool slotComplete: false
  // Loader.sourceComponent readback can lose its JavaScript projection for a
  // valid native QQmlComponent. Keep request, dispatch, resident item and
  // completion provenance as atomic records so synchronous property observers
  // cannot observe or take ownership through a half-published tuple.
  property var _submission: ({ source: null, generation: 0 })
  property var _dispatchedSubmission: null
  property bool _loaderSubmissionActive: false
  property var _residentLoad: null
  property var _completedLoad: null
  property var loadedComponent: null
  property var loadedItem: null
  property int resolutionAttempts: 0
  readonly property var activeItem: widgetLoader.item
  readonly property alias loadedSourceComponent: root.loadedComponent
  // Read-only scalar diagnostics for the bounded Bar IPC census. Keep the
  // Loader and its item private so diagnostics cannot become an object seam.
  readonly property bool loaderActive: widgetLoader.active
  readonly property int loaderStatus: widgetLoader.status
  readonly property bool loaderHasItem: widgetLoader.item !== null
  readonly property var containingWindow: activeItem && activeItem.QsWindow
    ? activeItem.QsWindow.window : null
  readonly property var moduleManifest: {
    if (scopedHost) return null
    void(resolverRevision)
    const resolver = bar && "hostWidgetResolver" in bar
      ? bar.hostWidgetResolver : null
    if (resolver && typeof resolver.manifestFor === "function")
      return resolver.manifestFor(moduleName)
    const registry = bar ? bar.pluginRegistry : null
    const installed = registry && registry.installedPlugins
      ? registry.installedPlugins : null
    return installed ? installed[moduleName] || null : null
  }
  // Every non-Shibumi widget is hosted through the same compatibility
  // adapter. This intentionally covers both Omarchy/Quattro built-ins and
  // third-party plugins; no provider-specific panel patch is required.
  readonly property bool suiteNativeModule:
    moduleName.indexOf("hancore.shibumi.") === 0
  readonly property bool hostedModule: !suiteNativeModule
  readonly property string fallbackTooltipText: {
    void(resolverRevision)
    const resolver = bar && "hostWidgetResolver" in bar ? bar.hostWidgetResolver : null
    const published = scopedHost ? scopedMetadata
      : resolver && typeof resolver.metadataFor === "function"
        ? resolver.metadataFor(moduleName) : null
    if (published && String(published.displayName || "").trim() !== "")
      return String(published.displayName).trim()
    const manifest = moduleManifest
    const metadata = manifest && manifest.barWidget
      && typeof manifest.barWidget === "object"
      ? manifest.barWidget : null
    return metadata && String(metadata.displayName || "").trim() !== ""
      ? String(metadata.displayName).trim()
      : manifest && String(manifest.name || "").trim() !== ""
        ? String(manifest.name).trim() : moduleName
  }
  property var compatibilityPanel: null
  property var compatibilityCard: null
  property int compatibilitySurfaceResolutionAttempts: 0
  readonly property int compatibilityTraversalDepthLimit: 8
  readonly property int compatibilityTraversalObjectLimit: 256
  readonly property bool hostPanelChromeEnabled: hostedModule
    && compatibilityPanel !== null
    && compatibilityCard !== null
    && bar && bar.visualTokens !== null
  readonly property bool v2PanelConnectionEnabled: hostPanelChromeEnabled
    && String(bar.visualTokens.shellStyle || "shibumi") !== "shibumi"
    && (bar.position === "top" || bar.position === "bottom")
  property real compatibilityConnectionReveal:
    v2PanelConnectionEnabled && compatibilityPanel.open ? 1 : 0
  property var connectedCompatibilityOwner: null
  readonly property point slotWindowPosition: {
    slotTransformWatcher.transform
    return root.mapToItem(null, 0, 0)
  }
  readonly property real compatibilityAnchorX:
    slotWindowPosition.x + width / 2
  property bool activeItemVisible: false
  property real activeItemImplicitWidth: 0
  property real activeItemImplicitHeight: 0
  readonly property real minimumResponsiveWidth: activeItem
    && "minimumResponsiveWidth" in activeItem
      ? Math.max(0, Number(activeItem.minimumResponsiveWidth) || 0)
      : implicitWidth

  implicitWidth: activeItemVisible
    ? (bar.vertical ? bar.barSize : activeItemImplicitWidth)
    : 0
  implicitHeight: activeItemVisible
    ? !bar.vertical && horizontalHostHeight > 0
      ? horizontalHostHeight : activeItemImplicitHeight
    : 0
  width: implicitWidth
  height: implicitHeight

  Component.onCompleted: {
    // Register first so a synchronous scoped resolution can be attributed to
    // this exact live slot rather than an unowned module ID.
    bar.registerModuleSlot(root)
    slotComplete = true
    ensureResolvedComponent()
  }
  Component.onDestruction: {
    clearCompatibilityConnection()
    if (bar.activePopout === activeItem
        && typeof bar.releasePopout === "function")
      bar.releasePopout(activeItem)
    bar.hideTooltip(activeItem)
    bar.unregisterModuleSlot(root)
  }
  onModuleSettingsChanged: injectProperties()
  onModuleNameChanged: {
    inlineHostEntry = null
    legacyComponent = null
    resolutionAttempts = 0
    ensureResolvedComponent()
  }
  onScopedHostChanged: {
    if (scopedHost) legacyComponent = null
    resolutionAttempts = 0
    ensureResolvedComponent()
  }
  onModuleEnabledChanged: {
    if (moduleEnabled) {
      resolutionAttempts = 0
      ensureResolvedComponent()
    } else {
      resolutionRetry.stop()
    }
    requestLoaderSourceSync()
  }
  onResolvedComponentChanged: {
    if (resolvedComponent !== null) {
      resolutionAttempts = 0
      resolutionRetry.stop()
    }
    requestLoaderSourceSync()
  }
  onSlotCompleteChanged: requestLoaderSourceSync()
  onAvailableWidthChanged: injectProperties()
  onActiveItemChanged: {
    // A binding notification for the resident item can arrive after onLoaded.
    // Replacement/teardown revokes it, but a successor submission completed by
    // synchronous reentry owns any newer resident record and must retain it.
    const observedSubmission = _submission
    const resident = _residentLoad
    if (!resident || activeItem !== resident.item) {
      if (invalidateCompletedLoad(observedSubmission)
          && _submission === observedSubmission) {
        const currentResident = _residentLoad
        if (!currentResident || activeItem !== currentResident.item)
          _residentLoad = null
      }
    }
    if (connectedCompatibilityOwner
        && connectedCompatibilityOwner !== activeItem)
      clearCompatibilityConnection()
    compatibilityPanel = null
    compatibilityCard = null
    compatibilitySurfaceResolutionAttempts = 0
    compatibilitySurfaceTimer.stop()
    syncActiveItemMetrics()
    deferredSync.restart()
  }
  onCompatibilityConnectionRevealChanged:
    publishCompatibilityConnection()
  onCompatibilityAnchorXChanged:
    publishCompatibilityConnection()
  onCompatibilityPanelChanged: {
    const providerOpen = activeItem
      && "opened" in activeItem && activeItem.opened === true
    if (!compatibilityPanel && hostedModule && providerOpen) {
      compatibilitySurfaceResolutionAttempts = 0
      compatibilitySurfaceTimer.restart()
    }
  }

  function syncActiveItemMetrics() {
    const target = activeItem
    activeItemVisible = !!(target && target.visible)
    activeItemImplicitWidth = target ? Number(target.implicitWidth) || 0 : 0
    activeItemImplicitHeight = target ? Number(target.implicitHeight) || 0 : 0
  }

  function invalidateCompletedLoad(expectedSubmission) {
    if (expectedSubmission !== undefined
        && _submission !== expectedSubmission) return false
    _completedLoad = null
    if (expectedSubmission !== undefined
        && _submission !== expectedSubmission) return false
    loadedComponent = null
    if (expectedSubmission !== undefined
        && _submission !== expectedSubmission) return false
    loadedItem = null
    return expectedSubmission === undefined
      || _submission === expectedSubmission
  }

  function publishCompletedLoad(completion, expectedSubmission,
      expectedResident) {
    if (_submission !== expectedSubmission
        || _residentLoad !== expectedResident) return false
    _completedLoad = completion
    if (_submission !== expectedSubmission
        || _residentLoad !== expectedResident
        || _completedLoad !== completion) return false
    loadedItem = completion.item
    if (_submission !== expectedSubmission
        || _residentLoad !== expectedResident
        || _completedLoad !== completion) return false
    loadedComponent = completion.source
    return _submission === expectedSubmission
      && _residentLoad === expectedResident
      && _completedLoad === completion
  }

  function submissionMatches(submission, item) {
    return submission !== null && submission.source !== null && item !== null
      && slotComplete && moduleEnabled && widgetLoader.active
      && widgetLoader.status === Loader.Ready
      && _submission === submission
      && resolvedComponent === submission.source
      && widgetLoader.item === item
  }

  function completedLoadMatches(source, generation, item) {
    const completion = _completedLoad
    return completion !== null && completion.source === source
      && completion.generation === generation && completion.item === item
      && loadedComponent === source && loadedItem === item
      && completion.submission === _submission
      && submissionMatches(completion.submission, item)
  }

  function residentLoadMatches(source, item) {
    const resident = _residentLoad
    return source !== null && item !== null && resident !== null
      && resident.source === source && resident.item === item
      && resident.dispatch === _dispatchedSubmission
      && widgetLoader.active && widgetLoader.status === Loader.Ready
      && widgetLoader.item === item && resolvedComponent === source
  }

  function currentLoadReady() {
    const completion = _completedLoad
    if (completion === null) return false
    const source = completion.source
    const item = completion.item
    const generation = completion.generation
    if (!completedLoadMatches(source, generation, item)) return false
    const resolver = bar && "hostWidgetResolver" in bar
      ? bar.hostWidgetResolver : null
    let current = null
    try {
      current = scopedHost ? scopedComponent
        : resolver && typeof resolver.componentFor === "function"
          ? resolver.componentFor(moduleName)
          : bar && typeof bar.registeredWidgetComponent === "function"
            ? bar.registeredWidgetComponent(moduleName) : null
    } catch (error) {
      current = null
    }
    // Direct host-snapshot access and legacy metadata getters can re-enter QML.
    // Recheck both the atomic completion record and current source identity.
    return current !== null && current === source
      && _completedLoad === completion
      && completedLoadMatches(source, generation, item)
  }

  function submitLoaderSource(candidate) {
    const nextSource = slotComplete && moduleEnabled ? candidate : null
    const previousSubmission = _submission
    if (previousSubmission && previousSubmission.source === nextSource) return

    // Claim the complete successor request before any invalidating write. Every
    // later write can synchronously re-enter this function, so the outer call
    // rechecks object identity before it can clear or dispatch anything else.
    const request = {
      source: nextSource,
      generation: previousSubmission
        ? previousSubmission.generation + 1 : 1
    }
    const activationRequired = nextSource !== null
      && (!previousSubmission || previousSubmission.source === null)
    if (activationRequired || nextSource === null)
      _loaderSubmissionActive = false
    _submission = request
    if (_submission !== request) return
    if (!invalidateCompletedLoad(request)) return
    if (_submission !== request) return
    // Direct scoped bindings can change while completion invalidation emits.
    // Never dispatch the request that was current before that reentrant host
    // publication; the next-turn sync owns the newest exact handle.
    if (resolvedComponent !== nextSource) {
      requestLoaderSourceSync()
      return
    }

    // If reentry returns to the still-resident source before another setter was
    // dispatched, adopt that exact confirmed item under the new request. The
    // native same-handle setter may be a no-op and emit no onLoaded signal.
    const resident = _residentLoad
    if (residentLoadMatches(nextSource, resident ? resident.item : null)) {
      const completion = {
        submission: request,
        source: nextSource,
        generation: request.generation,
        item: resident.item
      }
      publishCompletedLoad(completion, request, resident)
      return
    }

    // Record the controlled dispatch before calling the typed setter so a
    // synchronous onLoaded signal can attribute its exact request. A stale
    // outer call may not clear a successor resident tuple or call the setter.
    _dispatchedSubmission = request
    if (_submission !== request || _dispatchedSubmission !== request) return
    _residentLoad = null
    if (_submission !== request || _dispatchedSubmission !== request) return
    widgetLoader.sourceComponent = nextSource
    if (_submission !== request || _dispatchedSubmission !== request) return
    _loaderSubmissionActive = nextSource !== null
  }

  function synchronizeLoaderSource() {
    submitLoaderSource(!("claimLoadedOwner" in bar) || bar.widgetSlotLoadAdmitted(root) ? resolvedComponent : null)
  }

  function requestLoaderSourceSync() {
    // A synchronous Loader can inject properties before a scoped Component
    // binding has unwound. One next-turn setter preserves direct host identity
    // without evaluating that binding reentrantly; same-turn changes coalesce.
    if (scopedHost) scopedLoaderSync.restart()
    else synchronizeLoaderSource()
  }

  function ensureResolvedComponent() {
    let component = resolvedComponent
    if (!scopedHost) {
      const resolver = bar && "hostWidgetResolver" in bar
        ? bar.hostWidgetResolver : null
      component = resolver && typeof resolver.ensureComponent === "function"
        ? resolver.ensureComponent(moduleName)
        : bar && typeof bar.registeredWidgetComponent === "function"
          ? bar.registeredWidgetComponent(moduleName) : null
      if (legacyComponent !== component) legacyComponent = component
    }
    if (component || !moduleEnabled) {
      resolutionAttempts = 0
      resolutionRetry.stop()
      return
    }
    // PluginRegistry writes are not atomic from QML's point of view. Retry for
    // a short bounded window so a temporarily absent manifest entry point
    // cannot strand this or a future third-party widget at width zero.
    if (resolutionAttempts < 10) {
      resolutionAttempts++
      resolutionRetry.restart()
    } else if (bar && typeof bar.noteHostWidgetResolution === "function") {
      bar.noteHostWidgetResolution(root, false)
    }
  }

  function refreshResolvedComponent() {
    if (scopedHost) {
      if (resolvedComponent === null && moduleEnabled) ensureResolvedComponent()
      return
    }
    const component = bar && typeof bar.registeredWidgetComponent === "function"
      ? bar.registeredWidgetComponent(moduleName) : null
    if (legacyComponent !== component) legacyComponent = component
    if (component === null && moduleEnabled) ensureResolvedComponent()
  }

  function compatibilityPanelCandidate(candidate) {
    if (!candidate
        || (typeof candidate !== "object"
          && typeof candidate !== "function")) return false
    try {
      return "anchorItem" in candidate
        && "cardOrigin" in candidate
        && "borderSpec" in candidate
        && "contentWidth" in candidate
        && "contentHeight" in candidate
        && "open" in candidate
    } catch (error) {
      return false
    }
  }

  function compatibilityTraversalChildren(candidate) {
    const children = []
    if (!candidate
        || (typeof candidate !== "object"
          && typeof candidate !== "function")) return children

    try {
      const objects = candidate.data || []
      const count = Math.min(Number(objects.length) || 0,
        compatibilityTraversalObjectLimit)
      for (let index = 0; index < count; index++)
        if (objects[index]) children.push(objects[index])
    } catch (error) {}

    // Loader.item is not guaranteed to appear in the Loader's QML data list.
    // Follow only real Loader ownership edges; arbitrary foreign `item`
    // properties are not a safe panel-discovery contract.
    try {
      if (candidate instanceof Loader && candidate.item)
        children.push(candidate.item)
    } catch (error) {}
    return children
  }

  function findCompatibilityPanel(owner) {
    const initial = compatibilityTraversalChildren(owner)
    const queue = []
    const seen = []
    for (let index = 0; index < initial.length; index++)
      queue.push({ object: initial[index], depth: 0 })

    // Breadth-first traversal preserves the existing direct-panel precedence.
    // The depth and object caps keep foreign, unsandboxed object trees bounded.
    for (let cursor = 0;
         cursor < queue.length
           && cursor < compatibilityTraversalObjectLimit;
         cursor++) {
      const entry = queue[cursor]
      const candidate = entry.object
      if (!candidate || seen.indexOf(candidate) >= 0) continue
      seen.push(candidate)
      if (compatibilityPanelCandidate(candidate)) return candidate
      if (entry.depth >= compatibilityTraversalDepthLimit) continue

      const nested = compatibilityTraversalChildren(candidate)
      for (let index = 0;
           index < nested.length
             && queue.length < compatibilityTraversalObjectLimit;
           index++) {
        if (seen.indexOf(nested[index]) < 0)
          queue.push({ object: nested[index], depth: entry.depth + 1 })
      }
    }
    return null
  }

  function findCompatibilityCard(panel) {
    const objects = panel && panel.data ? panel.data : []
    for (let index = 0; index < objects.length; index++) {
      const candidate = objects[index]
      if (!candidate
          || !("contentTopInset" in candidate)
          || !("borderSpec" in candidate)
          || !("radius" in candidate)
          || !("color" in candidate)) continue
      return candidate
    }
    return null
  }

  function resolveCompatibilitySurface() {
    const panel = findCompatibilityPanel(activeItem)
    compatibilityPanel = panel
    compatibilityCard = findCompatibilityCard(panel)
    if (panel) {
      compatibilitySurfaceResolutionAttempts = 0
      compatibilitySurfaceTimer.stop()
    } else if (hostedModule && activeItem
        && compatibilitySurfaceResolutionAttempts < 20) {
      // A nested Loader can complete after the outer bar-widget Loader.
      compatibilitySurfaceTimer.restart()
    }
    publishCompatibilityConnection()
  }

  function clearCompatibilityConnection() {
    const owner = connectedCompatibilityOwner
    connectedCompatibilityOwner = null
    if (owner && bar && typeof bar.clearConnectedPanel === "function")
      bar.clearConnectedPanel(owner)
  }

  function publishCompatibilityConnection() {
    const owner = activeItem
    if (!owner || !bar
        || typeof bar.publishConnectedPanel !== "function") return false
    if (!v2PanelConnectionEnabled) {
      if (connectedCompatibilityOwner === owner
          && compatibilityConnectionReveal <= 0.001)
        clearCompatibilityConnection()
      return false
    }
    const card = compatibilityCard
    if (!card || compatibilityAnchorX <= 0 || screenName === "")
      return false
    const published = bar.publishConnectedPanel(owner, screenName,
      compatibilityAnchorX, compatibilityConnectionReveal, {
        hostCaret: true,
        cardX: Number(card.x) || 0,
        cardY: Number(card.y) || 0,
        cardWidth: Number(card.width) || 0,
        cardHeight: Number(card.height) || 0
      })
    if (published && compatibilityConnectionReveal > 0.001)
      connectedCompatibilityOwner = owner
    else if (compatibilityConnectionReveal <= 0.001
        && connectedCompatibilityOwner === owner)
      connectedCompatibilityOwner = null
    return published
  }

  function applyInlineSettings(nextEntry) {
    inlineHostEntry = nextEntry
    inlineSettingsSync.restart()
  }

  function clearInlineSettings() {
    inlineHostEntry = null
    inlineSettingsSync.restart()
  }

  function injectProperties() {
    const target = activeItem
    if (!target) return
    if ("bar" in target) target.bar = bar
    if ("moduleName" in target) target.moduleName = moduleName
    if ("hostGroupId" in target) target.hostGroupId = region
    if ("settings" in target) target.settings = moduleSettings
    if ("availableWidth" in target) target.availableWidth = availableWidth
  }

  TransformWatcher {
    id: slotTransformWatcher

    a: root.containingWindow ? root.containingWindow.contentItem : null
    b: root
  }

  HoverHandler {
    id: fallbackTooltipHover

    enabled: root.hostedModule && root.fallbackTooltipText !== ""
    onHoveredChanged: {
      if (hovered) fallbackTooltipProbe.restart()
      else {
        fallbackTooltipProbe.stop()
        if (root.bar) root.bar.hideTooltip(root)
      }
    }
  }

  Timer {
    id: fallbackTooltipProbe

    interval: 0
    repeat: false
    onTriggered: {
      if (!fallbackTooltipHover.hovered || !root.bar) return
      // A plugin-provided WidgetButton tooltip wins. The manifest fallback
      // only fills the deliberate/accidental empty-tooltip case.
      if (root.bar.pendingTooltipTarget || root.bar.tooltipTarget) return
      root.bar.showTooltip(root, root.fallbackTooltipText)
    }
  }

  Behavior on compatibilityConnectionReveal {
    NumberAnimation {
      duration: root.compatibilityPanel && root.compatibilityPanel.open
        ? 160 : 120
      easing.type: root.compatibilityPanel && root.compatibilityPanel.open
        ? Easing.OutCubic : Easing.InCubic
    }
  }

  Binding {
    target: root.compatibilityPanel
    property: "borderSpec"
    value: root.bar && root.bar.visualTokens
      ? Commons.Border.flat(root.bar.visualTokens.panelBorder,
          root.bar.visualTokens.panelBorderWidth)
      : Commons.Border.flat("transparent", 0)
    when: root.hostPanelChromeEnabled
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.compatibilityCard
    property: "color"
    value: root.bar && root.bar.visualTokens
      ? root.bar.visualTokens.panelBackground : "transparent"
    when: root.hostPanelChromeEnabled
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.compatibilityCard
    property: "radius"
    value: root.bar && root.bar.visualTokens
      ? root.bar.visualTokens.panelRadius : 0
    when: root.hostPanelChromeEnabled
    restoreMode: Binding.RestoreBindingOrValue
  }

  Connections {
    target: root.activeItem
    ignoreUnknownSignals: true

    function onVisibleChanged() { root.syncActiveItemMetrics() }
    function onImplicitWidthChanged() { root.syncActiveItemMetrics() }
    function onImplicitHeightChanged() { root.syncActiveItemMetrics() }
    function onOpenedChanged() {
      // Re-resolve on the provider's public open signal as well as during the
      // bounded construction retry. This covers a Loader activated on demand.
      const panelOpened = root.activeItem
        && "opened" in root.activeItem
        && root.activeItem.opened === true
      if (root.hostedModule) {
        if (panelOpened && !root.compatibilityPanel)
          root.compatibilitySurfaceResolutionAttempts = 0
        root.resolveCompatibilitySurface()
        if (!panelOpened) {
          // A close may destroy an on-demand Loader. Resolve once to clear
          // stale objects, but never leave discovery polling running.
          compatibilitySurfaceTimer.stop()
        }
      } else root.publishCompatibilityConnection()
    }
  }

  Connections {
    target: root.compatibilityCard
    ignoreUnknownSignals: true

    function onXChanged() { root.publishCompatibilityConnection() }
    function onYChanged() { root.publishCompatibilityConnection() }
    function onWidthChanged() { root.publishCompatibilityConnection() }
    function onHeightChanged() { root.publishCompatibilityConnection() }
  }


  Connections {
    target: !root.scopedHost && root.bar && "hostWidgetResolver" in root.bar
      ? root.bar.hostWidgetResolver : null
    // Legacy component creation can publish while a URL lookup is still being
    // evaluated. Defer that cache refresh to keep the fallback acyclic.
    function onRevisionChanged() { resolverRefresh.restart() }
  }
  Connections {
    target: "claimLoadedOwner" in root.bar ? root.bar : null
    function onLoadedOwnersChanged() { root.requestLoaderSourceSync() }
  }
  Timer {
    id: scopedLoaderSync

    interval: 0
    repeat: false
    onTriggered: root.synchronizeLoaderSource()
  }

  Timer {
    id: inlineSettingsSync

    interval: 0
    repeat: false
    onTriggered: root.injectProperties()
  }

  Timer {
    id: resolverRefresh
    interval: 0
    repeat: false
    onTriggered: root.refreshResolvedComponent()
  }

  Timer {
    id: deferredSync
    interval: 0
    onTriggered: {
      root.injectProperties()
      root.syncActiveItemMetrics()
      root.resolveCompatibilitySurface()
    }
  }

  Timer {
    id: compatibilitySurfaceTimer

    interval: 40
    repeat: false
    onTriggered: {
      root.compatibilitySurfaceResolutionAttempts++
      root.resolveCompatibilitySurface()
    }
  }

  Timer {
    id: resolutionRetry
    interval: Math.min(400, 40 * (root.resolutionAttempts + 1))
    repeat: false
    onTriggered: root.ensureResolvedComponent()
  }

  Loader {
    id: widgetLoader
    anchors.fill: parent
    // Both activation and source submission stay gated until this exact slot
    // is registered. sourceComponent has no binding: submitLoaderSource() is
    // its single assignment path and records provenance before setter dispatch.
    active: root.slotComplete && root.moduleEnabled
      && root._loaderSubmissionActive
      && root._submission !== null
      && root._submission.source !== null
    onLoaded: {
      const completedSubmission = root._dispatchedSubmission
      const completedSource = completedSubmission
        ? completedSubmission.source : null
      const completedGeneration = completedSubmission
        ? completedSubmission.generation : -1
      const completedItem = widgetLoader.item
      root.injectProperties()
      root.syncActiveItemMetrics()
      // Injection can synchronously submit a replacement. Confirm only the
      // exact atomic request and item that emitted this completion.
      let completionCurrent = root.submissionMatches(completedSubmission,
        completedItem)
      let resident = null
      if (completionCurrent) {
        resident = {
          dispatch: completedSubmission,
          source: completedSource,
          item: completedItem
        }
        root._residentLoad = resident
        completionCurrent = root._submission === completedSubmission
          && root._dispatchedSubmission === completedSubmission
          && root._residentLoad === resident
          && root.submissionMatches(completedSubmission, completedItem)
      }
      let completion = null
      if (completionCurrent) {
        completion = {
          submission: completedSubmission,
          source: completedSource,
          generation: completedGeneration,
          item: completedItem
        }
        completionCurrent = root.publishCompletedLoad(completion,
          completedSubmission, resident)
          && root._residentLoad === resident
          && root.submissionMatches(completedSubmission, completedItem)
      }
      if (completionCurrent) {
        if (!root.currentLoadReady()) {
          if (root._completedLoad === completion)
            root.invalidateCompletedLoad(completedSubmission)
        } else if (root.bar
            && typeof root.bar.noteHostWidgetResolution === "function") {
          root.bar.noteHostWidgetResolution(root, true)
        }
        if ("claimLoadedOwner" in root.bar && !root.bar.claimLoadedOwner(
            root, completedItem)) root.requestLoaderSourceSync()
      }
      deferredSync.restart()
    }
  }
}
