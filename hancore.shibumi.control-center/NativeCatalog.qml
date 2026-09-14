pragma ComponentBehavior: Bound

import QtQuick
import "NativeCatalogModel.js" as Model

// A process-wide public catalog observation, never a manifest/settings registry.
// Admission comes from the existing Control Center Runtime provider; this local
// component neither imports Runtime nor discovers providers/foreign components.
Item {
  id: root
  required property bool admitted
  required property var sourceToken
  required property string shellDirectory
  property bool demand: false
  property var backendOverride: null
  readonly property bool active: admitted && Qt.isQtObject(sourceToken)
    && demand && shellDirectory !== ""
  readonly property QtObject backend: {
    var candidate = backendOverride !== null ? backendOverride : nativeLoader.item
    return Qt.isQtObject(candidate) ? candidate : null
  }
  readonly property bool backendSupported: {
    try {
      return !!backend && typeof backend.start === "function" && typeof backend.cancel === "function"
        && typeof backend.busy === "boolean" && typeof backend.completed === "function"
        && typeof backend.drained === "function"
    } catch (_) { return false }
  }
  property bool _ready: false
  property bool _refreshing: false
  readonly property alias ready: root._ready
  readonly property alias refreshing: root._refreshing
  property string errorCode: "unavailable"
  property int requestSerial: 0
  property int localGeneration: 0
  property int _epoch: 0
  property var _publication: null
  // Public authority is revoked through _publication. Keep only the last
  // bounded, validated value for content comparison across demand/source/read
  // gaps so an identical recovery cannot manufacture an inventory change.
  property var _retainedSnapshot: null
  property var _operation: null
  // A QObject-typed guard emits loss when a replaced backend is destroyed.
  // A QObject nested only in the plain JS operation record has no such notify.
  readonly property QtObject _drainBackend: _operation && Qt.isQtObject(_operation.backend)
    ? _operation.backend : null
  on_DrainBackendChanged: Qt.callLater(evaluate)
  property bool _wanted: false
  property int _deferred: 0
  // QProcess can deliver final collector/running callbacks after its logical
  // drain. Keep its Loader context alive for one short bounded grace period;
  // admission/publication are still revoked synchronously by invalidate().
  property bool _nativeActive: false
  function deferNativeActivity() { nativeActivityDelay.restart() }
  readonly property var snapshot: _publication ? _publication.snapshot : null
  readonly property int readSerial: _publication ? _publication.serial : 0
  readonly property bool nativeConstructed: nativeLoader.item !== null
  signal settled(int serial, string result)
  signal contentChanged()

  function observation() { return ready && active ? _publication : null }

  function sourceCurrent(op) {
    return active && backendSupported && op.owner === sourceToken && op.backend === backend
      && op.directory === shellDirectory && op.epoch === _epoch
  }

  function current(op) {
    return _operation === op && !op.cancelled && sourceCurrent(op)
  }

  function schedule() {
    _wanted = active
    var token = ++_deferred
    Qt.callLater(function() {
      if (token !== root._deferred || !root._wanted || !root.active) return
      root.refresh()
    })
  }

  function cancelBackend(candidate) {
    try {
      if (Qt.isQtObject(candidate) && typeof candidate.cancel === "function") candidate.cancel()
    } catch (_) {
      // Publication is already revoked. A throwing delegate is not a drain;
      // accepted work remains held until its signal or QObject destruction.
    }
  }

  function invalidate() {
    reconcile.stop()
    _epoch++
    _deferred++
    _ready = false
    _publication = null
    errorCode = "unavailable"
    var op = _operation
    if (op) {
      op.cancelled = true
      cancelBackend(op.backend)
    }
    schedule()
    Qt.callLater(evaluate)
  }

  // Accepted/queued only, not a fresh snapshot or an action postcondition.
  // Unlike refresh()'s immediate attempt this retains one follow-up after drain.
  function requestRefresh() {
    if (!active || !backendSupported || requestSerial >= 2147483647) return false
    var owner = sourceToken, command = backend, epoch = _epoch
    schedule()
    return active && backendSupported && sourceToken === owner && backend === command
      && _epoch === epoch && _wanted
  }

  function refresh() {
    if (!active || !backendSupported || _operation || backend.busy || requestSerial >= 2147483647)
      return false
    var op = { owner: sourceToken, backend: backend, directory: shellDirectory, epoch: _epoch,
      serial: requestSerial + 1, cancelled: false, accepted: false, event: null, drained: false }
    requestSerial = op.serial
    if (_operation || requestSerial !== op.serial || !sourceCurrent(op) || backend.busy) return false
    reconcile.stop()
    _wanted = false
    _operation = op
    _refreshing = true
    if (!current(op)) { Qt.callLater(evaluate); return false }
    try { op.accepted = op.backend.start(op.serial) === true } catch (_) { op.accepted = false }
    Qt.callLater(evaluate)
    return op.accepted && current(op)
  }

  function receive(serial, output, ok) {
    var op = _operation
    if (!op || serial !== op.serial || !current(op)) return
    op.event = { output: output, ok: ok === true }
    // Even an inline replacement must unwind start() before publication.
    Qt.callLater(evaluate)
  }

  function afterOperation() {
    if (_wanted) schedule()
    else if (active && backendSupported && !_operation) reconcile.restart()
  }

  function evaluate() {
    var op = _operation
    if (!op) { if (_wanted) schedule(); return }
    if (!current(op)) {
      // Retain the old backend's exact drain even through A->B->A replacement.
      // No replacement starts until that accepted read drains or its QObject
      // ceases to exist; destroyed objects cannot be reintroduced as the same A.
      if (Qt.isQtObject(op.backend)
          && (op.accepted ? !op.drained : op.backend.busy === true)) return
      _operation = null
      _refreshing = false
      settled(op.serial, "revoked")
      afterOperation()
      return
    }
    if (op.accepted && !op.drained) return
    var value = op.accepted && op.event && op.event.ok ? Model.parse(op.event.output) : null
    if (value) {
      var changed = !Model.same(_retainedSnapshot, value)
      var retained = changed ? value : _retainedSnapshot
      localGeneration++
      if (current(op)) {
        _retainedSnapshot = retained
        if (changed) contentChanged()
      }
      if (current(op)) _publication = Object.freeze({ serial: op.serial,
        generation: localGeneration, snapshot: retained })
      if (current(op)) _ready = true
      if (current(op)) errorCode = ""
    } else {
      _ready = false
      if (current(op)) _publication = null
      if (current(op)) errorCode = "read-failed"
    }
    var result = current(op) ? (value ? "confirmed" : "failed") : "revoked"
    if (_operation !== op) return
    _operation = null
    _refreshing = false
    if (!sourceCurrent(op)) result = "revoked"
    settled(op.serial, result)
    afterOperation()
  }

  onActiveChanged: { invalidate(); deferNativeActivity() }
  onSourceTokenChanged: invalidate()
  onShellDirectoryChanged: invalidate()
  onBackendOverrideChanged: { invalidate(); deferNativeActivity() }
  onBackendChanged: { invalidate() }
  onBackendSupportedChanged: {
    if (!backendSupported) invalidate()
    else if (active) schedule()
  }
  Component.onCompleted: {
    deferNativeActivity()
    if (active) schedule()
  }
  Component.onDestruction: {
    _deferred++
    if (_operation) cancelBackend(_operation.backend)
  }

  Timer {
    id: nativeActivityDelay
    interval: 50
    onTriggered: {
      root._nativeActive = root.active && root.backendOverride === null
      // Keep the released command graph alive through deferred QProcess
      // callbacks. Publication and native authority were already revoked.
    }
  }
  Loader {
    id: nativeLoader
    active: root._nativeActive
    sourceComponent: Component {
      NativeCatalogCommand {
        admitted: root.active
        sourceToken: root.sourceToken
        shellDirectory: root.shellDirectory
      }
    }
  }
  Connections {
    target: root._drainBackend || root.backend
    ignoreUnknownSignals: true
    function onCompleted(serial, output, ok) { root.receive(serial, output, ok) }
    function onDrained(serial) {
      var op = root._operation
      if (op && op.serial === serial) op.drained = true
      Qt.callLater(root.evaluate)
    }
  }
  // No complete native catalog subscription: async Bar fallback can change its
  // DTO without registry/config hints. Wait 5s AFTER drain (including failures),
  // never tick while a read runs. Explicit action refreshes coalesce separately.
  // Final demand/owner loss stops this UI/structural-consumer-owned work.
  Timer {
    id: reconcile
    interval: 5000
    repeat: false
    onTriggered: root.requestRefresh()
  }
}
