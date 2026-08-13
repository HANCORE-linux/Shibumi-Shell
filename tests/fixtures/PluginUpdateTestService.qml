pragma ComponentBehavior: Bound

import QtQuick

QtObject {
  id: root

  property bool running: false
  property bool checked: false
  property int updateCount: 0
  property int checkedCount: 0
  property int unmanagedCount: 0
  property int failedCount: 0
  property string error: ""
  property int checkCount: 0
  property int invalidationCount: 0
  property int observedPluginRevision: -1
  property int consumerCount: 0
  readonly property string shortStatusText: running ? "checking…"
    : error !== "" ? "check failed"
    : !checked ? "not checked"
    : updateCount === 1 ? "1 available" : updateCount + " available"
  readonly property string statusText: running
    ? "Checking third-party plugins…"
    : error !== "" ? error
      : checked ? (updateCount === 1
        ? "1 update available" : updateCount + " updates available")
      : "Check third-party plugins for updates"

  function acquireConsumer() {
    consumerCount++
    Qt.callLater(function() { root.check(false) })
    return true
  }

  function releaseConsumer() {
    if (consumerCount <= 0) return false
    consumerCount--
    return true
  }

  function check(force) {
    if (running || (force !== true && checked)) return false
    checkCount++
    checked = true
    updateCount = 2
    checkedCount = 3
    return true
  }

  function observePluginRevision(revision, rescan) {
    const next = Number(revision)
    if (observedPluginRevision < 0) {
      observedPluginRevision = next
      return false
    }
    if (observedPluginRevision === next) return false
    observedPluginRevision = next
    invalidate(rescan === true)
    return true
  }

  function invalidate(rescan) {
    invalidationCount++
    checked = false
    return true
  }
}
