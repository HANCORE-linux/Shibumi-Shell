import QtQuick

// Entirely local nodes and delegates. No native singleton or action fallback.
Item {
  id: backend
  property bool ready: true
  property real inputPeak: 0.4
  property var nodes: [sink, source]
  property var defaultAudioSink: sink
  property var defaultAudioSource: source
  readonly property alias volume: sinkAudio.volume
  function setDefaultSink(node) { defaultAudioSink = node }
  function setDefaultSource(node) { defaultAudioSource = node }

  QtObject { id: sinkAudio; property real volume: 0.42; property bool muted: false }
  QtObject { id: sourceAudio; property real volume: 0.64; property bool muted: false }
  QtObject {
    id: sink
    property int id: 1
    property bool ready: true
    property bool isSink: true
    property bool isStream: false
    property string name: "fixture_output"
    property string description: "Fixture Output"
    property var audio: sinkAudio
    property var properties: ({})
  }
  QtObject {
    id: source
    property int id: 3
    property bool ready: true
    property bool isSink: false
    property bool isStream: false
    property string name: "fixture_input"
    property string description: "Fixture Microphone"
    property var audio: sourceAudio
    property var properties: ({})
  }
}
