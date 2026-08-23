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

  function actionSucceeded(value) {
    return value && value.ok === true
  }

  function selectSecondSink() {
    return actionSucceeded(
      audioBackend.setDefaultSink(audioBackend.audioSinks[1].id))
  }

  function selectSecondSource() {
    return actionSucceeded(
      audioBackend.setDefaultSource(audioBackend.audioSources[1].id))
  }

  function setFirstStreamVolume(value) {
    return actionSucceeded(
      audioBackend.setStreamVolume(audioBackend.audioStreams[0].id, value))
  }

  function toggleFirstStreamMute() {
    return actionSucceeded(
      audioBackend.toggleStreamMute(audioBackend.audioStreams[0].id))
  }

  function toggleInputMute() {
    return actionSucceeded(audioBackend.toggleInputMute())
  }

  function setInputVolume(value) {
    return actionSucceeded(audioBackend.setInputVolume(value))
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
