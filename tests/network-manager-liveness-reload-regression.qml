pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int ticks: 0

  function fail(message) {
    console.error("network-manager-liveness-reload-regression:", message)
    Qt.exit(1)
  }

  PersistentProperties {
    id: testState
    reloadableId: "networkManagerLivenessReloadTestState"
    property int phase: 0
    property bool afterReload: false
    property bool postReloadSnapshotSent: false
    onReloaded: afterReload = true
  }

  Network.NetworkLivenessContinuity {
    id: continuityState
  }

  QtObject {
    id: fakeTransport
    signal protocolLine(string line)
    signal transportFailed()
  }

  Network.NetworkManagerLiveness {
    id: liveness
    active: true
    watcherOverride: fakeTransport
    continuityState: continuityState
    startupTimeoutMs: 1000
  }

  Connections {
    target: Quickshell
    function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("reload lifecycle timed out")

      if (testState.phase === 0) {
        fakeTransport.protocolLine(
          '{"schemaVersion":1,"event":"snapshot","sequence":1,"present":true}')
        testState.phase = 1
        return
      }

      if (testState.phase === 1) {
        if (!liveness.serviceUsable) return
        fakeTransport.protocolLine(
          '{"schemaVersion":1,"event":"owner","sequence":2,"present":false,"replacement":false}')
        fakeTransport.protocolLine(
          '{"schemaVersion":1,"event":"owner","sequence":3,"present":true,"replacement":false}')
        if (!liveness.recoveryBlocked || !liveness.processRestartRequired
            || liveness.serviceUsable || !liveness.servicePresent)
          return root.fail("pre-reload owner loss did not block recovery")
        testState.phase = 2
        Quickshell.reload(false)
        return
      }

      if (!testState.afterReload) return
      if (!testState.postReloadSnapshotSent) {
        testState.postReloadSnapshotSent = true
        fakeTransport.protocolLine(
          '{"schemaVersion":1,"event":"snapshot","sequence":1,"present":true}')
        return
      }
      if (!liveness.helperReady || !liveness.servicePresent) return
      if (!liveness.recoveryBlocked || liveness.serviceUsable
          || liveness.phase !== "recovery-blocked")
        return root.fail("soft reload reopened process-lifetime backend: "
          + JSON.stringify({
            blocked: liveness.recoveryBlocked,
            restart: liveness.processRestartRequired,
            usable: liveness.serviceUsable,
            phase: liveness.phase,
            helper: liveness.helperReady,
            present: liveness.servicePresent
          }))
      console.log("network manager liveness reload regression passed")
      Qt.exit(0)
    }
  }
}
