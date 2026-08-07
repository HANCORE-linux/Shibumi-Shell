import QtQuick
import Quickshell
import "../core" as Core

ShellRoot {
  id: root

  property int stage: 0
  property bool desiredVisible: true
  property bool backingAvailable: true
  property var activeScreen: fakeScreen

  function fail(message) {
    console.error("window-recovery-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeScreen
    property string name: "TEST-1"
    property int width: 1920
    property int height: 1080
  }

  QtObject {
    id: fakeWindow
    signal resourcesLost()
    signal closed()
    property bool visible: root.desiredVisible && recovery.recoveryVisible
    readonly property bool backingWindowVisible:
      root.backingAvailable && visible
  }

  Core.WindowRecovery {
    id: recovery
    targetWindow: fakeWindow
    targetScreen: root.activeScreen
    recoveryAllowed: root.desiredVisible
    retryInterval: 10
    verifyInterval: 20
    maxAttempts: 3
  }

  Timer {
    id: probe
    interval: 5
    repeat: true
    running: true
    onTriggered: {
      if (root.stage === 0) {
        if (!fakeWindow.visible) return root.fail("initial binding is false")
        fakeWindow.resourcesLost()
        fakeScreen.width = 0
        if (fakeWindow.visible)
          return root.fail("resourcesLost did not declaratively unmap the window")
        root.stage = 1
        return
      }
      if (root.stage === 1 && !recovery.pending) {
        if (!recovery.recoveryVisible)
          return root.fail("screen loss left the recovery visibility latch false")
        fakeScreen.width = 1920
        fakeWindow.resourcesLost()
        root.stage = 2
        return
      }
      if (root.stage === 2 && !recovery.pending
          && fakeWindow.backingWindowVisible) {
        root.desiredVisible = false
        if (fakeWindow.visible)
          return root.fail("resourcesLost recovery destroyed the visibility binding")
        root.desiredVisible = true
        fakeWindow.closed()
        root.stage = 3
        return
      }
      if (root.stage === 3 && !recovery.pending
          && fakeWindow.backingWindowVisible) {
        root.backingAvailable = false
        fakeWindow.resourcesLost()
        root.stage = 4
        return
      }
      if (root.stage === 4 && recovery.attempt >= 1) {
        root.activeScreen = null
        root.stage = 5
        return
      }
      if (root.stage === 5 && !recovery.pending) {
        if (!recovery.recoveryVisible)
          return root.fail("null-screen verification left the latch false")
        root.activeScreen = fakeScreen
        fakeWindow.resourcesLost()
        root.stage = 6
        return
      }
      if (root.stage === 6 && !recovery.pending && recovery.attempt >= 3) {
        root.desiredVisible = false
        root.stage = 7
        return
      }
      if (root.stage === 7) {
        if (fakeWindow.visible)
          return root.fail("retry exhaustion destroyed the visibility binding")
        console.log("window recovery regression passed")
        Qt.exit(0)
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    onTriggered: root.fail("timed out at stage " + root.stage
      + " attempt=" + recovery.attempt + " pending=" + recovery.pending)
  }
}
