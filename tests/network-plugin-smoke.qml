import QtQuick
import Quickshell
import "network" as Network
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int phaseTicks: 0
  property int speedPhase: 0
  property int speedFailureTicks: 0
  property int destructionTicks: 0
  property bool restartContractPassed: false
  property bool speedContractPassed: false
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
    speedTestPhaseDuration: 120
  }

  Item { id: currentSpeedOwner }

  Network.Service {
    id: currentService
    bar: fakeBar
    panelComponent: currentNetworkPanelComponent
    speedTestPhaseDuration: 120
    Component.onCompleted: beginSession(currentSpeedOwner)
  }

  Network.Service {
    id: failingSpeedService
    bar: fakeBar
    panelComponent: currentNetworkPanelComponent
    speedTestExecutable: "omarchy-network-speedtest-fail"
  }

  Network.Service {
    id: emptySpeedService
    bar: fakeBar
    panelComponent: currentNetworkPanelComponent
    speedTestExecutable: "omarchy-network-speedtest-empty"
  }

  Network.Service {
    id: missingSpeedService
    bar: fakeBar
    panelComponent: currentNetworkPanelComponent
    speedTestExecutable: "shibumi-definitely-missing-speedtest"
  }

  Network.Service {
    id: malformedSpeedService
    bar: fakeBar
    panelComponent: currentNetworkPanelComponent
    speedTestExecutable: "omarchy-network-speedtest-malformed"
  }

  Network.Service {
    id: resistantSpeedService
    bar: fakeBar
    panelComponent: currentNetworkPanelComponent
    speedTestExecutable: "omarchy-network-speedtest-resistant"
    speedTestPhaseDuration: 10000
  }

  Loader {
    id: immediateDestructionLoader
    active: false
    sourceComponent: Component {
      Network.Service {
        bar: fakeBar
        panelComponent: currentNetworkPanelComponent
        speedTestPhaseDuration: 10000
      }
    }
  }

  Loader {
    id: destructionSpeedLoader
    active: true
    sourceComponent: Component {
      Network.Service {
        bar: fakeBar
        panelComponent: currentNetworkPanelComponent
        speedTestPhaseDuration: 10000
      }
    }
  }

  Timer {
    interval: 20
    repeat: true
    running: !root.speedContractPassed
    onTriggered: {
      if (root.speedPhase === 0) {
        if (!extractedService.ready || !currentService.ready) return
        if (!extractedService.speedTestReady || !currentService.speedTestReady
            || !extractedService.runSpeedTest()
            || extractedService.runSpeedTest()
            || !extractedService.speedTestRunning
            || extractedService.speedTestPhase !== "down"
            || extractedService.backend.speedTestRunCount !== 0
            || !currentService.runSpeedTest()
            || !currentService.speedTestRunning
            || currentService.speedTestPhase !== "down")
          return root.fail("Shibumi-owned speed-test startup")
        currentService.endSession(currentSpeedOwner)
        if (currentService.sessionCount !== 0
            || currentService.speedTestRunning
            || currentService.speedTestPhase !== "")
          return root.fail("Shibumi-owned speed-test final-session cleanup")
        currentService.beginSession(currentSpeedOwner)
        if (!currentService.runSpeedTest()
            || !currentService.speedTestPendingRun
            || !currentService.speedTestRunning)
          return root.fail("immediate close/reopen speed-test queue")
        root.speedPhase = 1
        return
      }

      if (!root.restartContractPassed
          && !currentService.speedTestRunning
          && !currentService.speedTestPendingRun) {
        if (currentService.speedTestPhase !== ""
            || currentService.speedTestDownloadMbps !== "42.5"
            || currentService.speedTestUploadMbps !== "17.25"
            || currentService.speedTestError !== "")
          return root.fail("queued close/reopen speed-test completion")
        currentService.endSession(currentSpeedOwner)
        root.restartContractPassed = true
      }

      if (root.speedPhase === 1) {
        if (extractedService.speedTestPhase === "down") {
          if (extractedService.speedTestDownloadMbps === "") return
          if (extractedService.speedTestDownloadMbps !== "42.5")
            return root.fail("inline speed-test download sample")
          return
        }
        if (extractedService.speedTestPhase !== "up"
            || !extractedService.speedTestRunning
            || extractedService.speedTestDownloadMbps !== "42.5")
          return root.fail("inline speed-test phase transition")
        root.speedPhase = 2
        return
      }

      if (root.speedPhase === 2) {
        if (extractedService.speedTestRunning) {
          if (extractedService.speedTestPhase !== "up")
            return root.fail("inline speed-test upload phase")
          return
        }
        if (extractedService.speedTestPhase !== ""
            || extractedService.speedTestDownloadMbps !== "42.5"
            || extractedService.speedTestUploadMbps !== "17.25"
            || extractedService.speedTestError !== ""
            || extractedService.backend.speedTestRunCount !== 0
            || extractedService.formatSpeed("107") !== "107 Mbps"
            || extractedService.formatSpeed("9.25") !== "9.3 Mbps"
            || extractedService.formatSpeed("") !== "—")
          return root.fail("inline speed-test completion and formatting")
        if (!failingSpeedService.ready || !failingSpeedService.runSpeedTest())
          return root.fail("inline speed-test failure startup")
        root.speedPhase = 3
        return
      }

      if (root.speedPhase === 3) {
        root.speedFailureTicks++
        if (failingSpeedService.speedTestRunning) return
        if (failingSpeedService.speedTestError === "Speed test failed"
            && root.speedFailureTicks < 20) return
        if (failingSpeedService.speedTestPhase !== ""
            || failingSpeedService.speedTestDownloadMbps !== ""
            || failingSpeedService.speedTestUploadMbps !== ""
            || failingSpeedService.speedTestError !== "fixture speed failure")
          return root.fail("inline speed-test failure reporting")
        if (!emptySpeedService.ready || !emptySpeedService.runSpeedTest())
          return root.fail("empty inline speed-test startup")
        root.speedPhase = 4
        return
      }

      if (root.speedPhase === 4) {
        if (emptySpeedService.speedTestRunning) return
        if (emptySpeedService.speedTestPhase !== ""
            || emptySpeedService.speedTestError
              !== "Speed test produced no download data")
          return root.fail("empty inline speed-test rejection")
        if (!missingSpeedService.ready || !missingSpeedService.runSpeedTest())
          return root.fail("missing inline speed-test startup")
        root.speedPhase = 5
        return
      }

      if (root.speedPhase === 5) {
        if (missingSpeedService.speedTestRunning) return
        if (missingSpeedService.speedTestPhase !== ""
            || missingSpeedService.speedTestError.indexOf(
              "Unable to start network speed test") < 0)
          return root.fail("missing inline speed-test executable reporting")
        if (!malformedSpeedService.ready
            || !malformedSpeedService.runSpeedTest())
          return root.fail("malformed inline speed-test startup")
        root.speedPhase = 6
        return
      }

      if (root.speedPhase === 6) {
        if (malformedSpeedService.speedTestRunning) return
        if (malformedSpeedService.speedTestDownloadMbps !== ""
            || malformedSpeedService.speedTestError
              !== "Speed test produced no download data")
          return root.fail("malformed inline speed-test rejection")
        if (!resistantSpeedService.ready
            || !resistantSpeedService.runSpeedTest())
          return root.fail("resistant inline speed-test startup")
        root.speedPhase = 7
        return
      }

      if (root.speedPhase === 7) {
        if (resistantSpeedService.speedTestDownloadMbps === "") return
        resistantSpeedService.stopSpeedTest()
        immediateDestructionLoader.active = true
        root.speedPhase = 8
        return
      }

      if (root.speedPhase === 8) {
        const immediateService = immediateDestructionLoader.item
        if (!immediateService || !immediateService.ready) return
        if (!immediateService.runSpeedTest())
          return root.fail("immediate destruction speed-test startup")
        immediateDestructionLoader.active = false
        const destructionService = destructionSpeedLoader.item
        if (!destructionService || !destructionService.ready
            || !destructionService.runSpeedTest())
          return root.fail("destruction speed-test startup")
        root.speedPhase = 9
        return
      }

      if (root.speedPhase === 9) {
        const destructionService = destructionSpeedLoader.item
        if (!destructionService || !destructionService.speedTestRunning) return
        if (destructionService.speedTestDownloadMbps === "") return
        destructionSpeedLoader.active = false
        root.speedPhase = 10
        return
      }

      if (root.speedPhase === 10) {
        root.destructionTicks++
        if (immediateDestructionLoader.item !== null
            || destructionSpeedLoader.item !== null)
          return root.fail("active speed-test service survived Loader teardown")
        if (root.destructionTicks < 140 || !root.restartContractPassed) return
        root.speedContractPassed = true
      }
    }
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
            || root.phaseTicks < 3 || !root.speedContractPassed) return
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
