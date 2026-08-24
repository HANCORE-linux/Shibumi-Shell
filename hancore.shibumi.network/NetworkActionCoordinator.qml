pragma ComponentBehavior: Bound

import QtQuick
import "NetworkActionModel.js" as Model
import "NetworkActionAuthority.js" as Authority

// Process-wide native action completion coordinator. Dispatch acceptance comes
// from NetworkBackendAdapter; completion is derived only from later primitive
// snapshots. No credential is retained or published. Production Service.qml
// does not instantiate this source-only Step 5 seam.
Item {
  id: root

  property bool active: false
  property var networkAdapter: null
  property int actionTimeoutMs: 30000
  property real generation: 0

  readonly property int schemaVersion: Model.SchemaVersion
  readonly property bool authorized: implementation.authorized
  readonly property bool busy: implementation.dispatchInProgress
    || implementation.state.phase === "pending"
  readonly property string phase: implementation.state.phase
  readonly property string actionId: implementation.state.actionId
  readonly property string actionKind: implementation.state.kind
  readonly property string actionEntityId: implementation.state.entityId
  readonly property string failureCode:
    implementation.state.phase === "failed" ? implementation.state.code : ""
  readonly property string failureMessage:
    implementation.state.phase === "failed" ? implementation.state.message : ""
  readonly property var actionSnapshot: implementation.publicSnapshot()
  QtObject {
    id: authorityGuard
    property bool authorityAlive: true
    property int claim: 0
  }

  visible: false
  width: 0
  height: 0

  function setWifiEnabled(request, enabled) {
    if (typeof enabled !== "boolean")
      return implementation.localResult(false, "invalid",
        "Wi-Fi state must be boolean.", "", request)
    return implementation.dispatch(
      enabled ? "wifi-enable" : "wifi-disable", request, null)
  }
  function connectNetwork(request) {
    return implementation.dispatch("connect", request, null)
  }
  function connectNetworkWithPsk(request, passphrase) {
    return implementation.dispatch("connect-with-psk", request, passphrase)
  }
  function disconnectNetwork(request) {
    return implementation.dispatch("disconnect", request, null)
  }
  function connectProfile(request) {
    return implementation.dispatch("connect-profile", request, null)
  }
  function forgetProfile(request) {
    return implementation.dispatch("forget-profile", request, null)
  }
  function clearResult() { return implementation.clearResult() }

  onActiveChanged: {
    if (active) implementation.claimAuthority()
    else implementation.shutdown()
  }
  onNetworkAdapterChanged: implementation.adapterChanged()

  Timer {
    interval: 250
    repeat: true
    running: root.active && !root.authorized
    onTriggered: implementation.claimAuthority()
  }

  Timer {
    id: actionTimeout
    interval: Math.max(100, Math.min(120000, root.actionTimeoutMs))
    repeat: false
    onTriggered: implementation.failPending(
      implementation.state.timeoutCode || "timeout")
  }

  Timer {
    id: deferredReconcile
    interval: 0
    repeat: false
    onTriggered: implementation.reconcile()
  }

  Connections {
    target: root.networkAdapter
    ignoreUnknownSignals: true
    function onGenerationChanged() {
      implementation.reconcile()
      if (root.busy) deferredReconcile.restart()
    }
  }

  QtObject {
    id: implementation

    property bool authorized: false
    property int authorityClaim: 0
    property int nextActionSequence: 1
    property bool shutdownRequested: false
    property bool dispatchInProgress: false
    property var state: idleState()

    function idleState() {
      return {
        phase: "idle", actionId: "", kind: "", entityId: "",
        relatedEntityId: "", targetEnabled: null, code: "idle", message: "",
        dispatchGeneration: 0, observedGeneration: 0,
        deviceId: ""
      }
    }

    function bumpGeneration() {
      if (root.generation < Model.MaxSafeInteger) root.generation++
    }

    function publicSnapshot() {
      const snapshot = {
        schemaVersion: root.schemaVersion,
        phase: state.phase,
        actionId: state.actionId,
        kind: state.kind,
        entityId: state.entityId,
        relatedEntityId: state.relatedEntityId,
        targetEnabled: state.targetEnabled,
        code: state.code,
        message: state.message,
        dispatchGeneration: state.dispatchGeneration,
        observedGeneration: state.observedGeneration,
        generation: root.generation
      }
      return Model.clonePublicSnapshot(snapshot)
    }

    function claimAuthority() {
      if (!root.active || shutdownRequested || authorized) return authorized
      authorityClaim = Authority.claim(authorityGuard)
      authorityGuard.claim = authorityClaim
      authorized = authorityClaim > 0
      return authorized
    }

    function requestData(request) {
      try {
        if (!request || typeof request !== "object" || Array.isArray(request))
          return { ok: false, entityId: "", generation: 0 }
        const keys = Reflect.ownKeys(request)
        if (keys.length !== 2 || keys.indexOf("entityId") < 0
            || keys.indexOf("generation") < 0)
          return { ok: false, entityId: "", generation: 0 }
        const entityDescriptor = Object.getOwnPropertyDescriptor(
          request, "entityId")
        const generationDescriptor = Object.getOwnPropertyDescriptor(
          request, "generation")
        const entityId = "value" in entityDescriptor
          ? entityDescriptor.value : entityDescriptor.get.call(request)
        const generation = "value" in generationDescriptor
          ? generationDescriptor.value : generationDescriptor.get.call(request)
        return Model.validEntityId(entityId, false)
            && Model.validGeneration(generation)
          ? { ok: true, entityId: entityId, generation: generation }
          : { ok: false, entityId: "", generation: 0 }
      } catch (error) {
        return { ok: false, entityId: "", generation: 0 }
      }
    }

    function requestEntity(request) {
      return requestData(request).entityId
    }

    function localResult(accepted, code, message, resultActionId, request) {
      const entityId = requestEntity(request)
      let adapterGeneration = 0
      try {
        if (root.networkAdapter
            && Model.validGeneration(root.networkAdapter.generation))
          adapterGeneration = root.networkAdapter.generation
      } catch (error) {}
      return {
        accepted: accepted === true,
        code: String(code || "invalid"),
        message: String(message || ""),
        actionId: String(resultActionId || ""),
        entityId: entityId,
        generation: adapterGeneration
      }
    }

    function adapterView() {
      try {
        const adapter = root.networkAdapter
        if (!adapter || typeof adapter !== "object"
            || adapter.active !== true
            || !Model.validGeneration(adapter.generation)) return null
        const backend = adapter.backendSnapshot
        if (!Model.exactKeys(backend, [
              "schemaVersion", "available", "degraded", "connectivity",
              "generation"
            ]) || backend.schemaVersion !== Model.SchemaVersion
            || adapter.schemaVersion !== Model.SchemaVersion
            || typeof backend.available !== "boolean"
            || typeof backend.degraded !== "boolean"
            || Model.ConnectivityTokens.indexOf(backend.connectivity) < 0
            || backend.generation !== adapter.generation)
          return null
        const view = {
          available: backend.available,
          degraded: backend.degraded,
          generation: adapter.generation,
          radio: adapter.radioSnapshot,
          devices: adapter.deviceSnapshots,
          networks: adapter.networkSnapshots,
          profiles: adapter.profileSnapshots
        }
        return Model.validView(view) ? view : null
      } catch (error) {
        return null
      }
    }

    function actionContext(kind, entityId, view) {
      return view ? Model.actionContext(kind, entityId,
        view.radio, view.networks, view.profiles) : null
    }

    function dispatchMethod(kind, request, secret) {
      const adapter = root.networkAdapter
      if (!adapter) return null
      if (kind === "wifi-enable") return adapter.setWifiEnabled(request, true)
      if (kind === "wifi-disable") return adapter.setWifiEnabled(request, false)
      if (kind === "connect") return adapter.connectNetwork(request)
      if (kind === "connect-with-psk")
        return adapter.connectNetworkWithPsk(request, secret)
      if (kind === "disconnect") return adapter.disconnectNetwork(request)
      if (kind === "connect-profile") return adapter.connectProfile(request)
      if (kind === "forget-profile") return adapter.forgetProfile(request)
      return null
    }

    function nextId() {
      const value = Model.actionId(authorityClaim, nextActionSequence)
      nextActionSequence++
      if (nextActionSequence > Model.MaxSafeInteger) nextActionSequence = 1
      return value
    }

    function setTerminal(source, success, code, observedGeneration) {
      actionTimeout.stop()
      state = {
        phase: success ? "succeeded" : "failed",
        actionId: source.actionId,
        kind: source.kind,
        entityId: source.entityId,
        relatedEntityId: source.relatedEntityId,
        targetEnabled: source.targetEnabled,
        code: code,
        message: Model.fixedTerminalMessage(code),
        dispatchGeneration: source.dispatchGeneration,
        observedGeneration: Model.validGeneration(observedGeneration)
          && observedGeneration >= source.dispatchGeneration
          && observedGeneration >= source.observedGeneration
            ? observedGeneration : source.observedGeneration,
        deviceId: source.deviceId
      }
      bumpGeneration()
      if (shutdownRequested) finishShutdown()
    }

    function beginPending(action, observedGeneration, completionBlocked,
        timeoutCode) {
      action.observedGeneration = Model.validGeneration(observedGeneration)
        && observedGeneration >= action.dispatchGeneration
          ? observedGeneration : action.dispatchGeneration
      action.completionBlocked = completionBlocked === true
      action.timeoutCode = String(timeoutCode || "timeout")
      state = action
      bumpGeneration()
      actionTimeout.restart()
      reconcile()
    }

    function dispatch(kind, request, secret) {
      const parsedRequest = requestData(request)
      const entityId = parsedRequest.entityId
      const safeRequest = {
        entityId: parsedRequest.entityId,
        generation: parsedRequest.generation
      }
      if (!root.active || !authorized || shutdownRequested)
        return localResult(false, "unavailable",
          "Network action coordinator is unavailable.", "", safeRequest)
      if (root.busy)
        return localResult(false, "busy",
          "Another network action is still pending.", state.actionId,
          safeRequest)
      const viewBefore = adapterView()
      if (!viewBefore || viewBefore.available !== true
          || viewBefore.degraded === true || !parsedRequest.ok
          || entityId === ""
          || parsedRequest.generation !== viewBefore.generation)
        return localResult(false, entityId === "" ? "invalid" : "stale-generation",
          entityId === "" ? "Network action request is invalid."
            : "Network state changed before dispatch.", "", safeRequest)
      const context = actionContext(kind, entityId, viewBefore)
      if (!context)
        return localResult(false, "invalid",
          "Network action precondition is not satisfied.", "", safeRequest)

      const id = nextId()
      const action = {
        phase: "pending", actionId: id, kind: kind, entityId: entityId,
        relatedEntityId: context.relatedEntityId,
        targetEnabled: context.targetEnabled, code: "pending", message: "",
        dispatchGeneration: viewBefore.generation,
        observedGeneration: viewBefore.generation,
        deviceId: context.deviceId
      }
      const adapterBefore = root.networkAdapter
      dispatchInProgress = true
      try {
        const result = dispatchMethod(kind, {
          entityId: entityId, generation: viewBefore.generation
        }, secret)
        const adapterUnchanged = root.networkAdapter === adapterBefore
        const currentGeneration = root.networkAdapter
          && root.networkAdapter.generation
        const currentValid = Model.validGeneration(currentGeneration)
          && currentGeneration >= viewBefore.generation
        if (!Model.validDispatchResult(result, entityId)
            || !adapterUnchanged || !currentValid
            || result.generation !== currentGeneration) {
          beginPending(action, currentValid ? currentGeneration
            : viewBefore.generation, !adapterUnchanged || !currentValid,
            !adapterUnchanged ? "adapter-replaced" : "timeout")
          return localResult(false, "uncertain",
            "Network dispatch outcome is uncertain.", id, safeRequest)
        }
        action.observedGeneration = result.generation
        if (!result.ok) {
          beginPending(action, result.generation, false, "timeout")
          return localResult(false, "uncertain",
            "Network dispatch outcome is uncertain.", id, safeRequest)
        }

        beginPending(action, result.generation, false, "timeout")
        return localResult(true, "accepted", "", id, safeRequest)
      } catch (error) {
        beginPending(action, viewBefore.generation, false, "timeout")
        return localResult(false, "uncertain",
          "Network dispatch outcome is uncertain.", id, safeRequest)
      } finally {
        dispatchInProgress = false
        if (state.phase === "pending") deferredReconcile.restart()
        else if (shutdownRequested) finishShutdown()
      }
    }

    function reconcile() {
      if (dispatchInProgress || state.phase !== "pending"
          || state.completionBlocked === true) return
      let advertisedGeneration = null
      try {
        const value = root.networkAdapter && root.networkAdapter.generation
        if (Model.validGeneration(value)) advertisedGeneration = value
      } catch (error) {
        return
      }
      if (advertisedGeneration === null
          || advertisedGeneration < state.observedGeneration) return
      if (advertisedGeneration > state.observedGeneration) {
        const advanced = Object.assign({}, state)
        advanced.observedGeneration = advertisedGeneration
        state = advanced
        bumpGeneration()
      }
      const view = adapterView()
      if (!view || view.generation < state.observedGeneration) return
      const result = Model.reconcile(state, view)
      if (!result.terminal) return
      setTerminal(state, result.success, result.code,
        view ? view.generation : state.observedGeneration)
    }

    function failPending(code) {
      if (!root.busy) return false
      let observed = state.observedGeneration
      try {
        const value = root.networkAdapter && root.networkAdapter.generation
        if (Model.validGeneration(value) && value > observed) observed = value
      } catch (error) {}
      setTerminal(state, false, code, observed)
      return true
    }

    function clearResult() {
      if (root.busy) return false
      state = idleState()
      bumpGeneration()
      return true
    }

    function adapterChanged() {
      if (root.busy) {
        const next = Object.assign({}, state)
        next.completionBlocked = true
        next.timeoutCode = "adapter-replaced"
        state = next
        bumpGeneration()
      }
      if (root.active && !authorized && !shutdownRequested) claimAuthority()
    }

    function finishShutdown() {
      Authority.release(authorityClaim)
      authorityClaim = 0
      authorityGuard.claim = 0
      authorized = false
      shutdownRequested = false
      if (root.active) claimAuthority()
    }

    function shutdown() {
      if (shutdownRequested) return
      shutdownRequested = true
      if (dispatchInProgress) return
      if (state.phase === "pending") {
        reconcile()
        if (state.phase === "pending") return
      }
      finishShutdown()
    }

    function destroying() {
      actionTimeout.stop()
      if (root.busy) Authority.block(authorityClaim)
      else Authority.release(authorityClaim)
      authorityClaim = 0
      authorityGuard.claim = 0
      authorized = false
    }
  }

  Component.onCompleted: if (root.active)
    implementation.claimAuthority()
  Component.onDestruction: implementation.destroying()
}
