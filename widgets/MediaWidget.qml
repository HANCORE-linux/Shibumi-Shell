pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.media"
  manageIpc: false
  property url panelSource: Qt.resolvedUrl("MediaPanel.qml")
  readonly property var mediaService: bar && bar.shell
    && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var spectrumService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.media") : null
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property bool active: mediaService
    ? mediaService.hasMedia === true && activePlayer !== null : false
  readonly property bool playing: active && activePlayer.isPlaying === true
  readonly property string title: activePlayer ? String(activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? String(activePlayer.trackArtist || "") : ""
  readonly property string trackLabel: title && artist
    ? title + "  ·  " + artist : title || artist
  readonly property string tooltipText: active
    ? (artist ? artist + " — " + title : title) : "No active media player"
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property bool fullMode: setting("compact", false) === true
  readonly property bool spectrumEnabled: setting("spectrum", true) !== false
  readonly property bool spectrumRequested: visible && active && fullMode
    && (!bar || !bar.vertical)
  readonly property var museLevels: spectrumService && spectrumService.levels
    ? spectrumService.levels : []
  readonly property string spectrumState: spectrumService
    ? String(spectrumService.state || "inactive") : "unavailable"
  property var leasedSpectrumService: null
  readonly property bool panelLoaded: panelLoader.item !== null
  readonly property var panelItem: panelLoader.item
  readonly property var interactionTarget: actionButton
  readonly property var museInteractionTarget: museMouse
  readonly property bool museVisible: muse.visible
  readonly property int museBandCount: muse.renderedBandCount

  visible: mediaService !== null
  implicitWidth: visible ? (bar && bar.vertical
    ? bar.barSize : mediaSurface.implicitWidth) : 0
  implicitHeight: visible ? (bar && bar.vertical
    ? mediaSurface.implicitHeight : bar ? bar.barSize : 28) : 0

  function runAction(action) {
    return mediaService && typeof mediaService.runAction === "function"
      ? mediaService.runAction(String(action || ""), false) === true : false
  }

  function runMusePrimaryAction() {
    return runAction("playPause")
  }

  function runMuseWheel(delta) {
    if (Number(delta) === 0) return false
    return runAction(Number(delta) > 0 ? "next" : "previous")
  }

  function syncSpectrumLease() {
    const next = spectrumRequested ? spectrumService : null
    if (leasedSpectrumService === next) return
    if (leasedSpectrumService
        && typeof leasedSpectrumService.endSpectrum === "function")
      leasedSpectrumService.endSpectrum(root)
    leasedSpectrumService = next
    if (leasedSpectrumService
        && typeof leasedSpectrumService.beginSpectrum === "function")
      leasedSpectrumService.beginSpectrum(root)
  }

  function releaseSpectrumLease() {
    if (leasedSpectrumService
        && typeof leasedSpectrumService.endSpectrum === "function")
      leasedSpectrumService.endSpectrum(root)
    leasedSpectrumService = null
  }

  function syncPanelLoader() {
    if (!opened) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(panelSource, {
      anchorItem: mediaSurface,
      bar: root.bar,
      ownerWidget: root,
      mediaService: root.mediaService,
      spectrumService: root.spectrumService,
      spectrumEnabled: root.spectrumEnabled
    })
  }

  onOpenedChanged: syncPanelLoader()
  onSpectrumRequestedChanged: syncSpectrumLease()
  onSpectrumServiceChanged: syncSpectrumLease()
  Component.onCompleted: syncSpectrumLease()
  Component.onDestruction: releaseSpectrumLease()

  Item {
    id: mediaSurface
    anchors.centerIn: parent
    implicitWidth: !root.tokens ? 0 : root.bar && root.bar.vertical
      ? root.bar.barSize
      : (root.active
          ? (root.fullMode ? muse.implicitWidth : activeRow.implicitWidth)
          : idleIcon.implicitWidth)
        + 2 * root.tokens.pillPaddingX
    implicitHeight: root.bar && root.bar.vertical
      ? Commons.Style.space(34) : root.tokens ? root.tokens.slotHeight : 28
    width: implicitWidth
    height: implicitHeight

    PillSurface {
      anchors.fill: parent
      anchors.topMargin: root.tokens
        ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
      anchors.bottomMargin: root.tokens
        ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
      bar: root.bar
    }

    // This is the one registered surface used by KeyboardPanel's bar-click
    // forwarding. Transport controls above it retain their dedicated actions.
    Ui.WidgetButton {
      id: actionButton
      anchors.fill: parent
      bar: root.mediaService ? root.bar : null
      text: " "
      keepSpace: true
      horizontalMargin: 0
      verticalPadding: 0
      fixedWidth: mediaSurface.width
      fixedHeight: mediaSurface.height
      tooltipText: root.tooltipText
      onPressed: function(button) {
        if (button === Qt.RightButton || !root.active) root.toggle()
        else if (button === Qt.MiddleButton) root.runAction("next")
        else root.runAction("playPause")
      }
      onWheelMoved: function(delta) {
        root.runAction(delta > 0 ? "previous" : "next")
      }
    }

    IconText {
      id: idleIcon
      anchors.centerIn: parent
      visible: !root.active
      text: "music_note"
      color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, 0.45) : Commons.Color.foreground
      font.pixelSize: 15
      fill: 0
    }

    Row {
      id: activeRow
      visible: root.active && !root.fullMode
        && (!root.bar || !root.bar.vertical)
      anchors.centerIn: parent
      spacing: root.tokens ? root.tokens.compactGap : Commons.Style.space(4)

      MediaControl {
        icon: "skip_previous"
        enabled: root.activePlayer && root.activePlayer.canGoPrevious === true
        action: "previous"
      }

      MediaControl {
        icon: root.playing ? "pause" : "play_arrow"
        enabled: root.activePlayer && (root.activePlayer.canTogglePlaying === true
          || root.activePlayer.canPlay === true || root.activePlayer.canPause === true)
        action: "playPause"
        accent: true
      }

      MediaControl {
        icon: "skip_next"
        enabled: root.activePlayer && root.activePlayer.canGoNext === true
        action: "next"
      }

      Item {
        id: marqueeMask
        width: Commons.Style.space(88)
        height: mediaSurface.height
        visible: false
        layer.enabled: true

        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "white" }
            GradientStop { position: 0.92; color: "white" }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
      }

      Item {
        id: marqueeClip
        width: Commons.Style.space(88)
        height: mediaSurface.height
        anchors.verticalCenter: parent.verticalCenter
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: marqueeMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.5
        }

        function reset() {
          marqueeAnimation.stop()
          marqueeText.x = 0
          Qt.callLater(function() {
            if (root.visible && root.playing && !root.opened
                && marqueeText.implicitWidth > marqueeClip.width)
              marqueeAnimation.start()
          })
        }

        Text {
          id: marqueeText
          anchors.verticalCenter: parent.verticalCenter
          text: root.trackLabel
          color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
            root.bar.foreground.b, root.playing ? 0.85 : 0.42)
            : Commons.Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: root.tokens ? root.tokens.labelSize : Commons.Style.font.body
          renderType: Text.NativeRendering
          onTextChanged: marqueeClip.reset()
        }

        Connections {
          target: root
          function onPlayingChanged() { marqueeClip.reset() }
          function onOpenedChanged() { marqueeClip.reset() }
          function onVisibleChanged() { marqueeClip.reset() }
        }

        SequentialAnimation {
          id: marqueeAnimation
          loops: Animation.Infinite
          PauseAnimation { duration: 2000 }
          NumberAnimation {
            target: marqueeText
            property: "x"
            to: -(marqueeText.implicitWidth - marqueeClip.width + 4)
            duration: Math.max(100,
              marqueeText.implicitWidth - marqueeClip.width + 4) * 20
            easing.type: Easing.Linear
          }
          PauseAnimation { duration: 900 }
          PropertyAction { target: marqueeText; property: "x"; value: 0 }
        }
      }

      MediaPulse {
        anchors.verticalCenter: parent.verticalCenter
        playing: root.playing
        tint: root.bar ? root.bar.urgent : Commons.Color.accent
      }
    }

    MediaMuse {
      id: muse
      visible: root.active && root.fullMode
        && (!root.bar || !root.bar.vertical)
      anchors.centerIn: parent
      levels: root.museLevels
      playing: root.playing
      tint: root.bar ? root.bar.urgent : Commons.Color.accent

      MouseArea {
        id: museMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.runMusePrimaryAction()
        onWheel: function(wheel) {
          if (wheel.angleDelta.y === 0) return
          root.runMuseWheel(wheel.angleDelta.y)
          wheel.accepted = true
        }
      }
    }

    Column {
      visible: root.active && root.bar && root.bar.vertical
      anchors.centerIn: parent
      spacing: Commons.Style.space(2)

      IconText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.playing ? "pause" : "play_arrow"
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.pixelSize: root.tokens ? root.tokens.iconSize : Commons.Style.font.body
        fill: 1
      }

      MediaPulse {
        anchors.horizontalCenter: parent.horizontalCenter
        playing: root.playing
        tint: root.bar ? root.bar.urgent : Commons.Color.accent
        scale: 0.75
      }
    }
  }

  Loader { id: panelLoader }

  component MediaControl: Item {
    required property string icon
    required property string action
    property bool accent: false

    implicitWidth: Commons.Style.space(18)
    implicitHeight: mediaSurface.height
    opacity: enabled ? 1 : 0.28

    IconText {
      anchors.centerIn: parent
      text: parent.icon
      color: parent.accent && root.bar
        ? root.bar.urgent : root.bar ? root.bar.foreground : Commons.Color.foreground
      font.pixelSize: 13
      fill: parent.accent ? 1 : 0
    }

    MouseArea {
      anchors.fill: parent
      enabled: parent.enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.runAction(parent.action)
    }
  }
}
