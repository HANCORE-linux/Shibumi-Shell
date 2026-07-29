pragma ComponentBehavior: Bound

import QtQuick

// Own the Component handles used by the replacement bar. Quattro's widget
// registry can retain handles owned by a previously active bar after a hot
// switch; resolving the same official manifest entry points here keeps their
// lifetime tied to Shibumi instead.
QtObject {
  id: root

  required property var bar
  property var components: ({})
  property var componentUrls: ({})
  property int revision: 0

  function entryPointUrl(widgetId) {
    const registry = bar ? bar.pluginRegistry : null
    const plugins = registry && registry.installedPlugins
      ? registry.installedPlugins : null
    const manifest = plugins ? plugins[String(widgetId || "")] : null
    if (!manifest || !registry || typeof registry.entryPointUrl !== "function")
      return ""
    return String(registry.entryPointUrl(manifest, "barWidget") || "")
  }

  function componentFor(widgetId) {
    const id = String(widgetId || "")
    const existing = components[id]
    return existing && existing.status === Component.Ready ? existing : null
  }

  function ensureComponent(widgetId) {
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

  property Connections registryConnections: Connections {
    target: root.bar ? root.bar.pluginRegistry : null
    function onPluginsChanged() { root.syncRegistry() }
  }
}
