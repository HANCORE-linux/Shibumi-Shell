pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var audioBackend
  readonly property int renderedSinkCount: audioBackend.audioSinks.length
  readonly property int renderedSourceCount: audioBackend.audioSources.length
  readonly property int renderedStreamCount: audioBackend.audioStreams.length

  function firstSinkLabel() {
    return audioBackend.nodeLabel(audioBackend.audioSinks[0])
  }

  function secondSinkLabel() {
    return audioBackend.nodeLabel(audioBackend.audioSinks[1])
  }

  function selectSecondSink() {
    return audioBackend.setDefaultSink(audioBackend.audioSinks[1])
  }

  function selectSecondSource() {
    return audioBackend.setDefaultSource(audioBackend.audioSources[1])
  }

  function setFirstStreamVolume(value) {
    return audioBackend.setStreamVolume(audioBackend.audioStreams[0], value)
  }

  function toggleFirstStreamMute() {
    return audioBackend.toggleStreamMute(audioBackend.audioStreams[0])
  }

  function toggleInputMute() {
    return audioBackend.toggleInputMute()
  }

  function setInputVolume(value) {
    return audioBackend.setInputVolume(value)
  }

  Component.onCompleted: {
    if (ownerWidget.opened && bar && typeof bar.requestPopout === "function")
      bar.requestPopout(ownerWidget)
  }

  Component.onDestruction: {
    if (bar && bar.activePopout === ownerWidget
        && typeof bar.releasePopout === "function")
      bar.releasePopout(ownerWidget)
  }
}
