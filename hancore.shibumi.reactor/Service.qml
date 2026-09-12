pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../hancore.shibumi.state/runtime" as SuiteRuntime

// Mode 0 keeps this facade worker-free. Modes 7 and 8 load exactly one
// process-wide backend and forward its events to every per-output renderer.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property bool runtimeProbesEnabled: true

  SuiteRuntime.HostShell { id: suiteShell; host: root.shell }
  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.reactor"
    implementationVersion: "0.1.1-beta.12"
    owner: root
    host: root.shell
    manifest: root.manifest
  }
  readonly property bool backendAdmitted: runtimeProvider.registered
  readonly property var stateService: suiteShell.serviceFor("hancore.shibumi.state")
  readonly property int mode: ready && stateService.config
    && stateService.config.reactor
    ? Math.max(0, Math.min(8, Number(stateService.config.reactor.mode) || 0)) : 0
  readonly property bool ready: backendAdmitted && stateService !== null
    && stateService.ready === true
  readonly property int desiredBackendMode: ready && (mode === 7 || mode === 8) ? mode : 0
  property int loadedBackendMode: 0
  readonly property var backend: desiredBackendMode !== 0
    && loadedBackendMode === desiredBackendMode ? backendLoader.item : null
  // Observe actual Loader existence, even during deferred teardown.
  readonly property bool backendLoaded: backendLoader.item !== null
  readonly property string backendKind: mode === 7 && backend ? "events"
    : mode === 8 && backend ? "quotes" : "none"
  readonly property bool armed: backend !== null && backend.armed === true
  readonly property var eventHistory: mode === 7 && backend
    ? backend.eventHistory : []
  readonly property int eventCount: mode === 8 && backend
    ? Number(backend.eventCount || 0) : eventHistory.length

  signal eventRaised(var event)
  signal cleared()

  visible: false
  width: 0
  height: 0

  function setMode(value) {
    if (!ready) return false
    let next
    try { next = Number(value) } catch (error) { return false }
    if (!Number.isInteger(next) || next < 0 || next > 8 || !ready) return false
    return stateService && typeof stateService.setReactorMode === "function"
      ? stateService.setReactorMode(next) : false
  }

  function runTest(kind, argument) {
    return backend !== null && typeof backend.runTest === "function"
      ? backend.runTest(kind, argument) : false
  }

  function clear() { return runTest("clear", "") }

  // Publish loss and disable the old backend before destroying its QML
  // context. Coalesced callbacks always consult current admission/mode.
  function syncBackend() {
    const next = desiredBackendMode
    if (next === loadedBackendMode && backendLoader.active === (next !== 0)) return
    backendLoader.active = false
    loadedBackendMode = next
    backendLoader.active = next !== 0
  }
  onDesiredBackendModeChanged: Qt.callLater(syncBackend)
  onBackendChanged: if (backend === null) cleared()
  Component.onCompleted: Qt.callLater(syncBackend)

  Loader {
    id: backendLoader
    active: false
    sourceComponent: root.loadedBackendMode === 7 ? eventBackendComponent : quoteBackendComponent
  }

  Component {
    id: eventBackendComponent

    ReactorService {
      shell: suiteShell
      backendEnabled: root.desiredBackendMode === 7
      runtimeProbesEnabled: root.runtimeProbesEnabled
    }
  }

  Component {
    id: quoteBackendComponent

    QuoteService {
      backendEnabled: root.desiredBackendMode === 8
      runtimeProbesEnabled: root.runtimeProbesEnabled
    }
  }

  Connections {
    target: root.backend
    function onEventRaised(event) { if (root.backend) root.eventRaised(event) }
    function onCleared() { if (root.backend) root.cleared() }
  }

  IpcHandler {
    target: "shibumi-reactor"
    enabled: root.backendAdmitted

    function setMode(mode: int): string {
      return JSON.stringify({ accepted: root.setMode(mode), mode: mode })
    }
    function off(): string {
      return JSON.stringify({ accepted: root.setMode(0), mode: 0 })
    }
    function test(kind: string, argument: string): string {
      return JSON.stringify({ accepted: root.runTest(kind, argument), kind: kind })
    }
    function monsweep(): string {
      return JSON.stringify({
        accepted: root.mode === 7 && root.runTest("monsweep", ""),
        kind: "monsweep"
      })
    }
    function clear(): string {
      return JSON.stringify({ accepted: root.clear(), kind: "clear" })
    }
    function state(): string {
      return JSON.stringify({
        mode: root.mode,
        serviceLoaded: root.backendLoaded,
        backend: root.backendKind,
        armed: root.armed,
        events: root.eventCount
      })
    }
  }
}
