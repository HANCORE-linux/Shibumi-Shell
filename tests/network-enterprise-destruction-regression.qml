pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property string entityId:
    'shibumi-network-v1:["network",["device","Corp","wpa2-eap"]]'
  property string deviceId:
    'shibumi-network-v1:["device",["wifi","AA","wlan0"]]'
  property string fixturePath:
    Qt.resolvedUrl("fixtures/network-enterprise-fixture.py")
      .toString().replace(/^file:\/\//, "")
  property string capturePath:
    Qt.resolvedUrl("fixtures/network-enterprise-destruction.json")
      .toString().replace(/^file:\/\//, "")

  function fail(message) {
    console.error("network-enterprise-destruction-regression:", message)
    Qt.exit(1)
  }

  QtObject {
    id: adapter
    property real generation: 7
    function enterpriseConnectionDescriptor(request) {
      return {
        ok: true, code: "accepted", message: "",
        entityId: request.entityId, generation: request.generation,
        descriptor: {
          deviceId: root.deviceId, entityId: root.entityId, generation: 7,
          hardwareAddress: "02:00:00:00:00:01",
          interfaceName: "wlan0", security: "wpa2-eap",
          ssidHex: "436F7270"
        }
      }
    }
  }

  Component {
    id: dispatcherComponent
    Network.NetworkEnterpriseDispatcher {
      active: true
      networkAdapter: adapter
      commandOverride: [
        "/usr/bin/python3", root.fixturePath, root.capturePath, "slow"
      ]
      workerTimeoutMs: 10000
      drainTimeoutMs: 200
    }
  }

  Loader {
    id: primaryLoader
    active: true
    sourceComponent: dispatcherComponent
  }
  Loader {
    id: replacementLoader
    active: false
    sourceComponent: dispatcherComponent
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 180)
        return root.fail("destruction lifecycle timed out in phase " + root.phase)
      const primary = primaryLoader.item
      const replacement = replacementLoader.item
      if (root.phase === 0) {
        if (!primary || !primary.authorized || !primary.available) return
        const result = primary.connectNetworkEnterprise({
          entityId: root.entityId, generation: 7
        }, {
          method: "peap-mschapv2", identity: "user@example.test",
          password: "destruction secret",
          serverDomain: "radius.example.test"
        })
        if (!result.ok || result.code !== "accepted")
          return root.fail("destruction worker was rejected")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (!primary || primary.phase !== "dispatching" || root.ticks < 8) return
        primaryLoader.active = false
        replacementLoader.active = true
        root.phase = 2
        root.ticks = 0
        return
      }
      if (root.phase === 2) {
        if (!replacement || root.ticks < 40) return
        if (replacement.authorized)
          return root.fail("destroyed uncertain dispatcher released authority")
        console.log("network enterprise destruction regression passed")
        Qt.exit(0)
      }
    }
  }
}
