pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui as Ui

Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property bool manageIpc: false
  property bool opened: false
  property real outputVolume: 0.42
  property bool outputMuted: false
  property real inputVolume: 0.64
  property bool inputMuted: false
  property var sink: sinkA
  property var source: sourceA
  property var audioSinks: [sinkA, sinkC, sinkB]
  property var audioSources: [sourceA, sourceB]
  property var audioStreams: [streamA, streamB]
  property int defaultSinkChanges: 0
  property int defaultSourceChanges: 0
  property int outputVolumeChanges: 0
  property int inputVolumeChanges: 0
  property int openCount: 0
  readonly property var internalButton: button
  readonly property bool backendKeyboardPanelOpen:
    backendKeyboardPanel.open
  readonly property bool backendKeyboardPanelVisible:
    backendKeyboardPanel.visible

  QtObject {
    id: backendKeyboardPanel
    property Item anchorItem: root
    property var owner: root
    property bool open: root.opened
    property bool visible: root.opened
    function beginFocusPrime() {}
  }

  implicitWidth: 27
  implicitHeight: 35

  function open() {
    openCount++
    opened = true
    if (bar) bar.requestPopout(root)
  }

  function close() {
    opened = false
    if (bar) bar.releasePopout(root)
  }

  function toggle() { opened ? close() : open() }
  function toggleOutputMute() { outputMuted = !outputMuted }
  function setOutputVolume(value) {
    outputVolumeChanges++
    outputVolume = Math.max(0, Math.min(1, value))
  }
  function toggleInputMute() { inputMuted = !inputMuted }
  function setInputVolume(value) {
    inputVolumeChanges++
    inputVolume = Math.max(0, Math.min(1, value))
  }
  function setDefaultSink(node) {
    sink = node
    defaultSinkChanges++
  }
  function setDefaultSource(node) {
    source = node
    defaultSourceChanges++
  }
  // Match the current Omarchy helper's nickname-first behavior so the Shibumi
  // bridge test proves that visible labels restore the fuller description.
  function nodeLabel(node) {
    return node ? String(node.nickname || node.description || node.name || "") : ""
  }
  function sinkGlyph(_node) { return "speaker" }
  function sourceGlyph(_node) { return "mic" }
  function streamLabel(node) { return node ? String(node.description || "App") : "App" }

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
    id: sinkAudioC
    property real volume: 1.00
    property bool muted: false
  }

  QtObject {
    id: sourceAudioA
    property real volume: 0.64
    property bool muted: false
  }

  QtObject {
    id: sourceAudioB
    property real volume: 0.55
    property bool muted: false
  }

  QtObject {
    id: streamAudioA
    property real volume: 0.25
    property bool muted: false
  }

  QtObject {
    id: streamAudioB
    property real volume: 0.70
    property bool muted: true
  }

  QtObject {
    id: sinkA
    property int id: 1
    property string name: "sink-a"
    property bool ready: true
    property string nickname: "SteelSeries Arctis 7"
    property string description: "SteelSeries Arctis 7 Chat"
    property var properties: ({
      "device.id": "99",
      "node.nick": "SteelSeries Arctis 7",
      "device.profile.description": "Chat"
    })
    property var audio: sinkAudioA
  }

  QtObject {
    id: sinkB
    property int id: 2
    property string name: "sink-b"
    property bool ready: true
    property string nickname: "USB Audio #1"
    property string description: "SteelSeries Arctis 7"
    property var properties: ({
      "device.id": "99",
      "node.nick": "USB Audio #1",
      "device.profile.description": "Game"
    })
    property var audio: sinkAudioB
  }

  QtObject {
    id: sinkC
    property int id: 7
    property string name: "sink-hdmi"
    property bool ready: true
    property string nickname: "27GL850"
    property string description: "TU104 HD Audio Controller Digital Stereo (HDMI)"
    property var properties: ({
      "device.id": "80",
      "device.profile.description": "Digital Stereo (HDMI)"
    })
    property var audio: sinkAudioC
  }

  QtObject {
    id: sourceA
    property int id: 3
    property string name: "source-a"
    property string description: "Internal Microphone"
    property var audio: sourceAudioA
  }

  QtObject {
    id: sourceB
    property int id: 4
    property string name: "source-b"
    property string description: "USB Microphone"
    property var audio: sourceAudioB
  }

  QtObject {
    id: streamA
    property int id: 5
    property string description: "Browser"
    property var audio: streamAudioA
  }

  QtObject {
    id: streamB
    property int id: 6
    property string description: "Music"
    property var audio: streamAudioB
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "speaker"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleOutputMute()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      root.setOutputVolume(root.outputVolume + (delta > 0 ? 0.05 : -0.05))
    }
  }
}
