import QtQuick
import Quickshell
import "widgets" as Widgets
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int phaseTicks: 0
  property real fullWidth: 0
  property var clickTargets: []

  function fail(message) {
    console.error("network-widget-smoke:", message)
    Qt.exit(1)
  }

  Fixtures.NetworkTestService { id: sharedNetworkService }
  Fixtures.NetworkTestService { id: unavailableService; ready: false }

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
    property var networkService: sharedNetworkService
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
    id: firstLoader
    active: true
    sourceComponent: Component {
      Widgets.NetworkWidget {
        bar: fakeBar
        settings: ({ compact: false })
        networkServiceOverride: sharedNetworkService
        popupSource: Qt.resolvedUrl("fixtures/NetworkTestView.qml")
      }
    }
  }

  Loader {
    id: secondLoader
    active: true
    sourceComponent: Component {
      Widgets.NetworkWidget {
        bar: fakeBar
        settings: ({ compact: false })
        networkServiceOverride: sharedNetworkService
        popupSource: Qt.resolvedUrl("fixtures/NetworkTestView.qml")
      }
    }
  }

  Widgets.NetworkWidget {
    id: unavailableNetwork
    bar: fakeBar
    networkServiceOverride: unavailableService
  }

  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      root.phaseTicks++
      const first = firstLoader.item
      const second = secondLoader.item
      if (root.phase === 0) {
        if (!first || !second || !first.networkReady || !second.networkReady
            || root.phaseTicks < 3) return
        if (first.networkService !== second.networkService
            || first.networkService !== sharedNetworkService
            || first.mode !== "wifi" || first.label !== "Test Network"
            || first.signal !== 73 || first.implicitHeight !== 35
            || unavailableNetwork.visible)
          return root.fail("shared backend readiness/state/geometry")
        if (first.childPanelWidget("omarchy.network") !== first
            || !first.ownsPanelWidget(first)
            || second.childPanelWidget("omarchy.network") !== second)
          return root.fail("screen-local alias routing")
        if (root.clickTargets.length !== 2 || sharedNetworkService.sessionCount !== 0)
          return root.fail("visible click targets or closed lifecycle")

        root.fullWidth = first.implicitWidth
        first.settings = ({ compact: true })
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 1) {
        if (root.phaseTicks < 3) return
        if (!first.compact || first.implicitWidth >= root.fullWidth)
          return root.fail("compact presentation width")

        first.interactionTarget.triggerPress(Qt.LeftButton)
        second.open()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 2) {
        if (root.phaseTicks < 3) return
        if (!first.opened || !second.opened || !first.panelLoaded
            || !second.panelLoaded || sharedNetworkService.sessionCount !== 2
            || sharedNetworkService.beginCount !== 2
            || sharedNetworkService.viewLoadCount !== 2)
          return root.fail("two-output local panel sessions")

        first.interactionTarget.triggerPress(Qt.RightButton)
        if (!first.opened || !sharedNetworkService.lastScanWifi
            || sharedNetworkService.refreshCount !== 1)
          return root.fail("right-click scan forwarding")

        sharedNetworkService.kind = "ethernet"
        sharedNetworkService.label = "enp1s0"
        sharedNetworkService.downloadRate = 1536
        sharedNetworkService.uploadRate = 2 * 1024 * 1024
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 3) {
        if (root.phaseTicks < 2) return
        if (first.mode !== "ethernet" || second.label !== "enp1s0"
            || second.displayLabel !== "Ethernet"
            || !second.v1TrafficPresentation || second.v2TrafficPresentation
            || second.compactRate(second.downloadRate) !== "1.5K"
            || second.compactRate(second.uploadRate) !== "2.0M"
            || first.tooltipText.indexOf("Ethernet") !== 0)
          return root.fail("shared reactive ethernet state")
        const v2Tokens = ({})
        for (const key in fakeBar.visualTokens)
          v2Tokens[key] = fakeBar.visualTokens[key]
        v2Tokens.v2Shell = true
        fakeBar.visualTokens = v2Tokens
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 4) {
        if (root.phaseTicks < 2) return
        if (second.v1TrafficPresentation || !second.v2TrafficPresentation)
          return root.fail("V2 ethernet traffic presentation")
        first.close()
        secondLoader.active = false
        root.phase++
        root.phaseTicks = 0
      } else {
        if (sharedNetworkService.sessionCount !== 0
            || sharedNetworkService.endCount !== 2
            || first.panelLoaded || root.clickTargets.length !== 1)
          return root.fail("session and loader teardown")
        firstLoader.active = false
        Qt.callLater(function() {
          if (root.clickTargets.length !== 0)
            return root.fail("click target destruction cleanup")
          console.log("network widget smoke passed")
          Qt.quit()
        })
        stop()
      }
    }
  }
}
