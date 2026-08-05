pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "bluetooth" as Bluetooth
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("bluetooth-backend-regression:", message)
    Qt.exit(1)
  }

  Item {
    id: fakeBar
    property bool bluetoothOpen: false
    function summonBarWidget(_id) { bluetoothOpen = true; return true }
    function hideBarWidget(_id) { bluetoothOpen = false; return true }
    function isBarWidgetOpen(_id) { return bluetoothOpen }
  }

  Fixtures.BluetoothTestBackend { id: discoveryFixture }

  Bluetooth.Service {
    id: discoveryService
    bar: fakeBar
    backendOverride: discoveryFixture
    discoveryRetryInterval: 50
    discoveryRequestTimeoutInterval: 100
  }

  QtObject {
    id: nativeAdapter
    property bool enabled: true
    property bool discovering: false
  }

  QtObject {
    id: audioDevice
    property string address: "FE:DC:BA:98:76:54"
    property string name: "Shibumi Delayed Audio Device"
    property string deviceName: name
    property bool connected: false
    property bool paired: true
    property bool bonded: true
    property bool trusted: true
    property var adapter: nativeAdapter
  }

  QtObject {
    id: audioSink
    property bool ready: true
    property bool isSink: true
    property bool isStream: false
    property int sinkId: 771
    property int id: sinkId
    property string name: "bluez_output.FE_DC_BA_98_76_54.a2dp-sink"
    property string description: "Shibumi Delayed Audio Device"
    property string nickname: ""
    property string nick: ""
    property var properties: ({
      "api.bluez5.address": "FE:DC:BA:98:76:54"
    })
  }

  QtObject {
    id: commandRunner
    property int count: 0
    property var lastCommand: []
    function run(command) { count++; lastCommand = command }
  }

  QtObject {
    id: audioOutput
    property int count: 0
    property var lastSink: null
    function setDefaultSink(sink) { count++; lastSink = sink }
  }

  Bluetooth.BluetoothBackendAdapter {
    id: audioBackend
    adapterOverride: nativeAdapter
    nativeDevicesOverride: [audioDevice]
    pipewireNodesOverride: [audioSink]
    commandRunnerOverride: commandRunner
    audioOutputOverride: audioOutput
    audioSwitchInterval: 30
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (root.ticks < 3) return

        discoveryFixture.rejectedDiscoveryStarts = 1
        discoveryService.beginSession(root)

        if (!audioBackend.connectDevice(audioDevice)
            || commandRunner.count !== 1)
          return root.fail("isolated connect command boundary")
        // UI pending may expire before the helper's pair+connect sequence.
        audioBackend.nativePendingActions = ({})
        audioDevice.connected = true

        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (root.ticks < 25) return
        if (audioOutput.count !== 1 || audioOutput.lastSink !== audioSink)
          return root.fail("late connection lost its audio intent")
        if (!discoveryService.discovering
            || discoveryFixture.discoveryStartAttempts < 2)
          return root.fail("discovery start rejection was not retried")

        // A scan that disappears while the panel remains open must recover.
        discoveryFixture.fakeAdapter.discovering = false

        audioDevice.connected = false
        if (!audioBackend.connectDevice(audioDevice))
          return root.fail("second isolated connect command")
        audioBackend.nativePendingActions = ({})
        audioDevice.connected = true
        audioDevice.connected = false

        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.ticks < 25) return
        if (!discoveryService.discovering
            || discoveryFixture.discoveryStartAttempts < 3)
          return root.fail("ended discovery was not recovered")
        if (audioOutput.count !== 1)
          return root.fail("disconnected device received a stale audio handoff")

        // Switching to an enabled, idle adapter with an open session must
        // establish a fresh Shibumi-owned discovery lease.
        discoveryFixture.alternateAdapter.discovering = false
        discoveryFixture.selectedAdapter = discoveryFixture.alternateAdapter

        audioDevice.connected = false
        if (!audioBackend.connectDevice(audioDevice))
          return root.fail("third isolated connect command")
        audioBackend.nativePendingActions = ({})
        audioDevice.connected = true
        nativeAdapter.enabled = false

        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.ticks < 25) return
        if (!discoveryService.discovering
            || discoveryFixture.discoveryStartAttempts < 4)
          return root.fail("enabled adapter replacement was not scanned")
        if (audioOutput.count !== 1)
          return root.fail("radio-off allowed a stale audio handoff")

        discoveryService.endSession(root)
        discoveryFixture.rejectedDiscoveryStarts = 1
        discoveryService.beginSession(root)
        discoveryService.endSession(root)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 4) {
        if (root.ticks < 4) return
        if (discoveryService.discovering)
          return root.fail("final session close left discovery running")
        discoveryFixture.alternateAdapter.discovering = true
        root.phase++
        root.ticks = 0
      } else {
        if (root.ticks < 2) return
        if (!discoveryService.discovering)
          return root.fail("expired discovery request claimed an external scan")
        discoveryFixture.alternateAdapter.discovering = false
        console.log("bluetooth backend regression passed")
        Qt.quit()
        stop()
      }
    }
  }
}
