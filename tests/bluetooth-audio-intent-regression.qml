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
    id: deviceWrongAddress
    property string address: "CC:00:00:00:00:03"
    property string name: "Intent A"
    property string deviceName: name
    property bool connected: true
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
    property bool ready: true
    property string name: "bluez_output.AA_00_00_00_00_01.a2dp-sink"
    property string description: "Intent A"
    property string nickname: ""
    property string nick: ""
    property var properties: ({ "api.bluez5.address": deviceA.address })
  }

  QtObject {
    id: malformedSinkId
    property bool isSink: true
    property bool isStream: false
    property string id: "abc"
    property bool ready: true
    property string name: "bluez_output.DD_00_00_00_00_04.a2dp-sink"
    property string description: "Malformed ID"
    property string nickname: ""
    property string nick: ""
    property var properties: ({ "api.bluez5.address": "DD:00:00:00:00:04" })
  }

  QtObject {
    id: sinkB
    property bool isSink: true
    property bool isStream: false
    property int id: 802
    property bool ready: true
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
    property string lastEntityId: ""
    function setDefaultSink(entityId) {
      count++
      lastEntityId = String(entityId)
      return {
        ok: true,
        code: "ok",
        message: "",
        entityId: lastEntityId,
        generation: 0
      }
    }
  }

  QtObject {
    id: incompleteAudioOutput
  }

  QtObject {
    id: typedFailingAudioOutput
    function setDefaultSink(_entityId) {
      return {
        ok: false,
        code: "unavailable",
        message: "fixture delegate failure",
        entityId: "sink:801",
        generation: 7
      }
    }
  }

  QtObject {
    id: booleanFailingAudioOutput
    function setDefaultSink(_entityId) { return false }
  }

  QtObject {
    id: routeOverride
    property int count: 0
    property var lastRequest: null
    function routeBluetoothDevice(request) {
      count++
      lastRequest = request
      return {
        ok: true,
        code: "ok",
        message: "",
        entityId: "",
        generation: 0
      }
    }
  }

  Bluetooth.BluetoothBackendAdapter {
    id: seamBackend
    adapterOverride: nativeAdapter
    nativeDevicesOverride: []
    pipewireNodesOverride: []
    audioRouteOverride: routeOverride
  }

  Bluetooth.BluetoothAudioRouteAdapter {
    id: pipewireNotReadyRoute
    nodesOverride: []
    readyOverride: false
  }

  Bluetooth.BluetoothAudioRouteAdapter {
    id: pipewireReadyEmptyRoute
    nodesOverride: []
    readyOverride: true
  }

  Bluetooth.BluetoothBackendAdapter {
    id: backend
    adapterOverride: nativeAdapter
    nativeDevicesOverride: [deviceA, deviceB]
    pipewireNodesOverride: [sinkA, sinkB, malformedSinkId]
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
        const unavailablePipewireRoute =
          pipewireNotReadyRoute.routeBluetoothDevice({
            address: deviceA.address,
            name: deviceA.name,
            deviceName: deviceA.deviceName
          })
        const staleEmptyPipewireRoute =
          pipewireReadyEmptyRoute.routeBluetoothDevice({
            address: deviceA.address,
            name: deviceA.name,
            deviceName: deviceA.deviceName
          })
        sinkA.ready = false
        const unavailableRoute = backend.requestBluetoothAudioRoute(deviceA)
        sinkA.ready = true
        const invalidAddressRoute = backend.requestBluetoothAudioRoute({
          address: "ZZ",
          name: "Intent A",
          deviceName: "Intent A"
        })
        const malformedIdRoute = backend.requestBluetoothAudioRoute({
          address: "DD:00:00:00:00:04",
          name: "Malformed ID",
          deviceName: "Malformed ID"
        })
        backend.audioOutputOverride = incompleteAudioOutput
        const unsupportedRoute = backend.requestBluetoothAudioRoute(deviceA)
        backend.audioOutputOverride = typedFailingAudioOutput
        const typedFailure = backend.requestBluetoothAudioRoute(deviceA)
        backend.audioOutputOverride = booleanFailingAudioOutput
        const booleanFailure = backend.requestBluetoothAudioRoute(deviceA)
        backend.audioOutputOverride = audioOutput
        if (!seamBackend.requestBluetoothAudioRoute(deviceA).ok
            || unavailablePipewireRoute.ok
            || unavailablePipewireRoute.code !== "unavailable"
            || staleEmptyPipewireRoute.ok
            || staleEmptyPipewireRoute.code !== "stale-id"
            || routeOverride.count !== 1
            || routeOverride.lastRequest.address !== deviceA.address
            || routeOverride.lastRequest.name !== deviceA.name
            || "adapter" in routeOverride.lastRequest
            || "connected" in routeOverride.lastRequest
            || backend.requestBluetoothAudioRoute(deviceWrongAddress).ok
            || invalidAddressRoute.ok
            || malformedIdRoute.ok
            || malformedIdRoute.code !== "stale-id"
            || unsupportedRoute.ok
            || unsupportedRoute.code !== "unsupported"
            || typedFailure.ok
            || typedFailure.code !== "unavailable"
            || typedFailure.message !== "fixture delegate failure"
            || typedFailure.entityId !== "sink:801"
            || typedFailure.generation !== 7
            || booleanFailure.ok
            || booleanFailure.code !== "unavailable"
            || unavailableRoute.ok)
          return root.fail("Bluetooth route seam leaked, misrouted, or mutated an unavailable sink")
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
        if (audioOutput.count !== 1
            || audioOutput.lastEntityId !== "sink:802")
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
