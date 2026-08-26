pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property bool staleInjected: false
  readonly property string fixturePath:
    Qt.resolvedUrl("fixtures/network-qr-secret-fixture.py")
      .toString().replace(/^file:\/\//, "")
  readonly property string deviceId: NetworkModel.deviceId(
    "wifi", "02:00:00:00:00:01", "wlan0")
  readonly property string networkId: NetworkModel.networkId(
    root.deviceId, "Private", "wpa2-psk")
  readonly property var descriptor: ({
    networkId: root.networkId,
    profileUuid: "11111111-2222-4333-8444-555555555555",
    deviceId: root.deviceId,
    interfaceName: "wlan0",
    hardwareAddress: "02:00:00:00:00:01",
    ssid: "Private",
    ssidHex: "50726976617465",
    security: "wpa2-psk",
    generation: 7
  })

  function fail(message) {
    console.error("network-qr-secret-dispatcher-regression:", message)
    Qt.exit(1)
  }

  function start(mode, nextPhase) {
    consumer.ready = false
    dispatcher.commandOverride = [
      "/usr/bin/python3", root.fixturePath, mode
    ]
    const result = dispatcher.request(consumer, root.descriptor)
    if (!result.accepted || !result.requestToken) {
      root.fail("QR secret fixture was rejected: " + mode)
      return false
    }
    consumer.expectedToken = result.requestToken
    root.phase = nextPhase
    root.ticks = 0
    return true
  }

  QtObject {
    id: liveness
    property bool serviceUsable: true
  }

  QtObject {
    id: service
    property bool current: true
    function qrSecretRequestCurrent(_descriptor) { return current }
  }

  QtObject {
    id: consumer
    property int stagedCount: 0
    property int committedCount: 0
    property int rejectedCount: 0
    property bool ready: false
    property string expectedToken: ""
    property string rejectedCode: ""
    function stageSavedSecret(evidence, psk) {
      if (!evidence || evidence.requestToken !== expectedToken
          || psk !== "correct horse" || ready) return false
      stagedCount++
      return true
    }
    function commitSavedSecret(requestToken) {
      if (requestToken !== expectedToken || ready) return false
      committedCount++
      ready = true
      return true
    }
    function rejectSavedSecret(requestToken, code) {
      if (requestToken !== expectedToken) return false
      rejectedCount++
      rejectedCode = String(code || "")
      ready = false
      return true
    }
  }

  Network.NetworkQrSecretDispatcher {
    id: dispatcher
    active: true
    networkService: service
    nativeLiveness: liveness
    workerTimeoutMs: 1000
    drainTimeoutMs: 100
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, "chunked"
    ]
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 240)
        return root.fail("timed out in phase " + root.phase)
      if (root.phase === 0) {
        if (!dispatcher.authorized) return
        root.start("chunked", 1)
        return
      }
      if (root.phase === 1) {
        if (dispatcher.phase !== "succeeded") return
        if (consumer.stagedCount !== 1 || consumer.committedCount !== 1
            || consumer.rejectedCount !== 0 || !consumer.ready)
          return root.fail("clean chunked completion did not commit once")
        root.start("delayed-exit", 2)
        return
      }
      if (root.phase === 2) {
        if (dispatcher.phase === "staged" && !root.staleInjected) {
          root.staleInjected = true
          service.current = false
          return
        }
        if (dispatcher.phase !== "failed" || dispatcher.workerRunning) return
        if (consumer.stagedCount !== 2 || consumer.committedCount !== 1
            || consumer.rejectedCount !== 1 || consumer.ready)
          return root.fail("stale topology committed a staged QR")
        service.current = true
        root.start("malformed", 3)
        return
      }
      if (root.phase === 3) {
        if (dispatcher.phase !== "failed" || dispatcher.workerRunning) return
        if (consumer.stagedCount !== 2 || consumer.committedCount !== 1
            || consumer.rejectedCount !== 2 || consumer.ready)
          return root.fail("malformed output crossed the secret boundary")
        root.start("extra", 4)
        return
      }
      if (root.phase === 4) {
        if (dispatcher.phase !== "failed" || dispatcher.workerRunning) return
        if (consumer.stagedCount !== 3 || consumer.committedCount !== 1
            || consumer.rejectedCount !== 3 || consumer.ready)
          return root.fail("extra output left a staged QR visible")
        root.start("nonzero", 5)
        return
      }
      if (root.phase === 5) {
        if (dispatcher.phase !== "failed" || dispatcher.workerRunning) return
        if (consumer.stagedCount !== 4 || consumer.committedCount !== 1
            || consumer.rejectedCount !== 4 || consumer.ready)
          return root.fail("nonzero exit committed a staged QR")
        root.start("authorization-denied", 6)
        return
      }
      if (root.phase === 6) {
        if (dispatcher.phase !== "failed" || dispatcher.workerRunning) return
        if (dispatcher.errorCode !== "authorization-denied"
            || consumer.rejectedCode !== "authorization-denied"
            || consumer.rejectedCount !== 5 || consumer.ready)
          return root.fail("bounded worker failure reason was not preserved")
        root.start("slow", 7)
        if (!dispatcher.cancel(consumer, consumer.expectedToken))
          return root.fail("exact QR secret cancellation was rejected")
        return
      }
      if (root.phase === 7) {
        if (dispatcher.workerRunning) return
        if (dispatcher.phase !== "cancelled"
            || consumer.committedCount !== 1
            || consumer.rejectedCount !== 6 || consumer.ready)
          return root.fail("cancelled secret worker did not settle")
        console.log("network QR secret dispatcher regression passed")
        Qt.exit(0)
      }
    }
  }
}
