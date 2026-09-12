pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Cooperative suite wiring, not a QML security boundary. Native backends and
// their workers stay in their existing service owners. No host discovery here.
QtObject {
  id: runtime

  readonly property int contractVersion: 1
  readonly property string suiteVersion: "0.1.1-beta.13"
  readonly property var providerIds: [
    "hancore.shibumi.state", "hancore.shibumi.control-center",
    "hancore.shibumi.reactor", "hancore.shibumi.telemetry",
    "hancore.shibumi.power-state", "hancore.shibumi.workspaces",
    "hancore.shibumi.update-center", "hancore.shibumi.status",
    "hancore.shibumi.cpu", "hancore.shibumi.audio", "hancore.shibumi.ai",
    "hancore.shibumi.center", "hancore.shibumi.media",
    "hancore.shibumi.quick-access", "hancore.shibumi.network",
    "hancore.shibumi.brightness", "hancore.shibumi.bluetooth",
    "hancore.shibumi.storage"
  ]
  property string payloadDigest: ""
  property bool retired: false
  readonly property bool ready: !retired && /^[0-9a-f]{64}$/.test(payloadDigest)
  property int revision: 0
  property int nextSerial: 0
  // Internal coordination only. Underscores are API conventions, not access
  // control: QML imports are cooperative, not a sandbox.
  property var _leases: []
  // Omarchy 4.0.3's first registry generation can revoke a configured
  // bar-only widget on the first shell.json mutation. Prime that public host
  // registry exactly once per Quickshell process, before the Bar is admitted.
  property string hostRegistryPrimePhase: "idle"
  property int hostRegistryPrimePid: 0
  property int hostRegistryPrimeAttemptCount: 0
  property int hostRegistryPrimeRevision: 0
  property int hostRegistryPrimeTimeoutMs: 7000
  property var _hostRegistryPrimeInitialOwner: null
  property int _hostRegistryPrimeInitialSerial: 0
  property bool _hostRegistryPrimeAcknowledged: false
  property var _hostRegistryPrimeReplacementOwner: null
  readonly property bool hasActiveBar: _selected("hancore.shibumi.bar") !== null
  readonly property var publishedBarConfig: {
    const lease = _selected("hancore.shibumi.bar")
    if (!lease || lease.owner.injectionComplete !== true
        || !plain(lease.owner.barConfig)
        || lease.owner.barConfig.id !== lease.id) return null
    // This is the full bar's documented host-injected snapshot, not its
    // mutable layout/view state. Do not expose the owner's data by reference.
    try { return JSON.parse(JSON.stringify(lease.owner.barConfig)) }
    catch (error) { return null }
  }

  function plain(value) {
    return !!value && typeof value === "object" && !Array.isArray(value)
  }

  function equalJson(left, right, depth) {
    if (depth > 64) return false
    if (left === right) return true
    if (!left || !right || typeof left !== "object" || typeof right !== "object"
        || Array.isArray(left) !== Array.isArray(right)) return false
    const keys = Object.keys(left)
    if (keys.length !== Object.keys(right).length) return false
    for (const key of keys) {
      if (!Object.prototype.hasOwnProperty.call(right, key)
          || !equalJson(left[key], right[key], depth + 1)) return false
    }
    return true
  }

  function same(left, right) {
    // QVariantMap sorts object keys during initial native injection. Object
    // order is not a configuration change; array order and every value are.
    try {
      return equalJson(JSON.parse(JSON.stringify(left)), JSON.parse(JSON.stringify(right)), 0)
    } catch (error) { return false }
  }

  function captureMarker(text) {
    if (retired) return
    try {
      const marker = JSON.parse(String(text || ""))
      const digest = String(marker.suitePayloadDigest || "")
      if (marker.suiteId !== "hancore.shibumi" || !/^[0-9a-f]{64}$/.test(digest)) {
        retire()
        return
      }
      if (payloadDigest && payloadDigest !== digest) {
        retire()
        return
      }
      payloadDigest = digest
    } catch (error) { retire() }
  }

  function retire() {
    retired = true
    payloadDigest = ""
    _leases = []
    hostRegistryPrimeDeadline.stop()
    if (["dispatching", "acknowledged"].indexOf(
        hostRegistryPrimePhase) >= 0) {
      hostRegistryPrimePhase = "failed"
      hostRegistryPrimeRevision++
    }
    if (hostRegistryPrimeProcess.running)
      hostRegistryPrimeProcess.running = false
    revision++
  }

  function scopedBarLease(owner) {
    const lease = _selected("hancore.shibumi.bar")
    return lease && lease.owner === owner && lease.host
        && "pluginId" in lease.host
        && lease.host.pluginId === "hancore.shibumi.bar"
      ? lease : null
  }

  function hostRegistryPrimeReadyFor(owner, processId) {
    void(hostRegistryPrimeRevision)
    return hostRegistryPrimePhase === "ready"
      && hostRegistryPrimePid === processId
      && processId === Quickshell.processId
      && scopedBarLease(owner) !== null
  }

  function evaluateHostRegistryPrime() {
    if (["dispatching", "acknowledged"].indexOf(
        hostRegistryPrimePhase) < 0) return
    const lease = _selected("hancore.shibumi.bar")
    if (lease && lease.serial > _hostRegistryPrimeInitialSerial
        && lease.owner !== _hostRegistryPrimeInitialOwner)
      _hostRegistryPrimeReplacementOwner = lease.owner
    if (!_hostRegistryPrimeAcknowledged
        || !_hostRegistryPrimeReplacementOwner || !lease
        || lease.owner !== _hostRegistryPrimeReplacementOwner) return
    hostRegistryPrimeDeadline.stop()
    hostRegistryPrimePhase = "ready"
    hostRegistryPrimeRevision++
  }

  function failHostRegistryPrime() {
    if (["dispatching", "acknowledged"].indexOf(
        hostRegistryPrimePhase) < 0) return
    hostRegistryPrimeDeadline.stop()
    hostRegistryPrimePhase = "failed"
    hostRegistryPrimeRevision++
    if (hostRegistryPrimeProcess.running)
      hostRegistryPrimeProcess.running = false
  }

  function requestHostRegistryPrime(owner, processId) {
    const pid = Number(processId)
    const lease = scopedBarLease(owner)
    if (!ready || !lease
        || serviceFor("hancore.shibumi.state") === null
        || !Number.isInteger(pid) || pid <= 1
        || pid !== Quickshell.processId) return false
    if (hostRegistryPrimePhase === "ready")
      return hostRegistryPrimeReadyFor(owner, pid)
    if (hostRegistryPrimePhase !== "idle"
        || hostRegistryPrimeAttemptCount !== 0
        || hostRegistryPrimePid !== 0) {
      evaluateHostRegistryPrime()
      return hostRegistryPrimeReadyFor(owner, pid)
    }

    hostRegistryPrimePid = pid
    hostRegistryPrimeAttemptCount = 1
    _hostRegistryPrimeInitialOwner = owner
    _hostRegistryPrimeInitialSerial = lease.serial
    _hostRegistryPrimeAcknowledged = false
    _hostRegistryPrimeReplacementOwner = null
    // Publish the one-shot claim before dispatch. The expected plugin-Bar
    // rebuild destroys its requester synchronously.
    hostRegistryPrimePhase = "dispatching"
    hostRegistryPrimeRevision++
    hostRegistryPrimeDeadline.interval = hostRegistryPrimeTimeoutMs
    hostRegistryPrimeDeadline.restart()
    hostRegistryPrimeProcess.command = [
      "/usr/bin/quickshell", "ipc", "--pid", String(pid),
      "call", "--", "shell", "rescanPlugins"
    ]
    hostRegistryPrimeProcess.running = true
    return false
  }

  property Process hostRegistryPrimeProcess: Process {
    running: false
    onExited: function(exitCode, _exitStatus) {
      if (runtime.hostRegistryPrimePhase !== "dispatching") return
      if (exitCode !== 0) {
        runtime.failHostRegistryPrime()
        return
      }
      runtime._hostRegistryPrimeAcknowledged = true
      runtime.hostRegistryPrimePhase = "acknowledged"
      runtime.hostRegistryPrimeRevision++
      runtime.evaluateHostRegistryPrime()
    }
  }

  property Timer hostRegistryPrimeDeadline: Timer {
    interval: runtime.hostRegistryPrimeTimeoutMs
    repeat: false
    onTriggered: runtime.failHostRegistryPrime()
  }

  function validLease(lease) {
    return ready && lease && lease.owner && lease.host
      && lease.digest === payloadDigest && lease.version === suiteVersion
  }

  function _selected(id) {
    void(revision)
    let result = null
    for (const lease of _leases) {
      if (lease.id !== id || !validLease(lease)) continue
      // Overlapping lifetimes are unavailable, never last-writer-wins.
      if (result) return null
      result = lease
    }
    return result
  }

  function isActiveBar(owner) {
    const lease = _selected("hancore.shibumi.bar")
    return !!lease && lease.owner === owner
  }

  function providerRecord(id, owner, host, manifest, version) {
    const key = String(id || "")
    if (!ready || !owner || !host || typeof owner !== "object"
        || typeof host !== "object" || version !== suiteVersion
        || !plain(manifest) || manifest.id !== key || manifest.version !== version) return null
    // createObject(initialProperties) can marshal an array as a QVariantList.
    // Detach JSON metadata before checking its shape; don't treat arbitrary
    // array-like objects as arrays or infer kinds from truthiness.
    let kinds
    try { kinds = JSON.parse(JSON.stringify(manifest.kinds)) }
    catch (error) { return null }
    if (!Array.isArray(kinds) || kinds.length > 6) return null
    const kind = key === "hancore.shibumi.bar" ? "bar" : "service"
    if (kind === "service" && providerIds.indexOf(key) < 0) return null
    if (kinds.indexOf(kind) < 0) return null
    if ("pluginId" in host && host.pluginId !== key) return null
    return { id: key, owner: owner, host: host, version: version,
      digest: payloadDigest }
  }

  function refreshProvider(previous, id, owner, host, manifest, version) {
    let next = null
    try { next = providerRecord(id, owner, host, manifest, version) }
    catch (error) { next = null } // Invalid new input must revoke the old lease.
    const current = _leases.indexOf(previous) >= 0 ? previous : null
    const others = _leases.filter(function(lease) { return lease !== current })
    if (others.some(function(lease) { return lease.owner === owner })) next = null
    // Native config publication refreshes retained manifests synchronously.
    // Equivalent metadata is the same provider lifetime, not a revocation.
    if (next && current && current.id === next.id && current.owner === next.owner
        && current.host === next.host && current.version === next.version
        && current.digest === next.digest) return current
    if (next) next.serial = ++nextSerial
    if (current || next) {
      // Publish only the final set. Removing then adding would briefly make
      // an overlapping provider selectable in synchronous signal handlers.
      _leases = next ? others.concat([next]) : others
      revision++
      evaluateHostRegistryPrime()
    }
    return next
  }

  function unregisterProvider(lease) {
    if (!lease || _leases.indexOf(lease) < 0) return
    _leases = _leases.filter(function(current) { return current !== lease })
    revision++
    evaluateHostRegistryPrime()
  }

  function serviceFor(id) {
    const key = String(id || "")
    if (providerIds.indexOf(key) < 0) return null
    const lease = _selected(key)
    return lease ? lease.owner : null
  }

  function firstPartyServiceFor(id) {
    const key = String(id || "")
    if (["omarchy.idle", "omarchy.media", "omarchy.notifications"].indexOf(key) < 0) return null
    const lease = _selected("hancore.shibumi.bar")
    return lease && typeof lease.host.firstPartyServiceFor === "function"
      ? lease.host.firstPartyServiceFor(key) : null
  }

  property FileView marker: FileView {
    path: {
      const url = String(Qt.resolvedUrl("../.shibumi-managed.json"))
      if (url.indexOf("file:///") !== 0) return ""
      try { return decodeURIComponent(url.substring(7)) } catch (error) { return "" }
    }
    watchChanges: true
    printErrors: false
    onLoaded: runtime.captureMarker(text())
    onLoadFailed: runtime.retire()
    // An installed generation never upgrades itself in a running engine.
    // Transactional updates drain the shell before publishing new bytes.
    onFileChanged: runtime.retire()
  }
}
