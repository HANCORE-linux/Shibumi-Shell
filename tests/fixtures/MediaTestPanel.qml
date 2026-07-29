pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property Item anchorItem
  required property var bar
  required property var ownerWidget
  required property var mediaService
  property var spectrumService: null
  property bool spectrumEnabled: true
  readonly property int renderedSourceCount: mediaService && mediaService.sourcePlayers
    ? mediaService.sourcePlayers.length : 0
  readonly property bool spectrumWorkerRunning: false
  readonly property real currentLength: mediaService && mediaService.activePlayer
    ? Number(mediaService.activePlayer.length || 0) : 0

  function formatTime(seconds) {
    const value = Math.max(0, Math.floor(Number(seconds) || 0))
    return Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0")
  }

  function selectSource(index) {
    const players = mediaService && mediaService.sourcePlayers
      ? mediaService.sourcePlayers : []
    if (index < 0 || index >= players.length || !mediaService
        || typeof mediaService.playerKey !== "function"
        || typeof mediaService.selectPlayer !== "function") return false
    return mediaService.selectPlayer(mediaService.playerKey(players[index])) === true
  }

  Component.onCompleted: {
    if (ownerWidget.opened && bar && typeof bar.requestPopout === "function")
      bar.requestPopout(ownerWidget)
  }
  Component.onDestruction: {
    if (bar && bar.activePopout === ownerWidget
        && typeof bar.releasePopout === "function") bar.releasePopout(ownerWidget)
  }
}
