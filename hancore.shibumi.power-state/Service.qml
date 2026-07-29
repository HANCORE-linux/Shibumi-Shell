pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower
import "PowerModel.js" as PowerModel

// One process-wide state and action owner for the separate G12 battery and
// G14 power-profile views. Views never poll hardware or invoke profiles.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property int contractVersion: 1
  readonly property bool ready: true

  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool hasBattery: !!(batteryDevice && batteryDevice.isPresent
    && batteryDevice.isLaptopBattery)
  readonly property int percent: PowerModel.clampPercent(
    batteryDevice ? batteryDevice.percentage : 0)
  readonly property int batteryState: batteryDevice
    ? batteryDevice.state : UPowerDeviceState.Unknown
  readonly property bool charging: hasBattery
    && batteryState === UPowerDeviceState.Charging
  readonly property bool fullyCharged: hasBattery
    && batteryState === UPowerDeviceState.FullyCharged
  readonly property bool discharging: hasBattery && UPower.onBattery
    && batteryState === UPowerDeviceState.Discharging
  readonly property real timeToEmpty: batteryDevice
    ? Number(batteryDevice.timeToEmpty) || 0 : 0
  readonly property real timeToFull: batteryDevice
    ? Number(batteryDevice.timeToFull) || 0 : 0
  readonly property real changeRate: batteryDevice
    ? Number(batteryDevice.changeRate) || 0 : 0
  readonly property real energyCapacity: batteryDevice
    ? Number(batteryDevice.energyCapacity) || 0 : 0
  readonly property bool healthSupported: !!(batteryDevice
    && batteryDevice.healthSupported)
  readonly property int healthPercent: healthSupported
    ? PowerModel.clampPercent(batteryDevice.healthPercentage) : 0
  readonly property string batteryId: String(batteryInfo["battery-id"] || "")
  readonly property string batteryHealthText: batteryInfo.health !== undefined
    ? String(batteryInfo.health || "")
    : healthSupported ? healthPercent + "%" : ""
  readonly property string timeText: PowerModel.duration(
    charging ? timeToFull : timeToEmpty) || String(batteryInfo.time || "")
  readonly property string helperBatteryState: String(batteryInfo.state || "")
  readonly property string batteryStatus: helperBatteryState === "holding" ? "Holding"
    : fullyCharged ? "Full"
    : charging ? "Charging"
    : discharging ? "Discharging"
    : hasBattery ? "On battery" : "No battery"

  property var batteryInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property bool profilesReady: false
  property bool profileActionRunning: false
  property string profileError: ""
  property int profileConsumers: 0
  property int detailConsumers: 0
  property bool profileRefreshPending: false
  property bool activeProfileRefreshPending: false
  property bool detailRefreshPending: false

  readonly property bool profileAvailable: profilesReady && profiles.length > 0
  readonly property string activeProfileLabel: PowerModel.profileLabel(activeProfile)
  readonly property string activeProfileShortName: PowerModel.profileShortName(activeProfile)

  function acquireProfiles() {
    profileConsumers++
    if (profilesReady) refreshActiveProfile()
    else refreshProfiles()
  }

  function releaseProfiles() {
    profileConsumers = Math.max(0, profileConsumers - 1)
  }

  function acquireBatteryDetails() {
    detailConsumers++
    refreshBatteryDetails()
  }

  function releaseBatteryDetails() {
    detailConsumers = Math.max(0, detailConsumers - 1)
  }

  function refreshProfiles() {
    if (profilesProc.running) {
      profileRefreshPending = true
      return
    }
    profilesProc.running = true
  }

  function refreshActiveProfile() {
    if (activeProfileProc.running) {
      activeProfileRefreshPending = true
      return
    }
    activeProfileProc.running = true
  }

  function refreshBatteryDetails() {
    if (!hasBattery) return
    if (batteryProc.running) {
      detailRefreshPending = true
      return
    }
    batteryProc.running = true
  }

  function setProfile(profile) {
    var value = String(profile || "")
    if (profileActionRunning || profiles.indexOf(value) < 0) return false
    profileError = ""
    profileActionRunning = true
    profileAction.command = ["powerprofilesctl", "set", value]
    profileAction.running = true
    return true
  }

  function cycleProfile() {
    if (profiles.length === 0) return false
    var index = profiles.indexOf(activeProfile)
    return setProfile(profiles[(Math.max(0, index) + 1) % profiles.length])
  }

  function profileLabel(profile) {
    return PowerModel.profileLabel(profile)
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = PowerModel.parseProfiles(text)
        if (parsed.profiles.length > 0) {
          root.profiles = parsed.profiles
          root.profilesReady = true
          if (parsed.activeProfile) root.activeProfile = parsed.activeProfile
        }
      }
    }
    onExited: {
      if (!root.profileRefreshPending) return
      root.profileRefreshPending = false
      Qt.callLater(root.refreshProfiles)
    }
  }

  Process {
    id: activeProfileProc
    command: ["busctl", "--system", "get-property",
      "org.freedesktop.UPower.PowerProfiles",
      "/org/freedesktop/UPower/PowerProfiles",
      "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var match = String(text || "").match(/^s\s+"([^"]+)"/)
        if (match && root.profiles.indexOf(match[1]) >= 0)
          root.activeProfile = match[1]
      }
    }
    onExited: {
      if (!root.activeProfileRefreshPending) return
      root.activeProfileRefreshPending = false
      Qt.callLater(root.refreshActiveProfile)
    }
  }

  Process {
    id: batteryProc
    command: ["bash", "-c",
      "omarchy-battery-status --shell || exit; "
      + "battery=$(upower -e 2>/dev/null | grep '/battery_' | head -n1); "
      + "battery=${battery##*/}; battery=${battery#battery_}; "
      + "[[ $battery =~ ^[A-Za-z0-9._-]+$ ]] || exit 0; "
      + "sys=/sys/class/power_supply/$battery; "
      + "[[ -d $sys ]] || exit 0; "
      + "printf 'battery-id\\t%s\\n' \"$battery\"; "
      + "full=$(cat \"$sys/charge_full\" 2>/dev/null || cat \"$sys/energy_full\" 2>/dev/null || true); "
      + "design=$(cat \"$sys/charge_full_design\" 2>/dev/null || cat \"$sys/energy_full_design\" 2>/dev/null || true); "
      + "if [[ $full =~ ^[0-9]+$ && $design =~ ^[0-9]+$ && $design -gt 0 ]]; then "
      + "health=$(awk -v full=\"$full\" -v design=\"$design\" 'BEGIN { value=full*100/design; if (value>100) value=100; if (value<0) value=0; printf \"%d%%\", value }'); "
      + "printf 'health\\t%s\\n' \"$health\"; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = PowerModel.parseKeyValue(text)
        if (Object.keys(parsed).length > 0) root.batteryInfo = parsed
      }
    }
    onExited: {
      if (!root.detailRefreshPending) return
      root.detailRefreshPending = false
      Qt.callLater(root.refreshBatteryDetails)
    }
  }

  Process {
    id: profileAction
    onExited: function(exitCode) {
      root.profileActionRunning = false
      if (exitCode !== 0) root.profileError = "Could not change power profile"
      root.refreshProfiles()
    }
  }

  Timer {
    interval: 5000
    running: root.profileConsumers > 0
    repeat: true
    onTriggered: root.refreshActiveProfile()
  }

  Timer {
    interval: 5 * 60 * 1000
    running: root.profileConsumers > 0
    repeat: true
    onTriggered: root.refreshProfiles()
  }

  Timer {
    interval: 5000
    running: root.detailConsumers > 0 && root.hasBattery
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshBatteryDetails()
  }

  onHasBatteryChanged: if (!hasBattery) batteryInfo = ({})
}
