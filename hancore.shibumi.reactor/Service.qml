pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Mode 0 keeps this facade worker-free. Modes 7 and 8 load exactly one
// process-wide backend and forward its events to every per-output renderer.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property bool runtimeProbesEnabled: true

  readonly property var stateService: shell
    && typeof shell.serviceFor === "function"
    ? shell.serviceFor("hancore.shibumi.state") : null
  readonly property int mode: stateService && stateService.config
    && stateService.config.reactor
    ? Math.max(0, Math.min(8, Number(stateService.config.reactor.mode) || 0)) : 0
  readonly property bool ready: stateService !== null
    && stateService.ready === true
  readonly property var backend: backendLoader.item
  readonly property bool backendLoaded: backend !== null
  readonly property string backendKind: mode === 7 && backendLoaded ? "events"
    : mode === 8 && backendLoaded ? "quotes" : "none"
  readonly property bool armed: backendLoaded && backend.armed === true
  readonly property var eventHistory: mode === 7 && backendLoaded
    ? backend.eventHistory : []
  readonly property int eventCount: mode === 8 && backendLoaded
    ? Number(backend.eventCount || 0) : eventHistory.length

  signal eventRaised(var event)
  signal cleared()

  visible: false
  width: 0
  height: 0

  function setMode(value) {
    const next = Number(value)
    return stateService && typeof stateService.setReactorMode === "function"
      ? stateService.setReactorMode(next) : false
  }

  function runTest(kind, argument) {
    return backendLoaded && typeof backend.runTest === "function"
      ? backend.runTest(kind, argument) : false
  }

  function clear() { return runTest("clear", "") }

  Loader {
    id: backendLoader
    active: root.ready && (root.mode === 7 || root.mode === 8)
    sourceComponent: !active ? null
      : root.mode === 7 ? eventBackendComponent : quoteBackendComponent
  }

  Component {
    id: eventBackendComponent

    ReactorService {
      shell: root.shell
      runtimeProbesEnabled: root.runtimeProbesEnabled
    }
  }

  Component {
    id: quoteBackendComponent

    QuoteService {
      runtimeProbesEnabled: root.runtimeProbesEnabled
    }
  }

  Connections {
    target: root.backend
    function onEventRaised(event) { root.eventRaised(event) }
    function onCleared() { root.cleared() }
  }

  IpcHandler {
    target: "shibumi-reactor"

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
