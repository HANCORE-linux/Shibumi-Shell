import QtQuick
import Quickshell
import "network" as Network
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

  function appearanceSettings(mode) {
    return ({
      displayMode: String(mode),
      color: "color05",
      colorMode: "border",
      tone: "background",
      surfaceOpacity: 0.6
    })
  }

  Fixtures.NetworkTestService { id: sharedNetworkService }
  Fixtures.NetworkTestService { id: unavailableService; ready: false }

  Component {
    id: networkPanelComponent
    Fixtures.NetworkTestPanel {}
  }

  Component {
    id: currentNetworkPanelComponent
    Fixtures.NetworkCurrentTestPanel {}
  }

  Component {
    id: speedTestPanelComponent
    Fixtures.NetworkSpeedTestPanel {}
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
    property var networkService: sharedNetworkService
    property var visualTokens: ({
      shellStyle: "shibumi",
      v2Shell: false,
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
      iconSize: 15,
      ink: fakeBar.foreground,
      seal: fakeBar.urgent,
      paper: fakeBar.background,
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

    function registeredWidgetSource(_id) { return "" }
    function registeredWidgetComponent(_id) { return null }
    function widgetSettings(_group, _module) { return ({}) }
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

  Network.Service {
    id: extractedService
    bar: fakeBar
    panelComponent: networkPanelComponent
  }

  Item { id: currentSpeedOwner }

  Network.Service {
    id: currentService
    bar: fakeBar
    panelComponent: currentNetworkPanelComponent
    speedTestPanelComponent: speedTestPanelComponent
    Component.onCompleted: beginSession(currentSpeedOwner)
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
            || !extractedService.ready || !currentService.ready
            || !currentService.speedTestReady
            || extractedService.kind !== "wifi"
            || extractedService.label !== "Fixture Network"
            || first.mode !== "wifi" || first.label !== "Test Network"
            || first.signal !== 73 || first.implicitHeight !== 35
            || !first.v1CustomToneActive || second.v1CustomToneActive
            || !Qt.colorEqual(first.v1Ink, fakeBar.background)
            || !Qt.colorEqual(first.v1Seal, fakeBar.background)
            || !Qt.colorEqual(first.v1Indigo, fakeBar.background)
            || unavailableNetwork.visible)
          return root.fail("shared backend readiness/state/geometry")
        if (first.childPanelWidget("omarchy.network") !== first
            || !first.ownsPanelWidget(first)
            || second.childPanelWidget("omarchy.network") !== second)
          return root.fail("screen-local alias routing")
        if (root.clickTargets.length !== 2 || sharedNetworkService.sessionCount !== 0)
          return root.fail("visible click targets or closed lifecycle")
        const enterpriseEntry = {
          network: ({}),
          securityKind: "enterprise",
          ssid: "Fixture Enterprise"
        }
        if (!extractedService.connectEnterprise(
              enterpriseEntry, "user@example.test", "test-secret")
            || extractedService.backend.enterpriseConnectCount !== 1
            || extractedService.backend.enterpriseSsid !== "Fixture Enterprise"
            || extractedService.backend.enterpriseIdentity !== "user@example.test"
            || extractedService.backend.enterprisePassphrase !== "test-secret"
            || extractedService.connectEnterprise(enterpriseEntry, "", "test-secret")
            || extractedService.connectEnterprise(enterpriseEntry, "user@example.test", ""))
          return root.fail("enterprise credential forwarding and validation")
        if (!extractedService.runSpeedTest()
            || extractedService.backend.speedTestRunCount !== 1
            || !extractedService.speedTestRunning
            || extractedService.formatSpeed("107") !== "107 Mbps"
            || extractedService.formatSpeed("9.25") !== "9.3 Mbps"
            || extractedService.formatSpeed("") !== "—")
          return root.fail("speed test forwarding and inline Mbps formatting")
        extractedService.backend.speedTestRunning = false
        if (currentService.legacySpeedTestBackend
            || !currentService.runSpeedTest()
            || currentService.speedTestBackend.runCount !== 1
            || !currentService.speedTestRunning
            || currentService.speedTestPhase !== "down"
            || currentService.speedTestDownloadMbps !== "42.5")
          return root.fail("standalone speed-test adapter contract")
        const currentSpeedBackend = currentService.speedTestBackend
        currentService.endSession(currentSpeedOwner)
        if (currentSpeedBackend.closeCount !== 1
            || currentService.sessionCount !== 0)
          return root.fail("standalone speed-test adapter cleanup")

        root.fullWidth = first.implicitWidth
        sharedNetworkService.label = "Fixture Wi-Fi network with a deliberately long SSID"
        first.settings = root.appearanceSettings("text")
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 1) {
        if (root.phaseTicks < 3) return
        if (first.v2Presentation || first.displayMode !== "text"
            || first.implicitWidth <= 0 || first.implicitWidth > 160)
          return root.fail("V1 Wi-Fi bounded text presentation")
        const textV2Tokens = ({})
        for (const key in fakeBar.visualTokens)
          textV2Tokens[key] = fakeBar.visualTokens[key]
        textV2Tokens.v2Shell = true
        textV2Tokens.shellStyle = "full"
        fakeBar.visualTokens = textV2Tokens
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 2) {
        if (root.phaseTicks < 3) return
        if (!first.v2Presentation || first.displayMode !== "text"
            || first.implicitWidth <= 0 || first.implicitWidth > 160)
          return root.fail("V2 Wi-Fi bounded text presentation")
        first.settings = root.appearanceSettings("icon")
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 3) {
        if (root.phaseTicks < 3) return
        if (!first.v2Presentation || !first.compact
            || first.implicitWidth >= root.fullWidth)
          return root.fail("V2 compact presentation width")
        const compactV1Tokens = ({})
        for (const key in fakeBar.visualTokens)
          compactV1Tokens[key] = fakeBar.visualTokens[key]
        compactV1Tokens.v2Shell = false
        compactV1Tokens.shellStyle = "shibumi"
        fakeBar.visualTokens = compactV1Tokens
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 4) {
        if (root.phaseTicks < 3) return
        if (first.v2Presentation || !first.compact
            || first.implicitWidth >= root.fullWidth
            || !first.v1CustomToneActive
            || !Qt.colorEqual(first.v1Seal, fakeBar.background))
          return root.fail("V1 compact presentation width/tone")

        first.interactionTarget.triggerPress(Qt.LeftButton)
        second.open()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 5) {
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

        first.settings = root.appearanceSettings("full")
        const wifiV2Tokens = ({})
        for (const key in fakeBar.visualTokens)
          wifiV2Tokens[key] = fakeBar.visualTokens[key]
        wifiV2Tokens.v2Shell = true
        wifiV2Tokens.shellStyle = "full"
        fakeBar.visualTokens = wifiV2Tokens
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 6) {
        if (root.phaseTicks < 3) return
        if (!first.v2Presentation || first.mode !== "wifi"
            || first.displayMode !== "full"
            || first.implicitWidth <= 0 || first.implicitWidth > 140)
          return root.fail("V2 Wi-Fi bounded full presentation")
        const ethernetV1Tokens = ({})
        for (const key in fakeBar.visualTokens)
          ethernetV1Tokens[key] = fakeBar.visualTokens[key]
        ethernetV1Tokens.v2Shell = false
        ethernetV1Tokens.shellStyle = "shibumi"
        fakeBar.visualTokens = ethernetV1Tokens
        sharedNetworkService.kind = "ethernet"
        sharedNetworkService.label = "enp1s0"
        sharedNetworkService.downloadRate = 1536
        sharedNetworkService.uploadRate = 2 * 1024 * 1024
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 7) {
        if (root.phaseTicks < 2) return
        if (first.mode !== "ethernet" || second.label !== "enp1s0"
            || second.displayLabel !== "Ethernet"
            || !second.v1TrafficPresentation || second.v2TrafficPresentation
            || second.compactRate(second.downloadRate) !== "1.5K"
            || second.compactRate(second.uploadRate) !== "2.0M"
            || first.tooltipText.indexOf("Ethernet") !== 0)
          return root.fail("shared reactive ethernet state")
        const ethernetV2Tokens = ({})
        for (const key in fakeBar.visualTokens)
          ethernetV2Tokens[key] = fakeBar.visualTokens[key]
        ethernetV2Tokens.v2Shell = true
        ethernetV2Tokens.shellStyle = "full"
        fakeBar.visualTokens = ethernetV2Tokens
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 8) {
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
          console.log("network plugin smoke passed")
          Qt.quit()
        })
        stop()
      }
    }
  }
}
