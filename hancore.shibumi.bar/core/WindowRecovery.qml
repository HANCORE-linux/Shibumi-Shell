import QtQuick
import Quickshell

Scope {
  id: root

  required property var targetWindow
  required property var targetScreen
  property bool recoveryAllowed: true
  property bool pending: false
  property int attempt: 0
  property string pendingReason: ""

  function screenReady() {
    return targetScreen !== null
      && targetScreen.name !== ""
      && targetScreen.width > 0
      && targetScreen.height > 0
  }

  function schedule(reason) {
    if (!recoveryAllowed || pending || !screenReady()) return
    pending = true
    attempt = 0
    pendingReason = String(reason || "recovery")
    retryTimer.restart()
  }

  Connections {
    target: root.targetWindow
    function onResourcesLost() { root.schedule("resourcesLost") }
    function onClosed() { root.schedule("closed") }
  }

  onRecoveryAllowedChanged: {
    if (!recoveryAllowed) {
      retryTimer.stop()
      verifyTimer.stop()
      pending = false
      attempt = 0
      pendingReason = ""
    }
  }

  Timer {
    id: retryTimer
    interval: 750
    onTriggered: {
      if (!root.recoveryAllowed || !root.screenReady()) {
        root.pending = false
        root.pendingReason = ""
        return
      }
      if (root.attempt === 0)
        console.warn("[Shibumi WindowRecovery] " + root.targetScreen.name
          + ": " + root.pendingReason)
      root.attempt++
      root.targetWindow.visible = true
      verifyTimer.restart()
    }
  }

  Timer {
    id: verifyTimer
    interval: 1200
    onTriggered: {
      if (!root.recoveryAllowed) {
        root.pending = false
        return
      }
      if (root.targetWindow.backingWindowVisible) {
        root.pending = false
        root.attempt = 0
        root.pendingReason = ""
      } else if (root.attempt < 3 && root.screenReady()) {
        retryTimer.restart()
      } else {
        console.warn("[Shibumi WindowRecovery] targeted recovery failed for " + root.targetScreen.name)
        root.pending = false
        root.pendingReason = ""
      }
    }
  }
}
