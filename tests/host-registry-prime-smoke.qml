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
  property var newestBar: null
  property var overlappingBar: null
  readonly property string privateCanary: "registry-prime-private-path-user-data"

  function fail(message) {
    console.error("host-registry-prime-smoke:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  function warningEvidence(pluginId, screenLabel) {
    return {
      pluginId: pluginId || "fixture.widget",
      screenLabel: screenLabel || "TEST-1",
      retryCount: 10,
      facadeScoped: true,
      facadeRegistryPresent: true,
      facadeConfigured: true,
      facadeEnabled: true,
      previouslyResolved: true,
      outputSequence: true,
      shutdown: false
    }
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
    implementationVersion: "0.1.1-beta.15"
    owner: stateOwner
    host: stateHost
    manifest: ({ id: "hancore.shibumi.state",
      version: "0.1.1-beta.15", kinds: ["service"] })
  }

  QtObject {
    id: barHost
    property string pluginId: "hancore.shibumi.bar"
  }

  Component {
    id: barFactory
    Item {
      id: owner
      property var providerHost: barHost
      property string privateMetadata: root.privateCanary
      property bool shutdownPrepared: false
      property bool screensaverPreHidden: false
      property bool mutationAdmissionReady: true
      property bool warningEligible: true
      function hostWidgetResolutionWarningCurrent(pluginId) {
        return warningEligible && pluginId === "fixture.widget"
      }
      Shared.Provider {
        pluginId: "hancore.shibumi.bar"
        implementationVersion: "0.1.1-beta.15"
        owner: owner
        host: owner.providerHost
        manifest: ({ id: "hancore.shibumi.bar",
          version: "0.1.1-beta.15", kinds: ["bar"] })
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

  Timer {
    id: scopeLossTimer
    interval: 20
    repeat: false
    onTriggered: {
      if (root.firstBar) root.firstBar.providerHost = null
    }
  }

  IpcHandler {
    target: "shell"
    function rescanPlugins(): void {
      if (root.mode === "refusal") {
        Shared.Runtime.hostRegistryPrimeProcess.signal(15)
        return
      }
      root.rescanCalls++
      if (["success", "owner-change", "process-change", "diagnostic"]
          .indexOf(root.mode) >= 0)
        replacementTimer.restart()
      else if (root.mode === "scope-loss")
        scopeLossTimer.restart()
    }
  }

  Component.onCompleted: {
    if (["success", "refusal", "timeout", "owner-change",
         "process-change", "scope-loss", "diagnostic"].indexOf(mode) < 0)
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

      const primeSucceeds = ["success", "owner-change", "process-change",
        "diagnostic"].indexOf(root.mode) >= 0
      if (primeSucceeds) {
        if (root.stage === 5) {
          if (!root.replacementBar
              || !Shared.Runtime.isActiveBar(root.replacementBar)) return
          const firstWarning = Shared.Runtime.noteHostWidgetResolutionExhausted(
            root.replacementBar, Quickshell.processId,
            root.warningEvidence("fixture.widget", "DP/private"))
          const duplicateWarning = Shared.Runtime.noteHostWidgetResolutionExhausted(
            root.replacementBar, Quickshell.processId,
            root.warningEvidence())
          if (!firstWarning || duplicateWarning)
            return root.fail("passive warning was not process bounded: "
              + JSON.stringify({first: firstWarning,
                duplicate: duplicateWarning,
                emitted: Shared.Runtime.hostWidgetResolutionWarningEmitted,
                prime: Shared.Runtime.hostRegistryPrimePhase,
                state: Shared.Runtime.serviceFor("hancore.shibumi.state") !== null}))
          stateHost.pluginId = ""
          stateHost.pluginId = "hancore.shibumi.state"
          root.replacementBar.destroy()
          root.replacementBar = null
          root.newestBar = barFactory.createObject(root)
          root.stage = 4
          root.attempts = 0
          return
        }
        if (root.stage === 3) {
          if (!root.newestBar || !Shared.Runtime.isActiveBar(root.newestBar)) return
          if (!Shared.Runtime.hostRegistryPrimeReadyFor(
                root.newestBar, Quickshell.processId)
              || !Shared.Runtime.requestHostRegistryPrime(
                root.newestBar, Quickshell.processId)
              || root.rescanCalls !== 1
              || Shared.Runtime.hostRegistryPrimeAttemptCount !== 1)
            return root.fail("post-prime owner change lost process admission")
          console.log("host registry prime owner-change passed")
          Qt.exit(0)
          return
        }
        if (root.stage === 4) {
          if (!root.newestBar || !Shared.Runtime.isActiveBar(root.newestBar)
              || Shared.Runtime.noteHostWidgetResolutionExhausted(
                root.newestBar, Quickshell.processId,
                root.warningEvidence())
              || !Shared.Runtime.hostWidgetResolutionWarningEmitted
              || root.rescanCalls !== 1
              || Shared.Runtime.hostRegistryPrimeAttemptCount !== 1)
            return root.fail("owner replacement replenished warning or rescan budget")
          console.log("host registry prime diagnostic passed")
          Qt.exit(0)
          return
        }
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
        if (root.mode === "owner-change") {
          root.replacementBar.destroy()
          root.replacementBar = null
          root.newestBar = barFactory.createObject(root)
          root.stage = 3
          root.attempts = 0
          return
        }
        if (root.mode === "diagnostic") {
          const invalid = root.warningEvidence("../private", "DP/private")
          root.replacementBar.warningEligible = false
          if (Shared.Runtime.noteHostWidgetResolutionExhausted(
                root.replacementBar, Quickshell.processId, invalid)
              || Shared.Runtime.noteHostWidgetResolutionExhausted(
                root.replacementBar, Quickshell.processId,
                root.warningEvidence())
              || Shared.Runtime.hostWidgetResolutionWarningEmitted)
            return root.fail("ineligible warning consumed the process budget")
          root.replacementBar.warningEligible = true
          root.overlappingBar = barFactory.createObject(root)
          if (Shared.Runtime.hasActiveBar
              || Shared.Runtime.noteHostWidgetResolutionExhausted(
                root.replacementBar, Quickshell.processId,
                root.warningEvidence()))
            return root.fail("overlapping Bar emitted a warning")
          root.overlappingBar.destroy()
          root.overlappingBar = null
          root.stage = 5
          root.attempts = 0
          return
        }
        if (root.mode === "process-change"
            && (Shared.Runtime.requestHostRegistryPrime(
                  root.replacementBar, Quickshell.processId + 1)
                || !Shared.Runtime.hostRegistryPrimeReadyFor(
                  root.replacementBar, Quickshell.processId)))
          return root.fail("changed process identity reused the prime")
        console.log("host registry prime " + root.mode + " passed")
        Qt.exit(0)
        return
      }

      if (Shared.Runtime.hostRegistryPrimePhase !== "failed") return
      const expectedCalls = root.mode === "refusal" ? 0 : 1
      const expectedOwner = root.mode === "scope-loss" ? null : root.firstBar
      if (root.rescanCalls !== expectedCalls
          || Shared.Runtime.hostRegistryPrimeAttemptCount !== 1
          || Shared.Runtime.hasActiveBar !== (expectedOwner !== null)
          || (expectedOwner && !Shared.Runtime.isActiveBar(expectedOwner))
          || (expectedOwner && Shared.Runtime.hostRegistryPrimeReadyFor(
            expectedOwner, Quickshell.processId))
          || (expectedOwner && Shared.Runtime.requestHostRegistryPrime(
            expectedOwner, Quickshell.processId))
          || (expectedOwner && Shared.Runtime.noteHostWidgetResolutionExhausted(
            expectedOwner, Quickshell.processId, root.warningEvidence()))
          || Shared.Runtime.hostWidgetResolutionWarningEmitted)
        return root.fail("failed prime did not remain fail closed")
      if (root.mode === "scope-loss") {
        root.firstBar.providerHost = barHost
        if (!Shared.Runtime.isActiveBar(root.firstBar)
            || Shared.Runtime.requestHostRegistryPrime(
              root.firstBar, Quickshell.processId))
          return root.fail("scope restoration retried a terminal prime")
      }
      console.log("host registry prime " + root.mode + " passed")
      Qt.exit(0)
    }
  }
}
