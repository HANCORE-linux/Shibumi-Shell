pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "bluetooth" as Bluetooth

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property int adapterSerial: 0
  property int destroyedAdapters: 0
  property bool sessionOpen: false

  function fail(message) {
    console.error("bluetooth-adapter-hotplug-regression:", message)
    Qt.exit(1)
  }

  Component {
    id: adapterComponent
    QtObject {
      property int serial: root.adapterSerial
      property bool enabled: true
      property bool discovering: false
      Component.onDestruction: root.destroyedAdapters++
    }
  }

  Loader {
    id: adapterLoader
    active: false
    sourceComponent: adapterComponent
  }

  QtObject {
    id: fixture
    property bool adapterPresent: true
    property var adapter: adapterPresent ? adapterLoader.item : null
    property var connectedDevices: []
    property var knownDevices: []
    property var discoveredDevices: []
    property var pendingActions: ({})
    property int delayedTick: 0
    property var delayedRequests: []
    property int discoveryStartAttempts: 0
    property int appliedStarts: 0
    property int droppedStarts: 0

    function requestDiscovery(target) {
      discoveryStartAttempts++
      delayedRequests = delayedRequests.concat([{
        "target": target,
        "dueTick": delayedTick + 8
      }])
      delayedStart.start()
    }
  }

  Timer {
    id: delayedStart
    interval: 20
    repeat: true
    onTriggered: {
      fixture.delayedTick++
      const remaining = []
      const requests = fixture.delayedRequests
      for (let index = 0; index < requests.length; index++) {
        const request = requests[index]
        if (request.dueTick <= fixture.delayedTick) {
          // A native Quickshell adapter owns its D-Bus watcher. Once the
          // adapter is removed, that old completion cannot target a later
          // adapter object even if this fixture still holds a JS wrapper.
          if (request.target && request.target === fixture.adapter) {
            fixture.appliedStarts++
            request.target.discovering = true
          } else {
            fixture.droppedStarts++
          }
        } else {
          remaining.push(request)
        }
      }
      fixture.delayedRequests = remaining
      if (remaining.length === 0) stop()
    }
  }

  Bluetooth.BluetoothBackendAdapter {
    id: backend
    backendOverride: fixture
    discoveryDesired: root.sessionOpen
    discoveryRequestTimeoutInterval: 300
  }

  // This is the same bounded reconciliation predicate used by Service.qml,
  // kept local so the test can inspect the adapter's ownership fields.
  Timer {
    interval: 50
    repeat: true
    triggeredOnStart: true
    running: root.sessionOpen && backend.adapterAvailable
      && backend.radioEnabled && !backend.discovering
    onTriggered: backend.startDiscovery()
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.ticks++

      if (root.phase === 0) {
        if (root.ticks < 2) return
        root.adapterSerial = 1
        adapterLoader.active = true
        root.sessionOpen = true
        if (!adapterLoader.item || !backend.startDiscovery())
          return root.fail("could not start the pending Discovery session")
        if (fixture.discoveryStartAttempts !== 1 || backend.discovering
            || backend.discoveryRequestedAdapter !== adapterLoader.item)
          return root.fail("initial Discovery request did not remain pending")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (root.ticks < 1) return
        if (!adapterLoader.item || fixture.delayedRequests.length !== 1)
          return root.fail("pending Discovery request settled before unplug")
        fixture.adapterPresent = false
        if (backend.adapterAvailable || backend.discoveryRequestedAdapter !== null
            || backend.retiredDiscoveryAdapter !== adapterLoader.item
            || backend.discoveryOwned || backend.discoveryOwnerAdapter !== null)
          return root.fail("onAdapterChanged did not retire pending Discovery")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.ticks < 1) return
        adapterLoader.active = false
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.ticks < 5) return
        if (root.destroyedAdapters !== 1 || backend.adapterAvailable
            || fixture.appliedStarts !== 0 || fixture.droppedStarts !== 1
            || backend.discoveryRequestedAdapter !== null
            || backend.retiredDiscoveryAdapter !== null
            || Bluetooth.BluetoothDiscoveryGuard.guardCount() !== 0)
          return root.fail("unplug did not retire the pending adapter safely: destroyed="
                           + root.destroyedAdapters
                           + " available=" + backend.adapterAvailable
                           + " applied=" + fixture.appliedStarts
                           + " dropped=" + fixture.droppedStarts
                           + " guards="
                           + Bluetooth.BluetoothDiscoveryGuard.guardCount())

        root.adapterSerial = 2
        adapterLoader.active = true
        fixture.adapterPresent = true
        root.phase++
        root.ticks = 0
      } else if (root.phase === 4) {
        if (root.ticks < 7) return
        const replacement = adapterLoader.item
        if (!replacement || replacement.serial !== 2
            || fixture.discoveryStartAttempts !== 2
            || fixture.appliedStarts !== 1 || fixture.droppedStarts !== 1
            || !replacement.discovering || !backend.discovering
            || !backend.discoveryOwned
            || backend.discoveryOwnerAdapter !== replacement
            || backend.discoveryRequestedAdapter !== null)
          return root.fail("replug did not establish a fresh Discovery lease: attempts="
                           + fixture.discoveryStartAttempts
                           + " applied=" + fixture.appliedStarts
                           + " dropped=" + fixture.droppedStarts
                           + " backendDiscovering=" + backend.discovering)
        root.sessionOpen = false
        backend.stopDiscovery()
        root.phase++
        root.ticks = 0
      } else {
        if (root.ticks < 4) return
        if (root.sessionOpen || backend.discovering || backend.discoveryOwned
            || backend.discoveryOwnerAdapter !== null
            || adapterLoader.item.discovering
            || fixture.delayedRequests.length !== 0
            || Bluetooth.BluetoothDiscoveryGuard.guardCount() !== 0)
          return root.fail("replug Discovery lease did not settle cleanly")
        console.log("bluetooth adapter hotplug regression passed")
        Qt.quit()
        stop()
      }
    }
  }
}
