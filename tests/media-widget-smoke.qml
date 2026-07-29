import QtQuick
import Quickshell
import "widgets" as Widgets

ShellRoot {
  id: root

  property int phase: 0
  property int waits: 0
  property real activeWidth: 0
  property var mediaSettings: ({ spectrum: false, compact: false })

  function fail(message) {
    console.error("media-widget-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: playerA
    property string key: "player-a"
    property string identity: "Vesktop"
    property string desktopEntry: "vesktop"
    property string trackTitle: "A deliberately long track title for marquee validation"
    property string trackArtist: "Artist A"
    property string trackAlbum: "Album A"
    property string trackArtUrl: ""
    property bool isPlaying: true
    property bool canGoPrevious: true
    property bool canGoNext: true
    property bool canTogglePlaying: true
    property bool canPlay: true
    property bool canPause: true
    property real position: 61
    property real length: 245
  }

  QtObject {
    id: playerB
    property string key: "player-b"
    property string identity: "Firefox"
    property string desktopEntry: "firefox"
    property string trackTitle: "Track B"
    property string trackArtist: "Artist B"
    property string trackAlbum: ""
    property string trackArtUrl: ""
    property bool isPlaying: false
    property bool canGoPrevious: false
    property bool canGoNext: true
    property bool canTogglePlaying: true
    property bool canPlay: true
    property bool canPause: true
    property real position: 0
    property real length: 180
  }

  QtObject {
    id: mediaState
    property var activePlayer: playerA
    property var sourcePlayers: [playerA, playerB]
    readonly property bool hasMedia: activePlayer !== null
      && (activePlayer.trackTitle !== "" || activePlayer.trackArtist !== "")
    property string lastAction: ""
    property string lastTarget: ""
    property string selectedKey: ""
    property int actionCount: 0

    function playerKey(player) { return player ? String(player.key || "") : "" }

    function runAction(action, showFeedback, targetKey) {
      lastAction = String(action || "")
      lastTarget = String(targetKey || "")
      actionCount++
      if (lastAction === "playPause" && activePlayer)
        activePlayer.isPlaying = !activePlayer.isPlaying
      return activePlayer !== null
    }

    function selectPlayer(key) {
      selectedKey = String(key || "")
      if (selectedKey === playerA.key) activePlayer = playerA
      else if (selectedKey === playerB.key) activePlayer = playerB
      else return false
      return true
    }
  }

  QtObject {
    id: fakeSpectrum
    property var clients: []
    property var levels: [
      0.04, 0.04, 0.04, 0.04, 0.04, 0.04,
      0.04, 0.04, 0.04, 0.04, 0.04, 0.04,
      0.04, 0.04, 0.04, 0.04, 0.04, 0.04,
      0.04, 0.04, 0.04, 0.04, 0.04, 0.04
    ]
    property var themeColors: []
    property string state: "running"
    property bool workerRunning: false
    readonly property int clientCount: clients.length

    function beginSpectrum(owner) {
      if (!owner || clients.indexOf(owner) >= 0) return false
      clients = clients.concat([owner])
      return true
    }

    function endSpectrum(owner) {
      if (!owner || clients.indexOf(owner) < 0) return false
      clients = clients.filter(function(candidate) { return candidate !== owner })
      return true
    }
  }

  QtObject {
    id: fakeShell
    property bool serviceAvailable: true
    function firstPartyServiceFor(id) {
      return serviceAvailable && String(id || "") === "omarchy.media"
        ? mediaState : null
    }
    function serviceFor(id) {
      return String(id || "") === "hancore.shibumi.media"
        ? fakeSpectrum : null
    }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 28
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#e8e8e8"
    property color barForeground: foreground
    property color background: "#181818"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var shell: fakeShell
    property var activePopout: null
    property var clickTargets: []
    property var visualTokens: ({
      pillHeight: 24,
      pillRadius: 12,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      pillPaddingX: 9,
      slotHeight: 28,
      contentGap: 5,
      compactGap: 4,
      labelSize: 12,
      iconSize: 15,
      presentation: ({ radius: "large" })
    })

    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
    function registerClickTarget(target) {
      if (clickTargets.indexOf(target) < 0) clickTargets = clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      clickTargets = clickTargets.filter(function(item) { return item !== target })
    }
  }

  Loader {
    id: mediaLoader
    active: true
    sourceComponent: Component {
      Widgets.MediaWidget {
        bar: fakeBar
        settings: root.mediaSettings
        panelSource: Qt.resolvedUrl("fixtures/MediaTestPanel.qml")
      }
    }
  }

  Widgets.MediaWidget {
    id: unavailableMedia
    bar: unavailableBar
    settings: ({ spectrum: false })
  }

  QtObject {
    id: unavailableBar
    property var shell: null
    property int barSize: 28
    property bool vertical: false
    property string fontFamily: "monospace"
    property color foreground: "#e8e8e8"
    property color barForeground: foreground
    property color background: "#181818"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var visualTokens: fakeBar.visualTokens
    property var clickTargets: []
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function registerClickTarget(target) {
      if (clickTargets.indexOf(target) < 0) clickTargets = clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      clickTargets = clickTargets.filter(function(item) { return item !== target })
    }
  }

  Timer {
    interval: 60
    repeat: true
    running: true
    onTriggered: {
      const media = mediaLoader.item
      if (root.phase === 0) {
        if (!media || !media.mediaService || !media.active || !media.playing
            || media.trackLabel.indexOf("Artist A") < 0 || media.panelLoaded
            || media.fullMode || media.museBandCount !== 24
            || fakeSpectrum.clientCount !== 0
            || unavailableMedia.visible || fakeBar.clickTargets.length !== 1)
          return root.fail("initial media service/presentation contract")
        root.activeWidth = media.implicitWidth
        media.interactionTarget.triggerPress(Qt.LeftButton)
        if (mediaState.lastAction !== "playPause" || playerA.isPlaying)
          return root.fail("play/pause action forwarding")
        media.interactionTarget.wheelMoved(120)
        if (mediaState.lastAction !== "previous")
          return root.fail("wheel previous action forwarding")
        root.mediaSettings = ({ spectrum: false, compact: true })
      } else if (root.phase === 1) {
        if (!media.fullMode || !media.museVisible
            || fakeSpectrum.clientCount !== 1)
          return root.fail("FULL muse presentation/lease")
        media.runMusePrimaryAction()
        if (mediaState.lastAction !== "playPause" || !playerA.isPlaying)
          return root.fail("FULL muse play/pause forwarding")
        media.runMuseWheel(120)
        if (mediaState.lastAction !== "next")
          return root.fail("FULL muse wheel-next forwarding")
        media.runMuseWheel(-120)
        if (mediaState.lastAction !== "previous")
          return root.fail("FULL muse wheel-previous forwarding")
        root.mediaSettings = ({ spectrum: false, compact: false })
      } else if (root.phase === 2) {
        if (media.fullMode || media.museVisible
            || fakeSpectrum.clientCount !== 0)
          return root.fail("FULL muse lease release")
        media.interactionTarget.triggerPress(Qt.RightButton)
      } else if (root.phase === 3) {
        if (!media.opened || !media.panelLoaded || !media.panelItem) return
        if (media.panelItem.renderedSourceCount !== 2
            || media.panelItem.spectrumWorkerRunning
            || media.panelItem.formatTime(61) !== "1:01"
            || media.panelItem.currentLength !== 245)
          return root.fail("lazy panel/state contract")
        if (!media.panelItem.selectSource(1)
            || mediaState.selectedKey !== "player-b"
            || mediaState.activePlayer !== playerB)
          return root.fail("source selection forwarding")
        media.close()
      } else if (root.phase === 4) {
        if (media.opened || media.panelLoaded || media.activePlayer !== playerB)
          return root.fail("lazy panel close")
        mediaState.activePlayer = null
      } else if (root.phase === 5) {
        if (media.active || media.implicitWidth >= root.activeWidth)
          return root.fail("idle V1 presentation")
        media.interactionTarget.triggerPress(Qt.LeftButton)
      } else if (root.phase === 6) {
        if (!media.opened || !media.panelLoaded) return
        media.close()
        mediaLoader.active = false
      } else {
        if (fakeBar.clickTargets.length !== 0 || fakeBar.activePopout !== null
            || fakeSpectrum.clientCount !== 0)
          return root.fail("media teardown")
        stop()
        console.log("media widget smoke passed")
        Qt.quit()
      }
      root.phase++
    }
  }
}
