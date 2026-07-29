pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "services" as Services

ShellRoot {
  id: root

  property int attempts: 0
  property bool detailsRequested: false
  readonly property bool expectBattery: Quickshell.env("SHIBUMI_POWER_EXPECT_BATTERY") === "1"

  Services.PowerService { id: power }

  function fail(message) {
    console.error("power-service-live-probe:", message)
    Qt.exit(1)
  }

  Component.onCompleted: power.acquireProfiles()

  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      root.attempts++
      if (!power.profilesReady || power.activeProfile === "") {
        if (root.attempts >= 50) root.fail("profile helper did not become ready")
        return
      }
      if (power.hasBattery !== root.expectBattery)
        return root.fail("battery presence mismatch")
      if (root.expectBattery && !root.detailsRequested) {
        root.detailsRequested = true
        power.acquireBatteryDetails()
        return
      }
      if (root.expectBattery && Object.keys(power.batteryInfo).length === 0) {
        if (root.attempts >= 50) root.fail("battery detail helper did not become ready")
        return
      }
      if (power.profiles.indexOf(power.activeProfile) < 0)
        return root.fail("active profile is not in validated profile list")
      if (root.expectBattery && (power.percent < 0 || power.percent > 100))
        return root.fail("battery percentage out of range")

      console.log("SHIBUMI_POWER_PROBE_OK", JSON.stringify({
        hasBattery: power.hasBattery,
        percent: power.percent,
        charging: power.charging,
        profiles: power.profiles,
        activeProfile: power.activeProfile,
        batteryInfo: power.batteryInfo
      }))
      if (root.detailsRequested) power.releaseBatteryDetails()
      power.releaseProfiles()
      stop()
      Qt.quit()
    }
  }
}
