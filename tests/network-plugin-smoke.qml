import QtQuick
import Quickshell
import "network" as Network
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property real fullWidth: 0
  property var clickTargets: []
  property var dynamicNetworkService: null
  property int caseBLastTrafficOwners: -1
  property int caseBLastTrafficEnds: -1

  function fail(message) {
    console.error("network-widget-smoke:", message)
    Qt.exit(1)
  }

  function appearanceSettings(mode) {
    return ({
      displayMode: String(mode), color: "color05", colorMode: "border",
      tone: "background", surfaceOpacity: 0.6
    })
  }

  Fixtures.NetworkTestService { id: sharedNetworkService }
  Fixtures.NetworkTestService { id: replacementNetworkService }
  Fixtures.NetworkTestService { id: unavailableService; ready: false }
  Fixtures.NetworkTestService { id: vanishedCaseAService; kind: "ethernet" }

  Component {
    id: dynamicNetworkServiceComponent

    Fixtures.NetworkTestService {
      kind: "ethernet"
      trafficFailuresRemaining: 1000
    }
  }

  Item {
    id: fakeBar
    visible: false
    width: 0
    height: 0
    property bool vertical: false
    property int barSize: 35
    property int sizeHorizontal: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: root.clickTargets
    property var shell: null
    property var visualTokens: ({
      shellStyle: "shibumi", v2Shell: false, pillHeight: 24,
      pillRadius: 12, pillPaddingX: 9, pill: "#332f2f",
      pillBorder: "#555050", pillBorderWidth: 1, pillShadow: "#000000",
      shadowEnabled: false, slotHeight: 28, contentGap: 5,
      compactGap: 4, labelSize: 12, iconSize: 15,
      ink: fakeBar.foreground, seal: fakeBar.urgent, paper: fakeBar.background,
      widgetHasFill: function(settings) {
        return settings && settings.color === "color05"
      },
      widgetFillColor: function(settings) {
        return settings && settings.color === "color05"
          ? "#cc8844" : "transparent"
      },
      widgetSurfaceOpacity: function(settings) {
        return settings && settings.surfaceOpacity !== undefined
          ? Number(settings.surfaceOpacity) : 1
      },
      widgetContentColor: function(settings, fallback) {
        return settings && settings.color === "color05"
          && settings.tone === "background" ? fakeBar.background : fallback
      }
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
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
  }

  Loader {
    id: firstLoader
    active: true
    sourceComponent: Component {
      Network.BarWidget {
        bar: fakeBar
        settings: root.appearanceSettings("full")
        networkServiceOverride: sharedNetworkService
        popupSource: Qt.resolvedUrl("fixtures/NetworkTestView.qml")
      }
    }
  }

  Loader {
    id: secondLoader
    active: true
    sourceComponent: Component {
      Network.BarWidget {
        bar: fakeBar
        settings: ({ compact: false })
        networkServiceOverride: sharedNetworkService
        popupSource: Qt.resolvedUrl("fixtures/NetworkTestView.qml")
      }
    }
  }

  Network.BarWidget {
    id: unavailableNetwork
    bar: fakeBar
    networkServiceOverride: unavailableService
  }

  Loader {
    id: vanishedCaseALoader
    active: false
    sourceComponent: Component {
      Network.BarWidget {
        bar: fakeBar
        settings: root.appearanceSettings("full")
        networkServiceOverride: vanishedCaseAService
      }
    }
  }

  Loader {
    id: vanishedCaseBLoader
    active: false
    sourceComponent: Component {
      Network.BarWidget {
        bar: fakeBar
        settings: root.appearanceSettings("full")
      }
    }
  }

  Connections {
    target: root.dynamicNetworkService
    ignoreUnknownSignals: true
    function onTrafficConsumerCountChanged() {
      root.caseBLastTrafficOwners = target.trafficConsumerCount
    }
    function onTrafficEndCountChanged() {
      root.caseBLastTrafficEnds = target.trafficEndCount
    }
  }

  Timer {
    interval: 60
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("timed out in phase " + root.phase)
      const first = firstLoader.item
      const second = secondLoader.item
      if ((root.phase < 60 && !first) || (root.phase < 5 && !second)) return

      if (root.phase === 0) {
        if (!first.networkReady || !second.networkReady || root.ticks < 3) return
        if (first.networkService !== second.networkService
            || first.networkService !== sharedNetworkService
            || first.mode !== "wifi" || first.label !== "Test Network"
            || first.signal !== 73 || first.implicitHeight !== 35
            || !first.v1CustomToneActive || second.v1CustomToneActive
            || !Qt.colorEqual(first.v1Ink, fakeBar.background)
            || !Qt.colorEqual(first.v1Seal, fakeBar.background)
            || unavailableNetwork.visible
            || first.childPanelWidget("omarchy.network") !== first
            || first.childPanelWidget("hancore.shibumi.network") !== first
            || !first.ownsPanelWidget(first)
            || root.clickTargets.length !== 2
            || sharedNetworkService.sessionCount !== 0
            || sharedNetworkService.trafficConsumerCount !== 0
            || "wiredConnected" in sharedNetworkService)
          return root.fail("shared native facade readiness/state/geometry")
        root.fullWidth = first.implicitWidth
        sharedNetworkService.label =
          "Fixture Wi-Fi network with a deliberately long SSID"
        first.settings = root.appearanceSettings("text")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (root.ticks < 3) return
        if (first.v2Presentation || first.displayMode !== "text"
            || first.implicitWidth <= 0 || first.implicitWidth > 160)
          return root.fail("V1 bounded text presentation")
        const tokens = Object.assign({}, fakeBar.visualTokens, {
          v2Shell: true, shellStyle: "full"
        })
        fakeBar.visualTokens = tokens
        first.settings = root.appearanceSettings("icon")
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (root.ticks < 3) return
        if (!first.v2Presentation || !first.compact
            || first.implicitWidth >= root.fullWidth)
          return root.fail("V2 compact presentation")
        first.interactionTarget.triggerPress(Qt.LeftButton)
        second.open()
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (root.ticks < 3) return
        if (!first.opened || !second.opened || !first.panelLoaded
            || !second.panelLoaded || sharedNetworkService.sessionCount !== 2
            || sharedNetworkService.beginCount !== 2
            || sharedNetworkService.viewLoadCount !== 2)
          return root.fail("two-output local panel sessions")
        replacementNetworkService.beginFailuresRemaining = 1
        first.networkServiceOverride = replacementNetworkService
        root.phase = 30
        root.ticks = 0
        return
      }

      if (root.phase === 30) {
        if (root.ticks < 8) return
        if (first.sessionService !== replacementNetworkService
            || replacementNetworkService.sessionCount !== 1
            || replacementNetworkService.beginCount !== 1
            || sharedNetworkService.sessionCount !== 1
            || !first.panelLoaded)
          return root.fail("open panel did not retry replacement leases")
        first.networkServiceOverride = sharedNetworkService
        root.phase = 31
        root.ticks = 0
        return
      }

      if (root.phase === 31) {
        if (root.ticks < 3) return
        if (first.sessionService !== sharedNetworkService
            || sharedNetworkService.sessionCount !== 2
            || replacementNetworkService.sessionCount !== 0
            || replacementNetworkService.endCount !== 1)
          return root.fail("open panel retained the replaced service")
        sharedNetworkService.speedTestReady = false
        sharedNetworkService.ready = false
        if (!first.openNetworkPresentation("speed"))
          return root.fail("cold speed presentation was rejected")
        root.phase = 32
        root.ticks = 0
        return
      }

      if (root.phase === 32) {
        if (root.ticks < 4) return
        if (first.pendingPresentationMode !== "speed"
            || sharedNetworkService.speedRunCount !== 0
            || first.panelLoaded)
          return root.fail("cold speed request was dropped before service readiness")
        sharedNetworkService.ready = true
        root.phase = 320
        root.ticks = 0
        return
      }

      if (root.phase === 320) {
        if (root.ticks < 4) return
        if (first.pendingPresentationMode !== "speed"
            || sharedNetworkService.speedRunCount !== 0
            || !first.panelItem || first.panelItem.speedDetailsVisible !== true)
          return root.fail("cold speed request was dropped before worker readiness")
        sharedNetworkService.speedTestReady = true
        root.phase = 33
        root.ticks = 0
        return
      }

      if (root.phase === 33) {
        if (root.ticks < 3) return
        if (first.pendingPresentationMode !== ""
            || sharedNetworkService.speedRunCount !== 1
            || sharedNetworkService.speedTestRunning !== true)
          return root.fail("ready speed owner did not consume pending IPC")
        sharedNetworkService.speedTestRunning = false
        first.interactionTarget.triggerPress(Qt.RightButton)
        if (!sharedNetworkService.lastScanWifi
            || sharedNetworkService.refreshCount !== 1)
          return root.fail("right-click scanner request")
        sharedNetworkService.trafficFailuresRemaining = 1
        sharedNetworkService.kind = "ethernet"
        sharedNetworkService.label = "enp1s0"
        sharedNetworkService.downloadRate = 1536
        sharedNetworkService.uploadRate = 2 * 1024 * 1024
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (root.ticks < 7) return
        if (first.mode !== "ethernet" || second.label !== "enp1s0"
            || second.displayLabel !== "Ethernet"
            || second.compactRate(second.downloadRate) !== "1.5K"
            || second.compactRate(second.uploadRate) !== "2.0M"
            || sharedNetworkService.trafficConsumerCount !== 2
            || sharedNetworkService.trafficBeginCount !== 2)
          return root.fail("shared Ethernet telemetry leases")
        first.close()
        secondLoader.active = false
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (root.ticks < 3) return
        if (sharedNetworkService.sessionCount !== 0
            || sharedNetworkService.endCount !== 5
            || sharedNetworkService.trafficConsumerCount !== 1
            || sharedNetworkService.trafficEndCount !== 1
            || first.panelLoaded || root.clickTargets.length !== 1)
          return root.fail("panel and destroyed-bar lease cleanup: "
            + JSON.stringify({ sessions: sharedNetworkService.sessionCount,
              ends: sharedNetworkService.endCount,
              traffic: sharedNetworkService.trafficConsumerCount,
              trafficEnds: sharedNetworkService.trafficEndCount,
              loaded: first.panelLoaded, clicks: root.clickTargets.length }))
        sharedNetworkService.kind = "wifi"
        sharedNetworkService.label = "Test Network"
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (root.ticks < 3) return
        if (sharedNetworkService.trafficConsumerCount !== 0
            || sharedNetworkService.trafficEndCount !== 2)
          return root.fail("Ethernet telemetry final release")
        firstLoader.active = false
        root.phase = 60
        root.ticks = 0
        return
      }

      if (root.phase === 60) {
        if (root.ticks < 2) return
        if (root.clickTargets.length !== 0)
          return root.fail("click target destruction cleanup")
        vanishedCaseALoader.active = true
        root.phase = 61
        root.ticks = 0
        return
      }

      if (root.phase === 61) {
        const caseA = vanishedCaseALoader.item
        if (!caseA || !caseA.networkReady
            || caseA.trafficService !== vanishedCaseAService
            || vanishedCaseAService.trafficConsumerCount !== 1) return
        if (vanishedCaseAService.trafficBeginCount !== 1
            || vanishedCaseAService.trafficEndCount !== 0)
          return root.fail("vanished service setup did not acquire one consumer")
        caseA.networkServiceOverride = null
        root.phase = 62
        root.ticks = 0
        return
      }

      if (root.phase === 62) {
        if (root.ticks < 2) return
        const caseA = vanishedCaseALoader.item
        if (!caseA || caseA.networkService !== null || caseA.networkReady
            || caseA.trafficService !== null
            || vanishedCaseAService.trafficConsumerCount !== 0
            || vanishedCaseAService.trafficBeginCount !== 1
            || vanishedCaseAService.trafficEndCount !== 1)
          return root.fail("vanished service did not release its consumer")
        console.log("network vanished-service release regression passed")
        vanishedCaseALoader.active = false
        vanishedCaseBLoader.active = true
        root.phase = 70
        root.ticks = 0
        return
      }

      if (root.phase === 70) {
        const caseB = vanishedCaseBLoader.item
        if (!caseB) return
        root.dynamicNetworkService = dynamicNetworkServiceComponent.createObject(root)
        if (!root.dynamicNetworkService)
          return root.fail("dynamic network service creation")
        root.caseBLastTrafficOwners = root.dynamicNetworkService.trafficConsumerCount
        root.caseBLastTrafficEnds = root.dynamicNetworkService.trafficEndCount
        caseB.networkServiceOverride = root.dynamicNetworkService
        root.phase = 71
        root.ticks = 0
        return
      }

      if (root.phase === 71) {
        const caseB = vanishedCaseBLoader.item
        const dynamicService = root.dynamicNetworkService
        if (!caseB || !dynamicService || !caseB.networkReady
            || dynamicService.trafficFailuresRemaining === 1000) return
        if (caseB.networkService !== dynamicService
            || caseB.trafficService !== null
            || dynamicService.trafficFailuresRemaining <= 0
            || dynamicService.trafficConsumerCount !== 0
            || dynamicService.trafficBeginCount !== 0
            || dynamicService.trafficEndCount !== 0)
          return root.fail("failed traffic acquire unexpectedly retained a lease")
        dynamicService.destroy()
        root.phase = 72
        root.ticks = 0
        return
      }

      if (root.phase === 72) {
        if (root.ticks < 7) return
        const caseB = vanishedCaseBLoader.item
        if (!caseB || root.dynamicNetworkService !== null
            || caseB.networkService !== null || caseB.networkReady
            || caseB.mode !== "none" || caseB.trafficService !== null
            || root.caseBLastTrafficOwners !== 0
            || root.caseBLastTrafficEnds !== 0)
          return root.fail("destroyed failed-acquire service was not cleared")
        console.log("network failed-acquire destruction regression passed")
        vanishedCaseBLoader.active = false
        console.log("network plugin smoke passed")
        Qt.quit()
        stop()
      }
    }
  }
}
