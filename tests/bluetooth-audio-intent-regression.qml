pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "bluetooth" as Bluetooth

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("bluetooth-audio-intent-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: nativeAdapter
    property bool enabled: true
    property bool discovering: false
  }

  QtObject {
    id: deviceA
    property string address: "AA:00:00:00:00:01"
    property string name: "Intent A"
    property string deviceName: name
    property bool connected: false
    property bool paired: true
    property bool bonded: true
    property bool trusted: true
    property var adapter: nativeAdapter
  }

  QtObject {
    id: deviceB
    property string address: "BB:00:00:00:00:02"
    property string name: "Intent B"
    property string deviceName: name
    property bool connected: false
    property bool paired: true
    property bool bonded: true
    property bool trusted: true
    property var adapter: nativeAdapter
  }

  QtObject {
    id: sinkA
    property bool isSink: true
    property bool isStream: false
    property int id: 801
    property string name: "bluez_output.AA_00_00_00_00_01.a2dp-sink"
    property string description: "Intent A"
    property string nickname: ""
    property string nick: ""
    property var properties: ({ "api.bluez5.address": deviceA.address })
  }

  QtObject {
    id: sinkB
    property bool isSink: true
    property bool isStream: false
    property int id: 802
    property string name: "bluez_output.BB_00_00_00_00_02.a2dp-sink"
    property string description: "Intent B"
    property string nickname: ""
    property string nick: ""
    property var properties: ({ "api.bluez5.address": deviceB.address })
  }

  QtObject {
    id: commandRunner
    property int count: 0
    function run(_command) { count++ }
  }

  QtObject {
    id: audioOutput
    property int count: 0
    property var lastSink: null
    function setDefaultSink(sink) { count++; lastSink = sink }
  }

  Bluetooth.BluetoothBackendAdapter {
    id: backend
    adapterOverride: nativeAdapter
    nativeDevicesOverride: [deviceA, deviceB]
    pipewireNodesOverride: [sinkA, sinkB]
    commandRunnerOverride: commandRunner
    audioOutputOverride: audioOutput
    audioSwitchInterval: 20
    audioIntentTimeoutInterval: 120
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (root.ticks < 2) return
        if (!backend.connectDevice(deviceA) || !backend.connectDevice(deviceB))
          return root.fail("could not create ordered connect intents")
        backend.nativePendingActions = ({})
        deviceA.connected = true
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (root.ticks < 3) return
        if (audioOutput.count !== 0)
          return root.fail("superseded intent A changed the default sink")
        deviceB.connected = true
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.ticks < 4) return
        if (audioOutput.count !== 1 || audioOutput.lastSink !== sinkB)
          return root.fail("latest intent B did not exclusively hand off audio")
        deviceB.connected = false
        if (!backend.connectDevice(deviceB))
          return root.fail("could not create expiring intent B")
        backend.nativePendingActions = ({})
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.ticks < 8) return
        deviceB.connected = true
        root.phase++
        root.ticks = 0
      } else {
        if (root.ticks < 4) return
        if (audioOutput.count !== 1)
          return root.fail("expired intent B changed the default sink")
        console.log("bluetooth audio intent regression passed")
        Qt.quit()
        stop()
      }
    }
  }
}
