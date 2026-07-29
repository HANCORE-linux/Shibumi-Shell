pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  property bool hasBattery: false
  property int percent: 20
  property bool charging: true
  property bool fullyCharged: false
  property bool discharging: false
  property string timeText: "1h 11m"
  property string batteryStatus: "Charging"
  property real changeRate: 34.5
  property bool healthSupported: true
  property int healthPercent: 96
  property string batteryId: "BAT0"
  property string batteryHealthText: "96%"
  property var batteryInfo: ({ size: "50Wh", cycles: "102", threshold: "75-80%" })

  property var profiles: ["power-saver", "balanced", "performance"]
  property string activeProfile: "balanced"
  property bool profilesReady: true
  property bool profileAvailable: profilesReady && profiles.length > 0
  property string activeProfileLabel: label(activeProfile)
  property string activeProfileShortName: activeProfile === "power-saver" ? "SAV"
    : activeProfile === "performance" ? "PRF" : "BAL"
  property bool profileActionRunning: false
  property string profileError: ""
  property int profileConsumers: 0
  property int detailConsumers: 0
  property int refreshProfilesCalls: 0
  property int refreshDetailsCalls: 0
  property int setProfileCalls: 0

  function label(profile) {
    if (profile === "power-saver") return "Power Saver"
    if (profile === "performance") return "Performance"
    return "Balanced"
  }
  function profileLabel(profile) { return label(profile) }
  function acquireProfiles() { profileConsumers++ }
  function releaseProfiles() { profileConsumers = Math.max(0, profileConsumers - 1) }
  function acquireBatteryDetails() { detailConsumers++; refreshBatteryDetails() }
  function releaseBatteryDetails() { detailConsumers = Math.max(0, detailConsumers - 1) }
  function refreshProfiles() { refreshProfilesCalls++ }
  function refreshBatteryDetails() { refreshDetailsCalls++ }
  function setProfile(profile) {
    if (profiles.indexOf(profile) < 0) return false
    setProfileCalls++
    activeProfile = profile
    return true
  }
  function cycleProfile() {
    var index = profiles.indexOf(activeProfile)
    return setProfile(profiles[(Math.max(0, index) + 1) % profiles.length])
  }
}
