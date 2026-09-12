import QtQuick
import "." as Local

// Adapt the documented injection. The native object remains the delegate;
// this wrapper never searches parents, scans plugins or creates services.
QtObject {
  id: api
  property var host: null
  readonly property bool scoped: !!host && "pluginId" in host
  readonly property var barConfig: {
    if (!host) return null
    if ("barConfig" in host) return Local.Runtime.plain(host.barConfig) ? host.barConfig : null
    return Local.Runtime.plain(host.shellConfig)
      && Local.Runtime.plain(host.shellConfig.bar) ? host.shellConfig.bar : null
  }
  readonly property var shellConfig: scoped ? (barConfig ? {bar: barConfig} : null)
    : host && "shellConfig" in host ? host.shellConfig : null
  // Keep the native bar-state surface. Do not publish the entire active
  // suite bar as a general service/widget facade; visual anchors are local.
  readonly property var bar: host && "bar" in host ? host.bar : null
  readonly property var pluginRegistry: !scoped && host && "pluginRegistry" in host
    ? host.pluginRegistry : null

  function serviceFor(id) {
    const key = String(id || "")
    if (Local.Runtime.providerIds.indexOf(key) < 0) return null
    if (scoped) return Local.Runtime.serviceFor(key)
    // Explicit legacy-host integration, not fallback after a scoped refusal.
    return host && typeof host.serviceFor === "function" ? host.serviceFor(key) : null
  }

  function firstPartyServiceFor(id) {
    const key = String(id || "")
    if (["omarchy.idle", "omarchy.media", "omarchy.notifications"].indexOf(key) < 0) return null
    if (scoped) return Local.Runtime.firstPartyServiceFor(key)
    return host && typeof host.firstPartyServiceFor === "function"
      ? host.firstPartyServiceFor(key) : null
  }

  function mutateShellConfig(mutator) {
    return host && typeof host.mutateShellConfig === "function"
      ? host.mutateShellConfig(mutator) : false
  }
  function updateEntryInline(id, settings) {
    return host && typeof host.updateEntryInline === "function"
      ? host.updateEntryInline(id, settings) : false
  }
  function pluginShellForBarEntry(ownerId, moduleName) {
    return host && typeof host.pluginShellForBarEntry === "function"
      ? host.pluginShellForBarEntry(ownerId, moduleName) : null
  }
  function summon(id, payloadJson) {
    return host && typeof host.summon === "function" ? host.summon(id, payloadJson) : false
  }
  function hide(id) {
    return host && typeof host.hide === "function" ? host.hide(id) : false
  }
  function toggle(id, payloadJson) {
    return host && typeof host.toggle === "function" ? host.toggle(id, payloadJson) : false
  }
  function isPluginOpen(id) {
    return host && typeof host.isPluginOpen === "function" ? host.isPluginOpen(id) : false
  }
}
