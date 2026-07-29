pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "reactor" as Reactor
import "audio" as Audio

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property var lastEvent: null
  property int raisedCount: 0
  property int clearedCount: 0

  function fail(message) {
    console.error("reactor-plugin-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeState
    property bool ready: true
    property int revision: 0
    property var config: ({ reactor: { mode: 0 } })
    function setReactorMode(value) {
      const mode = Number(value)
      if (!Number.isInteger(mode) || mode < 0 || mode > 8) return false
      config = ({ reactor: { mode: mode } })
      revision++
      return true
    }
  }

  QtObject {
    id: fakeWorkspace
    property int focusedId: 1
    function workspaceState(_id) { return ({ windowCount: 2 }) }
  }

  QtObject {
    id: fakePendingModel
    property int count: 0
    function get(_index) { return null }
  }

  QtObject {
    id: fakeNotifications
    property var pendingModel: fakePendingModel
  }

  QtObject {
    id: fakeStatus
    property bool notificationsSilenced: false
    property string voxtypeState: "idle"
    property var notificationService: fakeNotifications
  }

  QtObject {
    id: fakePower
    property bool hasBattery: true
    property bool discharging: false
    property int percent: 80
  }

  QtObject {
    id: fakeAi
    property var providers: []
    function usagePercent(_provider) { return 0 }
  }

  QtObject { id: fakeNetwork; property string kind: "wifi" }

  Audio.Service { id: fakeAudio }

  QtObject {
    id: fakeUpdate
    property int totalUpdateCount: 0
  }

  QtObject {
    id: fakeMedia
    property string title: ""
    property string artist: ""
    property string album: ""
  }

  QtObject {
    id: fakeShell
    property var bar: null
    function serviceFor(pluginId) {
      if (pluginId === "hancore.shibumi.state") return fakeState
      if (pluginId === "hancore.shibumi.reactor") return reactorService
      if (pluginId === "hancore.shibumi.workspaces") return fakeWorkspace
      if (pluginId === "hancore.shibumi.status") return fakeStatus
      if (pluginId === "hancore.shibumi.power-state") return fakePower
      if (pluginId === "hancore.shibumi.ai") return fakeAi
      if (pluginId === "hancore.shibumi.network") return fakeNetwork
      if (pluginId === "hancore.shibumi.audio") return fakeAudio
      if (pluginId === "hancore.shibumi.update-center") return fakeUpdate
      return null
    }
    function firstPartyServiceFor(pluginId) {
      if (pluginId === "omarchy.media") return fakeMedia
      return null
    }
  }

  Reactor.Service {
    id: reactorService
    shell: fakeShell
    runtimeProbesEnabled: false
  }

  Connections {
    target: reactorService
    function onEventRaised(event) {
      root.lastEvent = event
      root.raisedCount++
    }
    function onCleared() { root.clearedCount++ }
  }

  Timer {
    id: watchdog
    interval: 6000
    running: true
    onTriggered: root.fail("timeout in phase " + root.phase)
  }

  Timer {
    interval: 60
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks < 3) return

      if (root.phase === 0) {
        if (!reactorService.ready || reactorService.mode !== 0
            || reactorService.backendLoaded || reactorService.backendKind !== "none"
            || reactorService.runTest("text", "NO|BACKEND"))
          return root.fail("mode-zero gating")
        fakeAudio.report(root, true, false)
        reactorService.setMode(7)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (reactorService.mode !== 7 || !reactorService.backendLoaded
            || reactorService.backendKind !== "events"
            || reactorService.backend.audioService !== fakeAudio
            || reactorService.backend.networkService !== fakeNetwork)
          return root.fail("event backend dependency resolution")
        if (!reactorService.runTest("text-short", "LOCAL|EVENT"))
          return root.fail("event test rejected")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.raisedCount !== 1 || !root.lastEvent
            || root.lastEvent.left !== "LOCAL" || root.lastEvent.right !== "EVENT"
            || reactorService.eventHistory.length !== 1)
          return root.fail("event forwarding")
        reactorService.clear()
        reactorService.setMode(8)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.clearedCount !== 1 || reactorService.mode !== 8
            || !reactorService.backendLoaded
            || reactorService.backendKind !== "quotes"
            || !reactorService.runTest("quote", ""))
          return root.fail("quote backend activation")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 4) {
        if (root.raisedCount !== 2 || !root.lastEvent
            || root.lastEvent.profile !== "quote"
            || reactorService.eventCount !== 1)
          return root.fail("quote forwarding")
        reactorService.setMode(0)
        root.phase++
        root.ticks = 0
      } else {
        if (reactorService.mode !== 0 || reactorService.backendLoaded
            || reactorService.backendKind !== "none" || fakeState.revision !== 3)
          return root.fail("backend teardown")
        fakeAudio.release(root)
        if (fakeAudio.ready) return root.fail("audio snapshot cleanup")
        stop()
        watchdog.stop()
        console.log("reactor plugin smoke passed")
        Qt.quit()
      }
    }
  }
}
