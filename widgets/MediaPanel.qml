pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var mediaService
  property var spectrumService: null
  property bool spectrumEnabled: true
  property string focusSection: "controls"
  property int cursorIndex: 1
  property real currentPosition: 0
  property real currentLength: 0
  property real lastReportedPosition: -1
  property var leasedSpectrumService: null

  readonly property var player: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService && mediaService.sourcePlayers
    ? mediaService.sourcePlayers : []
  readonly property bool active: mediaService
    ? mediaService.hasMedia === true && player !== null : false
  readonly property bool playing: active && player.isPlaying === true
  readonly property bool spectrumRequested: open && active && spectrumEnabled
  readonly property var levels: spectrumService && spectrumService.levels
    ? spectrumService.levels : flatLevels(active ? 0.04 : 0.02)
  readonly property var spectrumThemeColors: spectrumService
    && spectrumService.themeColors ? spectrumService.themeColors : []
  readonly property int renderedSourceCount: sourceRepeater.count
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

  function selectSource(index) {
    if (index < 0 || index >= sourcePlayers.length || !mediaService
        || typeof mediaService.selectPlayer !== "function") return false
    return mediaService.selectPlayer(playerKey(sourcePlayers[index])) === true
  }

  function activateCursor() {
    if (focusSection === "sources") return selectSource(cursorIndex)
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
        cursorIndex = Math.max(0, Math.min(2, cursorIndex + dx))
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
    if (!player) return
    const reported = Number(player.position || 0)
    currentLength = Math.max(0, Number(player.length || 0))
    if (Math.abs(reported - lastReportedPosition) > 0.05) {
      currentPosition = reported
      lastReportedPosition = reported
    } else if (playing) {
      const cap = currentLength > 0 ? currentLength : reported + 1e9
      currentPosition = Math.min(cap, currentPosition + 0.5)
    }
  }

  function resetPosition() {
    currentPosition = player ? Number(player.position || 0) : 0
    currentLength = player ? Math.max(0, Number(player.length || 0)) : 0
    lastReportedPosition = -1
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
  onPlayingChanged: {
    lastReportedPosition = -1
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

  property Timer positionTimer: Timer {
    interval: 500
    repeat: true
    running: panel.open && panel.active
    triggeredOnStart: true
    onTriggered: panel.syncPosition()
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

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "NOW PLAYING"
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.body
          font.letterSpacing: 2
          font.weight: Font.Medium
          renderType: Text.NativeRendering
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(8)

          Text {
            visible: panel.active && panel.playerName !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: panel.playerName
            color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
              panel.bar.foreground.g, panel.bar.foreground.b, 0.45)
              : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            renderType: Text.NativeRendering
          }

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

        Rectangle {
          width: Commons.Style.space(56)
          height: width
          radius: Commons.Style.space(5)
          color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
            panel.bar.foreground.g, panel.bar.foreground.b, 0.10)
            : Commons.Color.background
          clip: true

          Image {
            anchors.fill: parent
            source: panel.player ? String(panel.player.trackArtUrl || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            retainWhileLoading: true
          }

          IconText {
            anchors.centerIn: parent
            visible: !panel.player || !panel.player.trackArtUrl
            text: "music_note"
            color: panel.bar ? panel.bar.urgent : Commons.Color.accent
            font.pixelSize: Commons.Style.font.displayLarge
            fill: 1
          }
        }

        Column {
          width: parent.width - Commons.Style.space(66)
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
        }
      }

      Item {
        width: parent.width
        height: Commons.Style.space(18)
        visible: panel.active && panel.currentLength > 0

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
            Behavior on width { NumberAnimation { duration: 450 } }
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

        MediaSpectrum {
          anchors.fill: parent
          visible: panel.active
          levels: panel.levels
          tint: panel.bar ? panel.bar.urgent : Commons.Color.accent
          themeColors: panel.spectrumThemeColors
          opacity: panel.playing ? 1 : 0.5
        }

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
        spacing: Commons.Style.space(12)

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
      }

      Ui.PanelSeparator {
        visible: panel.sourcePlayers.length > 1
        foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
      }

      Column {
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
            radius: panel.controlRadius
            color: cursor || sourceMouse.containsMouse
              ? panel.bar ? Qt.rgba(panel.bar.urgent.r, panel.bar.urgent.g,
                panel.bar.urgent.b, 0.14) : Commons.Color.background
              : "transparent"

            Row {
              anchors.fill: parent
              anchors.leftMargin: Commons.Style.space(6)
              anchors.rightMargin: Commons.Style.space(6)
              spacing: Commons.Style.space(7)

              IconText {
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

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

    IconText {
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

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }

  component MediaPanelButton: Ui.PanelActionButton {
    required property string icon
    required property string action
    required property int controlIndex
    property bool accent: false

    iconText: icon
    foreground: accent && panel.bar
      ? panel.bar.urgent : panel.bar ? panel.bar.foreground : Commons.Color.foreground
    hoverColor: panel.bar ? panel.bar.urgent : Commons.Color.accent
    fontFamily: "Material Symbols Rounded"
    fontSize: accent ? Commons.Style.font.iconLarge : Commons.Style.font.icon
    size: accent ? Commons.Style.space(34) : Commons.Style.space(28)
    radius: panel.controlRadius
    hasCursor: panel.focusSection === "controls" && panel.cursorIndex === controlIndex
    onHovered: function(isHovered) {
      if (isHovered) {
        panel.focusSection = "controls"
        panel.cursorIndex = controlIndex
      }
    }
    onClicked: panel.runAction(action)
  }
}
