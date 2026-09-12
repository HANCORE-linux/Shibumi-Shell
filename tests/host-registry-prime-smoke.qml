import QtQuick
import Quickshell
import Quickshell.Io
import "hancore.shibumi.state/runtime" as Shared

ShellRoot {
  id: root

  readonly property string mode: Quickshell.env("SHIBUMI_PRIME_MODE")
  property int stage: 0
  property int attempts: 0
  property int rescanCalls: 0
  property var firstBar: null
  property var replacementBar: null

  function fail(message) {
    console.error("host-registry-prime-smoke:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  QtObject {
    id: stateOwner
    property bool ready: true
  }

  QtObject {
    id: stateHost
    property string pluginId: "hancore.shibumi.state"
  }

  Shared.Provider {
    id: stateProvider
    pluginId: "hancore.shibumi.state"
    implementationVersion: "0.1.1-beta.12"
    owner: stateOwner
    host: stateHost
    manifest: ({ id: "hancore.shibumi.state",
      version: "0.1.1-beta.12", kinds: ["service"] })
  }

  QtObject {
    id: barHost
    property string pluginId: "hancore.shibumi.bar"
  }

  Component {
    id: barFactory
    Item {
      id: owner
      Shared.Provider {
        pluginId: "hancore.shibumi.bar"
        implementationVersion: "0.1.1-beta.12"
        owner: owner
        host: barHost
        manifest: ({ id: "hancore.shibumi.bar",
          version: "0.1.1-beta.12", kinds: ["bar"] })
      }
    }
  }

  Timer {
    id: replacementTimer
    interval: 20
    repeat: false
    onTriggered: {
      if (root.firstBar) root.firstBar.destroy()
      root.firstBar = null
      root.replacementBar = barFactory.createObject(root)
    }
  }

  IpcHandler {
    target: "shell"
    function rescanPlugins(): void {
      root.rescanCalls++
      if (root.mode === "success") replacementTimer.restart()
    }
  }

  Component.onCompleted: {
    if (["success", "no-rebuild"].indexOf(mode) < 0)
      fail("invalid SHIBUMI_PRIME_MODE")
    Shared.Runtime.hostRegistryPrimeTimeoutMs = 300
  }

  Timer {
    interval: 10
    repeat: true
    running: true

    onTriggered: {
      root.attempts++
      if (root.attempts > 500) root.fail("timed out at stage " + root.stage)

      if (root.stage === 0) {
        if (!Shared.Runtime.ready || !stateProvider.registered) return
        root.firstBar = barFactory.createObject(root)
        root.stage = 1
        root.attempts = 0
        return
      }

      if (root.stage === 1) {
        if (!root.firstBar || !Shared.Runtime.isActiveBar(root.firstBar)) return
        if (Shared.Runtime.requestHostRegistryPrime(
              root.firstBar, Quickshell.processId + 1)
            || Shared.Runtime.hostRegistryPrimeAttemptCount !== 0)
          return root.fail("wrong process id was admitted")
        if (Shared.Runtime.requestHostRegistryPrime(
              root.firstBar, Quickshell.processId)
            || Shared.Runtime.hostRegistryPrimeAttemptCount !== 1
            || Shared.Runtime.hostRegistryPrimePhase !== "dispatching")
          return root.fail("initial prime claim was not one-shot")
        Shared.Runtime.requestHostRegistryPrime(
          root.firstBar, Quickshell.processId)
        if (Shared.Runtime.hostRegistryPrimeAttemptCount !== 1)
          return root.fail("duplicate request dispatched another prime")
        root.stage = 2
        root.attempts = 0
        return
      }

      if (root.mode === "success") {
        if (Shared.Runtime.hostRegistryPrimePhase !== "ready") return
        if (!root.replacementBar
            || !Shared.Runtime.isActiveBar(root.replacementBar)
            || !Shared.Runtime.hostRegistryPrimeReadyFor(
              root.replacementBar, Quickshell.processId)
            || !Shared.Runtime.requestHostRegistryPrime(
              root.replacementBar, Quickshell.processId)
            || root.rescanCalls !== 1
            || Shared.Runtime.hostRegistryPrimeAttemptCount !== 1)
          return root.fail("replacement Bar was not exclusively admitted")
        console.log("host registry prime success passed")
        Qt.exit(0)
        return
      }

      if (Shared.Runtime.hostRegistryPrimePhase !== "failed") return
      if (root.rescanCalls !== 1
          || Shared.Runtime.hostRegistryPrimeAttemptCount !== 1
          || !root.firstBar || !Shared.Runtime.isActiveBar(root.firstBar)
          || Shared.Runtime.hostRegistryPrimeReadyFor(
            root.firstBar, Quickshell.processId)
          || Shared.Runtime.requestHostRegistryPrime(
            root.firstBar, Quickshell.processId))
        return root.fail("missing rebuild did not fail closed")
      console.log("host registry prime no-rebuild failure passed")
      Qt.exit(0)
    }
  }
}
