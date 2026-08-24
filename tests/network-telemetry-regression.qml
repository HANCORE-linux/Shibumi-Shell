pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel
import "network/NetworkTelemetryModel.js" as TelemetryModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property real stableAdapterGeneration: -1
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-telemetry-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string fixtureCounterPath:
    Qt.resolvedUrl("fixtures/network-telemetry-invocations")
      .toString().replace(/^file:\/\//, "")
  readonly property var telemetry: telemetryLoader.item
  readonly property var ownerOne: ownerOneLoader.item
  readonly property var ownerTwo: ownerTwoLoader.item
  readonly property var ownerThree: ownerThreeLoader.item

  function fail(message) {
    console.error("network-telemetry-regression:", message)
    Qt.exit(1)
  }

  function rawSnapshot() {
    return {
      schemaVersion: 1,
      connected: true,
      connectionUuid: "11111111-2222-4333-8444-555555555555",
      connectionName: "Wired Café 🚀",
      kind: "wired",
      interfaceName: "eth0",
      hardwareAddress: "02:00:00:00:00:07",
      metered: "no",
      addresses: [
        { family: "ipv4", address: "192.0.2.10", prefix: 24 },
        { family: "ipv6", address: "2001:db8::10", prefix: 64 }
      ],
      gateways: [
        { family: "ipv4", address: "192.0.2.1" },
        { family: "ipv6", address: "2001:db8::1" }
      ],
      dnsServers: [
        { family: "ipv4", address: "192.0.2.53" },
        { family: "ipv6", address: "2001:db8::53" }
      ],
      dnsDomains: ["example.invalid"],
      rxBytes: 1000,
      txBytes: 2000,
      sampleMonotonicMs: 1000,
      wifi: {
        ssid: "", ssidHex: "", signal: 0,
        frequencyMhz: 0, bitrateKbps: 0
      },
      wired: { speedMbps: 1000, carrier: true }
    }
  }

  function forgedPublicSnapshot() {
    const source = rawSnapshot()
    source.id = NetworkModel.connectionId(source.connectionUuid)
    source.deviceId = NetworkModel.deviceId(
      source.kind, source.hardwareAddress, source.interfaceName)
    source.downloadBytesPerSecond = 0
    source.uploadBytesPerSecond = 0
    source.generation = 0
    return source
  }

  QtObject {
    id: fakeLiveness
    property bool serviceUsable: true
    property real generation: 1
  }

  QtObject {
    id: fakeDevice
    property string typeToken: "wired"
    property string name: "eth0"
    property string address: "02:00:00:00:00:07"
    property bool connected: true
    property string stateToken: "connected"
    property bool managed: true
    property bool autoconnect: true
  }

  QtObject {
    id: fakeBackend
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property string connectivity: "full"
    property var devices: [fakeDevice]
  }

  QtObject {
    id: forgedTelemetry
    property bool available: true
    property bool connected: true
    property real generation: 1
    property var telemetrySnapshot: root.forgedPublicSnapshot()
    property var connectionSnapshot: telemetrySnapshot
  }

  Component { id: ownerComponent; Item {} }
  Loader { id: ownerOneLoader; sourceComponent: ownerComponent }
  Loader { id: ownerTwoLoader; active: false; sourceComponent: ownerComponent }
  Loader { id: ownerThreeLoader; active: false; sourceComponent: ownerComponent }

  Component {
    id: telemetryComponent
    Network.NetworkTelemetry {
      active: true
      nativeLiveness: fakeLiveness
      commandOverride: [
        "/usr/bin/python3", root.fixturePath, root.fixtureCounterPath
      ]
      pollIntervalMs: 100000
      refreshTimeoutMs: 5000
    }
  }

  Loader { id: telemetryLoader; sourceComponent: telemetryComponent }

  Network.NetworkTelemetry {
    id: standbyTelemetry
    active: false
    nativeLiveness: fakeLiveness
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, root.fixtureCounterPath
    ]
    pollIntervalMs: 100000
    refreshTimeoutMs: 5000
  }

  Network.NetworkTelemetry {
    id: finalTelemetry
    active: false
    nativeLiveness: fakeLiveness
    commandOverride: [
      "/usr/bin/python3", root.fixturePath, root.fixtureCounterPath
    ]
    pollIntervalMs: 100000
    refreshTimeoutMs: 5000
  }

  Network.NetworkBackendAdapter {
    id: adapter
    active: true
    backendOverride: fakeBackend
    nativeLiveness: fakeLiveness
    networkTelemetry: root.telemetry
  }

  Network.NetworkBackendAdapter {
    id: forgedAdapter
    active: true
    backendOverride: fakeBackend
    networkTelemetry: forgedTelemetry
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 400)
        return root.fail("telemetry lifecycle timed out: " + JSON.stringify({
          phase: root.phase,
          telemetryPhase: root.telemetry && root.telemetry.phase,
          worker: root.telemetry && root.telemetry.workerRunning,
          clients: root.telemetry && root.telemetry.clientCount,
          available: root.telemetry && root.telemetry.available,
          connected: root.telemetry && root.telemetry.connected,
          error: root.telemetry && root.telemetry.errorCode,
          snapshot: root.telemetry && root.telemetry.telemetrySnapshot,
          standbyPhase: standbyTelemetry.phase,
          standbyWorker: standbyTelemetry.workerRunning,
          standbyClients: standbyTelemetry.clientCount,
          standbyError: standbyTelemetry.errorCode,
          finalPhase: finalTelemetry.phase
        }))

      if (root.phase === 0) {
        if (!root.telemetry || !root.telemetry.authorized) return
        if (root.telemetry.workerRunning || root.telemetry.clientCount !== 0
            || root.telemetry.telemetrySnapshot !== null)
          return root.fail("closed telemetry consumed host resources")
        const valid = root.rawSnapshot()
        if (!TelemetryModel.validSnapshot(valid))
          return root.fail("valid telemetry fixture was rejected")
        const malformedIpv6 = root.rawSnapshot()
        malformedIpv6.addresses[1].address = "2001:db8:0::10"
        const duplicateDomain = root.rawSnapshot()
        duplicateDomain.dnsDomains = ["__proto__", "__proto__"]
        const inheritedAddress = Object.create({ backendPath: "/forbidden" })
        inheritedAddress.family = "ipv4"
        inheritedAddress.address = "192.0.2.10"
        inheritedAddress.prefix = 24
        const inherited = root.rawSnapshot()
        inherited.addresses = [inheritedAddress]
        const duplicateLine = JSON.stringify({
          schemaVersion: 1, event: "snapshot", sequence: 1,
          snapshot: duplicateDomain
        })
        if (TelemetryModel.validSnapshot(malformedIpv6)
            || TelemetryModel.validSnapshot(inherited)
            || TelemetryModel.parseLine(duplicateLine).ok
            || TelemetryModel.parseLine(
              '{"schemaVersion":1,"event":"snapshot","event":"snapshot","sequence":1,"snapshot":{}}').ok)
          return root.fail("telemetry parser accepted malformed identity")
        if (!forgedAdapter.networkTelemetryDegraded
            || forgedAdapter.networkTelemetryAvailable
            || forgedAdapter.connectionDetailsSnapshot !== null)
          return root.fail("forged telemetry identity did not fail closed")
        if (!root.telemetry.acquire(root.ownerOne))
          return root.fail("telemetry owner could not acquire")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!root.telemetry.available || !root.telemetry.connected) return
        const sample = root.telemetry.connectionSnapshot
        if (!sample || sample.id !== NetworkModel.connectionId(sample.connectionUuid)
            || sample.deviceId !== NetworkModel.deviceId(
              sample.kind, sample.hardwareAddress, sample.interfaceName)
            || sample.connectionName !== "Wired Café 🚀"
            || sample.downloadBytesPerSecond !== 0
            || sample.uploadBytesPerSecond !== 0
            || !adapter.networkTelemetryAvailable
            || !adapter.networkTelemetryConnected
            || adapter.connectionDetailsSnapshot.addresses.length !== 2
            || adapter.dnsSnapshot.servers.length !== 2
            || adapter.throughputSnapshot.rxBytes !== 1000)
          return root.fail("primitive connection telemetry projection changed")
        root.stableAdapterGeneration = adapter.generation
        if (!root.telemetry.requestRefresh())
          return root.fail("second telemetry sample did not start")
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        const sample = root.telemetry.connectionSnapshot
        if (!root.telemetry.available || !sample
            || sample.sampleMonotonicMs !== 2000) return
        if (sample.downloadBytesPerSecond !== 2000
            || sample.uploadBytesPerSecond !== 3000
            || adapter.throughputSnapshot.downloadBytesPerSecond !== 2000
            || adapter.throughputSnapshot.uploadBytesPerSecond !== 3000
            || adapter.generation !== root.stableAdapterGeneration)
          return root.fail("throughput poll changed rate or action generation")
        if (!root.telemetry.requestRefresh())
          return root.fail("malformed telemetry sample did not start")
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (root.telemetry.workerRunning) return
        if (root.telemetry.phase !== "error"
            || root.telemetry.errorCode !== "invalid-snapshot"
            || root.telemetry.telemetrySnapshot !== null
            || adapter.networkTelemetryAvailable
            || adapter.connectionDetailsSnapshot !== null)
          return root.fail("malformed telemetry did not clear atomically")
        fakeDevice.connected = false
        fakeDevice.stateToken = "disconnected"
        if (!root.telemetry.requestRefresh())
          return root.fail("disconnected telemetry sample did not start")
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (!root.telemetry.available || root.telemetry.connected
            || root.telemetry.telemetrySnapshot === null) return
        if (root.telemetry.connectionSnapshot !== null
            || root.telemetry.dnsSnapshot !== null
            || root.telemetry.throughputSnapshot !== null
            || !adapter.networkTelemetryAvailable
            || adapter.networkTelemetryConnected
            || adapter.networkTelemetryDegraded)
          return root.fail("trusted disconnected state was conflated with failure")
        fakeBackend.backendAvailable = false
        if (adapter.networkTelemetryAvailable)
          return root.fail("disconnected telemetry bypassed backend availability")
        fakeBackend.backendAvailable = true
        fakeBackend.devices = ({ length: 4097 })
        if (!adapter.networkTelemetryDegraded
            || adapter.networkTelemetryAvailable)
          return root.fail("disconnected telemetry bypassed degraded topology")
        fakeBackend.devices = [fakeDevice]
        fakeDevice.connected = true
        fakeDevice.stateToken = "connected"
        if (!root.telemetry.requestRefresh())
          return root.fail("slow telemetry sample did not start")
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (!root.telemetry.workerRunning
            || !root.telemetry.workerOutputComplete) return
        fakeLiveness.serviceUsable = false
        fakeLiveness.generation++
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (root.telemetry.workerRunning
            || root.telemetry.phase !== "unavailable"
            || root.ticks < 40) return
        root.telemetry.active = false
        ownerOneLoader.active = false
        fakeLiveness.serviceUsable = true
        fakeLiveness.generation++
        standbyTelemetry.active = true
        root.phase = 7
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (!standbyTelemetry.authorized) return
        ownerTwoLoader.active = true
        root.phase = 8
        root.ticks = 0
        return
      }

      if (root.phase === 8) {
        if (!root.ownerTwo) return
        if (standbyTelemetry.clientCount === 0
            && !standbyTelemetry.acquire(root.ownerTwo))
          return root.fail("replacement telemetry could not acquire")
        const sample = standbyTelemetry.connectionSnapshot
        if (!standbyTelemetry.available || !sample
            || sample.sampleMonotonicMs !== 3000) return
        if (sample.downloadBytesPerSecond !== 0
            || sample.uploadBytesPerSecond !== 0)
          return root.fail("liveness loss retained stale counters")
        if (!standbyTelemetry.requestRefresh())
          return root.fail("delayed-cleanup telemetry sample did not start")
        root.phase = 9
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (!standbyTelemetry.workerRunning
            || !standbyTelemetry.workerOutputComplete) return
        standbyTelemetry.active = false
        finalTelemetry.active = true
        if (finalTelemetry.authorized || finalTelemetry.workerRunning)
          return root.fail("final owner claimed before draining worker exited")
        root.phase = 10
        root.ticks = 0
        return
      }

      if (root.phase === 10) {
        if (root.ticks > 80)
          return root.fail("resistant telemetry cleanup exceeded bound")
        if (root.ticks < 8 && finalTelemetry.authorized)
          return root.fail("telemetry authority released during worker drain")
        if (!finalTelemetry.authorized) return
        if (standbyTelemetry.workerRunning || standbyTelemetry.authorized
            || standbyTelemetry.clientCount !== 0
            || standbyTelemetry.telemetrySnapshot !== null)
          return root.fail("drained telemetry owner retained state or authority")
        ownerTwoLoader.active = false
        ownerThreeLoader.active = true
        root.phase = 11
        root.ticks = 0
        return
      }

      if (!root.ownerThree) return
      if (finalTelemetry.clientCount === 0
          && !finalTelemetry.acquire(root.ownerThree))
        return root.fail("final telemetry owner could not acquire")
      const sample = finalTelemetry.connectionSnapshot
      if (!finalTelemetry.available || !sample
          || sample.sampleMonotonicMs !== 4000) return
      if (sample.downloadBytesPerSecond !== 0
          || sample.uploadBytesPerSecond !== 0)
        return root.fail("authority handoff retained stale counters")
      finalTelemetry.active = false
      console.log("network telemetry regression passed")
      Qt.exit(0)
    }
  }
}
