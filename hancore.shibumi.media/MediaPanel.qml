pragma ComponentBehavior: Bound

import QtQuick
import "MediaMotion.js" as Motion
import Quickshell.Services.Mpris
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/lib/presentation" as Presentation

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var mediaService
  property var spectrumService: null
  property bool spectrumEnabled: true
  property string focusSection: "controls"
  property int cursorIndex: 1
  property real currentPosition: 0
  readonly property real currentLength: player && player.lengthSupported === true
    ? Math.max(0, Number(player.length) || 0) : 0
  property real lastPositionRead: 0
  property bool motionStepping: false
  property int motionStep: 0
  readonly property bool motionRunning: open && visible && playing
  readonly property bool progressShown: open && active && !!player
    && player.positionSupported === true && player.lengthSupported === true
    && isFinite(currentLength) && currentLength > 0
  property var leasedSpectrumService: null

  readonly property var player: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService && mediaService.sourcePlayers
    ? mediaService.sourcePlayers : []
  readonly property bool active: !!(player && (player.trackTitle || player.trackArtist))
  readonly property bool playing: active && player.isPlaying === true
  readonly property bool spectrumRequested: open && active && spectrumEnabled && visible
  readonly property var pendingLevels: spectrumService && spectrumService.levels
    ? spectrumService.levels : flatLevels(active ? 0.04 : 0.02)
  property var levels: flatLevels(0.04)
  readonly property var spectrumThemeColors: spectrumService
    && spectrumService.themeColors ? spectrumService.themeColors : []
  readonly property int renderedSourceCount: sourceRepeater.count
  readonly property bool sourcesVisible: sourceList.visible
  readonly property bool vinylRotating: vinylArtwork.rotating
  readonly property bool albumVisible: albumText.visible
  readonly property bool playerNameVisible: playerText.visible
  readonly property var shuffleControl: shuffleButton
  readonly property var repeatControl: repeatButton
  readonly property var seekControl: seekMouse
  readonly property bool directAvailable: open && active && !!player && player.canControl === true && sourcePlayers.indexOf(player) >= 0
  readonly property bool seekAvailable: directAvailable && !!player && player.canSeek === true
    && player.positionSupported === true && player.lengthSupported === true && isFinite(player.length) && player.length > 0
  readonly property bool spectrumWorkerRunning: spectrumService
    ? spectrumService.workerRunning === true : false
  readonly property string spectrumState: spectrumService
    ? String(spectrumService.state || "inactive") : "unavailable"
  readonly property string playerName: player
    ? String(player.identity || player.desktopEntry || "") : ""

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(320))
  contentHeight: fittedContentHeight(content.implicitHeight)

  function flatLevels(value) {
    const result = []
    for (let i = 0; i < 24; i++) result.push(Number(value) || 0)
    return result
  }

  function playerKey(target) {
    return mediaService && typeof mediaService.playerKey === "function"
      ? String(mediaService.playerKey(target) || "") : ""
  }

  function runAction(action) {
    return mediaService && typeof mediaService.runAction === "function"
      ? mediaService.runAction(String(action || ""), false,
        playerKey(player)) === true : false
  }

  // Approved exception: only shuffle, repeat and seek mutate the selected native
  // player directly. Transport still belongs to Omarchy; no discovery, IPC or OSD.
  function directAction(action, target, value, trackId) {
    if (!directAvailable || !target || target !== player || target.canControl !== true) return false
    try {
      if (action === "shuffle" && target.shuffleSupported === true) {
        target.shuffle = !target.shuffle
      } else if (action === "repeat" && target.loopSupported === true) {
        target.loopState = target.loopState === MprisLoopState.None ? MprisLoopState.Track
          : target.loopState === MprisLoopState.Track ? MprisLoopState.Playlist : MprisLoopState.None
      } else if (action === "seek" && seekAvailable && target.uniqueId === trackId && typeof value === "number" && isFinite(value)) {
        target.position = Math.max(0, Math.min(target.length, value)) // Native API uses seconds.
        resetPosition()
      } else return false
      return true
    } catch (_error) { return false }
  }

  function controlAction(action) {
    return action === "shuffle" || action === "repeat" ? directAction(action, player) : runAction(action)
  }

  function selectSource(index) {
    if (index < 0 || index >= sourcePlayers.length || !mediaService
        || typeof mediaService.selectPlayer !== "function") return false
    return mediaService.selectPlayer(playerKey(sourcePlayers[index])) === true
  }

  function activateCursor() {
    if (focusSection === "sources") return selectSource(cursorIndex)
    if (cursorIndex === -1) return controlAction("shuffle")
    if (cursorIndex === 3) return controlAction("repeat")
    if (cursorIndex === 0) return runAction("previous")
    if (cursorIndex === 2) return runAction("next")
    return runAction("playPause")
  }

  function moveCursor(dx, dy) {
    if (focusSection === "controls") {
      if (dy > 0 && sourcePlayers.length > 1) {
        focusSection = "sources"
        cursorIndex = 0
      } else if (dx !== 0) {
        cursorIndex = Math.max(-1, Math.min(3, cursorIndex + dx))
      }
      return
    }

    if (dy < 0 && cursorIndex === 0) {
      focusSection = "controls"
      cursorIndex = 1
    } else if (dy !== 0 && sourcePlayers.length > 0) {
      cursorIndex = (cursorIndex + dy + sourcePlayers.length) % sourcePlayers.length
    }
  }

  function syncPosition() {
    // Revocation can notify before dependent QML bindings have reevaluated.
    const target = player
    if (!progressShown || !target) return
    const reported = Number(target.position)
    currentPosition = Math.floor(Math.max(0, Math.min(currentLength,
      isFinite(reported) ? reported : 0)))
    lastPositionRead = Date.now()
  }

  // Discrete native changes refresh immediately, including pause/seek. Only
  // periodic reads are restricted to playing; a closed panel never samples.
  function resetPosition() {
    if (!open) return
    if (progressShown) syncPosition()
    else currentPosition = 0
  }

  function advanceMotion() {
    if (!motionRunning) return
    const now = Date.now()
    const delta = 40
    motionStepping = true
    motionStep++
    vinylArtwork.advance(delta)
    if (!Motion.sameLevels(levels, pendingLevels)) levels = pendingLevels
    if (progressShown && now - lastPositionRead >= 1000) syncPosition()
    motionStepping = false
  }

  function formatTime(seconds) {
    const value = Math.max(0, Math.floor(Number(seconds) || 0))
    const minutes = Math.floor(value / 60)
    const rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  function syncSpectrumLease() {
    const next = spectrumRequested ? spectrumService : null
    if (leasedSpectrumService === next) return
    if (leasedSpectrumService
        && typeof leasedSpectrumService.endSpectrum === "function")
      leasedSpectrumService.endSpectrum(panel)
    leasedSpectrumService = next
    if (leasedSpectrumService
        && typeof leasedSpectrumService.beginSpectrum === "function")
      leasedSpectrumService.beginSpectrum(panel)
  }

  function releaseSpectrumLease() {
    if (leasedSpectrumService
        && typeof leasedSpectrumService.endSpectrum === "function")
      leasedSpectrumService.endSpectrum(panel)
    leasedSpectrumService = null
  }

  onPlayerChanged: resetPosition()
  onPlayingChanged: resetPosition()
  onOpenChanged: if (open) resetPosition()
  onPendingLevelsChanged: {
    if (open && visible && !playing && !Motion.sameLevels(levels, pendingLevels))
      levels = pendingLevels
  }

  property Connections positionSignals: Connections {
    target: panel.open ? panel.player : null
    ignoreUnknownSignals: true
    function onPositionChanged() { panel.resetPosition() }
    function onLengthChanged() { panel.resetPosition() }
    function onPositionSupportedChanged() { panel.resetPosition() }
    function onLengthSupportedChanged() { panel.resetPosition() }
    function onUniqueIdChanged() { panel.resetPosition() }
    function onTrackTitleChanged() { panel.resetPosition() }
    function onTrackArtistChanged() { panel.resetPosition() }
  }
  onSpectrumRequestedChanged: syncSpectrumLease()
  onSpectrumServiceChanged: syncSpectrumLease()
  onSourcePlayersChanged: {
    if (focusSection === "sources" && sourcePlayers.length <= 1) {
      focusSection = "controls"
      cursorIndex = 1
    } else if (focusSection === "sources") {
      cursorIndex = Math.max(0, Math.min(cursorIndex, sourcePlayers.length - 1))
    }
  }
  Component.onCompleted: {
    resetPosition()
    syncSpectrumLease()
  }
  Component.onDestruction: releaseSpectrumLease()

  // The existing panel clock also steps the vinyl/bands. Only every elapsed
  // second can sample position; no other animation or progress timer is needed.
  property Timer positionTimer: Timer {
    interval: 40
    repeat: true
    running: panel.motionRunning
    onTriggered: panel.advanceMotion()
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }
    onMoveRequested: function(dx, dy) { panel.moveCursor(dx, dy) }
    onActivateRequested: panel.activateCursor()

    Column {
      id: content
      width: parent.width
      spacing: Commons.Style.space(9)

      Item {
        width: parent.width
        height: Commons.Style.space(24)

        Presentation.PanelHeading {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "NOW PLAYING"
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(8)

          IconAction {
            anchors.verticalCenter: parent.verticalCenter
            icon: "close"
            tooltip: "Close"
            onClicked: panel.ownerWidget.close()
          }
        }
      }

      Ui.PanelSeparator {
        foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
      }

      Row {
        width: parent.width
        spacing: Commons.Style.space(10)
        visible: panel.active

        PanelVinyl {
          id: vinylArtwork
          width: Commons.Style.space(80)
          height: width
          tint: panel.bar ? panel.bar.urgent : Commons.Color.accent
          artSource: panel.player ? String(panel.player.trackArtUrl || "") : ""
          spinning: panel.open && panel.playing
          revolutionMs: 6000
        }

        Column {
          width: parent.width - vinylArtwork.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(3)

          Text {
            width: parent.width
            text: panel.player ? String(panel.player.trackTitle || "Unknown") : ""
            color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            font.weight: Font.Medium
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: panel.player ? String(panel.player.trackArtist || "") : ""
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.68)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }

          Text {
            id: albumText
            width: parent.width
            visible: text !== ""
            text: panel.player ? String(panel.player.trackAlbum || "") : ""
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.45)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }
          Text {
            id: playerText
            width: parent.width
            visible: text !== ""
            text: panel.playerName
            color: panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }
        }
      }

      MediaSpectrum {
        width: parent.width
        height: Commons.Style.space(40)
        visible: panel.active
        levels: panel.levels
        tint: panel.bar ? panel.bar.urgent : Commons.Color.accent
        themeColors: panel.spectrumThemeColors
        opacity: panel.playing ? 1 : 0.5
      }

      Item {
        width: parent.width
        height: Commons.Style.space(18)
        visible: panel.progressShown

        MouseArea {
          id: seekMouse
          anchors.fill: parent; z: 1
          enabled: panel.seekAvailable
          cursorShape: Qt.PointingHandCursor
          property var pressedPlayer: null
          property var pressedTrack: null
          onPressed: { pressedPlayer = panel.player; pressedTrack = pressedPlayer.uniqueId }
          onCanceled: pressedPlayer = null
          onClicked: function(mouse) {
            if (pressedPlayer && pressedPlayer === panel.player && pressedTrack === pressedPlayer.uniqueId)
              panel.directAction("seek", pressedPlayer, mouse.x / Math.max(1, width) * pressedPlayer.length, pressedTrack)
            pressedPlayer = null
          }
        }
        Rectangle {
          id: progressTrack
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Commons.Style.space(4)
          radius: height / 2
          color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
            panel.bar.foreground.g, panel.bar.foreground.b, 0.12)
            : Commons.Color.background

          Rectangle {
            height: parent.height
            width: parent.width * Math.min(1,
              panel.currentPosition / Math.max(1, panel.currentLength))
            radius: height / 2
            color: panel.bar ? panel.bar.urgent : Commons.Color.accent
          }
        }

        Text {
          anchors.left: parent.left
          anchors.top: progressTrack.bottom
          anchors.topMargin: 2
          text: panel.formatTime(panel.currentPosition)
          color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
            panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
            : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption
          renderType: Text.NativeRendering
        }

        Text {
          anchors.right: parent.right
          anchors.top: progressTrack.bottom
          anchors.topMargin: 2
          text: panel.formatTime(panel.currentLength)
          color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
            panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
            : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption
          renderType: Text.NativeRendering
        }
      }

      Item {
        width: parent.width
        height: Commons.Style.space(40)
        visible: !panel.active

        Column {
          anchors.centerIn: parent
          visible: !panel.active
          spacing: 1

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No song playing"
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "no active player"
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.32)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            renderType: Text.NativeRendering
          }
        }
      }

      Row {
        visible: panel.active
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Commons.Style.space(8)

        MediaPanelButton {
          id: shuffleButton
          icon: "shuffle"; action: "shuffle"; controlIndex: -1
          tooltipText: checked ? "Shuffle: On" : "Shuffle: Off"
          checked: !!panel.player && panel.player.shuffle === true
          enabled: panel.directAvailable && !!panel.player && panel.player.shuffleSupported === true
        }
        MediaPanelButton {
          icon: "skip_previous"
          action: "previous"
          controlIndex: 0
          enabled: panel.player && panel.player.canGoPrevious === true
        }
        MediaPanelButton {
          icon: panel.playing ? "pause" : "play_arrow"
          action: "playPause"
          controlIndex: 1
          accent: true
          enabled: panel.player && (panel.player.canTogglePlaying === true
            || panel.player.canPlay === true || panel.player.canPause === true)
        }
        MediaPanelButton {
          icon: "skip_next"
          action: "next"
          controlIndex: 2
          enabled: panel.player && panel.player.canGoNext === true
        }
        MediaPanelButton {
          id: repeatButton
          icon: panel.player && panel.player.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
          action: "repeat"; controlIndex: 3
          tooltipText: "Repeat: " + (!checked ? "Off" : panel.player.loopState === MprisLoopState.Track ? "Track" : "Playlist")
          checked: !!panel.player && (panel.player.loopState === MprisLoopState.Track || panel.player.loopState === MprisLoopState.Playlist)
          enabled: panel.directAvailable && !!panel.player && panel.player.loopSupported === true
        }
      }

      Ui.PanelSeparator {
        visible: panel.sourcePlayers.length > 1
        foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
      }

      Column {
        id: sourceList
        width: parent.width
        visible: panel.sourcePlayers.length > 1
        spacing: Commons.Style.space(2)

        Repeater {
          id: sourceRepeater
          model: panel.sourcePlayers

          delegate: Rectangle {
            id: sourceRow
            required property var modelData
            required property int index
            readonly property bool selected: panel.playerKey(panel.player)
              === panel.playerKey(modelData)
            readonly property bool cursor: panel.focusSection === "sources"
              && panel.cursorIndex === index

            width: parent.width
            height: Commons.Style.space(34)
            radius: panel.renderedSurfaceRadius
            color: cursor || sourceMouse.containsMouse
              ? panel.bar ? Qt.rgba(panel.bar.urgent.r, panel.bar.urgent.g,
                panel.bar.urgent.b, 0.14) : Commons.Color.background
              : "transparent"

            Row {
              anchors.fill: parent
              anchors.leftMargin: Commons.Style.space(6)
              anchors.rightMargin: Commons.Style.space(6)
              spacing: Commons.Style.space(7)

              Presentation.IconText {
                anchors.verticalCenter: parent.verticalCenter
                text: sourceRow.modelData && sourceRow.modelData.isPlaying
                  ? "pause" : "play_arrow"
                color: sourceRow.selected && panel.bar
                  ? panel.bar.urgent : panel.bar
                    ? panel.bar.foreground : Commons.Color.foreground
                font.pixelSize: Commons.Style.font.icon
                fill: sourceRow.selected ? 1 : 0
              }

              Column {
                width: parent.width - Commons.Style.space(30)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                  width: parent.width
                  text: sourceRow.modelData
                    ? String(sourceRow.modelData.trackTitle
                      || sourceRow.modelData.identity || "Media source")
                    : "Media source"
                  color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
                  font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                  font.pixelSize: Commons.Style.font.bodySmall
                  font.weight: sourceRow.selected ? Font.Medium : Font.Normal
                  elide: Text.ElideRight
                  renderType: Text.NativeRendering
                }

                Text {
                  width: parent.width
                  visible: text !== ""
                  text: sourceRow.modelData
                    ? String(sourceRow.modelData.trackArtist
                      || sourceRow.modelData.identity || "") : ""
                  color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
                    panel.bar.foreground.g, panel.bar.foreground.b, 0.52)
                    : Commons.Color.foreground
                  font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                  font.pixelSize: Commons.Style.font.caption
                  elide: Text.ElideRight
                  renderType: Text.NativeRendering
                }
              }
            }

            MouseArea {
              id: sourceMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                panel.focusSection = "sources"
                panel.cursorIndex = sourceRow.index
              }
              onClicked: panel.selectSource(sourceRow.index)
            }
          }
        }
      }
    }
  }

  // Panel-local Muse-style mark, sampled by the panel's shared clock.
  component PanelVinyl: Item {
    id: vinyl
    required property color tint
    required property string artSource
    required property bool spinning
    property int revolutionMs: 6000
    readonly property bool rotating: visible && spinning && panel.motionRunning

    function advance(milliseconds) {
      if (rotating) rotation = (rotation + milliseconds * 360 / revolutionMs) % 360
    }

    onSpinningChanged: if (spinning) rotation = 0

    Canvas {
      anchors.fill: parent
      antialiasing: true
      property color canvasTint: vinyl.tint
      onCanvasTintChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
      onPaint: {
        const ctx = getContext("2d"), radius = Math.min(width, height) * 0.46
        ctx.clearRect(0, 0, width, height)
        ctx.save()
        ctx.translate(width / 2, height / 2)
        ctx.strokeStyle = canvasTint
        ctx.lineWidth = Math.max(1, radius * 0.045)
        ctx.beginPath(); ctx.arc(0, 0, radius, 0, Math.PI * 2); ctx.stroke()
        ctx.globalAlpha = 0.55
        for (let i = 0; i < 2; i++) {
          ctx.beginPath()
          ctx.arc(0, 0, radius * 0.64, i * Math.PI - 0.35, i * Math.PI + 2.35)
          ctx.stroke()
        }
        ctx.restore()
      }
    }
    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.38
      height: width
      radius: width / 2
      color: Commons.Util.alpha(vinyl.tint, 0.2)
      Image {
        anchors.centerIn: parent
        width: parent.width * 0.66
        height: width
        source: vinyl.artSource
        visible: status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
      }
      Rectangle {
        anchors.centerIn: parent
        width: Commons.Style.space(3)
        height: width
        radius: width / 2
        color: panel.bar ? panel.bar.background : Commons.Color.background
      }
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.renderedSurfaceRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

    Presentation.IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    Presentation.ShibumiPillToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }

  component MediaPanelButton: Rectangle {
    id: button
    required property string icon
    required property string action
    required property int controlIndex
    property bool accent: false
    property bool checked: false
    property string tooltipText: ""
    signal clicked()
    readonly property bool hot: enabled && (buttonMouse.containsMouse || panel.focusSection === "controls" && panel.cursorIndex === controlIndex)
    width: Commons.Style.space(24); height: width; radius: panel.renderedSurfaceRadius; opacity: enabled ? 1 : 0.35
    color: hot ? panel.controlHoverFillColor : checked ? panel.controlActiveFillColor : "transparent"
    border.width: 1; border.color: checked || hot ? panel.controlAccent : panel.controlMutedHigh
    // Same Material glyphs with integer sizes targeting Shuffle's ink.
    // Unhinted native outlines share a vertical ink center at -0.5 em.
    readonly property var glyphSpec: ({
      shuffle: {text: "\ue043", size: 10},
      repeat: {text: "\ue040", size: 10},
      repeat_one: {text: "\ue041", size: 10},
      skip_previous: {text: "\ue045", size: 13},
      play_arrow: {text: "\ue037", size: 15},
      pause: {text: "\ue034", size: 12},
      skip_next: {text: "\ue044", size: 13}
    })[icon] || {text: icon, size: 11}
    TextMetrics {
      id: iconMetrics
      text: button.glyphSpec.text
      font.family: "Material Symbols Rounded"
      font.pixelSize: Math.max(1, Math.round((Commons.Style.font.icon - 2) * button.glyphSpec.size / 11))
      font.hintingPreference: Font.PreferNoHinting
      renderType: Text.NativeRendering
    }
    Text {
      text: iconMetrics.text; font: iconMetrics.font
      color: button.accent || button.checked ? panel.controlAccent : panel.controlForeground
      renderType: Text.NativeRendering
      x: (parent.width - iconMetrics.tightBoundingRect.width) / 2 - iconMetrics.tightBoundingRect.x
      y: (parent.height + font.pixelSize) / 2 - baselineOffset
    }
    MouseArea {
      id: buttonMouse; anchors.fill: parent; enabled: button.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) { panel.focusSection = "controls"; panel.cursorIndex = button.controlIndex }
      onClicked: button.clicked()
    }
    Presentation.ShibumiPillToolTip { panel: panel; visible: button.tooltipText !== "" && buttonMouse.containsMouse; text: button.tooltipText }
    onClicked: panel.controlAction(action)
  }
}
