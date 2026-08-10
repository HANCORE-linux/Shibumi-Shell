import QtQuick
import Quickshell
import "audio" as Audio
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int phaseTicks: 0
  property real fullWidth: 0
  property int wheelCallsBefore: 0
  property var clickTargets: []

  function fail(message) {
    console.error("audio-plugin-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 35
    property int sizeHorizontal: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: root.clickTargets
    property var shell: null
    property var barWidgetRegistry: null
    property var visualTokens: ({
      pillHeight: 24,
      pillRadius: 12,
      pillPaddingX: 9,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      slotHeight: 28,
      contentGap: 5,
      compactGap: 4,
      labelSize: 12,
      iconSize: 15
    })

    function widgetSettings(group, module) {
      return group === "G6" && module === "omarchy.audio"
        ? ({ testSetting: "retained" }) : ({})
    }
    function registerClickTarget(target) {
      if (root.clickTargets.indexOf(target) < 0)
        root.clickTargets = root.clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      root.clickTargets = root.clickTargets.filter(item => item !== target)
    }
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
  }

  Loader {
    id: audioLoader
    active: true
    sourceComponent: Component {
      Audio.BarWidget {
        bar: fakeBar
        settings: ({ compact: false })
        panelComponent: audioPanelComponent
        popupSource: Qt.resolvedUrl("fixtures/AudioTestView.qml")
      }
    }
  }

  Component {
    id: audioPanelComponent
    Fixtures.AudioTestPanel {}
  }

  Audio.BarWidget {
    id: unavailableAudio
    bar: fakeBar
    panelComponent: null
  }

  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      root.phaseTicks++
      const audio = audioLoader.item
      if (root.phase === 0) {
        if (!audio || !audio.audioReady || root.phaseTicks < 3) return
        if (!audio || !audio.audioReady || audio.volume !== 42 || audio.muted
            || audio.implicitHeight !== 35 || unavailableAudio.visible)
          return root.fail("backend readiness/state/geometry")
        if (audio.compact)
          return root.fail("explicit full presentation resolved compact")
        if (!audio.audioPanel || audio.audioPanel.opacity !== 0
            || audio.audioPanel.settings.testSetting !== "retained"
            || audio.audioPanel.manageIpc
            || audio.audioPanel.opened || audio.audioPanel.openCount !== 0
            || audio.audioPanel.backendKeyboardPanelOpen
            || audio.audioPanel.backendKeyboardPanelVisible
            || audio.childPanelWidget("omarchy.audio") !== audio
            || !audio.ownsPanelWidget(audio)
            || !audio.ownsPanelWidget(audio.audioPanel))
          return root.fail("official panel bridge/routing/settings")
        if (root.clickTargets.length !== 1
            || audio.audioPanel.internalButton.registeredBar === fakeBar)
          return root.fail("duplicate official click target")
        audio.audioPanel.open()
        if (!audio.audioPanel.opened
            || audio.audioPanel.backendKeyboardPanelOpen
            || audio.audioPanel.backendKeyboardPanelVisible)
          return root.fail("hidden official KeyboardPanel became visible")
        audio.audioPanel.close()

        root.fullWidth = audio.implicitWidth
        audio.settings = ({ compact: true })
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 1) {
        if (root.phaseTicks < 3) return
        if (!audio.compact || !audio.horizontalValueVisible)
          return root.fail("V1 compact icon/value setting did not update")
        if (audio.implicitWidth >= root.fullWidth)
          return root.fail("compact presentation did not reduce width: "
            + audio.implicitWidth + " >= " + root.fullWidth)

        audio.interactionTarget.triggerPress(Qt.RightButton)
        if (!audio.muted) return root.fail("right-click mute forwarding")
        root.wheelCallsBefore = audio.audioPanel.outputVolumeChanges
        audio.interactionTarget.wheelMoved(120)
        audio.interactionTarget.wheelMoved(120)
        audio.interactionTarget.wheelMoved(0)
        if (audio.volume !== 52)
          return root.fail("wheel target did not accumulate immediately")
        if (audio.audioPanel.outputVolumeChanges !== root.wheelCallsBefore)
          return root.fail("wheel burst wrote the backend before settling")
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 2) {
        if (root.phaseTicks < 3) return
        if (audio.audioPanel.outputVolumeChanges !== root.wheelCallsBefore + 1
            || Math.abs(audio.audioPanel.outputVolume - 0.52) > 0.001)
          return root.fail("wheel burst was not coalesced into one final write")
        audio.interactionTarget.triggerPress(Qt.LeftButton)
        if (!audio.opened || audio.audioPanel.opened
            || audio.audioPanel.openCount !== 1)
          return root.fail("local mixer lifecycle/official panel isolation")
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 3) {
        if (!audio.panelLoaded || !audio.panelItem) return
        if (fakeBar.activePopout !== audio
            || audio.panelItem.renderedSinkCount !== 3
            || audio.panelItem.renderedSourceCount !== 2
            || audio.panelItem.renderedStreamCount !== 2)
          return root.fail("local mixer model/popout ownership")
        if (audio.panelItem.firstSinkLabel()
              !== "SteelSeries Arctis 7 Chat"
            || audio.panelItem.secondSinkLabel()
              !== "SteelSeries Arctis 7 Game")
          return root.fail("description-first output device labels")
        if (!audio.panelItem.selectSecondSink()
            || audio.audioPanel.defaultSinkChanges !== 1
            || audio.audioPanel.sink.id !== 2)
          return root.fail("output device forwarding")
        if (!audio.panelItem.selectSecondSource()
            || audio.audioPanel.defaultSourceChanges !== 1
            || audio.audioPanel.source.id !== 4)
          return root.fail("input device forwarding")
        if (!audio.panelItem.setFirstStreamVolume(0.75)
            || audio.audioPanel.audioStreams[0].audio.volume !== 0.75)
          return root.fail("stream volume forwarding")
        if (!audio.panelItem.toggleFirstStreamMute()
            || !audio.audioPanel.audioStreams[0].audio.muted)
          return root.fail("stream mute forwarding")
        if (!audio.panelItem.setInputVolume(0.35)
            || audio.audioPanel.inputVolumeChanges !== 1
            || Math.abs(audio.audioPanel.inputVolume - 0.35) > 0.001)
          return root.fail("input volume forwarding")
        if (!audio.panelItem.toggleInputMute() || !audio.audioPanel.inputMuted)
          return root.fail("input mute forwarding fixture")
        audio.close()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 4) {
        if (audio.opened || audio.panelLoaded || fakeBar.activePopout !== null)
          return root.fail("lazy local mixer close")
        audioLoader.active = false
        root.phase++
        root.phaseTicks = 0
      } else {
        if (root.clickTargets.length !== 0 || fakeBar.activePopout !== null)
          return root.fail("destruction cleanup")
        stop()
        console.log("audio plugin smoke passed")
        Qt.quit()
      }
    }
  }
}
