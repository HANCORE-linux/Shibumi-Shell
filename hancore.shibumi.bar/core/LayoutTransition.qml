pragma ComponentBehavior: Bound

import QtQuick

// One Bar-owned State -> native-layout operation. This is cooperative sequencing,
// not a cross-store transaction or a filesystem/native compare-and-swap.
Item {
  id: root
  required property var stateService
  required property var nativeWriter
  required property var observedBarConfig
  required property var planNativeLayout
  property var validateNativeLayout: null
  required property bool admitted
  property int stateTimeoutMs: 5000
  property int nativeTimeoutMs: 2500
  property var operation: null
  property int requestSerial: 0
  property string lastResult: "idle"
  property bool _busy: false
  property string _phase: "idle"
  readonly property alias busy: root._busy
  readonly property alias phase: root._phase
  readonly property bool supported: !!stateService
    && typeof stateService.normalizedLayoutFamilyPatch === "function"
    && typeof stateService.layoutFamilySnapshot === "function"
    && typeof stateService.setLayoutFamilyTransition === "function"
    && typeof stateService.compensateLayoutFamilyTransition === "function"
    && typeof stateService.same === "function"
    && "writeSerial" in stateService && "writePending" in stateService
  signal settledContext(int serial, string result, var context)
  signal settled(int serial, string result)
  visible: false
  width: 0
  height: 0

  function same(a, b) { return supported && stateService.same(a, b) }
  function copy(value) { return JSON.parse(JSON.stringify(value)) }
  function stateOnlyIntent(value) {
    return value && value.kind === "state-only"
  }
  function current(op) {
    return op && operation === op && !op.finishing && admitted && supported
      && stateService === op.writer && op.writer.ready === true
      && nativeWriter === op.nativeWriter
  }
  function stableState(op, patch) {
    return current(op) && op.writer.writePending === false && op.writer.writeSerial === op.serial
      && same(op.writer.layoutFamilySnapshot(patch), patch)
  }
  function stage(op, value, timeout) {
    if (!current(op)) return false
    op.stage = value
    deadline.stop()
    deadline.interval = timeout
    deadline.start()
    _phase = value
    return current(op)
  }
  function finish(op, result) {
    if (!op || operation !== op || op.finishing) return
    op.finishing = true
    deadline.stop()
    deferred.stop()
    op.dispatchDeferred = false
    op.evaluationDeferred = false
    lastResult = result
    operation = null // Publish loss before callbacks; newer requests own their state.
    _phase = "idle"
    _busy = false
    settledContext(op.id, result, {
      intent: copy(op.intent),
      patch: copy(op.patch),
      before: copy(op.before),
      nativeBefore: op.nativeBefore === undefined
        ? null : copy(op.nativeBefore),
      nativeAfter: op.nativeAfter === undefined
        ? null : copy(op.nativeAfter)
    })
    settled(op.id, result)
  }
  function revoke() {
    const op = operation
    if (op && !current(op)) finish(op, "revoked")
  }
  onAdmittedChanged: revoke()
  onStateServiceChanged: revoke()
  onNativeWriterChanged: revoke()
  onSupportedChanged: revoke()
  onObservedBarConfigChanged: deferEvaluation()

  function request(patchValue, intentValue) {
    const stateOnly = stateOnlyIntent(intentValue)
    if (operation !== null || busy || !admitted || !supported || stateService.ready !== true || stateService.writePending !== false
        || !Number.isInteger(stateService.writeSerial)
        || (!stateOnly && (!nativeWriter
          || typeof nativeWriter.mutateShellConfig !== "function"
          || typeof planNativeLayout !== "function"))) return false
    const patch = stateService.normalizedLayoutFamilyPatch(patchValue)
    const before = patch ? stateService.layoutFamilySnapshot(patch) : null
    if (!patch || !before) return false
    const op = {id: requestSerial + 1, writer: stateService, nativeWriter: nativeWriter,
      serial: stateService.writeSerial, before: before, patch: patch, intent: copy(intentValue),
      stage: "preparing", event: null, finishing: false, nativeChanged: false}
    requestSerial = op.id
    // A serial notification may itself submit another request. Never replace it.
    if (busy || requestSerial !== op.id || !admitted || stateService !== op.writer || nativeWriter !== op.nativeWriter
        || op.writer.ready !== true || op.writer.writePending !== false || op.writer.writeSerial !== op.serial) return false
    operation = op
    if (!current(op)) { finish(op, "revoked"); return false }
    _busy = true
    if (!stableState(op, before)) { finish(op, "conflict"); return false }
    if (same(before, patch)) {
      if (!stage(op, "native-ready", nativeTimeoutMs)) return false
      deferDispatch(op)
      return current(op)
    }
    return queueState(op, false)
  }

  function queueState(op, compensation) {
    const previousSerial = op.serial
    op.serial++
    op.event = null
    if (!stage(op, compensation ? "queue-compensation" : "queue-state", stateTimeoutMs)) return false
    // The phase notification must not allow a competing request to become ours.
    if (op.writer.writePending !== false || op.writer.writeSerial !== previousSerial
        || !same(op.writer.layoutFamilySnapshot(compensation ? op.patch : op.before),
          compensation ? op.patch : op.before)) {
      finish(op, "conflict"); return false
    }
    let accepted = false
    try {
      accepted = compensation
        ? op.writer.compensateLayoutFamilyTransition(previousSerial, op.patch, op.before) === true
        : op.writer.setLayoutFamilyTransition(op.patch) === true
    } catch (error) {
      finish(op, compensation ? "compensation-refused" : "state-refused")
      return false
    }
    if (!current(op)) return false
    if (!accepted || op.writer.writeSerial !== op.serial) {
      finish(op, compensation ? "compensation-refused" : "state-refused")
      return false
    }
    if (!stage(op, compensation ? "wait-compensation" : "wait-state", stateTimeoutMs)) return false
    deferEvaluation()
    return current(op)
  }

  function observeSettlement(serial, result) {
    const op = operation
    if (!current(op) || serial !== op.serial) return
    if (["queue-state", "wait-state", "queue-compensation", "wait-compensation"].indexOf(op.stage) < 0) return
    op.event = {serial: serial, result: result}
    // Completion can be synchronous inside queue(). Never run native work inside
    // State dispatch or before its property/binding notifications unwind.
    deferEvaluation()
  }
  function deferDispatch(op) {
    if (operation !== op || op.finishing) return
    op.dispatchDeferred = true
    deferred.restart()
  }
  function deferEvaluation() {
    const op = operation
    if (!op || op.finishing) return
    op.evaluationDeferred = true
    deferred.restart()
  }
  function evaluate(op) {
    if (operation !== op) return
    if (!current(op)) { finish(op, "revoked"); return }
    if (op.stage === "wait-state" || op.stage === "wait-compensation") {
      if (op.writer.writeSerial !== op.serial) { finish(op, "conflict"); return }
      if (!op.event || op.event.serial !== op.serial) return
      const rollback = op.stage === "wait-compensation"
      if (["confirmed", "unchanged"].indexOf(op.event.result) < 0
          || !stableState(op, rollback ? op.before : op.patch)) {
        finish(op, rollback ? "compensation-refused" : "state-refused"); return
      }
      if (rollback) { finish(op, "compensated"); return }
      if (stage(op, "native-ready", nativeTimeoutMs))
        deferDispatch(op)
    } else if (op.stage === "native-ready" || op.stage === "wait-native") {
      if (!stableState(op, op.patch)) { finish(op, "conflict"); return }
      if (op.stage === "wait-native" && same(observedBarConfig, op.expected))
        finish(op, op.nativeChanged || !same(op.before, op.patch) ? "confirmed" : "unchanged")
    }
  }

  function dispatchNative(op) {
    if (!current(op) || op.stage !== "native-ready") return
    if (!stableState(op, op.patch)) { finish(op, "conflict"); return }
    if (stateOnlyIntent(op.intent)) {
      finish(op, same(op.before, op.patch) ? "unchanged" : "confirmed")
      return
    }
    // A target already present in the injected view needs no native write.
    // In particular, background reconciliation must not perpetually republish
    // an unchanged Bar and trigger another registry notification/reconcile.
    const observed = observedBarConfig
    try {
      if (observed && observed.layout !== undefined)
        op.nativeBefore = copy(observed.layout)
      const present = planNativeLayout(observed ? observed.layout : null, op.intent)
      if (present && (typeof validateNativeLayout !== "function"
          || validateNativeLayout(observed.layout, op.intent, op.patch) === true)
          && same(present, observed.layout) && observedBarConfig === observed
          && stableState(op, op.patch)) {
        op.nativeAfter = copy(observed.layout)
        finish(op, same(op.before, op.patch) ? "unchanged" : "confirmed")
        return
      }
    } catch (error) { refusedBeforeNative(op); return }
    if (!stage(op, "native-dispatch", nativeTimeoutMs)) return
    if (!stableState(op, op.patch)) { finish(op, "conflict"); return }
    let invoked = false
    let planned = false
    let returned = false
    try {
      returned = op.nativeWriter.mutateShellConfig(function(config) {
        invoked = true
        if (!stableState(op, op.patch)) return
        if (config && config.bar && config.bar.layout !== undefined)
          op.nativeBefore = copy(config.bar.layout)
        const layout = planNativeLayout(config && config.bar ? config.bar.layout : null, op.intent)
        if (!layout || (typeof validateNativeLayout === "function"
            && validateNativeLayout(config && config.bar ? config.bar.layout : null,
              op.intent, op.patch) !== true)
            || !stableState(op, op.patch)) return
        op.expected = copy(config.bar)
        op.expected.layout = copy(layout)
        op.nativeAfter = copy(layout)
        op.nativeChanged = !same(config.bar, op.expected)
        // Keep opaque Bar fields and complete entry objects from this current
        // native callback, never from the pre-State injected snapshot.
        const assignment = copy(layout)
        planned = true // From this point an assignment may have taken effect.
        config.bar.layout = assignment
      })
    } catch (error) {
      if (!planned) refusedBeforeNative(op)
      else finish(op, "native-indeterminate")
      return
    }
    if (!current(op)) return
    if (!stableState(op, op.patch)) { finish(op, "conflict"); return }
    if (!planned) {
      if (invoked || returned === false) {
        refusedBeforeNative(op)
      } else finish(op, "native-indeterminate")
      return
    }
    // Even false can accompany a native no-op. Only injected configuration
    // establishes the postcondition, never the method's truthy return value.
    if (stage(op, "wait-native", nativeTimeoutMs)) deferEvaluation()
  }

  function refusedBeforeNative(op) {
    if (!current(op)) return
    if (!stableState(op, op.patch)) { finish(op, "conflict"); return }
    // No requested native layout was assigned. Only the still-owned State
    // projection may be compensated, and its readback must also settle.
    if (same(op.before, op.patch)) finish(op, "native-refused")
    else queueState(op, true)
  }

  Timer {
    id: deferred
    interval: 0
    repeat: false
    onTriggered: {
      const op = root.operation
      if (!op || op.finishing) return
      const dispatch = op.dispatchDeferred === true
      const evaluate = op.evaluationDeferred === true
      op.dispatchDeferred = false
      op.evaluationDeferred = false
      if (dispatch && root.operation === op) root.dispatchNative(op)
      if (evaluate && root.operation === op) root.evaluate(op)
    }
  }
  Connections {
    target: root.stateService
    ignoreUnknownSignals: true
    function onReadyChanged() { root.revoke() }
    function onPersistenceSettled(serial, result) { root.observeSettlement(serial, result) }
    function onWriteSerialChanged() { root.deferEvaluation() }
    function onWritePendingChanged() { root.deferEvaluation() }
    function onRevisionChanged() { root.deferEvaluation() }
  }
  Timer {
    id: deadline
    repeat: false
    onTriggered: {
      const op = root.operation
      if (op) root.finish(op, op.stage === "wait-native" || op.stage === "native-dispatch"
        ? "native-indeterminate" : op.stage === "wait-compensation"
          ? "compensation-timeout" : "state-timeout")
    }
  }
  Component.onDestruction: {
    deadline.stop()
    deferred.stop()
    const op = operation
    if (op) op.finishing = true
    operation = null
    _busy = false
    _phase = "idle"
  }
}
