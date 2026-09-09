import QtQuick
import "." as Local

QtObject {
  id: api

  required property string pluginId
  property var owner: null
  property bool isBar: false
  property var host: null
  readonly property bool shibumiHostShell: true

  readonly property var bar: Local.Registry.bar
    ? Local.Registry.bar
    : host && host.bar && "width" in host.bar ? host.bar : null
  readonly property var shellConfig: host && "shellConfig" in host
    ? host.shellConfig
    : ({ bar: host && host.barConfig ? host.barConfig : ({}) })
  readonly property var pluginRegistry: host && "pluginRegistry" in host
    && host.pluginRegistry && "rescan" in host.pluginRegistry
    ? host.pluginRegistry : Local.Registry.catalogue

  function serviceFor(id) {
    const service = Local.Registry.serviceFor(id)
    if (service) return service
    return host && typeof host.serviceFor === "function"
      ? host.serviceFor(String(id || "")) : null
  }

  function firstPartyServiceFor(id) {
    const key = String(id || "")
    const own = host && typeof host.firstPartyServiceFor === "function"
      ? host.firstPartyServiceFor(key) : null
    if (own) return own
    const barHost = Local.Registry.barHost
    return barHost && barHost !== host
      && typeof barHost.firstPartyServiceFor === "function"
      ? barHost.firstPartyServiceFor(key) : null
  }

  function mutateShellConfig(mutator) {
    return host && typeof host.mutateShellConfig === "function"
      ? host.mutateShellConfig(mutator) : false
  }

  function updateEntryInline(id, settings) {
    return host && typeof host.updateEntryInline === "function"
      ? host.updateEntryInline(id, settings) : false
  }

  function summon(id, payloadJson) {
    return host && typeof host.summon === "function"
      ? host.summon(id, payloadJson) : false
  }

  function hide(id) {
    return host && typeof host.hide === "function" ? host.hide(id) : false
  }

  function isPluginOpen(id) {
    return host && typeof host.isPluginOpen === "function"
      ? host.isPluginOpen(id) : false
  }

  onHostChanged: {
    if (isBar && owner && Local.Registry.bar === owner)
      Local.Registry.barHost = host
  }

  Component.onCompleted: {
    if (!owner) return
    if (isBar) {
      Local.Registry.bar = owner
      Local.Registry.barHost = host
    } else {
      Local.Registry.register(pluginId, owner)
    }
  }

  Component.onDestruction: {
    if (!owner) return
    if (isBar) {
      if (Local.Registry.bar === owner) {
        Local.Registry.bar = null
        Local.Registry.barHost = null
      }
    } else {
      Local.Registry.unregister(pluginId, owner)
    }
  }
}
