pragma ComponentBehavior: Bound

import QtQuick
import "NetworkActionModel.js" as Model
import "NetworkActionAuthority.js" as Authority
import "NetworkEnterpriseModel.js" as EnterpriseModel

// Process-wide native action completion coordinator. Dispatch acceptance comes
// from NetworkBackendAdapter; completion is derived only from later primitive
// snapshots. No credential is retained or published; Service.qml owns exactly
// one coordinator for all output-local panels.
Item {
  id: root

  property bool active: false
  property var networkAdapter: null
  property var enterpriseDispatcher: null
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
  function connectNetworkEnterprise(request, credentials) {
    const parsed = EnterpriseModel.credentialsData(credentials)
    if (!parsed.ok)
      return implementation.localResult(false, "invalid",
        "Enterprise credentials are invalid.", "", request)
    return implementation.dispatch(
      "connect-enterprise", request, parsed.credentials)
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
  onEnterpriseDispatcherChanged: implementation.dispatcherChanged()

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
    function onConnectionFailureGenerationChanged() {
      implementation.failureObserved()
    }
  }

  Connections {
    target: root.enterpriseDispatcher
    ignoreUnknownSignals: true
    function onLaunchFailed(entityId, dispatchGeneration) {
      implementation.enterpriseLaunchFailed(entityId, dispatchGeneration)
    }
    function onCompletionGenerationChanged() {
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
        deviceId: "", profileUuid: "", profileSsid: "",
        enterpriseToken: "",
        enterpriseSsidHex: "",
        enterpriseHardwareAddress: "", enterpriseInterfaceName: "",
        enterpriseSecurity: ""
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
      if (kind === "connect-enterprise") {
        const dispatcher = root.enterpriseDispatcher
        return dispatcher
          ? dispatcher.connectNetworkEnterprise(request, secret) : null
      }
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
      if (source.kind === "connect-enterprise"
          && EnterpriseModel.validRequestToken(source.enterpriseToken)) {
        try {
          if (root.enterpriseDispatcher
              && typeof root.enterpriseDispatcher.releaseCompletion
                === "function")
            root.enterpriseDispatcher.releaseCompletion(source.enterpriseToken)
        } catch (error) {}
      }
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
        deviceId: source.deviceId,
        profileUuid: source.profileUuid,
        profileSsid: source.profileSsid,
        enterpriseToken: "", enterpriseSsidHex: "",
        enterpriseHardwareAddress: "", enterpriseInterfaceName: "",
        enterpriseSecurity: ""
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
      if (kind === "connect-enterprise") {
        try {
          if (!root.enterpriseDispatcher
              || root.enterpriseDispatcher.available !== true)
            return localResult(false, "unavailable",
              "Enterprise connection dispatcher is unavailable.", "",
              safeRequest)
        } catch (error) {
          return localResult(false, "unavailable",
            "Enterprise connection dispatcher is unavailable.", "",
            safeRequest)
        }
      }
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
        deviceId: context.deviceId,
        profileUuid: context.profileUuid,
        profileSsid: context.profileSsid,
        enterpriseToken: "", enterpriseSsidHex: "",
        enterpriseHardwareAddress: "", enterpriseInterfaceName: "",
        enterpriseSecurity: ""
      }
      const adapterBefore = root.networkAdapter
      const dispatcherBefore = kind === "connect-enterprise"
        ? root.enterpriseDispatcher : null
      dispatchInProgress = true
      try {
        const result = dispatchMethod(kind, {
          entityId: entityId, generation: viewBefore.generation
        }, secret)
        const adapterUnchanged = root.networkAdapter === adapterBefore
        const dispatcherUnchanged = kind !== "connect-enterprise"
          || root.enterpriseDispatcher === dispatcherBefore
        let enterpriseEvidenceValid = kind !== "connect-enterprise"
        if (kind === "connect-enterprise" && dispatcherUnchanged) {
          try {
            const evidence = {
              deviceId: dispatcherBefore.lastDispatchDeviceId,
              entityId: dispatcherBefore.lastDispatchEntityId,
              generation: dispatcherBefore.lastDispatchGeneration,
              hardwareAddress: dispatcherBefore.lastDispatchHardwareAddress,
              interfaceName: dispatcherBefore.lastDispatchInterfaceName,
              security: dispatcherBefore.lastDispatchSecurity,
              ssidHex: dispatcherBefore.lastDispatchSsidHex
            }
            const token = dispatcherBefore.lastDispatchToken
            if (EnterpriseModel.validRequestToken(token)
                && EnterpriseModel.validDescriptor(evidence)
                && evidence.deviceId === context.deviceId
                && evidence.entityId === entityId
                && evidence.generation === viewBefore.generation) {
              action.enterpriseToken = token
              action.enterpriseSsidHex = evidence.ssidHex
              action.enterpriseHardwareAddress = evidence.hardwareAddress
              action.enterpriseInterfaceName = evidence.interfaceName
              action.enterpriseSecurity = evidence.security
              enterpriseEvidenceValid = true
            }
          } catch (error) {}
        }
        const currentGeneration = root.networkAdapter
          && root.networkAdapter.generation
        const currentValid = Model.validGeneration(currentGeneration)
          && currentGeneration >= viewBefore.generation
        if (!Model.validDispatchResult(result, entityId)
            || !adapterUnchanged || !dispatcherUnchanged
            || !enterpriseEvidenceValid || !currentValid
            || result.generation !== currentGeneration) {
          beginPending(action, currentValid ? currentGeneration
            : viewBefore.generation,
            !adapterUnchanged || !dispatcherUnchanged
              || !enterpriseEvidenceValid || !currentValid,
            !adapterUnchanged || !dispatcherUnchanged
              ? "adapter-replaced" : "timeout")
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

    function savedCatalogAbsent(uuidValue) {
      try {
        const adapter = root.networkAdapter
        if (!adapter || adapter.savedProfileCatalogAvailable !== true
            || !Array.isArray(adapter.savedProfileSnapshots)
            || adapter.savedProfileSnapshots.length > Model.MaxRows)
          return false
        const uuid = String(uuidValue || "")
        let count = 0
        for (let index = 0;
            index < adapter.savedProfileSnapshots.length; index++) {
          const row = adapter.savedProfileSnapshots[index]
          if (!row || typeof row.uuid !== "string") return false
          if (row.uuid === uuid) count++
        }
        return uuid !== "" && count === 0
      } catch (error) {
        return false
      }
    }

    function activeConnectionUuid() {
      try {
        const adapter = root.networkAdapter
        const value = adapter
          && typeof adapter.activeConnectionUuidForDevice === "function"
          ? adapter.activeConnectionUuidForDevice(state.deviceId) : ""
        return typeof value === "string" ? value : ""
      } catch (error) {
        return ""
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
      const result = Model.reconcile(
        state, view, activeConnectionUuid())
      if (state.kind === "connect-enterprise" && !result.terminal) {
        let completion = null
        try { completion = root.enterpriseDispatcher.completionSnapshot }
        catch (error) { return }
        if (view.generation > state.dispatchGeneration
            && Model.enterpriseConnected(state, view)
            && EnterpriseModel.completionMatches(completion,
              state.enterpriseToken, state.enterpriseSsidHex,
              state.deviceId, state.entityId, state.dispatchGeneration,
              state.enterpriseHardwareAddress, state.enterpriseInterfaceName,
              state.enterpriseSecurity))
          setTerminal(state, true, "completed", view.generation)
        return
      }
      if (!result.terminal) return
      if (result.success && state.kind === "forget-profile"
          && !savedCatalogAbsent(state.profileUuid)) return
      setTerminal(state, result.success, result.code,
        view ? view.generation : state.observedGeneration)
    }

    function failureObserved() {
      if (dispatchInProgress || state.phase !== "pending"
          || state.completionBlocked === true) return false
      let snapshot = null
      let observed = state.observedGeneration
      try {
        const adapter = root.networkAdapter
        if (!adapter || !Model.validGeneration(adapter.generation))
          return false
        snapshot = adapter.connectionFailureSnapshot
        observed = adapter.generation
      } catch (error) {
        return false
      }
      const result = Model.connectionFailure(state, snapshot, observed)
      if (!result || !result.terminal) return false
      setTerminal(state, false, result.code, observed)
      return true
    }

    function enterpriseLaunchFailed(entityId, dispatchGeneration) {
      if (state.phase !== "pending" || state.kind !== "connect-enterprise"
          || state.entityId !== entityId
          || state.dispatchGeneration !== dispatchGeneration) return false
      setTerminal(state, false, "unavailable", state.observedGeneration)
      return true
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

    function dispatcherChanged() {
      if (root.busy && state.kind === "connect-enterprise") {
        const next = Object.assign({}, state)
        next.completionBlocked = true
        next.timeoutCode = "adapter-replaced"
        state = next
        bumpGeneration()
      }
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
