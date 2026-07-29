pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "services" as Services

ShellRoot {
  id: root

  property int phase: 0
  property int attempts: 0

  Services.PowerService { id: power }

  function fail(message) {
    console.error("power-service-runtime-smoke:", message)
    Qt.exit(1)
  }

  Component.onCompleted: power.acquireProfiles()

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.attempts++
      if (root.phase === 0) {
        if (!power.profilesReady || power.activeProfile !== "balanced") {
          if (root.attempts >= 40) root.fail("initial validated profile state")
          return
        }
        if (power.profiles.length !== 3 || power.profileConsumers !== 1)
          return root.fail("profile list/shared lease")
        if (power.setProfile("performance;touch /tmp/unsafe"))
          return root.fail("unlisted profile accepted")
        if (!power.setProfile("performance"))
          return root.fail("listed profile rejected")
        root.phase = 1
        root.attempts = 0
      } else {
        if (power.profileActionRunning || power.activeProfile !== "performance") {
          if (root.attempts >= 40) root.fail("profile action/refresh")
          return
        }
        if (power.profileError !== "")
          return root.fail("successful action reported an error")
        power.releaseProfiles()
        if (power.profileConsumers !== 0)
          return root.fail("profile lease release")
        stop()
        console.log("power service runtime smoke passed")
        Qt.quit()
      }
    }
  }
}
