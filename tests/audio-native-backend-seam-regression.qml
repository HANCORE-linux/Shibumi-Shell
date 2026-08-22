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
    property bool isSink: true
    property bool isStream: false
    property string name: "bluez_output.AA_00_00_00_00_01.a2dp-sink"
    property string description: "Headset Output"
    property var audio: sinkAudioB
    property var properties: ({ "api.bluez5.address": "AA:00:00:00:00:01" })
  }

  QtObject {
    id: sinkWithoutId
    property bool isSink: true
    property bool isStream: false
    property string name: "bluez_output.BB_00_00_00_00_02.a2dp-sink"
    property string description: "Unstable Headset"
    property var audio: sinkAudioB
    property var properties: ({ "api.bluez5.address": "BB:00:00:00:00:02" })
  }

  QtObject {
    id: source
    property int id: 3
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
    property var nodes: [sinkA, sinkB, sinkWithoutId, source, stream]
    property var defaultAudioSink: sinkA
    property var defaultAudioSource: source
    property int sinkChanges: 0
    function setDefaultSink(node) {
      defaultAudioSink = node
      sinkChanges++
    }
    function setDefaultSource(node) { defaultAudioSource = node }
  }

  Audio.AudioBackendAdapter {
    id: backend
    active: true
    backendOverride: fakeBackend
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
        if (backend.rawNodes !== undefined || backend.sink !== undefined
            || backend.source !== undefined
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
        if (!routeResult.ok || routeResult.entityId !== "sink:2"
            || fakeBackend.defaultAudioSink !== sinkB
            || missingIdResult.ok || missingIdResult.code !== "stale-id")
          return root.fail("Bluetooth route resolution")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (root.ticks < 2) return
        if (!backend.setOutputVolume(0.55).ok
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
