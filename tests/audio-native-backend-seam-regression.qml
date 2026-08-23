import QtQuick
import Quickshell
import "audio" as Audio

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("audio-native-backend-seam-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: sinkAudioA
    property real volume: 0.42
    property bool muted: false
  }

  QtObject {
    id: sinkAudioB
    property real volume: 0.30
    property bool muted: false
  }

  QtObject {
    id: sourceAudio
    property real volume: 0.64
    property bool muted: false
  }

  QtObject {
    id: streamAudio
    property real volume: 0.75
    property bool muted: false
  }

  QtObject {
    id: sinkA
    property int id: 1
    property bool ready: true
    property bool isSink: true
    property bool isStream: false
    property string name: "alsa_output.pci-1"
    property string description: "Built-in Audio"
    property var audio: sinkAudioA
    property var properties: ({})
  }

  QtObject {
    id: sinkB
    property int id: 2
    property bool ready: true
    property bool isSink: true
    property bool isStream: false
    property string name: "bluez_output.AA_00_00_00_00_01.a2dp-sink"
    property string description: "Headset Output"
    property var audio: sinkAudioB
    property var properties: ({ "api.bluez5.address": "AA:00:00:00:00:01" })
  }

  QtObject {
    id: sinkWithoutId
    property bool ready: true
    property bool isSink: true
    property bool isStream: false
    property string name: "bluez_output.BB_00_00_00_00_02.a2dp-sink"
    property string description: "Unstable Headset"
    property var audio: sinkAudioB
    property var properties: ({ "api.bluez5.address": "BB:00:00:00:00:02" })
  }

  QtObject {
    id: sinkWithEmptyId
    property string id: ""
    property bool ready: true
    property bool isSink: true
    property bool isStream: false
    property string name: "bluez_output.DD_00_00_00_00_04.a2dp-sink"
    property string description: "Empty ID Headset"
    property var audio: sinkAudioA
    property var properties: ({ "api.bluez5.address": "DD:00:00:00:00:04" })
  }

  QtObject {
    id: source
    property int id: 3
    property bool ready: true
    property bool isSink: false
    property bool isStream: false
    property string name: "alsa_input.pci-1"
    property string description: "Built-in Microphone"
    property var audio: sourceAudio
    property var properties: ({})
  }

  QtObject {
    id: stream
    property int id: 8
    property bool ready: true
    property bool isSink: true
    property bool isStream: true
    property string name: "spotify"
    property string description: "Spotify"
    property string type: "Stream/Output/Audio"
    property var audio: streamAudio
    property var properties: ({})
  }

  QtObject {
    id: fakeBackend
    property bool ready: true
    property real inputPeak: 0.4
    property var nodes: [sinkA, sinkB, sinkWithoutId, sinkWithEmptyId, source, stream]
    property var defaultAudioSink: sinkA
    property var defaultAudioSource: source
    property int sinkChanges: 0
    function setDefaultSink(node) {
      defaultAudioSink = node
      sinkChanges++
    }
    function setDefaultSource(node) { defaultAudioSource = node }
  }

  QtObject {
    id: incompleteBackend
    property bool ready: true
    property var nodes: [sinkA]
    property var defaultAudioSink: sinkA
  }

  QtObject {
    id: typedFailingBackend
    property bool ready: true
    property var nodes: [sinkA]
    property var defaultAudioSink: sinkA
    function setDefaultSink(_node) {
      return {
        ok: false,
        code: "unavailable",
        message: "fixture delegate failure",
        entityId: "sink:1",
        generation: 9
      }
    }
  }

  Audio.AudioBackendAdapter {
    id: backend
    active: true
    peakMonitoringClients: 1
    backendOverride: fakeBackend
  }

  Audio.AudioBackendAdapter {
    id: incompleteBackendAdapter
    active: true
    backendOverride: incompleteBackend
  }

  Audio.AudioBackendAdapter {
    id: typedFailingAdapter
    active: true
    backendOverride: typedFailingBackend
  }

  Audio.Service {
    id: service
    nativeBackendEnabled: true
    nativeBackendOverride: fakeBackend
  }

  Timer {
    interval: 30
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.phase === 0) {
        if (!backend) return root.fail("native backend component did not instantiate")
        if (root.ticks < 3) return
        if (!backend.ready || backend.audioSinks.length !== 2
            || backend.audioSources.length !== 1
            || backend.audioStreams.length !== 1)
          return root.fail("native backend snapshots")
        const incompleteResult =
          incompleteBackendAdapter.setDefaultSink("sink:1")
        const typedFailure = typedFailingAdapter.setDefaultSink("sink:1")
        if (incompleteResult.ok || incompleteResult.code !== "unsupported"
            || typedFailure.ok
            || typedFailure.code !== "unavailable"
            || typedFailure.message !== "fixture delegate failure"
            || typedFailure.generation !== 9
            || backend.currentNodes !== undefined
            || backend.currentSink !== undefined
            || backend.currentSource !== undefined
            || backend.filterSinks !== undefined
            || backend.filterSources !== undefined
            || backend.filterStreams !== undefined
            || !service.nativeBackendReady
            || service.nativeAudioSinks.length !== 2
            || service.nativeAudioSinks[0].node !== undefined
            || backend.audioSinks[0].node !== undefined
            || backend.audioSinks[0].id !== "sink:1"
            || backend.sinkSnapshot.id !== "sink:1"
            || backend.sinkSnapshot.volume !== 0.42)
          return root.fail("primitive stable sink snapshot")
        const routeResult = backend.routeBluetoothDevice({
          address: "AA:00:00:00:00:01",
          name: "Headset",
          deviceName: "Headset"
        })
        const missingIdResult = backend.routeBluetoothDevice({
          address: "BB:00:00:00:00:02",
          name: "Unstable Headset",
          deviceName: "Unstable Headset"
        })
        const wrongAddressResult = backend.routeBluetoothDevice({
          address: "CC:00:00:00:00:03",
          name: "Headset Output",
          deviceName: "Headset Output"
        })
        const invalidAddressResult = backend.routeBluetoothDevice({
          address: "ZZ",
          name: "Headset Output",
          deviceName: "Headset Output"
        })
        const emptyIdResult = backend.routeBluetoothDevice({
          address: "DD:00:00:00:00:04",
          name: "Empty ID Headset",
          deviceName: "Empty ID Headset"
        })
        if (!routeResult.ok || routeResult.entityId !== "sink:2"
            || fakeBackend.defaultAudioSink !== sinkB
            || missingIdResult.ok || missingIdResult.code !== "stale-id"
            || wrongAddressResult.ok || wrongAddressResult.code !== "stale-id"
            || invalidAddressResult.ok || invalidAddressResult.code !== "stale-id"
            || emptyIdResult.ok || emptyIdResult.code !== "stale-id")
          return root.fail("Bluetooth route resolution")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (root.ticks < 2) return
        const generationBeforeVolume = backend.generation
        const outputResult = backend.setOutputVolume(0.55)
        if (Math.abs(backend.inputPeak - 0.4) > 0.001
            || !outputResult.ok
            || outputResult.generation <= generationBeforeVolume
            || Math.abs(sinkAudioB.volume - 0.55) > 0.001
            || !backend.toggleOutputMute().ok || !sinkAudioB.muted)
          return root.fail("typed output actions")
        if (!backend.setDefaultSource("source:3").ok
            || fakeBackend.defaultAudioSource !== source
            || !backend.setStreamVolume("stream:8", 0.65).ok
            || Math.abs(streamAudio.volume - 0.65) > 0.001
            || !backend.toggleStreamMute("stream:8").ok
            || !streamAudio.muted)
          return root.fail("typed source/stream actions")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.ticks < 2) return
        const sinkVolume = sinkAudioB.volume
        const sinkMuted = sinkAudioB.muted
        const streamVolume = streamAudio.volume
        const streamMuted = streamAudio.muted
        fakeBackend.ready = false
        const cachedUnavailablePeak = backend.inputPeak
        const cachedUnavailableOutput = backend.setOutputVolume(0.12)
        const cachedUnavailableMute = backend.toggleOutputMute()
        const cachedUnavailableSource = backend.setInputVolume(0.12)
        const cachedUnavailableStream = backend.setStreamVolume("stream:8", 0.12)
        const cachedUnavailableRoute = backend.setDefaultSink("sink:2")
        fakeBackend.ready = true
        if (cachedUnavailablePeak !== 0
            || cachedUnavailableOutput.ok
            || cachedUnavailableMute.ok
            || cachedUnavailableSource.ok
            || cachedUnavailableStream.ok
            || cachedUnavailableRoute.ok
            || sinkAudioB.volume !== sinkVolume
            || sinkAudioB.muted !== sinkMuted
            || streamAudio.volume !== streamVolume
            || streamAudio.muted !== streamMuted)
          return root.fail("cached nodes were mutated while backend was unavailable")
        sinkB.ready = false
        source.ready = false
        stream.ready = false
        const unavailableOutput = backend.setOutputVolume(0.12)
        const unavailableMute = backend.toggleOutputMute()
        const unavailableSource = backend.setInputVolume(0.12)
        const unavailableStream = backend.setStreamVolume("stream:8", 0.12)
        const unavailableRoute = backend.setDefaultSink("sink:2")
        const staleIdResult = backend.setDefaultSink("sink:999")
        if (unavailableOutput.ok || unavailableOutput.code !== "unavailable"
            || unavailableMute.ok || unavailableSource.ok
            || unavailableStream.ok || unavailableRoute.ok
            || staleIdResult.ok || staleIdResult.code !== "stale-id"
            || sinkAudioB.volume !== sinkVolume
            || sinkAudioB.muted !== sinkMuted
            || streamAudio.volume !== streamVolume
            || streamAudio.muted !== streamMuted)
          return root.fail("unavailable nodes were mutated")
        backend.active = false
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.ticks < 2) return
        if (backend.ready || backend.audioSinks.length !== 0
            || backend.audioSources.length !== 0
            || backend.audioStreams.length !== 0)
          return root.fail("inactive native backend remained active")
        stop()
        console.log("audio native backend seam regression passed")
        Qt.quit()
      }
    }
  }
}
