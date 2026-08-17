pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "services" as Services
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property int activationBaseline: 0
  property int legacyActivationBaseline: 0
  property var clickTargets: []
  readonly property bool canonicalService:
    Quickshell.env("SHIBUMI_TEST_CANONICAL_NETWORK") === "1"
  readonly property var networkService: networkServiceLoader.item
  readonly property var legacyService: legacyServiceLoader.item
  readonly property var destructionService: destructionServiceLoader.item

  function fail(message) {
    console.error("network-scanner-lifecycle-smoke:", message)
    Qt.exit(1)
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
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var shell: null
    property var activePopout: null
    property var clickTargets: root.clickTargets

    function widgetSettings(_group, _module) { return ({}) }
    function registeredWidgetSource(_id) { return "" }
    function registeredWidgetComponent(_id) { return null }
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(_owner) {}
    function releasePopout(_owner) {}
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return false }
  }

  Component {
    id: scannerGatePanel
    Fixtures.NetworkScannerGateTestPanel {}
  }

  Component {
    id: legacyScannerPanel
    Fixtures.NetworkScannerGateTestPanel { scannerRequiresOpened: false }
  }

  QtObject {
    id: destructionObserver
    property bool primaryEnabled: false
    property int trueWrites: 0
    property int falseWrites: 0
    function record(deviceName, enabled) {
      if (deviceName !== "primary") return
      primaryEnabled = enabled === true
      if (enabled === true) trueWrites++
      else falseWrites++
    }
    function reset() {
      primaryEnabled = false
      trueWrites = 0
      falseWrites = 0
    }
  }

  Component {
    id: destructionScannerPanel
    Fixtures.NetworkScannerGateTestPanel {
      scannerObserver: destructionObserver
    }
  }

  Component {
    id: pluginScannerService
    Network.Service { bar: fakeBar; panelComponent: scannerGatePanel }
  }

  Component {
    id: pluginLegacyService
    Network.Service { bar: fakeBar; panelComponent: legacyScannerPanel }
  }

  Component {
    id: canonicalScannerService
    Services.NetworkService { bar: fakeBar; panelComponent: scannerGatePanel }
  }

  Component {
    id: canonicalLegacyService
    Services.NetworkService { bar: fakeBar; panelComponent: legacyScannerPanel }
  }

  Component {
    id: pluginDestructionService
    Network.Service { bar: fakeBar; panelComponent: destructionScannerPanel }
  }

  Component {
    id: canonicalDestructionService
    Services.NetworkService {
      bar: fakeBar
      panelComponent: destructionScannerPanel
    }
  }

  Loader {
    id: networkServiceLoader
    sourceComponent: root.canonicalService
      ? canonicalScannerService : pluginScannerService
  }

  Loader {
    id: legacyServiceLoader
    sourceComponent: root.canonicalService
      ? canonicalLegacyService : pluginLegacyService
  }

  Loader {
    id: destructionServiceLoader
    active: false
    sourceComponent: root.canonicalService
      ? canonicalDestructionService : pluginDestructionService
  }

  Item { id: firstOwner }
  Item { id: secondOwner }
  Item { id: legacyOwner }
  Item { id: destructionOwner }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      const backend = networkService.backend

      if (root.phase === 0) {
        if (!networkService.ready || !legacyService.ready
            || !backend || root.ticks < 2) return
        if (backend.opened || backend.primaryScannerEnabled
            || backend.wifiNetworks.length !== 0
            || legacyService.backend.primaryScannerEnabled
            || legacyService.backend.wifiNetworks.length !== 0)
          return root.fail("hidden backends did not start closed and idle")
        root.legacyActivationBaseline =
          legacyService.backend.primaryActivationCount
        networkService.beginSession(firstOwner)
        legacyService.beginSession(legacyOwner)
        if (legacyService.backend.primaryActivationCount
            !== root.legacyActivationBaseline)
          return root.fail("legacy backend enabled scanning synchronously")
        root.phase = 1
        root.ticks = 0
        return
      }

      if (root.phase === 1) {
        if (backend.primaryActivationCount === 0) {
          if (root.ticks > 30)
            return root.fail("first active session did not acquire Wi-Fi scanning")
          return
        }
        if (legacyService.backend.primaryActivationCount
            <= root.legacyActivationBaseline) {
          if (root.ticks > 30)
            return root.fail("legacy host session did not acquire Wi-Fi scanning")
          return
        }
        if (!backend.primaryScannerEnabled
            || networkService.networks.length !== 1
            || networkService.sessionCount !== 1
            || backend.lastScanRequest !== false
            || !legacyService.backend.primaryScannerEnabled
            || legacyService.networks.length !== 1
            || legacyService.backend.lastScanRequest !== false)
          return root.fail("first scan did not publish the visible network model")
        root.activationBaseline = backend.primaryActivationCount
        if (!networkService.refresh(true))
          return root.fail("explicit rescan was rejected")
        root.phase = 2
        root.ticks = 0
        return
      }

      if (root.phase === 2) {
        if (backend.primaryActivationCount <= root.activationBaseline) {
          if (root.ticks > 30)
            return root.fail("explicit rescan did not cycle the scanner")
          return
        }
        if (backend.lastScanRequest !== false)
          return root.fail("hidden backend received ownership of the scan cycle")
        networkService.beginSession(secondOwner)
        networkService.endSession(firstOwner)
        if (networkService.sessionCount !== 1
            || !backend.primaryScannerEnabled)
          return root.fail("closing one of two sessions released the scanner")
        backend.replaceDevice()
        root.phase = 3
        root.ticks = 0
        return
      }

      if (root.phase === 3) {
        if (backend.secondaryActivationCount === 0) {
          if (root.ticks > 30)
            return root.fail("active-session adapter replacement was not rescanned")
          return
        }
        if (backend.primaryScannerEnabled
            || !backend.secondaryScannerEnabled
            || networkService.networks.length !== 1)
          return root.fail("adapter replacement leaked or lost scanner ownership")
        networkService.endSession(secondOwner)
        if (networkService.sessionCount !== 0
            || backend.secondaryScannerEnabled
            || networkService.scanning)
          return root.fail("final session close did not release scanner state")
        backend.detachDevice()
        networkService.beginSession(firstOwner)
        backend.attachPrimaryDevice()
        root.phase = 4
        root.ticks = 0
        return
      }

      if (root.phase === 4) {
        if (backend.primaryActivationCount <= root.activationBaseline + 1) {
          if (root.ticks > 30)
            return root.fail("late Wi-Fi adapter did not acquire active-session scanning")
          return
        }
        if (!backend.primaryScannerEnabled
            || networkService.networks.length !== 1)
          return root.fail("late adapter scan did not repopulate visible networks")
        networkService.endSession(firstOwner)
        legacyService.endSession(legacyOwner)
        if (backend.primaryScannerEnabled || networkService.sessionCount !== 0
            || legacyService.backend.primaryScannerEnabled
            || legacyService.sessionCount !== 0)
          return root.fail("late-adapter session did not clean up")
        legacyService.beginSession(legacyOwner)
        legacyService.endSession(legacyOwner)
        root.phase = 5
        root.ticks = 0
        return
      }

      if (root.phase === 5) {
        if (root.ticks < 10) return
        if (legacyService.backend.primaryScannerEnabled
            || legacyService.sessionCount !== 0
            || legacyService.scanning)
          return root.fail("immediate legacy open/close re-enabled scanning later")
        destructionObserver.reset()
        destructionServiceLoader.active = true
        root.phase = 6
        root.ticks = 0
        return
      }

      if (root.phase === 6) {
        if (!destructionService || !destructionService.ready) return
        destructionService.beginSession(destructionOwner)
        destructionService.endSession(destructionOwner)
        root.phase = 7
        root.ticks = 0
        return
      }

      if (root.phase === 7) {
        if (root.ticks < 10) return
        if (destructionObserver.primaryEnabled
            || destructionObserver.trueWrites !== 0)
          return root.fail("immediate gated open/close re-enabled scanning later")
        destructionServiceLoader.active = false
        root.phase = 8
        root.ticks = 0
        return
      }

      if (root.phase === 8) {
        if (destructionService !== null) return
        destructionObserver.reset()
        destructionServiceLoader.active = true
        root.phase = 9
        root.ticks = 0
        return
      }

      if (root.phase === 9) {
        if (!destructionService || !destructionService.ready) return
        destructionService.beginSession(destructionOwner)
        destructionServiceLoader.active = false
        root.phase = 10
        root.ticks = 0
        return
      }

      if (root.phase === 10) {
        if (destructionService !== null || root.ticks < 10) return
        if (destructionObserver.primaryEnabled
            || destructionObserver.trueWrites !== 0)
          return root.fail("destruction during scan delay re-enabled scanning")
        destructionObserver.reset()
        destructionServiceLoader.active = true
        root.phase = 11
        root.ticks = 0
        return
      }

      if (root.phase === 11) {
        if (!destructionService || !destructionService.ready) return
        if (destructionService.sessionCount === 0)
          destructionService.beginSession(destructionOwner)
        if (destructionObserver.trueWrites === 0) {
          if (root.ticks > 30)
            return root.fail("destruction fixture never acquired its scanner")
          return
        }
        destructionServiceLoader.active = false
        root.phase = 12
        root.ticks = 0
        return
      }

      if (destructionService !== null || root.ticks < 3) return
      if (destructionObserver.primaryEnabled
          || destructionObserver.falseWrites === 0)
        return root.fail("active service destruction leaked its scanner lease")
      console.log("network scanner lifecycle smoke passed")
      Qt.quit()
    }
  }
}
