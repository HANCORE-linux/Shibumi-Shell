pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "reactor" as Reactor
import "styles" as Shibumi
import "hancore.shibumi.state/runtime" as SuiteRuntime

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property bool stateEnabled: false
  property bool audioEnabled: false
  property bool firstOutput: true
  property int events: 0
  property int beforeLoss: 0
  property var cachedMode: null
  property var cachedTest: null
  readonly property var manifest: ({id: "hancore.shibumi.reactor", version: "0.1.1-beta.15.3", kinds: ["service"]})
  function check(value, message) {
    if (value) return
    console.error("reactor-runtime:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  QtObject {
    id: host
    property string pluginId: "hancore.shibumi.reactor"
    function serviceFor(id) { root.check(false, "raw scoped lookup: " + id); return null }
    function firstPartyServiceFor(id) { return null }
  }
  QtObject { id: stateHost; property string pluginId: "hancore.shibumi.state" }
  QtObject { id: audioHost; property string pluginId: "hancore.shibumi.audio" }
  QtObject {
    id: state
    property bool ready: true
    property var config: ({reactor: {mode: 7}})
    property int writes: 0
    function setReactorMode(value) { writes++; config = {reactor: {mode: value}}; return true }
  }
  QtObject {
    id: audio
    property bool ready: true
    property bool outputMuted: true
  }
  SuiteRuntime.Provider {
    pluginId: "hancore.shibumi.state"; implementationVersion: "0.1.1-beta.15.3"
    owner: state; host: root.stateEnabled ? stateHost : null
    manifest: ({id: "hancore.shibumi.state", version: "0.1.1-beta.15.3", kinds: ["service"]})
  }
  SuiteRuntime.Provider {
    pluginId: "hancore.shibumi.audio"; implementationVersion: "0.1.1-beta.15.3"
    owner: audio; host: root.audioEnabled ? audioHost : null
    manifest: ({id: "hancore.shibumi.audio", version: "0.1.1-beta.15.3", kinds: ["service"]})
  }
  Reactor.Service { id: service; runtimeProbesEnabled: false }
  Reactor.Service { id: duplicate; runtimeProbesEnabled: false }
  // This is the adapter supplied by the actual Bar entrypoint for scoped hosts;
  // the BarSurface's serviceFor call must not be mistaken for raw host access.
  SuiteRuntime.HostShell { id: rendererShell; host: host }
  readonly property var facade: rendererShell.serviceFor("hancore.shibumi.reactor")
  QtObject { id: visualBar; property color urgent: "#ef7777" }
  Loader {
    id: viewA
    active: root.firstOutput && root.facade !== null && (root.facade.mode === 7 || root.facade.mode === 8)
    sourceComponent: Shibumi.ReactorEventLayer {
      bar: visualBar; service: root.facade; screenName: "left"
      runs: [{x: 0, width: 20}, {x: 100, width: 20}]
      // No scene/window: inspect real renderer routing/lifetime, not pixels.
      width: 0; height: 0
    }
  }
  Loader {
    id: viewB
    active: root.facade !== null && (root.facade.mode === 7 || root.facade.mode === 8)
    sourceComponent: Shibumi.ReactorEventLayer {
      bar: visualBar; service: root.facade; screenName: "right"
      runs: [{x: 0, width: 20}, {x: 100, width: 20}]
      width: 0; height: 0
    }
  }
  Connections { target: service; function onEventRaised(event) { root.events++ } }
  Timer {
    interval: 30; repeat: true; running: true
    onTriggered: {
      root.check(++root.ticks < 180, "phase deadline " + root.phase)
      if (!SuiteRuntime.Runtime.ready) return
      if (root.phase === 0) {
        root.check(!service.backendAdmitted && !service.backendLoaded && !viewA.item
          && service.setMode(7) === false && service.runTest("text", "NO") === false,
          "pre-injection backend or action")
        service.shell = host
      } else if (root.phase === 1) {
        root.check(!service.backendAdmitted && !service.backendLoaded, "partial admission")
        service.manifest = root.manifest
      } else if (root.phase === 2) {
        if (!service.backendAdmitted) return
        root.check(!service.ready && !service.backendLoaded && !viewA.item,
          "missing State created backend or renderer")
        root.stateEnabled = true; root.audioEnabled = true
      } else if (root.phase === 3) {
        if (!service.backend || !viewA.item || !viewB.item) return
        root.check(service.backendKind === "events" && service.backend.audioService === audio
          && viewA.item !== viewB.item && viewA.item.service === service && viewB.item.service === service,
          "shared backend/local renderer identity")
        service.backend.armed = true
        service.backend.publish("text", {left: "LOCAL", screen: "left"})
      } else if (root.phase === 4) {
        root.check(viewA.item.pulses.length === 1 && viewB.item.pulses.length === 0,
          "targeted event crossed outputs")
        service.clear()
        root.beforeLoss = root.events
        root.audioEnabled = false
      } else if (root.phase === 5) {
        root.check(root.events === root.beforeLoss && !service.backend.audioService,
          "Audio removal emitted false UNMUTED")
        root.audioEnabled = true
      } else if (root.phase === 6) {
        root.check(root.events === root.beforeLoss && service.backend.audioService === audio,
          "Audio readmission emitted false MUTED")
        audio.ready = false
      } else if (root.phase === 7) {
        root.check(root.events === root.beforeLoss, "Audio unavailable emitted mute event")
        audio.ready = true
      } else if (root.phase === 8) {
        root.check(root.events === root.beforeLoss, "Audio reconnect emitted mute event")
        audio.outputMuted = false
      } else if (root.phase === 9) {
        root.check(root.events === root.beforeLoss + 1
          && service.eventHistory[service.eventHistory.length - 1].right === "UNMUTED",
          "real controlled mute transition not forwarded exactly once")
        root.firstOutput = false
      } else if (root.phase === 10) {
        root.check(!viewA.item && viewB.item && service.backendKind === "events",
          "local output removal destroyed shared owner or sibling")
        root.cachedMode = service.setMode; root.cachedTest = service.runTest
        service.shell = null
        root.check(!service.backend && root.cachedTest("text", "STALE") === false,
          "scope loss retained immediate backend action")
      } else if (root.phase === 11) {
        root.check(!service.backendLoaded && !viewB.item && root.cachedMode(8) === false,
          "scope loss retained backend/renderer/write")
        service.shell = host
      } else if (root.phase === 12) {
        if (!service.backend) return
        root.check(service.backendKind === "events" && viewB.item, "scope recovery")
        service.setMode(8)
      } else if (root.phase === 13) {
        if (!service.backend || service.backendKind !== "quotes") return
        root.check(viewB.item.pulses.length === 0 && service.runTest("quote", "") === true,
          "mode replacement retained old pulses or refused quote")
        duplicate.shell = host; duplicate.manifest = root.manifest
      } else if (root.phase === 14) {
        root.check(!service.backendAdmitted && !duplicate.backendAdmitted
          && !service.backendLoaded && !duplicate.backendLoaded && !viewB.item
          && root.cachedTest("quote", "") === false, "duplicate retained owner/backend")
        duplicate.manifest = null
      } else if (root.phase === 15) {
        if (!service.backend) return
        state.ready = false
      } else if (root.phase === 16) {
        root.check(!service.ready && service.mode === 0 && !service.backendLoaded && !viewB.item
          && root.cachedMode(7) === false, "State unready retained backend/write")
        state.ready = true
        state.config = {reactor: {mode: 0}}
        state.config = {reactor: {mode: 7}}
        state.config = {reactor: {mode: 8}}
      } else if (root.phase === 17) {
        if (!service.backend) return
        root.check(service.backendKind === "quotes", "queued callback applied stale mode")
        service.setMode(0)
      } else {
        root.check(service.ready && !service.backendLoaded && !viewA.item && !viewB.item,
          "mode-zero teardown")
        console.log("reactor runtime smoke passed")
        Qt.exit(0)
        return
      }
      root.phase++
    }
  }
}
