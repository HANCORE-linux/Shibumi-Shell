import QtQuick
import Quickshell
import "services" as Services
import "widgets" as Widgets
import "adapters" as Adapters
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int phaseTicks: 0
  property real fullWidth: 0
  property var clickTargets: []
  property int summonCount: 0
  property bool radioBeforeToggle: false
  property bool discoveryBeforeToggle: false

  function fail(message) {
    console.error("bluetooth-widget-smoke:", message)
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
    property var activePopout: null
    property var clickTargets: root.clickTargets
    property var shell: null
    property var barWidgetRegistry: null
    property var bluetoothService: sharedBluetoothService
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

    function registeredWidgetSource(_id) { return "" }
    function registeredWidgetComponent(_id) { return null }
    function widgetSettings(group, module) {
      return group === "G15" && module === "omarchy.bluetooth"
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
    function summonBarWidget(id) {
      if (id !== "omarchy.bluetooth") return false
      root.summonCount++
      return true
    }
  }

  Fixtures.BluetoothTestBackend {
    id: testBackend
  }

  QtObject {
    id: nativePendingDevice
    property string address: "FE:DC:BA:98:76:54"
    property string name: "Shibumi Pending Test Device"
    property string deviceName: name
    property bool connected: false
    property bool paired: true
    property bool bonded: true
    property bool trusted: true
  }

  Adapters.BluetoothBackendAdapter {
    id: nativeSignalAdapter
    nativeDevicesOverride: [nativePendingDevice]
  }

  Services.BluetoothService {
    id: sharedBluetoothService
    bar: fakeBar
    backendOverride: testBackend
  }

  QtObject {
    id: unavailableService
    property bool ready: false
    property bool adapterAvailable: false
    property bool radioEnabled: false
    property int connectedCount: 0
  }

  Loader {
    id: firstLoader
    active: true
    sourceComponent: Component {
      Widgets.BluetoothWidget {
        bar: fakeBar
        settings: ({ compact: false })
        bluetoothServiceOverride: sharedBluetoothService
        popupSource: Qt.resolvedUrl("fixtures/BluetoothTestView.qml")
      }
    }
  }

  Loader {
    id: secondLoader
    active: true
    sourceComponent: Component {
      Widgets.BluetoothWidget {
        bar: fakeBar
        settings: ({ compact: false })
        bluetoothServiceOverride: sharedBluetoothService
        popupSource: Qt.resolvedUrl("fixtures/BluetoothTestView.qml")
      }
    }
  }

  Widgets.BluetoothWidget {
    id: unavailableBluetooth
    bar: fakeBar
    bluetoothServiceOverride: unavailableService
  }

  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      root.phaseTicks++
      const first = firstLoader.item
      const second = secondLoader.item
      const backend = sharedBluetoothService.backend

      if (root.phase === 0) {
        if (!first || !second || !backend || !sharedBluetoothService.ready
            || root.phaseTicks < 3) return
        if (first.bluetoothService !== second.bluetoothService
            || first.bluetoothService !== sharedBluetoothService
            || !first.adapterAvailable || !first.radioEnabled
            || first.connectedCount !== 1 || first.implicitHeight !== 35
            || unavailableBluetooth.visible)
          return root.fail("shared backend readiness/state/geometry")
        if (backend !== testBackend)
          return root.fail("native adapter fixture boundary")
        if (first.childPanelWidget("omarchy.bluetooth") !== first
            || second.childPanelWidget("omarchy.bluetooth") !== second
            || !first.ownsPanelWidget(first))
          return root.fail("screen-local alias routing")
        if (root.clickTargets.length !== 2 || sharedBluetoothService.sessionCount !== 0)
          return root.fail("duplicate target or closed lifecycle")

        nativeSignalAdapter.setNativePendingAction(
          nativePendingDevice.address, "connecting")
        nativePendingDevice.connected = true

        root.fullWidth = first.implicitWidth
        first.settings = ({ compact: true })
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 1) {
        if (root.phaseTicks < 3) return
        if (!first.compact || first.implicitWidth >= root.fullWidth)
          return root.fail("compact presentation width")
        if (!first.showConnectedCount || first.connectedCount !== 1)
          return root.fail("connected count hidden in compact presentation")
        if (nativeSignalAdapter.pendingAction(nativePendingDevice.address) !== "")
          return root.fail("native connect transition did not clear pending state")

        nativeSignalAdapter.setNativePendingAction(
          nativePendingDevice.address, "disconnecting")
        nativePendingDevice.connected = false

        root.radioBeforeToggle = sharedBluetoothService.radioEnabled
        root.discoveryBeforeToggle = sharedBluetoothService.discovering
        first.toggleBluetooth()
        first.toggleBluetooth()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 2) {
        if (root.phaseTicks < 4) return
        if (backend.toggleCount !== 2
            || first.radioEnabled !== root.radioBeforeToggle
            || sharedBluetoothService.discovering !== root.discoveryBeforeToggle)
          return root.fail("radio/discovery rollback after toggle round trip")
        if (nativeSignalAdapter.pendingAction(nativePendingDevice.address) !== "")
          return root.fail("native disconnect transition did not clear pending state")

        nativeSignalAdapter.setNativePendingAction(
          nativePendingDevice.address, "forgetting")
        nativePendingDevice.paired = false
        nativePendingDevice.bonded = false
        nativePendingDevice.trusted = false

        backend.fakeAdapter.discovering = true
        sharedBluetoothService.beginSession(root)
        sharedBluetoothService.restartDiscovery()
        sharedBluetoothService.endSession(root)

        sharedBluetoothService.openPanel()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 3) {
        if (root.phaseTicks < 2) return
        if (nativeSignalAdapter.pendingAction(nativePendingDevice.address) !== "")
          return root.fail("native forget transition did not clear pending state")
        if (!sharedBluetoothService.discovering)
          return root.fail("external discovery refresh was claimed or stopped")
        backend.fakeAdapter.discovering = root.discoveryBeforeToggle

        first.interactionTarget.triggerPress(Qt.MiddleButton)
        if (root.summonCount !== 1
            || backend.toggleCount !== 2 || !first.radioEnabled || !first.opened)
          return root.fail("service IPC route, radio, or panel forwarding")

        second.open()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 4) {
        if (root.phaseTicks < 3) return
        if (!first.opened || !second.opened || !first.panelLoaded
            || !second.panelLoaded || sharedBluetoothService.sessionCount !== 2
            || backend.viewLoadCount !== 2 || !sharedBluetoothService.discovering
            || fakeBar.activePopout !== second)
          return root.fail("two-output local panel sessions")

        sharedBluetoothService.connectDevice(backend.knownDevices[0])
        sharedBluetoothService.disconnectDevice(backend.connectedDevices[0])
        sharedBluetoothService.forgetDevice(backend.knownDevices[0])
        if (backend.connectCount !== 1 || backend.disconnectCount !== 1
            || backend.forgetCount !== 1
            || sharedBluetoothService.pendingAction("66:77:88:99:AA:BB") !== "forgetting")
          return root.fail("backend device action forwarding")

        sharedBluetoothService.restartDiscovery()
        first.close()
        secondLoader.active = false
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 5) {
        if (root.phaseTicks < 3) return
        if (sharedBluetoothService.sessionCount !== 0
            || sharedBluetoothService.discovering || first.panelLoaded
            || root.clickTargets.length !== 1 || fakeBar.activePopout !== null)
          return root.fail("discovery, session, or local panel teardown")

        backend.selectedAdapter = backend.fakeAdapter
        backend.fakeAdapter.discovering = false
        sharedBluetoothService.beginSession(root)
        backend.alternateAdapter.discovering = true
        backend.selectedAdapter = backend.alternateAdapter
        sharedBluetoothService.endSession(root)
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 6) {
        if (root.phaseTicks < 2) return
        if (backend.fakeAdapter.discovering
            || !backend.alternateAdapter.discovering
            || sharedBluetoothService.sessionCount !== 0)
          return root.fail("adapter replacement discovery ownership")

        backend.selectedAdapter = backend.fakeAdapter
        backend.alternateAdapter.discovering = false
        backend.adapterPresent = false
        root.phase++
        root.phaseTicks = 0
      } else {
        if (root.phaseTicks < 2) return
        if (first.visible) return root.fail("missing-adapter fallback visibility")
        firstLoader.active = false
        Qt.callLater(function() {
          if (root.clickTargets.length !== 0)
            return root.fail("click target destruction cleanup")
          console.log("bluetooth widget smoke passed")
          Qt.quit()
        })
        stop()
      }
    }
  }
}
