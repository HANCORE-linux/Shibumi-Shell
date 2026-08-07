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
  property bool recoveryVisible: true
  property int retryInterval: 750
  property int verifyInterval: 1200
  property int maxAttempts: 3

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
    recoveryVisible = false
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
      recoveryVisible = true
    }
  }

  Timer {
    id: retryTimer
    interval: root.retryInterval
    onTriggered: {
      if (!root.recoveryAllowed || !root.screenReady()) {
        root.pending = false
        root.pendingReason = ""
        root.recoveryVisible = true
        return
      }
      if (root.attempt === 0)
        console.warn("[Shibumi WindowRecovery] " + root.targetScreen.name
          + ": " + root.pendingReason)
      root.attempt++
      root.recoveryVisible = true
      verifyTimer.restart()
    }
  }

  Timer {
    id: verifyTimer
    interval: root.verifyInterval
    onTriggered: {
      if (!root.recoveryAllowed) {
        root.pending = false
        root.recoveryVisible = true
        return
      }
      if (root.targetWindow.backingWindowVisible) {
        root.pending = false
        root.attempt = 0
        root.pendingReason = ""
      } else if (root.attempt < root.maxAttempts && root.screenReady()) {
        root.recoveryVisible = false
        retryTimer.restart()
      } else {
        const screenName = root.targetScreen
          ? String(root.targetScreen.name || "unknown") : "removed output"
        console.warn("[Shibumi WindowRecovery] targeted recovery failed for " + screenName)
        root.pending = false
        root.pendingReason = ""
        root.recoveryVisible = true
      }
    }
  }
}
