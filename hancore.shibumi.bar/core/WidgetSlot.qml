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
  // Make the component binding observe the resolver explicitly. A registry
  // refresh may briefly remove an entry point; the resolver publishes another
  // revision once that component can be created again.
  readonly property int resolverRevision: bar && "hostWidgetResolver" in bar
    && bar.hostWidgetResolver ? bar.hostWidgetResolver.revision : 0
  // Component handles are synchronized imperatively. Binding this property to
  // resolverRevision makes component creation publish a dependency change
  // while the same binding is still being evaluated on a fresh shell start.
  property var resolvedComponent: null
  property int resolutionAttempts: 0
  readonly property var activeItem: widgetLoader.item
  readonly property var containingWindow: activeItem && activeItem.QsWindow
    ? activeItem.QsWindow.window : null
  readonly property var moduleManifest: {
    void(resolverRevision)
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
  property var compatibilityContentHolder: null
  property real compatibilityNativeContentHeight: 0
  property real compatibilityMeasuredContentHeight: 0
  property int compatibilitySurfaceResolutionAttempts: 0
  property int compatibilityContentResolutionAttempts: 0
  readonly property bool compatibilityMeasurementRunning:
    compatibilityMeasureTimer.running || compatibilityOpenMeasureTimer.running
  readonly property int compatibilityTraversalDepthLimit: 8
  readonly property int compatibilityTraversalObjectLimit: 256
  readonly property bool hostPanelChromeEnabled: hostedModule
    && compatibilityPanel !== null
    && compatibilityCard !== null
    && bar && bar.visualTokens !== null
  // Omarchy KeyboardPanel normally derives its perpendicular offset from
  // the anchor window's dimensions. Shibumi deliberately keeps BarPanel
  // screen-sized so V1 edit mode can own one stable input surface, therefore
  // the host must translate that offset back to the visible bar edge.
  readonly property bool hostPanelPlacementEnabled: hostPanelChromeEnabled
    && "screenW" in compatibilityPanel
    && "screenH" in compatibilityPanel
    && Number(compatibilityPanel.screenW) > 0
    && Number(compatibilityPanel.screenH) > 0
  readonly property real compatibilityDesiredContentHeight: {
    const card = compatibilityCard
    if (!card || !compatibilityContentHolder) return 0
    return Math.ceil(compatibilityMeasuredContentHeight
      + (Number(card.contentTopInset) || 0)
      + (Number(card.contentBottomInset) || 0))
  }
  readonly property real compatibilityAvailableContentHeight: {
    const panel = compatibilityPanel
    if (!panel || !bar) return 0
    const screenHeight = Math.max(0, Number(panel.screenH) || 0)
    const margin = Math.max(0, Number(panel.margin) || 0)
    const gap = Math.max(0, Number(panel.gap) || 0)
    const barThickness = Math.max(0, Number(bar.barSize) || 0)
    return Math.max(120, screenHeight - barThickness - gap - margin)
  }
  readonly property real compatibilityHostedContentHeight: Math.min(
    compatibilityDesiredContentHeight,
    compatibilityAvailableContentHeight)
  readonly property bool hostPanelHeightRepairEnabled:
    hostPanelPlacementEnabled
    && (bar.position === "top" || bar.position === "bottom")
    && compatibilityNativeContentHeight <= 120
    && compatibilityHostedContentHeight
      > compatibilityNativeContentHeight + 0.5
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
    ensureResolvedComponent()
    bar.registerModuleSlot(root)
  }
  Component.onDestruction: {
    clearCompatibilityConnection()
    if (bar.activePopout === activeItem) bar.releasePopout(activeItem)
    bar.hideTooltip(activeItem)
    bar.unregisterModuleSlot(root)
  }
  onModuleSettingsChanged: injectProperties()
  onModuleNameChanged: {
    inlineHostEntry = null
    resolvedComponent = null
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
  }
  onResolvedComponentChanged: {
    if (resolvedComponent !== null) {
      resolutionAttempts = 0
      resolutionRetry.stop()
    }
  }
  onAvailableWidthChanged: injectProperties()
  onActiveItemChanged: {
    if (connectedCompatibilityOwner
        && connectedCompatibilityOwner !== activeItem)
      clearCompatibilityConnection()
    compatibilityPanel = null
    compatibilityCard = null
    compatibilityContentHolder = null
    compatibilityNativeContentHeight = 0
    compatibilityMeasuredContentHeight = 0
    compatibilitySurfaceResolutionAttempts = 0
    compatibilityContentResolutionAttempts = 0
    compatibilitySurfaceTimer.stop()
    compatibilityMeasureTimer.stop()
    compatibilityOpenMeasureTimer.stop()
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

  function ensureResolvedComponent() {
    const resolver = bar && "hostWidgetResolver" in bar
      ? bar.hostWidgetResolver : null
    const component = resolver && typeof resolver.ensureComponent === "function"
      ? resolver.ensureComponent(moduleName)
      : bar && typeof bar.registeredWidgetComponent === "function"
        ? bar.registeredWidgetComponent(moduleName) : null
    if (resolvedComponent !== component) resolvedComponent = component
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
    }
  }

  function refreshResolvedComponent() {
    const component = bar && typeof bar.registeredWidgetComponent === "function"
      ? bar.registeredWidgetComponent(moduleName) : null
    if (resolvedComponent !== component) resolvedComponent = component
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

  function compatibilityDescendantCount(item, depth) {
    if (!item || depth > 16) return 0
    const children = item.children || []
    let count = children.length
    for (let index = 0; index < children.length; index++)
      count += compatibilityDescendantCount(children[index], depth + 1)
    return count
  }

  function findCompatibilityContentHolder(card) {
    const children = card && card.children ? card.children : []
    let best = null
    let bestCount = 0
    for (let index = 0; index < children.length; index++) {
      const candidate = children[index]
      const count = compatibilityDescendantCount(candidate, 0)
      if (count > bestCount) {
        best = candidate
        bestCount = count
      }
    }
    return best
  }

  function measureCompatibilityContent(holder) {
    if (!holder) return 0
    let bottom = 0

    function visit(item, depth) {
      if (!item || depth > 16 || item.visible === false) return
      if (depth > 0) {
        let point = Qt.point(0, 0)
        try { point = item.mapToItem(holder, 0, 0) } catch (error) {}
        const itemHeight = Math.max(Number(item.height) || 0,
          Number(item.implicitHeight) || 0)
        const fillsHolder = Math.abs(Number(point.x) || 0) < 0.5
          && Math.abs(Number(point.y) || 0) < 0.5
          && Math.abs((Number(item.width) || 0)
            - (Number(holder.width) || 0)) < 0.5
          && Math.abs((Number(item.height) || 0)
            - (Number(holder.height) || 0)) < 0.5
        if (!fillsHolder)
          bottom = Math.max(bottom, (Number(point.y) || 0) + itemHeight)
      }
      const children = item.children || []
      for (let index = 0; index < children.length; index++)
        visit(children[index], depth + 1)
    }

    visit(holder, 0)
    return Math.ceil(Math.max(0, bottom))
  }

  function hostedCardOrigin(panel) {
    if (!panel || !bar) return Qt.point(0, 0)
    const screenWidth = Math.max(0, Number(panel.screenW) || 0)
    const screenHeight = Math.max(0, Number(panel.screenH) || 0)
    const contentWidth = Math.max(1, Number(panel.contentWidth) || 1)
    const contentHeight = Math.max(1, Number(panel.contentHeight) || 1)
    const margin = Math.max(0, Number(panel.margin) || 0)
    const gap = Math.max(0, Number(panel.gap) || 0)
    const barThickness = Math.max(0, Number(bar.barSize) || 0)
    const barPosition = "barPos" in panel
      ? String(panel.barPos || "top") : String(bar.position || "top")
    const anchorPosition = "anchorScreenPos" in panel
      ? panel.anchorScreenPos : slotWindowPosition
    const anchorWidth = "anchorW" in panel
      ? Math.max(0, Number(panel.anchorW) || 0) : width
    const anchorHeight = "anchorH" in panel
      ? Math.max(0, Number(panel.anchorH) || 0) : height
    const centered = "centerOnBar" in panel && !!panel.centerOnBar
    let x = 0
    let y = 0

    if (centered && (barPosition === "top" || barPosition === "bottom")) {
      x = screenWidth / 2 - contentWidth / 2
      y = barPosition === "bottom"
        ? screenHeight - barThickness - contentHeight - gap
        : barThickness + gap
    } else if (centered) {
      x = barPosition === "left" ? barThickness + gap
        : screenWidth - barThickness - contentWidth - gap
      y = screenHeight / 2 - contentHeight / 2
    } else if (barPosition === "bottom") {
      x = anchorPosition.x + anchorWidth / 2 - contentWidth / 2
      y = screenHeight - barThickness - contentHeight - gap
    } else if (barPosition === "left") {
      x = barThickness + gap
      y = anchorPosition.y + anchorHeight / 2 - contentHeight / 2
    } else if (barPosition === "right") {
      x = screenWidth - barThickness - contentWidth - gap
      y = anchorPosition.y + anchorHeight / 2 - contentHeight / 2
    } else {
      x = anchorPosition.x + anchorWidth / 2 - contentWidth / 2
      y = barThickness + gap
    }

    x = Math.max(margin, Math.min(x, screenWidth - contentWidth - margin))
    y = Math.max(margin, Math.min(y, screenHeight - contentHeight - margin))
    return Qt.point(Math.round(x), Math.round(y))
  }

  function resolveCompatibilitySurface() {
    const previousPanel = compatibilityPanel
    const panel = findCompatibilityPanel(activeItem)
    const currentNativeHeight = panel
      ? Math.max(0, Number(panel.contentHeight) || 0) : 0
    compatibilityPanel = panel
    compatibilityCard = findCompatibilityCard(panel)
    // Opening an already-discovered panel emits openedChanged after the host
    // height binding has expanded it. Preserve the smallest native height
    // observed for the same panel so that re-resolution cannot mistake the
    // host-repaired value for the provider's original geometry and collapse
    // the card back to KeyboardPanel's 120px safety minimum.
    compatibilityNativeContentHeight = panel && panel === previousPanel
        && compatibilityNativeContentHeight > 0
      ? Math.min(compatibilityNativeContentHeight, currentNativeHeight)
      : currentNativeHeight
    compatibilityContentHolder = findCompatibilityContentHolder(
      compatibilityCard)
    compatibilityMeasuredContentHeight = measureCompatibilityContent(
      compatibilityContentHolder)
    compatibilityContentResolutionAttempts = 0
    if (panel) {
      compatibilitySurfaceResolutionAttempts = 0
      compatibilitySurfaceTimer.stop()
    } else if (hostedModule && activeItem
        && compatibilitySurfaceResolutionAttempts < 20) {
      // A nested Loader can complete after the outer bar-widget Loader.
      compatibilitySurfaceTimer.restart()
    }
    if (hostedModule && compatibilityCard) {
      compatibilityOpenMeasureTimer.stop()
      compatibilityMeasureTimer.restart()
    } else {
      compatibilityMeasureTimer.stop()
      compatibilityOpenMeasureTimer.stop()
    }
    publishCompatibilityConnection()
  }

  function refreshCompatibilityContent() {
    if (!compatibilityCard || !activeItem) {
      compatibilityMeasureTimer.stop()
      compatibilityOpenMeasureTimer.stop()
      return
    }
    compatibilityContentHolder = findCompatibilityContentHolder(
      compatibilityCard)
    compatibilityMeasuredContentHeight = measureCompatibilityContent(
      compatibilityContentHolder)
    compatibilityContentResolutionAttempts++
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

  // KeyboardPanel measures its available height from the anchor window. The
  // Shibumi bar host is intentionally screen-sized, so hosted panels otherwise
  // mistake the whole screen for the bar and collapse to the 120px safety
  // minimum. Recover the provider's actual content height and cap it against
  // the visible screen edge; native-sized panels remain untouched.
  Binding {
    target: root.compatibilityPanel
    property: "contentHeight"
    value: root.compatibilityHostedContentHeight
    when: root.hostPanelHeightRepairEnabled
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

  Binding {
    target: root.compatibilityCard
    property: "x"
    value: root.hostedCardOrigin(root.compatibilityPanel).x
    when: root.hostPanelPlacementEnabled
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.compatibilityCard
    property: "y"
    value: root.hostedCardOrigin(root.compatibilityPanel).y
    when: root.hostPanelPlacementEnabled
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
          // stale objects, but never leave discovery or measurement polling.
          compatibilitySurfaceTimer.stop()
          compatibilityMeasureTimer.stop()
          compatibilityOpenMeasureTimer.stop()
        }
      } else root.publishCompatibilityConnection()
      if (panelOpened && root.hostedModule && root.compatibilityCard) {
        root.compatibilityContentResolutionAttempts = 0
        compatibilityMeasureTimer.restart()
      }
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
    target: root.bar && "hostWidgetResolver" in root.bar
      ? root.bar.hostWidgetResolver : null
    // A registry refresh publishes its revision from inside the resolver.
    // Re-entering ensureComponent() from that signal can publish a second
    // revision while resolvedComponent is still being evaluated. Defer the
    // lookup to the next event-loop turn so component resolution stays acyclic.
    function onRevisionChanged() { resolverRefresh.restart() }
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
    id: compatibilityMeasureTimer

    // Fast construction settling: 25 Hz for at most 800 ms after discovery
    // or open, owned by this hosted slot and stopped on close/destruction.
    interval: 40
    repeat: true
    onTriggered: {
      root.refreshCompatibilityContent()
      if (root.compatibilityContentResolutionAttempts >= 20) {
        stop()
        if (root.compatibilityPanel && root.compatibilityCard
            && root.compatibilityPanel.open)
          compatibilityOpenMeasureTimer.start()
      }
    }
  }

  Timer {
    id: compatibilityOpenMeasureTimer

    // Standard third-party panels such as Otoru change their rendered extent
    // after asynchronous work or later user actions. Reconcile at 4 Hz only
    // while that panel is open; close, unload and slot destruction stop it.
    interval: 250
    repeat: true
    onTriggered: {
      if (!root.activeItem || !root.compatibilityPanel
          || !root.compatibilityCard || !root.compatibilityPanel.open) {
        stop()
        const providerOpen = root.activeItem
          && "opened" in root.activeItem && root.activeItem.opened === true
        if (providerOpen && !root.compatibilityPanel) {
          root.compatibilitySurfaceResolutionAttempts = 0
          compatibilitySurfaceTimer.restart()
        }
        return
      }
      root.refreshCompatibilityContent()
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
    active: root.moduleEnabled && root.resolvedComponent !== null
    sourceComponent: root.resolvedComponent
    onLoaded: {
      root.injectProperties()
      root.syncActiveItemMetrics()
      deferredSync.restart()
    }
  }
}
