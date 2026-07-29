pragma ComponentBehavior: Bound

import QtQuick

// Process-wide observable audio snapshot. The official Quattro audio widget
// remains the PipeWire and action owner; screen-local Shibumi widgets only
// report the state they already consume from that owner.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var reports: []
  property bool ready: false
  property bool outputMuted: false

  visible: false
  width: 0
  height: 0

  function report(owner, available, muted) {
    if (!owner) return false
    const next = reports.filter(entry => entry.owner !== owner)
    next.push({ owner: owner, ready: available === true, muted: muted === true })
    reports = next
    syncSnapshot()
    return true
  }

  function release(owner) {
    if (!owner) return false
    const next = reports.filter(entry => entry.owner !== owner)
    if (next.length === reports.length) return false
    reports = next
    syncSnapshot()
    return true
  }

  function syncSnapshot() {
    for (let index = 0; index < reports.length; index++) {
      if (!reports[index].ready) continue
      ready = true
      outputMuted = reports[index].muted
      return
    }
    ready = false
    outputMuted = false
  }
}
