pragma ComponentBehavior: Bound

import QtQuick

// Scoped hosts publish accepted Component handles. Render exact configured
// IDs, with no original fallback or foreign manifest reconstruction. Legacy
// full registries retain their previously tested component-ownership route.
QtObject {
  id: root

  required property var bar
  property var components: ({})
  property var componentUrls: ({})
  property int revision: 0
  readonly property var hostRegistry: bar ? bar.pluginRegistry : null
  readonly property bool scoped: !!hostRegistry
    && "pluginId" in hostRegistry
  readonly property var widgetRegistry: bar ? bar.barWidgetRegistry : null
  readonly property var configuredLayout: bar && bar.barConfig
    ? bar.barConfig.layout : null

  function configured(id) {
    const layout = configuredLayout
    if (!layout) return false
    for (const region of ["left", "center", "right"]) {
      const entries = layout[region]
      if (!Array.isArray(entries)) return false
      for (const entry of entries)
        if (entry === id || (entry && entry.id === id)) return true
    }
    return false
  }

  function metadataFor(widgetId) {
    const selection = selectionFor(widgetId)
    return selection ? selection.metadata || (selection.manifest
      ? selection.manifest.barWidget : null) : null
  }

  function selectionFor(widgetId) {
    if (scoped) {
      const key = String(widgetId || "")
      const widgets = widgetRegistry ? widgetRegistry.widgets : null
      const entry = widgets && Object.prototype.hasOwnProperty.call(widgets, key)
        ? widgets[key] : null
      return entry && entry.metadata && entry.metadata.pluginId === key
        ? { id: key, component: entry.component, metadata: entry.metadata } : null
    }
    const registry = bar ? bar.pluginRegistry : null
    const plugins = registry && registry.installedPlugins
      ? registry.installedPlugins : null
    const requestedId = String(widgetId || "")
    if (!requestedId || !plugins) return null
    // The host owns clone selection. An explicit empty resolution is a
    // refusal, not permission to fall back to the original manifest.
    const id = typeof registry.resolveEnabledId === "function"
      ? String(registry.resolveEnabledId(requestedId) || "") : requestedId
    if (!id || !Object.prototype.hasOwnProperty.call(plugins, id)
        || !plugins[id] || typeof plugins[id] !== "object"
        || Array.isArray(plugins[id])) return null
    return { id: id, manifest: plugins[id] }
  }

  function manifestFor(widgetId) {
    const selection = selectionFor(widgetId)
    return selection ? selection.manifest || null : null
  }

  function entryPointUrl(widgetId) {
    const registry = bar ? bar.pluginRegistry : null
    const manifest = manifestFor(widgetId)
    if (!manifest || !registry || typeof registry.entryPointUrl !== "function")
      return ""
    return String(registry.entryPointUrl(manifest, "barWidget") || "")
  }

  function isComponentHandle(candidate) {
    // Scoped native registry handles can lose their JavaScript `status`
    // projection while remaining valid QQmlComponents accepted by Loader.
    // Check the installed Qt type itself; Ready-shaped data and arbitrary
    // QObjects must never reach Loader.sourceComponent.
    try { return !!candidate && candidate instanceof Component }
    catch (error) { return false }
  }

  function componentFor(widgetId) {
    const id = String(widgetId || "")
    if (scoped) {
      const selection = selectionFor(id)
      const component = selection ? selection.component : null
      return configured(id) && isComponentHandle(component)
        ? component : null
    }
    const existing = components[id]
    const url = entryPointUrl(id)
    return existing && existing.status === Component.Ready
      && url !== "" && componentUrls[id] === url ? existing : null
  }

  function ensureComponent(widgetId) {
    if (scoped) return componentFor(widgetId)
    const id = String(widgetId || "")
    const url = entryPointUrl(id)
    if (!id || !url) return null

    const existing = componentFor(id)
    if (existing && componentUrls[id] === url) return existing

    const component = Qt.createComponent(url, Component.PreferSynchronous)
    if (!component || component.status !== Component.Ready) {
      const detail = component && typeof component.errorString === "function"
        ? String(component.errorString()) : "component is not ready"
      console.warn("Shibumi could not resolve host widget " + id + ": " + detail)
      return null
    }

    const nextComponents = ({})
    const nextUrls = ({})
    for (const key in components) nextComponents[key] = components[key]
    for (const key in componentUrls) nextUrls[key] = componentUrls[key]
    nextComponents[id] = component
    nextUrls[id] = url
    components = nextComponents
    componentUrls = nextUrls
    // A registry refresh can invalidate a handle and emit revision before the
    // manifest entry point is available again. WidgetSlot then observes null,
    // and a later successful ensure must publish its own revision; otherwise
    // the slot remains bound to null until an unrelated registry event.
    revision++
    return component
  }

  function clear() {
    components = ({})
    componentUrls = ({})
    revision++
  }

  // shell.json mutations also emit PluginRegistry.pluginsChanged(). Preserve
  // component identity when the resolved entry point did not actually change;
  // otherwise every settings click destroys all bar widgets and their panels.
  function syncRegistry() {
    const nextComponents = ({})
    const nextUrls = ({})

    for (const id in components) {
      const component = components[id]
      const previousUrl = String(componentUrls[id] || "")
      const currentUrl = entryPointUrl(id)
      if (!component || component.status !== Component.Ready
          || currentUrl === "" || currentUrl !== previousUrl) continue
      nextComponents[id] = component
      nextUrls[id] = previousUrl
    }

    if (Object.keys(nextComponents).length !== Object.keys(components).length) {
      components = nextComponents
      componentUrls = nextUrls
    }
    // WidgetSlots re-resolve missing or changed entry points. Retained handles
    // stay identical, so their live instances and open panels remain intact.
    revision++
  }

  onScopedChanged: clear()
  onHostRegistryChanged: clear()
  onWidgetRegistryChanged: clear()
  onConfiguredLayoutChanged: revision++
  property Connections widgetConnections: Connections {
    target: root.scoped ? root.widgetRegistry : null
    function onWidgetsChanged() { root.revision++ }
    function onRevisionChanged() { root.revision++ }
  }
  property Connections registryConnections: Connections {
    target: !root.scoped && root.bar ? root.bar.pluginRegistry : null
    function onPluginsChanged() { root.syncRegistry() }
  }
}
