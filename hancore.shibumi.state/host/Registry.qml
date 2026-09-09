pragma Singleton

import QtQuick
import "." as Local

QtObject {
  id: registry

  property var services: ({})
  property var bar: null
  property var barHost: null
  readonly property var catalogue: Local.PluginCatalogue {}

  onBarChanged: catalogue.bar = bar
  onBarHostChanged: catalogue.barHost = barHost

  function register(id, service) {
    const key = String(id || "")
    if (!key || !service || services[key] === service) return
    const next = ({})
    for (const existing in services) next[existing] = services[existing]
    next[key] = service
    services = next
  }

  function unregister(id, service) {
    const key = String(id || "")
    if (!key || services[key] !== service) return
    const next = ({})
    for (const existing in services)
      if (existing !== key) next[existing] = services[existing]
    services = next
  }

  function serviceFor(id) {
    return services[String(id || "")] || null
  }
}
