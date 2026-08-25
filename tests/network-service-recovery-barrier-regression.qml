pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network

ShellRoot {
  id: root

  property int getterReads: 0

  function fail(message) {
    console.error("network-service-recovery-barrier-regression:", message)
    Qt.exit(1)
  }

  function findNamed(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    const children = item.children || []
    for (let index = 0; index < children.length; index++) {
      const found = findNamed(children[index], name)
      if (found) return found
    }
    return null
  }

  function blocked(result) {
    return result && result.accepted === false
      && result.code === "restart-required"
      && result.message === "Restart the shell to restore NetworkManager."
  }

  Network.Service {
    id: service
    active: false
  }

  Timer {
    interval: 100
    running: true
    onTriggered: {
      const liveness = root.findNamed(
        service, "shibumiNetworkManagerLiveness")
      if (!liveness) return root.fail("liveness owner was not discoverable")
      liveness.recoveryBlocked = true
      if (!service.mutationBlocked)
        return root.fail("live recovery block did not close the service")

      const poison = ({
        get entityId() {
          root.getterReads++
          throw new Error("blocked entry was materialized")
        }
      })
      const results = [
        service.toggleWifi(),
        service.connect(poison),
        service.connectWithPassphrase(poison, "not-retained"),
        service.connectEnterprise(poison, "identity", "not-retained",
          "radius.example.test"),
        service.disconnect(poison),
        service.forget(poison)
      ]
      for (let index = 0; index < results.length; index++) {
        if (!root.blocked(results[index]))
          return root.fail("public mutation route escaped at " + index)
      }
      if (root.getterReads !== 0)
        return root.fail("blocked action materialized attacker-controlled data")
      if (service.refresh(true) !== false
          || service.runSpeedTest(root) !== false)
        return root.fail("scan or speed-test escaped the recovery barrier")

      console.log("network service recovery barrier regression passed")
      Qt.exit(0)
    }
  }
}
