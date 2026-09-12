import QtQuick
import Quickshell
import qs.Commons
import "core" as Core
import "core/V2LayoutModel.js" as Layout
import "core/GroupRegistry.js" as GroupRegistry
import "StateStorageModel.js" as Model

Scope {
  id: root
  property bool admitted: true
  property bool planThrow: false
  property var writer: state
  property var host: native
  property int test: 0
  property int step: 0
  property int ticks: 0
  property int stateCalls: 0
  property int compensations: 0
  property var results: []
  property var snapshotResults: []
  property var settlementContexts: []
  property var busyHook: null
  property var phaseHook: null
  property var serialHook: null
  property bool destructionProbeAdmitted: true
  property var destructionProbe: null
  function check(value, message) {
    if (value) return
    console.error("layout-transition-smoke:", test, step, message)
    Qt.exit(1)
    throw new Error(message)
  }
  function initialSlots() {
    const value = Layout.defaultLayout(); value.left.push("G:example.a"); return value
  }
  function targetSlots() {
    const value = initialSlots(); value.left.pop(); value.right[value.right.length - 1] = "G:example.a"; return value
  }
  function initialBar() {
    return {id: "fixture.bar", position: "top", unknown: {deep: [42]}, layout: {
      left: [{id: "example.a", opaque: {deep: [7]}}], center: [], right: [{id: "example.other", keep: true}]}}
  }
  function start() { return controller.persistV2Layout(targetSlots()) }
  function forward() { state.complete("confirmed", true) }
  function resetCase() {
    check(!transition.busy && !snapshotTransition.busy,
      "previous operation remained busy")
    busyHook = null; phaseHook = null; serialHook = null
    admitted = true; writer = state; host = native; planThrow = false
    state.mode = "delayed"; state.writePending = false; state.desired = null
    state.config = {presentation: {shellStyle: "full"}, v2Layout: initialSlots(), v2Boundaries: [true, false],
      separators: {G2: true, G3: false}}
    native.actual = initialBar(); native.observed = Model.copy(native.actual)
    native.mode = "delayed"; native.calls = 0; native.revokeBefore = false
    results = []; snapshotResults = []; settlementContexts = []
    stateCalls = 0; compensations = 0; ticks = 0
  }
  Item {
    id: state
    property bool ready: true
    property bool writePending: false
    property int writeSerial: 0
    property int revision: 0
    property string mode: "delayed"
    property var config: ({})
    property var desired: null
    signal persistenceSettled(int serial, string result)
    function same(a, b) { return Model.same(a, b) }
    // Complete inert replacement: only projection/queue/settlement mechanics,
    // never a native writer or actual StateStorage fallback. Actual State is
    // exercised separately in the pinned native fixture and State service gate.
    function normalizedLayoutFamilyPatch(patch) {
      return patch && (!patch.v2Layout || Layout.valid(patch.v2Layout)) ? Model.copy(patch) : null
    }
    function layoutFamilySnapshot(patch) {
      const value = {}
      for (const key of Object.keys(patch || {})) {
        if (key === "separators") {
          value[key] = {}
          for (const group of Object.keys(patch[key]))
            value[key][group] = Object.prototype.hasOwnProperty.call(config.separators, group) ? config.separators[group] : null
        } else value[key] = config[key]
      }
      return Model.copy(value)
    }
    function setLayoutFamilyTransition(patch) {
      root.stateCalls++
      if (mode === "refuse") return false
      if (mode === "throw") throw new Error("fixture pre-queue refusal")
      desired = Model.copy(patch); writeSerial++; writePending = true
      if (mode === "sync") complete("confirmed", true)
      return true
    }
    function compensateLayoutFamilyTransition(serial, expected, before) {
      root.compensations++
      if (writePending || writeSerial !== serial || !same(layoutFamilySnapshot(expected), expected)) return false
      return setLayoutFamilyTransition(before)
    }
    function complete(result, publish) {
      if (publish) {
        const value = Model.copy(config)
        for (const key of Object.keys(desired || {})) {
          if (key === "separators") {
            for (const group of Object.keys(desired[key])) {
              if (desired[key][group] === null) delete value.separators[group]
              else value.separators[group] = desired[key][group]
            }
          } else value[key] = Model.copy(desired[key])
        }
        config = value; revision++
      }
      writePending = false
      persistenceSettled(writeSerial, result)
    }
  }
  QtObject { id: otherOwner }
  Item {
    id: native
    property var actual: ({})
    property var observed: ({})
    property string mode: "delayed"
    property int calls: 0
    property bool revokeBefore: false
    function mutateShellConfig(callback) {
      calls++
      if (mode === "refuse") return false
      if (mode === "throw-before") throw new Error("fixture before callback")
      if (mode === "no-callback") return true
      const config = {bar: Model.copy(actual)}
      if (revokeBefore) root.admitted = false
      callback(config)
      actual = config.bar
      if (mode === "throw-after") throw new Error("fixture after assignment")
      if (mode === "inline" || mode === "false-noop") observed = Model.copy(actual)
      return mode !== "false-noop"
    }
    // INJECT_NATIVE_PLAN
  }
  Item {
    id: fixtureBar
    readonly property bool layoutTransitionsSupported: transition.supported
    property bool legacyLayoutMutationAllowed: false
    readonly property bool layoutTransitionBusy: transition.busy
    function requestV2LayoutTransition(patch) { return transition.request(patch, patch.v2Layout) }
    function syncV2DynamicLayout(value) { root.check(false, "legacy native path called"); return false }
  }
  Core.LayoutController { id: controller; stateService: root.writer; bar: fixtureBar }
  Core.LayoutTransition {
    id: transition
    stateService: root.writer
    nativeWriter: root.host
    observedBarConfig: native.observed
    admitted: root.admitted && !snapshotTransition.busy
    stateTimeoutMs: 150
    nativeTimeoutMs: 150
    planNativeLayout: function(layout, intent) {
      if (root.planThrow) throw new Error("fixture planner failure")
      return native.planV2DynamicLayout(layout,
        intent && intent.kind === "v2-layout" ? intent.slots : intent)
    }
    onSettledContext: function(serial, result, context) {
      root.settlementContexts.push({serial: serial, result: result,
        context: context})
    }
    onSettled: function(serial, result) { root.results.push({serial: serial, result: result}) }
    onBusyChanged: if (root.busyHook) root.busyHook()
    onPhaseChanged: if (root.phaseHook) root.phaseHook()
    onRequestSerialChanged: if (root.serialHook) root.serialHook()
  }
  Component {
    id: destructionProbeComponent
    Core.LayoutTransition {
      stateService: root.writer
      nativeWriter: root.host
      observedBarConfig: native.observed
      admitted: root.destructionProbeAdmitted
      stateTimeoutMs: 150
      nativeTimeoutMs: 150
      planNativeLayout: function(layout, intent) {
        return native.planV2DynamicLayout(layout,
          intent && intent.kind === "v2-layout" ? intent.slots : intent)
      }
    }
  }
  Core.LayoutTransition {
    id: snapshotTransition
    stateService: root.writer
    nativeWriter: root.host
    observedBarConfig: native.observed
    admitted: root.admitted && !transition.busy
    nativeTimeoutMs: 150
    planNativeLayout: function(layout, intent) {
      if (!layout || !intent || intent.kind !== "provider-snapshot"
          || !intent.layout) return null
      return Model.copy(intent.layout)
    }
    validateNativeLayout: function(_layout, intent, patch) {
      return !!intent && intent.kind === "provider-snapshot"
        && state.same(intent.patch, patch)
    }
    onSettled: function(serial, result) {
      root.snapshotResults.push({serial: serial, result: result})
    }
  }
  function done(result) {
    check(!transition.busy && results.length === 1 && results[0].result === result,
      "wrong settled result: " + JSON.stringify(results))
    check(settlementContexts.length === 1
      && settlementContexts[0].serial === results[0].serial
      && settlementContexts[0].result === result,
      "missing detached settlement context")
    return true
  }
  function snapshotDone(result) {
    check(!snapshotTransition.busy && snapshotResults.length === 1
      && snapshotResults[0].result === result,
      "wrong provider snapshot result: " + JSON.stringify(snapshotResults))
    return true
  }
  property var cases: [
    function() {
      if (!step) { check(start(), "request refused"); step++; return false }
      if (step === 1) {
        check(native.calls === 0 && transition.busy, "native ran before State settlement")
        check(!start() && !controller.resetV2Layout() && stateCalls === 1, "conflicting request mutated State")
        if (++ticks < 12) return false
        const next = Model.copy(native.actual); next.unknown.concurrent = [11];
        next.layout.center.push({id: "example.new", foreign: 12}); native.actual = next
        forward(); step++; return false
      }
      if (step === 2) {
        if (!native.calls) return false
        check(transition.busy && native.observed.layout.left.length === 1, "native acceptance counted as publication")
        check(native.actual.unknown.concurrent[0] === 11 && native.actual.layout.center[0].foreign === 12
          && native.actual.layout.right[1].opaque.deep[0] === 7, "current native fields lost")
        check(settlementContexts.length === 0,
          "settlement context published before native observation")
        native.observed = Model.copy(native.actual); step++; return false
      }
      check(settlementContexts.length === 1
        && settlementContexts[0].context.nativeBefore.center[0].foreign === 12
        && settlementContexts[0].context.nativeBefore.left[0].opaque.deep[0] === 7,
        "native callback preimage was not retained exactly")
      return done("confirmed")
    },
    function() {
      if (!step) { check(start(), "refusal setup"); state.complete("refused", false); step++; return false }
      check(native.calls === 0, "refused State dispatched native"); return done("state-refused")
    },
    function() {
      if (!step) { check(start(), "wrong readback setup"); state.complete("confirmed", false); step++; return false }
      if (transition.busy && native.calls === 0) return false
      check(native.calls === 0, "mismatched State projection dispatched native"); return done("state-refused")
    },
    function() {
      if (!step) {
        check(start(), "future serial setup"); state.config = Object.assign({}, state.config, {v2Layout: targetSlots()})
        state.writePending = false; state.persistenceSettled(state.writeSerial + 1, "confirmed"); step++; return false
      }
      if (step === 1) {
        check(native.calls === 0, "future settlement authorized native")
        state.persistenceSettled(state.writeSerial - 1, "confirmed"); step++; return false
      }
      if (step === 2) {
        check(native.calls === 0, "old settlement authorized native")
        native.mode = "inline"; state.persistenceSettled(state.writeSerial, "unchanged"); step++; return false
      }
      if (transition.busy) return false
      return done("confirmed")
    },
    function() {
      if (!step) { state.mode = "sync"; native.mode = "inline"; check(start(), "sync settlement refused");
        check(native.calls === 0, "native ran inside synchronous State setter"); step++; return false }
      if (transition.busy) return false
      return done("confirmed")
    },
    function() {
      if (!step) { native.mode = "refuse"; check(start(), "compensation setup"); forward(); step++; return false }
      if (step === 1) {
        if (!compensations) {
          check(transition.busy, "native refusal skipped compensation"); return false
        }
        check(transition.busy && state.writePending && state.config.v2Layout.right.indexOf("G:example.a") >= 0,
          "compensation acceptance counted as saved")
        forward(); step++; return false
      }
      return done("compensated")
    },
    function() {
      if (!step) {
        planThrow = true; check(controller.resetV2Layout(), "reset request refused")
        forward(); step++; return false
      }
      if (step === 1) { if (!compensations) return false; forward(); step++; return false }
      check(Model.same(state.config.v2Boundaries, [true, false]) && state.config.separators.G2 === true
        && state.config.separators.G3 === false && !Object.prototype.hasOwnProperty.call(state.config.separators, "G1"),
        "reset compensation lost boundary or separator presence")
      return done("compensated")
    },
    function() {
      if (!step) { check(start(), "native timeout setup"); forward(); step++; return false }
      if (transition.busy) return false
      check(compensations === 0 && state.config.v2Layout.right.indexOf("G:example.a") >= 0,
        "indeterminate native timeout rolled back State")
      native.observed = Model.copy(native.actual)
      return done("native-indeterminate")
    },
    function() {
      if (!step) { native.mode = "no-callback"; check(start(), "no callback setup"); forward(); step++; return false }
      if (transition.busy) return false
      check(compensations === 0, "truthy no-callback guessed compensation")
      return done("native-indeterminate")
    },
    function() {
      if (!step) { check(start(), "revocation setup"); admitted = false; forward(); step++; return false }
      check(native.calls === 0, "revoked request dispatched native"); return done("revoked")
    },
    function() {
      if (!step) { check(start(), "writer replacement setup"); host = otherOwner; forward(); step++; return false }
      check(native.calls === 0, "replaced native owner dispatched"); return done("revoked")
    },
    function() {
      if (!step) { check(start(), "State replacement setup"); writer = otherOwner; forward(); step++; return false }
      check(native.calls === 0, "replaced State owner dispatched"); return done("revoked")
    },
    function() {
      if (!step) { check(start(), "newer request setup"); forward(); state.writeSerial++; step++; return false }
      check(native.calls === 0 && compensations === 0, "newer serial was overwritten"); return done("conflict")
    },
    function() {
      if (!step) { native.mode = "refuse"; check(start(), "external publication setup"); forward()
        state.config = Object.assign({}, state.config, {v2Layout: initialSlots()}); state.revision++; step++; return false }
      check(native.calls === 0 && compensations === 0, "external State projection overwritten"); return done("state-refused")
    },
    function() {
      if (!step) { native.mode = "throw-before"; check(start(), "pre-callback throw setup"); forward(); step++; return false }
      if (step === 1) {
        if (!compensations) { check(transition.busy, "pre-callback throw not compensated"); return false }
        forward(); step++; return false
      }
      return done("compensated")
    },
    function() {
      if (!step) { planThrow = true; check(start(), "planner throw setup"); forward(); step++; return false }
      if (step === 1) { if (!compensations) return false; forward(); step++; return false }
      return done("compensated")
    },
    function() {
      if (!step) { native.mode = "throw-after"; check(start(), "post-assignment throw setup"); forward(); step++; return false }
      if (transition.busy) return false
      check(compensations === 0 && native.actual.layout.right.length === 2, "applied throw was compensated")
      return done("native-indeterminate")
    },
    function() {
      if (!step) { native.revokeBefore = true; check(start(), "callback revocation setup"); forward(); step++; return false }
      if (transition.busy) return false
      check(Model.same(native.actual, initialBar()) && compensations === 0, "revoked callback changed native layout")
      return done("revoked")
    },
    function() {
      if (!step) {
        phaseHook = function() { if (transition.phase === "native-ready") admitted = false }
        check(start(), "phase reentry setup"); forward(); step++; return false
      }
      check(native.calls === 0, "phase notification revocation dispatched native"); return done("revoked")
    },
    function() {
      busyHook = function() { if (transition.busy) admitted = false }
      check(!start() && stateCalls === 0 && native.calls === 0, "busy notification revocation queued work")
      return done("revoked")
    },
    function() {
      if (!step) {
        serialHook = function() { serialHook = null; check(start(), "reentrant serial request refused") }
        check(!start() && stateCalls === 1, "older request replaced serial reentry")
        native.mode = "inline"; forward(); step++; return false
      }
      if (transition.busy) return false
      check(results[0].serial === transition.requestSerial, "older serial completed over newer request")
      return done("confirmed")
    },
    function() {
      serialHook = function() {
        serialHook = null
        busyHook = function() { if (transition.busy) admitted = false }
        check(!start(), "nested revoked request accepted")
        busyHook = null; admitted = true
      }
      check(!start() && stateCalls === 0, "older request replaced serial reentry")
      return done("revoked")
    },
    function() {
      if (!step) {
        native.mode = "false-noop"
        check(controller.persistV2Layout(initialSlots()), "already-target request refused")
        check(stateCalls === 0, "already-target State was rewritten"); step++; return false
      }
      if (transition.busy) return false
      return done("unchanged")
    },
    function() {
      if (!step) {
        const actual = Model.copy(native.actual); actual.layout.right.push(actual.layout.left.pop()); native.actual = actual
        native.mode = "false-noop"; check(start(), "false no-op setup"); forward(); step++; return false
      }
      if (transition.busy) return false
      check(native.calls === 1, "false no-op did not exercise native callback")
      return done("confirmed")
    },
    function() {
      if (!step) {
        check(start(), "missing entry setup")
        const value = Model.copy(native.actual); value.layout.left = []; native.actual = value
        forward(); step++; return false
      }
      if (step === 1) { if (!compensations) return false; forward(); step++; return false }
      check(native.actual.layout.right.length === 1, "missing provider was invented")
      return done("compensated")
    },
    function() {
      const oldLayout = initialBar().layout
      const oldPatch = {v1Layout: {order: {left: ["G6"], center: [], right: []},
        splits: {left: [false], center: [], right: []}},
        familyStates: {G6: {v1: true, v2: false}}}
      if (!step) {
        state.config = Object.assign({}, state.config, {
          v1Layout: {order: {left: ["G:provider.b"], center: [], right: []},
            splits: {left: [true], center: [], right: []}},
          familyStates: {G6: {v1: false, v2: false}}
        })
        native.actual = {id: "fixture.bar", position: "bottom",
          unknown: {concurrent: [91]}, layout: {
            left: [{id: "provider.b", opaque: {changed: true}}],
            center: [], right: [{id: "example.other", keep: false}]}}
        native.observed = Model.copy(native.actual)
        check(snapshotTransition.request(oldPatch, {kind: "provider-snapshot",
          layout: oldLayout, patch: oldPatch}), "V1 provider snapshot refused")
        step++; return false
      }
      if (step === 1) { state.complete("confirmed", true); step++; return false }
      if (step === 2) {
        if (!native.calls) return false
        check(state.same(native.actual.layout, oldLayout)
          && native.actual.position === "bottom"
          && native.actual.unknown.concurrent[0] === 91,
          "V1 provider snapshot lost exact layout or opaque Bar fields")
        native.observed = Model.copy(native.actual); step++; return false
      }
      check(state.same(state.config.v1Layout, oldPatch.v1Layout)
        && state.same(state.config.familyStates, oldPatch.familyStates)
        && state.same(state.config.v2Layout, initialSlots()),
        "V1 provider snapshot lost family or unrelated V2 state")
      return snapshotDone("confirmed")
    },
    function() {
      const oldLayout = initialBar().layout
      const oldV2 = initialSlots()
      const oldPatch = {v2Layout: oldV2,
        familyStates: {G6: {v1: false, v2: true}}}
      if (!step) {
        state.config = Object.assign({}, state.config, {v2Layout: targetSlots(),
          familyStates: {G6: {v1: false, v2: false}}})
        native.actual = {id: "fixture.bar", position: "top",
          unknown: {deep: [42], concurrent: [73]}, layout: {
            left: [{id: "provider.b", opaque: {changed: true}}],
            center: [{id: "foreign", retain: true}], right: []}}
        native.observed = Model.copy(native.actual)
        check(snapshotTransition.request(oldPatch, {kind: "provider-snapshot",
          layout: oldLayout, patch: oldPatch}), "V2 provider snapshot refused")
        step++; return false
      }
      if (step === 1) { state.complete("unchanged", true); step++; return false }
      if (step === 2) {
        if (!native.calls) return false
        check(state.same(native.actual.layout, oldLayout)
          && native.actual.unknown.concurrent[0] === 73,
          "V2 provider snapshot lost exact layout or opaque Bar fields")
        native.observed = Model.copy(native.actual); step++; return false
      }
      check(state.same(state.config.v2Layout, oldV2)
        && state.same(state.config.familyStates, oldPatch.familyStates),
        "V2 provider snapshot lost exact family state")
      return snapshotDone("confirmed")
    },
    function() {
      const patch = {familyStates: {G6: {v1: false, v2: true}}}
      if (!step) {
        check(transition.request(patch, {kind: "state-only"}),
          "state-only request refused")
        check(native.calls === 0 && transition.busy,
          "state-only request reached native before persistence")
        state.complete("confirmed", true); step++; return false
      }
      if (transition.busy) return false
      check(native.calls === 0 && state.same(state.config.familyStates,
        patch.familyStates), "confirmed state-only request used native or lost state")
      return done("confirmed")
    },
    function() {
      if (!step) {
        check(transition.request({familyStates: {G6: {v1: false, v2: true}}},
          {kind: "state-only"}), "state-only timeout setup refused")
        step++; return false
      }
      if (transition.busy) return false
      check(native.calls === 0, "timed-out state-only request reached native")
      return done("state-timeout")
    },
    function() {
      if (!step) {
        check(transition.request({familyStates: {G6: {v1: false, v2: true}}},
          {kind: "state-only"}), "state-only revocation setup refused")
        admitted = false; step++; return false
      }
      check(native.calls === 0, "revoked state-only request reached native")
      return done("revoked")
    },
    function() {
      if (!step) {
        check(transition.request({familyStates: {G6: {v1: false, v2: true}}},
          {kind: "state-only"}), "state-only writer replacement setup refused")
        writer = otherOwner; step++; return false
      }
      check(native.calls === 0, "replaced state-only writer reached native")
      return done("revoked")
    },
    function() {
      if (!step) {
        destructionProbeAdmitted = true
        destructionProbe = destructionProbeComponent.createObject(state)
        check(!!destructionProbe && destructionProbe.request(
          {v2Layout: initialSlots()},
          {kind: "v2-layout", slots: initialSlots()}),
          "destruction probe request refused")
        destructionProbeAdmitted = false
        destructionProbe.destroy()
        destructionProbe = null
        step++
        ticks = 0
        return false
      }
      if (++ticks < 6) return false
      check(native.calls === 0,
        "destroyed deferred transition invoked native writer")
      return true
    }
  ]
  Timer {
    interval: 10; running: true; repeat: true
    onTriggered: {
      if (root.step === 0) root.resetCase()
      if (!root.cases[root.test]()) return
      root.test++; root.step = 0
      if (root.test === root.cases.length) {
        stop(); console.log("serialized State/native layout sequencing passed; not desktop acceptance"); Qt.quit()
      }
    }
  }
  Timer { interval: 7000; running: true; onTriggered: root.check(false, "fixture deadline") }
}
