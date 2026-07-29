pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property var bar
  required property var entry
  property string region: ""
  property string screenName: ""
  property real availableWidth: 0
  readonly property string moduleName: bar.entryId(entry)
  readonly property var moduleSettings: bar.entrySettings(entry)
  readonly property bool moduleEnabled: moduleSettings.enabled !== false
  // Make the component binding observe the resolver explicitly. A registry
  // refresh may briefly remove an entry point; the resolver publishes another
  // revision once that component can be created again.
  readonly property int resolverRevision: bar && "hostWidgetResolver" in bar
    && bar.hostWidgetResolver ? bar.hostWidgetResolver.revision : 0
  readonly property var resolvedComponent: {
    void(resolverRevision)
    return bar && typeof bar.registeredWidgetComponent === "function"
      ? bar.registeredWidgetComponent(moduleName) : null
  }
  property int resolutionAttempts: 0
  readonly property var activeItem: widgetLoader.item
  readonly property var containingWindow: activeItem && activeItem.QsWindow
    ? activeItem.QsWindow.window : null
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
  implicitHeight: activeItemVisible ? activeItemImplicitHeight : 0
  width: implicitWidth
  height: implicitHeight

  Component.onCompleted: {
    ensureResolvedComponent()
    bar.registerModuleSlot(root)
  }
  Component.onDestruction: {
    if (bar.activePopout === activeItem) bar.releasePopout(activeItem)
    bar.hideTooltip(activeItem)
    bar.unregisterModuleSlot(root)
  }
  onModuleSettingsChanged: injectProperties()
  onModuleNameChanged: {
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
    syncActiveItemMetrics()
    deferredSync.restart()
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
      ? resolver.ensureComponent(moduleName) : null
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

  function injectProperties() {
    const target = activeItem
    if (!target) return
    if ("bar" in target) target.bar = bar
    if ("moduleName" in target) target.moduleName = moduleName
    if ("settings" in target) target.settings = moduleSettings
    if ("availableWidth" in target) target.availableWidth = availableWidth
  }

  Connections {
    target: root.activeItem
    ignoreUnknownSignals: true

    function onVisibleChanged() { root.syncActiveItemMetrics() }
    function onImplicitWidthChanged() { root.syncActiveItemMetrics() }
    function onImplicitHeightChanged() { root.syncActiveItemMetrics() }
  }


  Connections {
    target: root.bar && "hostWidgetResolver" in root.bar
      ? root.bar.hostWidgetResolver : null
    function onRevisionChanged() { root.ensureResolvedComponent() }
  }

  Timer {
    id: deferredSync
    interval: 0
    onTriggered: {
      root.injectProperties()
      root.syncActiveItemMetrics()
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
