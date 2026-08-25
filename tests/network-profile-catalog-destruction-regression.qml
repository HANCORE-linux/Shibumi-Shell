pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-profile-catalog-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string counterPath:
    Qt.resolvedUrl("fixtures/network-profile-catalog-resistant")
      .toString().replace(/^file:\/\//, "")

  function fail(message) {
    console.error("network-profile-catalog-destruction-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: liveness
    property bool serviceUsable: true
    property real generation: 1
  }

  Item { id: owner }

  Component {
    id: resistantComponent
    Network.NetworkProfileCatalog {
      active: true
      nativeLiveness: liveness
      commandOverride: [
        "/usr/bin/python3", root.fixturePath, "resistant", root.counterPath
      ]
      drainTimeoutMs: 100
      refreshTimeoutMs: 5000
      Component.onCompleted: acquire(owner)
    }
  }

  Component {
    id: replacementComponent
    Network.NetworkProfileCatalog {
      active: true
      nativeLiveness: liveness
      commandOverride: [
        "/usr/bin/python3", root.fixturePath, "normal", root.counterPath
      ]
    }
  }

  Loader { id: resistantLoader; sourceComponent: resistantComponent }
  Loader { id: replacementLoader; active: false; sourceComponent: replacementComponent }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 100)
        return root.fail("timed out in phase " + root.phase)
      if (root.phase === 0) {
        const catalog = resistantLoader.item
        if (!catalog || !catalog.authorized || !catalog.workerRunning
            || !catalog.workerOutputComplete) return
        resistantLoader.active = false
        replacementLoader.active = true
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        const replacement = replacementLoader.item
        if (!replacement || root.ticks < 12) return
        if (replacement.authorized || replacement.workerRunning)
          return root.fail("replacement overlapped a destroyed catalog worker")
        console.log("network profile catalog destruction regression passed")
        Qt.exit(0)
      }
    }
  }
}
