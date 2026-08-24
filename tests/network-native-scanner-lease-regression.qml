pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as Model

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property bool competitionStarted: false
  property bool gatewayLifecycleChecked: false
  property int malformedStage: 0
  property bool standbyReleased: false
  property int shutdownStage: 0
  readonly property var scanner: scannerLoader.item
  readonly property var ownerOne: ownerOneLoader.item
  readonly property var ownerTwo: ownerTwoLoader.item
  readonly property var pendingScanner: pendingScannerLoader.item
  readonly property var nativeScanner: nativeScannerLoader.item
  readonly property var doomedScanner: doomedScannerLoader.item

  function fail(message) {
    console.error("network-native-scanner-lease-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: wifiA
    property string entityId: Model.deviceId(
      "wifi", "AA:BB:CC:DD:EE:A1", "wlan-a")
    property bool scannerEnabled: false
    property int trueWrites: 0
    property int falseWrites: 0
    onScannerEnabledChanged: {
      if (scannerEnabled) trueWrites++
      else falseWrites++
    }
  }

  QtObject {
    id: wifiASecond
    property string entityId: Model.deviceId(
      "wifi", "AA:BB:CC:DD:EE:A2", "wlan-a-second")
    property bool scannerEnabled: false
    property int trueWrites: 0
    property int falseWrites: 0
    onScannerEnabledChanged: {
      if (scannerEnabled) trueWrites++
      else falseWrites++
    }
  }

  QtObject {
    id: wifiB
    property string entityId: Model.deviceId(
      "wifi", "AA:BB:CC:DD:EE:B1", "wlan-b")
    property bool scannerEnabled: false
    property int trueWrites: 0
    property int falseWrites: 0
    onScannerEnabledChanged: {
      if (scannerEnabled) trueWrites++
      else falseWrites++
    }
  }

  component FakeRawScannerDevice: QtObject {
    property string typeToken: "wifi"
    property string modeToken: "station"
    property string name: ""
    property string address: ""
    property bool managed: true
    property bool scannerEnabled: false
    property bool failEnable: false
    property bool failDisable: false
    property bool failRead: false
    property bool failSnapshot: false
    property int trueWrites: 0
    property int falseWrites: 0
    function snapshotName() {
      if (failSnapshot) throw new Error("fixture snapshot failure")
      return name
    }
    function snapshotAddress() { return address }
    function getScannerEnabled() {
      if (failRead) throw new Error("fixture scanner read failure")
      return scannerEnabled
    }
    function setScannerEnabled(enabled) {
      if (enabled && failEnable || !enabled && failDisable) return false
      scannerEnabled = enabled === true
      if (scannerEnabled) trueWrites++
      else falseWrites++
      return true
    }
  }

  FakeRawScannerDevice {
    id: rawScannerOne
    name: "wlan-raw-one"
    address: "AA:BB:CC:DD:EE:C1"
  }

  FakeRawScannerDevice {
    id: rawScannerTwo
    name: "wlan-raw-two"
    address: "AA:BB:CC:DD:EE:C2"
  }

  Network.NetworkScannerNativeGateway {
    id: rawGateway
    backendInitializedOverride: true
    radioEnabledOverride: true
    deviceObjectsOverride: [rawScannerOne, rawScannerTwo]
  }

  component FakeScannerBackend: QtObject {
    property bool backendAvailable: true
    property bool wifiEnabled: true
    property bool wifiHardwareEnabled: true
    property int topologyRevision: 0
    property var devices: []
    property int enableCalls: 0
    property int closeCalls: 0
    property bool throwOnEnable: false
    property bool failClose: false
    property var snapshotOverride: null
    readonly property var deviceSnapshots: {
      if (snapshotOverride !== null) return snapshotOverride
      const revision = topologyRevision
      void revision
      const rows = []
      for (let index = 0; index < devices.length; index++) {
        const device = devices[index]
        if (!device) continue
        rows.push({
          schemaVersion: Model.SchemaVersion,
          id: device.entityId,
          type: "wifi",
          managed: true,
          mode: "station",
          eligible: backendAvailable && wifiEnabled && wifiHardwareEnabled,
          ambiguous: false
        })
      }
      return rows
    }

    function closeScanner() {
      closeCalls++
      if (failClose)
        return {
          ok: false,
          code: "unavailable",
          message: "fixture cleanup failed",
          entityIds: []
        }
      for (let index = 0; index < devices.length; index++) {
        if (devices[index]) devices[index].scannerEnabled = false
      }
      return { ok: true, code: "accepted", message: "closed", entityIds: [] }
    }

    function enableScannerIds(ids) {
      enableCalls++
      if (throwOnEnable) throw new Error("fixture enable failure")
      const selected = []
      for (let idIndex = 0; idIndex < ids.length; idIndex++) {
        let match = null
        let count = 0
        for (let index = 0; index < devices.length; index++) {
          const device = devices[index]
          if (device && device.entityId === ids[idIndex]) {
            match = device
            count++
          }
        }
        if (count !== 1) {
          closeScanner()
          return {
            ok: false,
            code: count > 1 ? "ambiguous" : "stale-id",
            message: "fixture identity failure",
            entityIds: []
          }
        }
        selected.push(match)
      }
      for (let index = 0; index < selected.length; index++)
        selected[index].scannerEnabled = true
      return {
        ok: true,
        code: "accepted",
        message: "fixture scanner dispatch accepted",
        entityIds: ids.slice()
      }
    }
  }

  FakeScannerBackend {
    id: backendA
    devices: [wifiA, wifiASecond]
  }

  FakeScannerBackend {
    id: backendB
    devices: [wifiB]
  }

  Component {
    id: scannerComponent
    Network.NetworkScannerLease {
      active: true
      backendOverride: backendA
      scanDelayMs: 90
      scanWindowMs: 120
    }
  }

  Component {
    id: pendingScannerComponent
    Network.NetworkScannerLease {
      active: true
      backendOverride: backendA
      scanDelayMs: 90
      scanWindowMs: 120
    }
  }

  Component {
    id: doomedScannerComponent
    Network.NetworkScannerLease {
      active: true
      backendOverride: backendB
      scanDelayMs: 50
      scanWindowMs: 80
    }
  }

  Component {
    id: nativeScannerComponent
    Network.NetworkScannerLease {
      active: true
      nativeServiceAvailable: true
      scanDelayMs: 50
      scanWindowMs: 80
    }
  }

  Loader {
    id: scannerLoader
    sourceComponent: scannerComponent
  }

  Network.NetworkScannerLease {
    id: competingScanner
    active: false
    backendOverride: backendB
    scanDelayMs: 50
    scanWindowMs: 80
  }

  Loader {
    id: pendingScannerLoader
    active: false
    sourceComponent: pendingScannerComponent
  }

  Loader {
    id: nativeScannerLoader
    active: false
    sourceComponent: nativeScannerComponent
  }

  Loader {
    id: doomedScannerLoader
    active: false
    sourceComponent: doomedScannerComponent
  }

  Network.NetworkScannerLease {
    id: blockedStandbyScanner
    active: false
    backendOverride: backendA
    scanDelayMs: 50
    scanWindowMs: 80
  }

  Component { id: ownerComponent; Item {} }
  Loader { id: ownerOneLoader; sourceComponent: ownerComponent }
  Loader { id: ownerTwoLoader; sourceComponent: ownerComponent }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (!root.scanner || !root.ownerOne || !root.ownerTwo
            || root.ticks < 3) return
        if (!root.gatewayLifecycleChecked) {
          const rawOneId = Model.deviceId("wifi", rawScannerOne.address,
            rawScannerOne.name)
          const rawTwoId = Model.deviceId("wifi", rawScannerTwo.address,
            rawScannerTwo.name)
          rawScannerOne.scannerEnabled = true
          const foreignResult = rawGateway.enableScannerIds([rawOneId])
          rawGateway.closeScanner()
          if (foreignResult.ok || foreignResult.code !== "unavailable"
              || !rawScannerOne.scannerEnabled)
            return root.fail("native gateway claimed a foreign scanner")
          rawScannerOne.failRead = true
          const unreadableResult = rawGateway.enableScannerIds([rawOneId])
          rawScannerOne.failRead = false
          if (unreadableResult.ok || !rawScannerOne.scannerEnabled)
            return root.fail("unreadable foreign scanner was claimed")
          rawScannerOne.scannerEnabled = false

          rawScannerTwo.failSnapshot = true
          rawGateway.bumpTopology()
          if (!rawGateway.snapshotDegraded
              || rawGateway.deviceSnapshots.length !== 0)
            return root.fail("raw snapshot failure was partially published")
          rawScannerTwo.failSnapshot = false
          rawGateway.bumpTopology()

          rawScannerTwo.failEnable = true
          const partialResult = rawGateway.enableScannerIds([
            rawOneId, rawTwoId
          ])
          rawScannerTwo.failEnable = false
          if (partialResult.ok || rawScannerOne.scannerEnabled
              || rawScannerTwo.scannerEnabled
              || rawGateway.ownedDevices.length !== 0)
            return root.fail("native partial scanner dispatch leaked ownership")

          const acceptedRaw = rawGateway.enableScannerIds([
            rawOneId, rawTwoId
          ])
          rawScannerOne.failDisable = true
          rawGateway.prepareRemoval(rawScannerOne)
          if (!rawScannerOne.scannerEnabled
              || rawGateway.ownedDevices.indexOf(rawScannerOne) < 0)
            return root.fail("failed pre-removal close forgot ownership")
          rawScannerOne.failDisable = false
          const retriedRemoval = rawGateway.closeScanner()
          const tombstonedResult = rawGateway.enableScannerIds([rawOneId])
          rawGateway.deviceObjectsOverride = [rawScannerTwo]
          rawGateway.finishRemoval(rawScannerOne)
          const closedRaw = rawGateway.closeScanner()
          if (!acceptedRaw.ok || !retriedRemoval.ok
              || rawScannerOne.scannerEnabled || tombstonedResult.ok
              || tombstonedResult.code !== "stale-id"
              || !closedRaw.ok || rawScannerTwo.scannerEnabled
              || rawGateway.deviceSnapshots.length !== 1)
            return root.fail("native scanner tombstone lifecycle failed")
          root.gatewayLifecycleChecked = true
        }
        if (!root.competitionStarted) {
          if (!root.scanner.authorized) {
            if (root.ticks > 20)
              return root.fail("primary scanner did not claim authority")
            return
          }
          competingScanner.active = true
          root.competitionStarted = true
          root.ticks = 0
          return
        }
        if (root.ticks < 2) return
        if (!root.scanner.authorized || competingScanner.authorized
            || root.scanner.nativeGatewayLoaded
            || competingScanner.nativeGatewayLoaded
            || root.scanner.clientCount !== 0
            || wifiA.scannerEnabled || wifiASecond.scannerEnabled
            || wifiB.scannerEnabled)
          return root.fail("exclusive scanner authority did not start idle: "
            + JSON.stringify({
              primaryAuthorized: root.scanner.authorized,
              competingAuthorized: competingScanner.authorized,
              primaryNative: root.scanner.nativeGatewayLoaded,
              competingNative: competingScanner.nativeGatewayLoaded,
              clients: root.scanner.clientCount,
              wifiA: wifiA.scannerEnabled,
              wifiASecond: wifiASecond.scannerEnabled,
              wifiB: wifiB.scannerEnabled,
              primaryPhase: root.scanner.phase,
              competingPhase: competingScanner.phase
            }))
        if (!root.scanner.acquire(root.ownerOne)
            || root.scanner.phase !== "delay-pending"
            || wifiA.scannerEnabled || wifiASecond.scannerEnabled)
          return root.fail("first lease enabled scanning synchronously")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (!root.scanner.scannerEnabled) {
          if (root.ticks > 20) return root.fail("first lease never enabled")
          return
        }
        if (!wifiA.scannerEnabled || !wifiASecond.scannerEnabled
            || root.scanner.leasedDeviceIds.length !== 2
            || backendA.enableCalls !== 1)
          return root.fail("eligible Wi-Fi devices did not share one lease")
        if (!root.scanner.acquire(root.ownerOne)
            || !root.scanner.acquire(root.ownerTwo)
            || root.scanner.clientCount !== 2
            || !root.scanner.release(root.ownerOne)
            || root.scanner.clientCount !== 1
            || !wifiA.scannerEnabled || !wifiASecond.scannerEnabled)
          return root.fail("duplicate or non-final client changed ownership: "
            + JSON.stringify({
              clients: root.scanner.clientCount,
              wifiA: wifiA.scannerEnabled,
              wifiASecond: wifiASecond.scannerEnabled,
              phase: root.scanner.phase,
              acquireOne: root.scanner.acquire(root.ownerOne),
              acquireTwo: root.scanner.acquire(root.ownerTwo)
            }))
        const beforeTrueWrites = wifiA.trueWrites
        if (!root.scanner.requestScan()
            || root.scanner.phase !== "delay-pending"
            || wifiA.scannerEnabled || wifiASecond.scannerEnabled)
          return root.fail("explicit rescan did not enter a closed delay")
        root.phase = 2
        root.ticks = 0
        root.propertyBeforeRescan = beforeTrueWrites
        return
      }

      if (root.phase === 2) {
        if (root.ticks < 3) {
          if (wifiA.scannerEnabled || wifiASecond.scannerEnabled)
            return root.fail("rescan delay was bypassed")
          return
        }
        if (!root.scanner.scannerEnabled) return
        if (!wifiA.scannerEnabled || !wifiASecond.scannerEnabled
            || wifiA.trueWrites !== root.propertyBeforeRescan + 1)
          return root.fail("rescan did not produce one delayed re-enable")
        backendA.failClose = true
        root.scanner.backendOverride = backendB
        if (root.scanner.phase !== "cleanup-pending"
            || !wifiA.scannerEnabled || !wifiASecond.scannerEnabled
            || wifiB.scannerEnabled)
          return root.fail("failed cleanup did not block adapter replacement")
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (root.ticks < 4) {
          if (wifiB.scannerEnabled || !wifiA.scannerEnabled
              || !wifiASecond.scannerEnabled)
            return root.fail("cleanup-pending enabled replacement backend")
          return
        }
        if (backendA.failClose) {
          backendA.failClose = false
          return
        }
        if (!root.scanner.scannerEnabled) return
        if (wifiA.scannerEnabled || wifiASecond.scannerEnabled
            || !wifiB.scannerEnabled
            || root.scanner.leasedDeviceIds.length !== 1
            || root.scanner.leasedDeviceIds[0] !== wifiB.entityId)
          return root.fail("adapter replacement leaked scanner ownership")
        backendB.backendAvailable = false
        if (wifiB.scannerEnabled) return root.fail("backend loss leaked scanner")
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (root.scanner.phase !== "unavailable"
            || root.scanner.scannerEnabled || wifiB.scannerEnabled)
          return root.fail("unavailable scanner state was not fail closed")
        backendB.backendAvailable = true
        if (root.scanner.phase !== "delay-pending")
          return root.fail("backend recovery reused stale scanner state")
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (root.malformedStage === 0) {
          if (!root.scanner.scannerEnabled) return
          if (!wifiB.scannerEnabled) return root.fail("backend did not recover")
          const validRow = backendB.deviceSnapshots[0]
          backendB.snapshotOverride = [validRow, {
            schemaVersion: Model.SchemaVersion,
            id: "malformed-scanner-id",
            type: "wifi",
            managed: true,
            mode: "station",
            eligible: true,
            ambiguous: false
          }]
          backendB.topologyRevision++
          root.malformedStage = 1
          root.ticks = 0
          return
        }
        if (root.malformedStage === 1) {
          if (!root.scanner.snapshotDegraded
              || root.scanner.phase !== "unavailable"
              || wifiB.scannerEnabled)
            return root.fail("malformed scanner snapshot was partially accepted")
          backendB.snapshotOverride = null
          backendB.topologyRevision++
          root.malformedStage = 2
          root.ticks = 0
          return
        }
        if (!root.scanner.scannerEnabled) return
        if (!wifiB.scannerEnabled)
          return root.fail("scanner did not recover from degraded snapshot")
        ownerTwoLoader.active = false
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (root.ownerTwo !== null) return
        if (root.scanner.clientCount !== 0 || root.scanner.scannerEnabled
            || wifiB.scannerEnabled || root.scanner.phase !== "idle")
          return root.fail("destroyed final client leaked its lease: "
            + JSON.stringify({
              clients: root.scanner.clientCount,
              enabled: root.scanner.scannerEnabled,
              wifiB: wifiB.scannerEnabled,
              phase: root.scanner.phase
            }))
        if (!root.scanner.acquire(root.ownerOne))
          return root.fail("surviving owner could not reacquire")
        root.phase = 7
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (!root.scanner.scannerEnabled) return
        backendB.failClose = true
        root.scanner.active = false
        root.phase = 8
        root.ticks = 0
        return
      }

      if (root.phase === 8) {
        if (root.shutdownStage === 0) {
          if (root.scanner.phase !== "cleanup-pending"
              || !root.scanner.authorized || !wifiB.scannerEnabled
              || competingScanner.authorized)
            return root.fail("failed shutdown released scanner authority")
          if (root.ticks < 4) return
          ownerOneLoader.active = false
          root.shutdownStage = 1
          root.ticks = 0
          return
        }
        if (root.shutdownStage === 1) {
          if (root.ownerOne !== null) return
          if (root.scanner.phase !== "cleanup-pending"
              || !root.scanner.authorized || !wifiB.scannerEnabled)
            return root.fail("final owner loss bypassed pending cleanup")
          backendB.failClose = false
          root.shutdownStage = 2
          root.ticks = 0
          return
        }
        if (root.shutdownStage === 2) {
          if (root.scanner.authorized || wifiB.scannerEnabled) return
          ownerOneLoader.active = true
          scannerLoader.active = false
          root.shutdownStage = 3
          root.ticks = 0
          return
        }
        if (root.scanner !== null || !root.ownerOne) return
        if (!root.standbyReleased) {
          if (!competingScanner.authorized) {
            if (root.ticks > 30)
              return root.fail("standby scanner did not claim released authority: "
                + JSON.stringify({
                  active: competingScanner.active,
                  authorized: competingScanner.authorized,
                  phase: competingScanner.phase,
                  native: competingScanner.nativeGatewayLoaded
                }))
            return
          }
          competingScanner.active = false
          root.standbyReleased = true
          root.ticks = 0
          return
        }
        if (competingScanner.authorized) return
        pendingScannerLoader.active = true
        root.phase = 9
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (!root.pendingScanner || !root.pendingScanner.authorized) return
        if (!root.pendingScanner.acquire(root.ownerOne)
            || root.pendingScanner.phase !== "delay-pending")
          return root.fail("replacement authority did not enter delay")
        pendingScannerLoader.active = false
        root.phase = 10
        root.ticks = 0
        return
      }

      if (root.phase === 10) {
        if (root.pendingScanner !== null || root.ticks < 8) return
        if (wifiA.scannerEnabled || wifiASecond.scannerEnabled)
          return root.fail("destroyed delay epoch re-enabled scanning")
        nativeScannerLoader.active = true
        root.phase = 11
        root.ticks = 0
        return
      }

      if (root.phase === 11) {
        if (!root.nativeScanner) return
        if (!root.nativeScanner.authorized
            || !root.nativeScanner.nativeGatewayLoaded) {
          if (root.ticks > 20)
            return root.fail("native scanner gateway did not compile")
          return
        }
        if (root.nativeScanner.backendAvailable
            || root.nativeScanner.clientCount !== 0
            || root.nativeScanner.scannerEnabled)
          return root.fail("missing system bus native scanner was actionable")
        root.nativeScanner.active = false
        nativeScannerLoader.active = false
        doomedScannerLoader.active = true
        root.phase = 12
        root.ticks = 0
        return
      }

      if (root.phase === 12) {
        if (!root.doomedScanner || !root.doomedScanner.authorized
            || !root.ownerOne) return
        if (!root.doomedScanner.acquire(root.ownerOne))
          return root.fail("failed-destruction fixture could not acquire")
        root.phase = 13
        root.ticks = 0
        return
      }

      if (root.phase === 13) {
        if (!root.doomedScanner.scannerEnabled) return
        backendB.failClose = true
        doomedScannerLoader.active = false
        blockedStandbyScanner.active = true
        root.phase = 14
        root.ticks = 0
        return
      }

      if (root.phase === 14) {
        if (root.doomedScanner !== null || root.ticks < 15) return
        if (blockedStandbyScanner.authorized || !wifiB.scannerEnabled)
          return root.fail("failed final cleanup did not block authority: "
            + JSON.stringify({
              standby: blockedStandbyScanner.authorized,
              wifiB: wifiB.scannerEnabled,
              standbyPhase: blockedStandbyScanner.phase,
              backendFailClose: backendB.failClose
            }))
        ownerOneLoader.active = false
        root.phase = 15
        root.ticks = 0
        return
      }

      if (root.ownerOne !== null || root.ticks < 5) return
      if (blockedStandbyScanner.authorized)
        return root.fail("surviving token released blocked authority")
      console.log("network native scanner lease regression passed")
      Qt.exit(0)
    }
  }

  property int propertyBeforeRescan: 0
}
