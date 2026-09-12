pragma ComponentBehavior: Bound

import QtQuick

QtObject {
  id: root

  property bool running: false
  property bool scopedHost: true
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
  property int catalogConsumerCount: 0
  property int catalogAcquireCount: 0
  property int catalogReleaseCount: 0
  property int catalogWrongReleaseCount: 0
  property int catalogRefreshCount: 0
  property var catalogToken: null
  property var catalogHolder: null
  property var currentCatalogObservation: null
  readonly property bool catalogReady: currentCatalogObservation !== null
  readonly property int catalogReadSerial: catalogReady
    ? Number(currentCatalogObservation.serial || 0) : 0
  readonly property int catalogGeneration: catalogReady
    ? Number(currentCatalogObservation.generation || 0) : 0
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

  Component.onCompleted: {
    const row = Object.freeze({id: "fixture.native-widget", name: "Native Fixture",
      kinds: Object.freeze(["bar-widget"]), enabled: false, active: false,
      canDisable: true, firstParty: false, clonedFrom: "",
      description: "Searchable native fixture metadata", author: "Fixture Author",
      version: "1.2.3", tags: Object.freeze(["native", "searchable"]),
      barWidget: Object.freeze({displayName: "Native Fixture",
        description: "Searchable widget description", category: "Fixture",
        semanticCapabilities: Object.freeze([]), defaultSection: "left",
        allowMultiple: false})})
    const entries = Object.freeze([row])
    const byIdValue = Object.create(null)
    byIdValue[row.id] = row
    const byId = Object.freeze(byIdValue)
    currentCatalogObservation = Object.freeze({
      serial: 1,
      generation: 1,
      snapshot: Object.freeze({
        catalogKind: "native-listPlugins",
        entries: entries,
        byId: byId
      })
    })
  }

  function acquireCatalogConsumer(holder) {
    if (!Qt.isQtObject(holder)) return null
    if (catalogToken && catalogHolder === holder) return catalogToken
    if (catalogToken) return null
    catalogAcquireCount++
    catalogConsumerCount = 1
    catalogHolder = holder
    catalogToken = Object.freeze({ serial: catalogAcquireCount })
    return catalogToken
  }

  function releaseCatalogConsumer(token) {
    if (!catalogToken || token !== catalogToken) {
      catalogWrongReleaseCount++
      return false
    }
    catalogReleaseCount++
    catalogConsumerCount = 0
    catalogToken = null
    catalogHolder = null
    return true
  }

  function hasCatalogConsumer(token) {
    return catalogToken !== null && token === catalogToken
  }

  function catalogObservation(token) {
    return hasCatalogConsumer(token) ? currentCatalogObservation : null
  }

  function isCatalogObservationCurrent(token, observation) {
    return hasCatalogConsumer(token)
      && observation !== null && observation === currentCatalogObservation
  }

  function requestCatalogRefresh(token) {
    if (!hasCatalogConsumer(token)) return false
    catalogRefreshCount++
    return true
  }

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
