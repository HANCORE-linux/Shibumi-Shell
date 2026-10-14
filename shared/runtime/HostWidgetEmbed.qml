import QtQuick

// Local host handles stay untyped until Loader's setter. Scheduling remains
// with the consumer: no new timer, polling, or callLater feedback path.
QtObject {
  id: root
  property var bar: null
  property var shell: null
  property var registry: null
  property bool registryOnly: false
  property bool shuttingDown: false
  property var loads: []

  function componentHandle(value) {
    try { return value && value instanceof Component ? value : null }
    catch (error) { return null }
  }

  function registryComponent(view, id) {
    if (view) void(view.revision)
    const entry = view && view.widgets ? view.widgets[String(id || "")] : null
    return componentHandle(entry ? entry.component : null)
  }

  function resolveComponent(owner, id) {
    // An explicitly injected service snapshot precedes legacy Bar lookups.
    const injected = registryComponent(registry, id)
    if (injected || registryOnly) return injected
    if (bar) {
      if (owner && typeof bar.registeredEmbeddedWidgetComponent === "function")
        return componentHandle(bar.registeredEmbeddedWidgetComponent(owner, id))
      if (typeof bar.registeredWidgetComponent === "function")
        return componentHandle(bar.registeredWidgetComponent(id))
    }
    return registryComponent(bar && "barWidgetRegistry" in bar ? bar.barWidgetRegistry : null, id)
  }

  function resolveSource(id) {
    if (registryOnly) return ""
    if (bar && typeof bar.registeredWidgetSource === "function")
      return bar.registeredWidgetSource(id)
    const host = shell || (bar && "shell" in bar ? bar.shell : null)
    const view = host && "pluginRegistry" in host ? host.pluginRegistry : null
    const manifest = view && view.installedPlugins ? view.installedPlugins[String(id || "")] : null
    return view && typeof view.entryPointUrl === "function" ? view.entryPointUrl(manifest, "barWidget") : ""
  }

  function clearLoader(loader) {
    loader.sourceComponent = null
    loader.source = ""
  }

  function revoke() {
    const previous = loads
    loads = []
    for (const record of previous) clearLoader(record.loader)
  }

  function shutdown() {
    shuttingDown = true
    // Destroy children while their injected host facade is still valid.
    for (const record of loads)
      if (record.loader.item !== null) record.loader.active = false
    revoke()
  }

  function syncLoader(loader, handle, source, args, owner) {
    if (shuttingDown || !loader) return false
    const component = componentHandle(handle)
    const url = component ? "" : String(source || "")
    let record = loads.find(value => value.loader === loader)
    if (!record || record.owner !== owner || record.component !== component || record.url !== url) {
      loads = loads.filter(value => value.loader !== loader)
      clearLoader(loader)
      record = {loader: loader, owner: owner, component: component, url: url, attempts: 0}
      loads = loads.concat([record])
    }
    if (!owner || (!component && !url)) return false
    if (loader.item !== null) return true
    // Reuse only existing consumer wakeups. Exhaustion cannot create a loop;
    // a new owner or source begins a new bounded submission sequence.
    if (loader.status === Loader.Loading || record.attempts >= 10) return false
    record.attempts++
    clearLoader(loader)
    if (shuttingDown || loads.indexOf(record) < 0) return false
    if (component) loader.sourceComponent = component
    else loader.setSource(url, args)
    return loader.item !== null
  }

}
