pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkLivenessModel.js" as LivenessModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property real availableAdapterGeneration: -1

  function fail(message) {
    console.error("network-manager-liveness-regression:", message)
    Qt.exit(1)
  }

  function snapshot(present) {
    return JSON.stringify({
      schemaVersion: 1,
      event: "snapshot",
      sequence: 1,
      present: present === true
    })
  }

  function owner(sequence, present, replacement) {
    return JSON.stringify({
      schemaVersion: 1,
      event: "owner",
      sequence: sequence,
      present: present === true,
      replacement: replacement === true
    })
  }

  component FakeWatcher: QtObject {
    signal protocolLine(string line)
    signal transportFailed()
  }

  FakeWatcher { id: lossTransport }
  FakeWatcher { id: acquisitionTransport }
  FakeWatcher { id: malformedTransport }
  FakeWatcher { id: failedTransport }

  Network.NetworkManagerLiveness {
    id: lossWatcher
    active: true
    watcherOverride: lossTransport
    startupTimeoutMs: 500
  }

  Network.NetworkManagerLiveness {
    id: acquisitionWatcher
    active: true
    watcherOverride: acquisitionTransport
    startupTimeoutMs: 500
  }

  Network.NetworkManagerLiveness {
    id: malformedWatcher
    active: true
    watcherOverride: malformedTransport
    startupTimeoutMs: 500
  }

  Network.NetworkManagerLiveness {
    id: transportWatcher
    active: true
    watcherOverride: failedTransport
    startupTimeoutMs: 500
  }

  Network.NetworkLivenessContinuity {
    id: nativeContinuity
  }

  Network.NetworkManagerLiveness {
    id: inactiveWatcher
    active: false
    continuityState: nativeContinuity
  }

  Network.NetworkManagerLiveness {
    id: nativeAuthorityOne
    active: false
    continuityState: nativeContinuity
    commandOverride: ["/bin/sh", "-c",
      "printf '%s\\n' '{\"schemaVersion\":1,\"event\":\"snapshot\",\"sequence\":1,\"present\":true}'; exec sleep 5"]
    startupTimeoutMs: 500
  }

  Network.NetworkManagerLiveness {
    id: nativeAuthorityTwo
    active: false
    continuityState: nativeContinuity
    commandOverride: ["/bin/sh", "-c",
      "printf '%s\\n' '{\"schemaVersion\":1,\"event\":\"snapshot\",\"sequence\":1,\"present\":true}'; exec sleep 5"]
    startupTimeoutMs: 500
  }

  QtObject {
    id: livenessBackend
    property bool backendAvailable: lossWatcher.serviceUsable
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: []
  }

  Network.NetworkBackendAdapter {
    id: bindingAdapter
    active: true
    backendOverride: livenessBackend
    nativeLiveness: lossWatcher
  }

  Network.NetworkBackendAdapter {
    id: gatedNativeAdapter
    active: true
    nativeLiveness: lossWatcher
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (root.ticks < 3) return
        const duplicateRecords = [
          '{"schemaVersion":0,"schemaVersion":1,"event":"snapshot","sequence":1,"present":true}',
          '{"schemaVersion":1,"event":"owner","event":"snapshot","sequence":1,"present":true}',
          '{"schemaVersion":1,"event":"snapshot","sequence":0,"sequence":1,"present":true}',
          '{"schemaVersion":1,"event":"snapshot","sequence":1,"present":false,"present":true}',
          '{"schemaVersion":1,"event":"owner","sequence":2,"present":true,"replacement":false,"replacement":true}'
        ]
        for (let index = 0; index < duplicateRecords.length; index++) {
          if (LivenessModel.parseLine(duplicateRecords[index]).ok)
            return root.fail("duplicate protocol field was accepted")
        }
        if (inactiveWatcher.workerRunning || inactiveWatcher.helperReady
            || inactiveWatcher.phase !== "inactive"
            || gatedNativeAdapter.nativeGatewayLoaded)
          return root.fail("inactive watcher acquired host resources")
        lossTransport.protocolLine(root.snapshot(true))
        acquisitionTransport.protocolLine(root.snapshot(false))
        malformedTransport.protocolLine(root.snapshot(false))
        failedTransport.protocolLine(root.snapshot(true))
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!lossWatcher.serviceUsable || lossWatcher.phase !== "available"
            || acquisitionWatcher.serviceUsable
            || acquisitionWatcher.phase !== "absent"
            || malformedWatcher.serviceUsable
            || !transportWatcher.serviceUsable
            || !bindingAdapter.backendAvailable
            || !gatedNativeAdapter.nativeGatewayLoaded)
          return
        root.availableAdapterGeneration = bindingAdapter.generation
        lossTransport.protocolLine(root.owner(2, false, false))
        acquisitionTransport.protocolLine(root.owner(2, true, false))
        malformedTransport.protocolLine(root.owner(3, true, false))
        failedTransport.transportFailed()
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (lossWatcher.serviceUsable || !lossWatcher.recoveryBlocked
            || lossWatcher.servicePresent || bindingAdapter.backendAvailable
            || bindingAdapter.deviceSnapshots.length !== 0
            || gatedNativeAdapter.nativeGatewayLoaded
            || bindingAdapter.generation <= root.availableAdapterGeneration)
          return root.fail("owner loss did not close adapter generation")
        if (!acquisitionWatcher.serviceUsable
            || acquisitionWatcher.recoveryBlocked)
          return root.fail("first acquisition was treated as recovery")
        if (malformedWatcher.helperReady || malformedWatcher.serviceUsable
            || !malformedWatcher.recoveryBlocked)
          return root.fail("sequence gap did not latch recovery closed")
        if (transportWatcher.helperReady || transportWatcher.serviceUsable
            || !transportWatcher.recoveryBlocked)
          return root.fail("monitoring gap did not block recovery")

        lossTransport.protocolLine(root.owner(3, true, false))
        acquisitionTransport.protocolLine(root.owner(3, true, true))
        malformedTransport.protocolLine(root.snapshot(true))
        failedTransport.protocolLine(root.snapshot(true))
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (!lossWatcher.servicePresent || lossWatcher.serviceUsable
            || lossWatcher.phase !== "recovery-blocked"
            || !acquisitionWatcher.servicePresent
            || acquisitionWatcher.serviceUsable
            || !acquisitionWatcher.recoveryBlocked
            || !malformedWatcher.servicePresent
            || malformedWatcher.serviceUsable
            || !malformedWatcher.recoveryBlocked
            || !transportWatcher.servicePresent
            || transportWatcher.serviceUsable
            || !transportWatcher.recoveryBlocked)
          return root.fail("reacquisition contract was not fail closed")

        malformedTransport.protocolLine(JSON.stringify({
          schemaVersion: 1,
          event: "owner",
          sequence: 2,
          present: false,
          replacement: false,
          owner: ":fixture"
        }))
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (malformedWatcher.helperReady || malformedWatcher.serviceUsable
            || !malformedWatcher.recoveryBlocked)
          return root.fail("unknown protocol field did not block live state")
        lossWatcher.active = false
        acquisitionWatcher.active = false
        malformedWatcher.active = false
        transportWatcher.active = false
        if (lossWatcher.servicePresent || acquisitionWatcher.servicePresent
            || malformedWatcher.servicePresent || transportWatcher.servicePresent)
          return root.fail("watcher teardown retained owner state")
        nativeAuthorityOne.active = true
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (!nativeAuthorityOne.authorized
            || !nativeAuthorityOne.workerRunning
            || !nativeAuthorityOne.serviceUsable) return
        nativeAuthorityTwo.active = true
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (nativeAuthorityTwo.authorized || nativeAuthorityTwo.workerRunning)
          return root.fail("standby liveness watcher duplicated native worker")
        if (root.ticks < 5) return
        nativeAuthorityOne.active = false
        root.phase = 7
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (!nativeAuthorityTwo.authorized
            || !nativeAuthorityTwo.workerRunning
            || !nativeAuthorityTwo.servicePresent) return
        if (nativeAuthorityTwo.serviceUsable
            || !nativeAuthorityTwo.recoveryBlocked)
          return root.fail("monitor handoff trusted an unobserved continuity gap")
        if (nativeAuthorityOne.workerRunning)
          return root.fail("retired liveness owner retained its worker")
        nativeAuthorityTwo.active = false
        inactiveWatcher.active = true
        root.phase = 8
        root.ticks = 0
        return
      }

      if (root.ticks < 20) return
      if (inactiveWatcher.serviceUsable || inactiveWatcher.servicePresent)
        return root.fail("missing system bus became actionable")
      inactiveWatcher.active = false
      console.log("network manager liveness regression passed")
      Qt.exit(0)
    }
  }
}
