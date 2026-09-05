pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "bluetooth" as Bluetooth

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property var currentAdapter: adapterA
  property var currentDevices: [deviceA]
  property var firstRecord: null
  property var replacementRecord: null

  function fail(message) {
    console.error("bluetooth-device-identity-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: adapterA
    property string adapterId: "hci-identity"
    property string dbusPath: "/org/bluez/hci_identity"
    property bool enabled: true
    property bool discovering: false
  }

  QtObject {
    id: adapterB
    property string adapterId: "hci-identity"
    property string dbusPath: "/org/bluez/hci_identity"
    property bool enabled: true
    property bool discovering: false
  }

  component IdentityDevice: QtObject {
    property string address: "12:34:56:78:9A:BC"
    property string name: "Identity Fixture"
    property string deviceName: name
    property string icon: "audio-headset"
    property int state: 0
    property bool connected: false
    property bool paired: true
    property bool bonded: true
    property bool pairing: false
    property bool trusted: true
    property bool batteryAvailable: false
    property real battery: 0
    property var adapter: root.currentAdapter
    property string dbusPath: "/org/bluez/hci_identity/dev_12_34_56_78_9A_BC"
    property int nativeDisconnectCount: 0
    function disconnect() { nativeDisconnectCount++ }
  }

  IdentityDevice { id: deviceA }
  IdentityDevice { id: deviceB }
  IdentityDevice { id: duplicateDevice }

  QtObject {
    id: commandRunner
    property int count: 0
    property var commands: []
    function run(command) {
      count++
      commands = commands.concat([command.slice()])
    }
  }

  Bluetooth.BluetoothBackendAdapter {
    id: backend
    adapterOverride: root.currentAdapter
    nativeDevicesOverride: root.currentDevices
    commandRunnerOverride: commandRunner
    audioRouteHandoffReady: false
  }

  Timer {
    interval: 30
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (root.ticks < 3 || backend.knownDevices.length !== 1) return
        root.firstRecord = backend.knownDevices[0]
        const record = root.firstRecord
        if (!record || record.entityId !== deviceA.dbusPath
            || record.generation <= 0 || record.adapterGeneration <= 0
            || "adapter" in record || "disconnect" in record)
          return root.fail("native QObject crossed the detached record boundary")

        const originalName = record.name
        deviceA.name = "Mutated Native Name"
        if (record.name !== originalName)
          return root.fail("published device record remained native/reactive")

        const rawResult = backend.connectDevice(deviceA)
        const malformedResult = backend.connectDevice({
          address: "not-an-address",
          entityId: record.entityId,
          generation: record.generation,
          adapterId: record.adapterId,
          adapterEntityId: record.adapterEntityId,
          adapterGeneration: record.adapterGeneration
        })
        if (!rawResult || rawResult.ok !== false
            || rawResult.code !== "invalid-request"
            || !malformedResult || malformedResult.ok !== false
            || malformedResult.code !== "invalid-request"
            || commandRunner.count !== 0)
          return root.fail("malformed or raw identities reached dispatch")

        const connectResult = backend.connectDevice(record)
        if (!connectResult || connectResult.ok !== true
            || connectResult.code !== "dispatched"
            || commandRunner.count !== 1
            || commandRunner.commands[0][0] !== "omarchy-bluetooth-device"
            || commandRunner.commands[0][1] !== "connect"
            || commandRunner.commands[0][2] !== deviceA.address)
          return root.fail("validated connect did not dispatch exactly once")
        deviceA.connected = true
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (root.ticks < 2) return
        const disconnectResult = backend.disconnectDevice(root.firstRecord)
        if (!disconnectResult || disconnectResult.ok !== true
            || commandRunner.count !== 2
            || commandRunner.commands[1][1] !== "disconnect"
            || deviceA.nativeDisconnectCount !== 0)
          return root.fail("disconnect used multiple mutation paths")
        deviceA.connected = false
        const forgetResult = backend.forgetDevice(root.firstRecord)
        if (!forgetResult || forgetResult.ok !== true
            || commandRunner.count !== 3
            || commandRunner.commands[2][1] !== "forget")
          return root.fail("validated forget did not dispatch exactly once")

        // Observe absence before replacing the QObject with the same public
        // BlueZ identity. The replacement must receive a new incarnation.
        root.currentDevices = []
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.ticks < 2 || backend.knownDevices.length !== 0) return
        root.currentDevices = [deviceB]
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.ticks < 3 || backend.knownDevices.length !== 1) return
        root.replacementRecord = backend.knownDevices[0]
        const staleResult = backend.connectDevice(root.firstRecord)
        const currentResult = backend.connectDevice(root.replacementRecord)
        if (!staleResult || staleResult.ok !== false
            || staleResult.code !== "stale-entity"
            || root.replacementRecord.generation === root.firstRecord.generation
            || !currentResult || currentResult.ok !== true
            || commandRunner.count !== 4)
          return root.fail("device replacement did not reject the stale incarnation")

        root.currentDevices = [deviceB, duplicateDevice]
        root.phase++
        root.ticks = 0
      } else if (root.phase === 4) {
        if (root.ticks < 3 || backend.knownDevices.length !== 2) return
        const ambiguousResult = backend.connectDevice(root.replacementRecord)
        if (!ambiguousResult || ambiguousResult.ok !== false
            || ambiguousResult.code !== "ambiguous-entity"
            || commandRunner.count !== 4)
          return root.fail("ambiguous identity reached dispatch")

        root.currentDevices = [deviceB]
        root.currentAdapter = adapterB
        root.phase++
        root.ticks = 0
      } else {
        if (root.ticks < 3 || backend.knownDevices.length !== 1) return
        const staleAdapterResult = backend.connectDevice(root.replacementRecord)
        const currentAdapterRecord = backend.knownDevices[0]
        const currentAdapterResult = backend.connectDevice(currentAdapterRecord)
        if (!staleAdapterResult || staleAdapterResult.ok !== false
            || staleAdapterResult.code !== "stale-entity"
            || currentAdapterRecord.adapterGeneration
              === root.replacementRecord.adapterGeneration
            || !currentAdapterResult || currentAdapterResult.ok !== true
            || commandRunner.count !== 5)
          return root.fail("adapter replacement did not bind the action incarnation")

        console.log("bluetooth device identity regression passed")
        Qt.quit()
        stop()
      }
    }
  }
}
