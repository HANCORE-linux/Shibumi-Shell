pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../hancore.shibumi.state/runtime" as SuiteRuntime

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  readonly property bool hostObject: Qt.isQtObject(shell)
  readonly property bool scopedHost: hostObject && "pluginId" in shell
  readonly property bool available: hostObject
    && (!scopedHost || runtimeProvider.registered)
  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.control-center"
    implementationVersion: "0.1.1-beta.12"
    owner: root
    host: root.shell
    manifest: root.manifest
  }
  readonly property int pluginRevision: scopedHost
    ? (barWidgetRegistry ? Number(barWidgetRegistry.revision || 0) : 0)
    : pluginRegistry ? Number(pluginRegistry.registryRevision || 0) : 0
  // Read interest is independent of update scans and their network workers.
  // Only this existing admitted provider owns the process-wide native catalog.
  property var _catalogBackendOverride: null
  CatalogDemand { id: catalogDemand }
  NativeCatalog {
    id: nativeCatalog
    admitted: root.available && root.scopedHost
    sourceToken: root.shell
    shellDirectory: root.omarchyPath !== "" ? root.omarchyPath + "/shell" : ""
    demand: catalogDemand.count > 0
    backendOverride: root._catalogBackendOverride
    onSettled: (serial, result) => root.catalogSettled(serial, result)
  }
  readonly property alias catalogConsumerCount: catalogDemand.count
  readonly property bool catalogReady: nativeCatalog.observation() !== null
  readonly property alias catalogRefreshing: nativeCatalog.refreshing
  readonly property alias catalogErrorCode: nativeCatalog.errorCode
  readonly property alias catalogRequestSerial: nativeCatalog.requestSerial
  readonly property alias catalogReadSerial: nativeCatalog.readSerial
  readonly property alias catalogGeneration: nativeCatalog.localGeneration
  readonly property var catalogSnapshot: catalogReady ? nativeCatalog.snapshot : null
  // Primitive diagnostic, never the native command/registry object itself.
  readonly property alias catalogNativeConstructed: nativeCatalog.nativeConstructed
  signal catalogSettled(int serial, string result)

  function acquireCatalogConsumer(holder) { return catalogDemand.acquire(holder) }
  function releaseCatalogConsumer(token) { return catalogDemand.release(token) }
  function hasCatalogConsumer(token) { return catalogDemand.has(token) }
  function catalogObservation(token) {
    return catalogDemand.has(token) ? nativeCatalog.observation() : null
  }
  function isCatalogObservationCurrent(token, observation) {
    return observation !== null && catalogObservation(token) === observation
  }
  // Acceptance coalesces a future read; it is not a native mutation postcondition.
  function requestCatalogRefresh(token) {
    return catalogDemand.has(token) && nativeCatalog.requestRefresh()
  }
  // PluginShellApi.barConfigChanged is a public non-authoritative change hint.
  Connections {
    target: root.available && root.catalogConsumerCount > 0 && root.scopedHost
      && Qt.isQtObject(root.shell) ? root.shell : null
    ignoreUnknownSignals: true
    function onBarConfigChanged() { nativeCatalog.requestRefresh() }
  }
  Connections {
    target: root.available && root.catalogConsumerCount > 0 && root.scopedHost
      && Qt.isQtObject(root.barWidgetRegistry) ? root.barWidgetRegistry : null
    ignoreUnknownSignals: true
    function onRevisionChanged() { nativeCatalog.requestRefresh() }
  }

  readonly property string command: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/hancore.shibumi.control-center"
    + "/manager/shibumi-plugin-updates"
  readonly property bool running: scanActive
  property bool checked: false
  property int updateCount: 0
  property int checkedCount: 0
  property int unmanagedCount: 0
  property int failedCount: 0
  property string error: ""
  property double checkedAt: 0
  property bool rerunRequested: false
  property int timeoutSeconds: 45
  property int observedPluginRevision: -1
  property int invalidationEpoch: 0
  property int scanEpoch: -1
  property bool scanActive: false
  property bool scanStarted: false
  property int scanGeneration: 0
  property int consumerCount: 0
  property bool cancellationRequested: false
  property int rerunToken: 0
  readonly property string shortStatusText: running ? "checking…"
    : error !== "" ? "check failed"
    : !checked ? "not checked"
    : updateCount === 1 ? "1 available"
    : updateCount + " available"
  readonly property string statusText: {
    if (running) return "Checking third-party plugins…"
    if (error !== "") return error
    if (!checked) return "Check third-party plugins for updates"
    const checkedLabel = checkedCount === 1
      ? "1 Git plugin checked" : checkedCount + " Git plugins checked"
    const unmanagedLabel = unmanagedCount === 0 ? ""
      : "; " + unmanagedCount + " not Git-managed"
    const failedLabel = failedCount === 0 ? ""
      : "; " + failedCount + " could not be checked"
    if (updateCount === 0)
      return (failedCount > 0 ? "No updates found" : "Up to date")
        + " — " + checkedLabel + unmanagedLabel + failedLabel
    return (updateCount === 1 ? "1 update available"
      : updateCount + " updates available")
      + " — " + checkedLabel + unmanagedLabel + failedLabel
  }

  width: 0
  height: 0
  visible: false

  Component.onCompleted: observePluginRevision(pluginRevision, false)
  onPluginRevisionChanged:
    observePluginRevision(pluginRevision, consumerCount > 0)
  onAvailableChanged: {
    if (available) {
      if (consumerCount > 0) scheduleRerun()
      return
    }
    rerunToken++
    rerunRequested = false
    invalidationEpoch++
    clearResult()
    if (running) {
      cancellationRequested = true
      updateCheck.running = false
    }
  }

  function clearResult() {
    checked = false
    updateCount = 0
    checkedCount = 0
    unmanagedCount = 0
    failedCount = 0
    error = ""
    checkedAt = 0
  }

  function acquireConsumer() {
    consumerCount++
    if (cancellationRequested) {
      rerunRequested = true
      rerunToken++
      return false
    }
    return check(false)
  }

  function releaseConsumer() {
    if (consumerCount <= 0) return false
    consumerCount--
    if (consumerCount > 0) return true
    rerunToken++
    rerunRequested = false
    if (!running) return true
    cancellationRequested = true
    checkedAt = 0
    updateCheck.running = false
    return true
  }

  function scheduleRerun() {
    rerunRequested = true
    const token = ++rerunToken
    Qt.callLater(function() {
      if (token !== root.rerunToken || !root.rerunRequested
          || root.consumerCount <= 0 || root.running) return
      root.rerunRequested = false
      root.check(true)
    })
  }

  function observePluginRevision(revision, rescan) {
    // Legacy callers may carry a different registry-counter domain.
    const next = Number(scopedHost ? pluginRevision : revision)
    if (!isFinite(next) || Math.floor(next) !== next) return false
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
    checkedAt = 0
    invalidationEpoch++
    if (running) {
      clearResult()
      rerunRequested = rescan === true
      return false
    }
    if (rescan !== true) return true
    clearResult()
    return check(true)
  }

  function parseCount(output, key) {
    const prefix = key + "="
    const lines = String(output || "").split("\n")
    let found = -1
    for (let index = 0; index < lines.length; index++) {
      if (lines[index].indexOf(prefix) !== 0) continue
      if (found >= 0) return -1
      const raw = lines[index].slice(prefix.length)
      if (!/^\d+$/.test(raw)) return -1
      const value = Number(raw)
      if (!isFinite(value) || Math.floor(value) !== value
          || value > 2147483647) return -1
      found = value
    }
    return found
  }

  function settleUnstartedScan(generation) {
    if (generation !== scanGeneration || !scanActive || scanStarted) return false
    scanStartDeadline.stop()
    const cancelled = cancellationRequested
    cancellationRequested = false
    clearResult()
    if (!cancelled && available) error = "Plugin update check failed"
    scanEpoch = -1
    scanActive = false
    if (rerunRequested && consumerCount > 0) scheduleRerun()
    else if (consumerCount === 0) rerunRequested = false
    return true
  }

  function check(force) {
    if (!available || running || command === "") return false
    const maxAgeMs = 5 * 60 * 1000
    const ageMs = Date.now() - checkedAt
    if (force !== true && checkedAt > 0
        && ageMs >= 0 && ageMs < maxAgeMs) return false
    error = ""
    scanEpoch = invalidationEpoch
    const boundedTimeout = Math.max(1, Math.min(45,
      Math.floor(Number(timeoutSeconds || 45))))
    updateCheck.command = [
      "timeout", "--signal=TERM", "--kill-after=2s",
      boundedTimeout + "s", command, "--list"
    ]
    scanStarted = false
    scanGeneration++
    scanActive = true
    updateCheck.running = true
    scanStartDeadline.generation = scanGeneration
    scanStartDeadline.restart()
    return true
  }

  Timer {
    id: scanStartDeadline
    property int generation: 0
    interval: 1000
    onTriggered: {
      if (generation !== root.scanGeneration
          || !root.scanActive || root.scanStarted) return
      updateCheck.running = false
      root.settleUnstartedScan(generation)
    }
  }

  Process {
    id: updateCheck
    running: false
    onStarted: {
      if (!root.scanActive) {
        running = false
        return
      }
      root.scanStarted = true
      scanStartDeadline.stop()
    }
    onRunningChanged: {
      if (!running && root.scanActive && !root.scanStarted) {
        const generation = root.scanGeneration
        Qt.callLater(function() { root.settleUnstartedScan(generation) })
      }
    }
    stdout: StdioCollector {
      id: updateStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function(exitCode) {
      scanStartDeadline.stop()
      const output = updateStdout.text
      const finishedEpoch = root.scanEpoch
      if (root.cancellationRequested) {
        root.cancellationRequested = false
        root.clearResult()
        root.scanEpoch = -1
        root.scanStarted = false
        root.scanActive = false
        if (root.rerunRequested && root.consumerCount > 0) {
          root.scheduleRerun()
        }
        return
      }
      const stale = finishedEpoch !== root.invalidationEpoch
      if (stale) {
        root.clearResult()
        if (root.consumerCount > 0 && root.rerunRequested !== false)
          root.rerunRequested = true
      } else if (exitCode !== 0) {
        root.clearResult()
        root.error = exitCode === 124
          ? "Plugin update check timed out"
          : "Plugin update check failed"
      } else {
        const updateValue = root.parseCount(output, "PLUGIN_UPDATE_COUNT")
        const checkedValue = root.parseCount(output, "PLUGIN_CHECKED_COUNT")
        const unmanagedValue = root.parseCount(
          output, "PLUGIN_UNMANAGED_COUNT")
        const failedValue = root.parseCount(
          output, "PLUGIN_FETCH_FAILED_COUNT")
        if (updateValue < 0 || checkedValue < 0
            || unmanagedValue < 0 || failedValue < 0
            || updateValue > checkedValue) {
          root.clearResult()
          root.error = "Plugin update check returned invalid data"
        } else {
          root.updateCount = updateValue
          root.checkedCount = checkedValue
          root.unmanagedCount = unmanagedValue
          root.failedCount = failedValue
          root.checked = true
          root.checkedAt = finishedEpoch === root.invalidationEpoch
            ? Date.now() : 0
          root.error = ""
        }
      }
      if (root.scanEpoch !== finishedEpoch) return
      root.scanEpoch = -1
      root.scanStarted = false
      root.scanActive = false
      if (root.rerunRequested && root.consumerCount > 0) {
        root.scheduleRerun()
      } else if (root.consumerCount === 0) {
        root.rerunRequested = false
      }
    }
  }
}
