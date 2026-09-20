pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "powerState" as PowerState

ShellRoot {
  id: root

  property int phase: -1
  property int attempts: 0

  QtObject { id: scopedHost; property string pluginId: "hancore.shibumi.power-state" }
  PowerState.Service {
    id: power
    shell: scopedHost
    manifest: ({ id: "hancore.shibumi.power-state", version: "0.1.1-beta.15",
      kinds: ["service"], entryPoints: { service: "Service.qml" } })
    batterySnapshotOverride: ({ ready: false })
    commandOverrides: ({
      profiles: ["omarchy-powerprofiles-list", "--active-state"],
      activeProfile: ["busctl", "--system", "get-property", "org.freedesktop.UPower.PowerProfiles",
        "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"],
      battery: ["omarchy-battery-status", "--shell"],
      setProfile: ["powerprofilesctl", "set"]
    })
  }

  function fail(message) {
    console.error("power-service-runtime-smoke:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.attempts++
      if (root.phase === -1) {
        if (root.attempts > 100) return root.fail("admission deadline")
        if (!power.ready) return
        if (!power.acquireProfiles()) return root.fail("admitted acquire refused")
        root.phase = 0
        root.attempts = 0
      } else if (root.phase === 0) {
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
