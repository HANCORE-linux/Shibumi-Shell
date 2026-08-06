pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "bluetooth" as Bluetooth
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property bool raceOwnedImmediately: false
  property bool guardAdapterDestroyed: false

  function fail(message) {
    console.error("bluetooth-backend-regression:", message)
    Qt.exit(1)
  }

  Item {
    id: fakeBar
    property bool bluetoothOpen: false
    function summonBarWidget(_id) { bluetoothOpen = true; return true }
    function hideBarWidget(_id) { bluetoothOpen = false; return true }
    function isBarWidgetOpen(_id) { return bluetoothOpen }
  }

  Fixtures.BluetoothTestBackend { id: discoveryFixture }

  Bluetooth.Service {
    id: discoveryService
    bar: fakeBar
    backendOverride: discoveryFixture
    discoveryRetryInterval: 50
    discoveryRequestTimeoutInterval: 100
  }

  QtObject {
    id: nativeAdapter
    property bool enabled: true
    property bool discovering: false
  }

  QtObject {
    id: audioDevice
    property string address: "FE:DC:BA:98:76:54"
    property string name: "Shibumi Delayed Audio Device"
    property string deviceName: name
    property bool connected: false
    property bool paired: true
    property bool bonded: true
    property bool trusted: true
    property var adapter: nativeAdapter
  }

  QtObject {
    id: audioSink
    property bool ready: true
    property bool isSink: true
    property bool isStream: false
    property int sinkId: 771
    property int id: sinkId
    property string name: "bluez_output.FE_DC_BA_98_76_54.a2dp-sink"
    property string description: "Shibumi Delayed Audio Device"
    property string nickname: ""
    property string nick: ""
    property var properties: ({
      "api.bluez5.address": "FE:DC:BA:98:76:54"
    })
  }

  QtObject {
    id: commandRunner
    property int count: 0
    property var lastCommand: []
    function run(command) { count++; lastCommand = command }
  }

  QtObject {
    id: audioOutput
    property int count: 0
    property var lastSink: null
    function setDefaultSink(sink) { count++; lastSink = sink }
  }

  QtObject {
    id: destructionAdapter
    property bool enabled: true
    property bool discovering: false
    property int rejectedStops: 0
    property int stopAttempts: 0
    property bool startReplacementOnNextDiscovery: false
    onDiscoveringChanged: {
      if (discovering) {
        if (startReplacementOnNextDiscovery) {
          startReplacementOnNextDiscovery = false
          const replacement = destructibleBackendLoader.item
          if (!replacement)
            return root.fail("old discovery completed before replacement loaded")
          replacement.discoveryDesired = true
          if (!replacement.startDiscovery())
            return root.fail("replacement rejected inherited discovery")
          root.raceOwnedImmediately = replacement.discoveryOwned
        }
        return
      }
      stopAttempts++
      if (rejectedStops > 0) {
        rejectedStops--
        Qt.callLater(function() { destructionAdapter.discovering = true })
      }
    }
  }

  QtObject {
    id: destructionFixture
    property var adapter: destructionAdapter
    property var connectedDevices: []
    property var knownDevices: []
    property var discoveredDevices: []
    property var pendingActions: ({})
    property int delayedTick: 0
    property var delayedRequests: []
    property int delayedStartCount: 0
    function requestDiscovery(target) {
      delayedRequests = delayedRequests.concat([{
        "target": target,
        "dueTick": delayedTick + 6
      }])
      delayedDiscoveryStart.start()
    }
  }

  Timer {
    id: delayedDiscoveryStart
    interval: 20
    repeat: true
    onTriggered: {
      destructionFixture.delayedTick++
      const remaining = []
      const requests = destructionFixture.delayedRequests
      for (let index = 0; index < requests.length; index++) {
        const request = requests[index]
        if (request.dueTick <= destructionFixture.delayedTick) {
          destructionFixture.delayedStartCount++
          if (request.target) request.target.discovering = true
        } else {
          remaining.push(request)
        }
      }
      destructionFixture.delayedRequests = remaining
      if (remaining.length === 0) stop()
    }
  }

  Component {
    id: destructibleBackendComponent
    Bluetooth.BluetoothBackendAdapter {
      backendOverride: destructionFixture
      discoveryDesired: false
      discoveryRequestTimeoutInterval: 200
    }
  }

  Loader {
    id: destructibleBackendLoader
    active: false
    sourceComponent: destructibleBackendComponent
  }

  Component {
    id: destructibleGuardAdapterComponent
    QtObject {
      property bool discovering: false
      Component.onDestruction: root.guardAdapterDestroyed = true
    }
  }

  Loader {
    id: destructibleGuardAdapterLoader
    active: false
    sourceComponent: destructibleGuardAdapterComponent
  }

  Bluetooth.BluetoothBackendAdapter {
    id: audioBackend
    adapterOverride: nativeAdapter
    nativeDevicesOverride: [audioDevice]
    pipewireNodesOverride: [audioSink]
    commandRunnerOverride: commandRunner
    audioOutputOverride: audioOutput
    audioSwitchInterval: 30
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (root.ticks < 3) return

        discoveryFixture.rejectedDiscoveryStarts = 1
        discoveryService.beginSession(root)

        if (!audioBackend.connectDevice(audioDevice)
            || commandRunner.count !== 1)
          return root.fail("isolated connect command boundary")
        // UI pending may expire before the helper's pair+connect sequence.
        audioBackend.nativePendingActions = ({})
        audioDevice.connected = true

        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (root.ticks < 25) return
        if (audioOutput.count !== 1 || audioOutput.lastSink !== audioSink)
          return root.fail("late connection lost its audio intent")
        if (!discoveryService.discovering
            || discoveryFixture.discoveryStartAttempts < 2)
          return root.fail("discovery start rejection was not retried")

        // A scan that disappears while the panel remains open must recover.
        discoveryFixture.fakeAdapter.discovering = false

        audioDevice.connected = false
        if (!audioBackend.connectDevice(audioDevice))
          return root.fail("second isolated connect command")
        audioBackend.nativePendingActions = ({})
        audioDevice.connected = true
        audioDevice.connected = false

        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.ticks < 25) return
        if (!discoveryService.discovering
            || discoveryFixture.discoveryStartAttempts < 3)
          return root.fail("ended discovery was not recovered")
        if (audioOutput.count !== 1)
          return root.fail("disconnected device received a stale audio handoff")

        // Switching to an enabled, idle adapter with an open session must
        // establish a fresh Shibumi-owned discovery lease.
        discoveryFixture.alternateAdapter.discovering = false
        discoveryFixture.selectedAdapter = discoveryFixture.alternateAdapter

        audioDevice.connected = false
        if (!audioBackend.connectDevice(audioDevice))
          return root.fail("third isolated connect command")
        audioBackend.nativePendingActions = ({})
        audioDevice.connected = true
        nativeAdapter.enabled = false

        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.ticks < 25) return
        if (!discoveryService.discovering
            || discoveryFixture.discoveryStartAttempts < 4)
          return root.fail("enabled adapter replacement was not scanned")
        if (audioOutput.count !== 1)
          return root.fail("radio-off allowed a stale audio handoff")

        discoveryService.endSession(root)
        discoveryFixture.rejectedDiscoveryStarts = 1
        discoveryService.beginSession(root)
        discoveryService.endSession(root)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 4) {
        if (root.ticks < 4) return
        if (discoveryService.discovering)
          return root.fail("final session close left discovery running")
        discoveryFixture.alternateAdapter.discovering = true
        root.phase++
        root.ticks = 0
      } else if (root.phase === 5) {
        if (root.ticks < 2) return
        if (!discoveryService.discovering)
          return root.fail("expired discovery request claimed an external scan")
        discoveryFixture.alternateAdapter.discovering = false

        destructionAdapter.rejectedStops = 2
        destructionAdapter.stopAttempts = 0
        destructibleBackendLoader.active = true
        if (!destructibleBackendLoader.item)
          return root.fail("could not instantiate destructible backend")
        destructibleBackendLoader.item.discoveryDesired = true
        if (!destructibleBackendLoader.item.startDiscovery())
          return root.fail("could not start destructible discovery request")
        destructibleBackendLoader.active = false
        root.phase++
        root.ticks = 0
      } else if (root.phase === 6) {
        if (root.ticks < 12) return
        if (destructionFixture.delayedStartCount !== 1)
          return root.fail("delayed discovery start did not complete")
        if (destructionAdapter.discovering)
          return root.fail("destroyed backend left delayed discovery running")
        if (destructionAdapter.stopAttempts !== 3)
          return root.fail("teardown guard did not retry rejected stops: "
                           + destructionAdapter.stopAttempts)

        // Arm a second teardown guard, then replace the backend before that
        // delayed start settles. The replacement must disarm the old guard.
        destructibleBackendLoader.active = true
        if (!destructibleBackendLoader.item)
          return root.fail("could not instantiate second destructible backend")
        destructibleBackendLoader.item.discoveryDesired = true
        if (!destructibleBackendLoader.item.startDiscovery())
          return root.fail("could not start second destructible request")
        destructibleBackendLoader.active = false
        root.phase++
        root.ticks = 0
      } else if (root.phase === 7) {
        if (root.ticks < 1) return
        destructibleBackendLoader.active = true
        root.phase++
        root.ticks = 0
      } else if (root.phase === 8) {
        if (root.ticks < 1) return
        if (!destructibleBackendLoader.item)
          return root.fail("could not instantiate replacement backend")
        destructibleBackendLoader.item.discoveryDesired = true
        if (!destructibleBackendLoader.item.startDiscovery())
          return root.fail("replacement backend could not take discovery ownership")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 9) {
        if (root.ticks < 5) return
        if (destructionFixture.delayedStartCount !== 3
            || !destructionAdapter.discovering
            || !destructibleBackendLoader.item.discoveryOwned)
          return root.fail("replacement backend did not own delayed discovery: starts="
                           + destructionFixture.delayedStartCount
                           + " discovering=" + destructionAdapter.discovering
                           + " owned=" + destructibleBackendLoader.item.discoveryOwned
                           + " desired=" + destructibleBackendLoader.item.discoveryDesired
                           + " sameAdapter="
                           + (destructibleBackendLoader.item.adapter === destructionAdapter)
                           + " requested="
                           + (destructibleBackendLoader.item.discoveryRequestedAdapter !== null))
        destructibleBackendLoader.item.stopDiscovery()
        destructibleBackendLoader.active = false
        if (destructionAdapter.discovering)
          return root.fail("replacement backend did not release discovery")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 10) {
        if (root.ticks < 1) return

        // Complete a third old request immediately before replacement
        // startDiscovery(). Its adapter signal runs before the teardown
        // guard's dynamically connected handler and exposes the exact race.
        destructibleBackendLoader.active = true
        if (!destructibleBackendLoader.item)
          return root.fail("could not instantiate race backend")
        destructibleBackendLoader.item.discoveryDesired = true
        if (!destructibleBackendLoader.item.startDiscovery())
          return root.fail("could not start race discovery request")
        destructibleBackendLoader.active = false
        root.phase++
        root.ticks = 0
      } else if (root.phase === 11) {
        if (root.ticks < 1) return
        destructibleBackendLoader.active = true
        if (!destructibleBackendLoader.item)
          return root.fail("could not instantiate race replacement")
        if (!Bluetooth.BluetoothDiscoveryGuard.isArmed(destructionAdapter))
          return root.fail("teardown guard disappeared before race completion")
        destructionAdapter.startReplacementOnNextDiscovery = true
        root.phase++
        root.ticks = 0
      } else if (root.phase === 12) {
        if (root.ticks < 5) return
        if (destructionFixture.delayedStartCount !== 4
            || destructionAdapter.startReplacementOnNextDiscovery
            || !root.raceOwnedImmediately
            || !destructionAdapter.discovering
            || !destructibleBackendLoader.item.discoveryOwned)
          return root.fail("replacement did not inherit completed old discovery: starts="
                           + destructionFixture.delayedStartCount
                           + " discovering=" + destructionAdapter.discovering
                           + " owned=" + destructibleBackendLoader.item.discoveryOwned
                           + " triggerPending="
                           + destructionAdapter.startReplacementOnNextDiscovery
                           + " immediateOwned=" + root.raceOwnedImmediately
                           + " stopAttempts=" + destructionAdapter.stopAttempts)
        destructibleBackendLoader.item.stopDiscovery()
        destructibleBackendLoader.active = false
        if (destructionAdapter.discovering)
          return root.fail("inherited discovery was not released")
        destructibleGuardAdapterLoader.active = true
        const doomedAdapter = destructibleGuardAdapterLoader.item
        if (!doomedAdapter
            || !Bluetooth.BluetoothDiscoveryGuard.arm(doomedAdapter, 1000))
          return root.fail("could not arm destructible adapter guard")
        if (Bluetooth.BluetoothDiscoveryGuard.guardCount() !== 1)
          return root.fail("destructible adapter guard was not registered")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 13) {
        if (root.ticks < 1) return
        if (!destructibleGuardAdapterLoader.item
            || Bluetooth.BluetoothDiscoveryGuard.guardCount() !== 1)
          return root.fail("destructible adapter guard did not enter retry")
        destructibleGuardAdapterLoader.active = false
        root.phase++
        root.ticks = 0
      } else {
        if (root.ticks < 4) return
        if (!root.guardAdapterDestroyed)
          return root.fail("guard adapter fixture was not destroyed")
        if (Bluetooth.BluetoothDiscoveryGuard.guardCount() !== 0)
          return root.fail("destroyed adapter left its guard registered")
        console.log("bluetooth backend regression passed")
        Qt.quit()
        stop()
      }
    }
  }
}
