pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import "PowerModel.js" as PowerModel
import "../hancore.shibumi.state/runtime" as SuiteRuntime

// Beta.13 retains UPower plus the existing Omarchy/powerprofilesctl helpers.
// This is runtime admission, not a Power backend ownership transition.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var batterySnapshotOverride: null
  property var commandOverrides: null
  property int commandTimeoutMs: 10000
  property bool completed: false
  property bool stopping: false
  property int operationGeneration: 0

  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.power-state"
    implementationVersion: "0.1.1-beta.15"
    owner: root
    host: root.shell
    manifest: root.manifest
  }

  readonly property int contractVersion: 1
  readonly property bool backendAdmitted: completed && runtimeProvider.registered && !stopping
  // Wiring readiness is not UPower connection or profile-probe success.
  readonly property bool ready: backendAdmitted
  readonly property var admissionLease: backendAdmitted ? runtimeProvider.lease : null
  readonly property bool overridden: batterySnapshotOverride !== null || commandOverrides !== null
  readonly property bool batteryReady: batteryBackend.snapshot !== null
  readonly property bool hasBattery: batteryReady && batteryBackend.snapshot.isPresent
    && batteryBackend.snapshot.isLaptopBattery
  readonly property int percent: PowerModel.clampPercent(
    batteryReady ? batteryBackend.snapshot.percentage : 0)
  readonly property int batteryState: batteryReady
    ? batteryBackend.snapshot.state : UPowerDeviceState.Unknown
  readonly property bool charging: hasBattery && batteryState === UPowerDeviceState.Charging
  readonly property bool fullyCharged: hasBattery && batteryState === UPowerDeviceState.FullyCharged
  readonly property bool discharging: hasBattery && batteryBackend.snapshot.onBattery
    && batteryState === UPowerDeviceState.Discharging
  readonly property real timeToEmpty: batteryReady ? batteryBackend.snapshot.timeToEmpty : 0
  readonly property real timeToFull: batteryReady ? batteryBackend.snapshot.timeToFull : 0
  readonly property real changeRate: batteryReady ? batteryBackend.snapshot.changeRate : 0
  readonly property real energyCapacity: batteryReady ? batteryBackend.snapshot.energyCapacity : 0
  readonly property bool healthSupported: batteryReady && batteryBackend.snapshot.healthSupported
  readonly property int healthPercent: healthSupported
    ? PowerModel.clampPercent(batteryBackend.snapshot.healthPercentage) : 0
  readonly property string batteryId: String(batteryInfo["battery-id"] || "")
  readonly property string batteryHealthText: batteryInfo.health !== undefined
    ? String(batteryInfo.health || "") : healthSupported ? healthPercent + "%" : ""
  readonly property string timeText: PowerModel.duration(
    charging ? timeToFull : timeToEmpty) || String(batteryInfo.time || "")
  readonly property string helperBatteryState: String(batteryInfo.state || "")
  readonly property string batteryStatus: helperBatteryState === "holding" ? "Holding"
    : fullyCharged ? "Full" : charging ? "Charging" : discharging ? "Discharging"
    : hasBattery ? "On battery" : "No battery"

  property var batteryInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property bool profilesReady: false
  readonly property bool profileActionRunning: profileAction.busy
  property string profileError: ""
  property int profileConsumers: 0
  property int detailConsumers: 0
  property bool profileRefreshPending: false
  property bool activeProfileRefreshPending: false
  property bool detailRefreshPending: false
  // Ungated observability includes draining operations after admission loss.
  readonly property int busyWorkers: Number(profilesProc.busy) + Number(activeProfileProc.busy)
    + Number(batteryProc.busy) + Number(profileAction.busy)
  readonly property bool profileAvailable: ready && profilesReady && profiles.length > 0
  readonly property string activeProfileLabel: PowerModel.profileLabel(activeProfile)
  readonly property string activeProfileShortName: PowerModel.profileShortName(activeProfile)

  function copyBattery(value) {
    try {
      if (!value || typeof value !== "object" || value.ready !== true) return null
      var result = ({})
      var flags = ["isPresent", "isLaptopBattery", "onBattery", "healthSupported"]
      var numbers = ["percentage", "state", "timeToEmpty", "timeToFull", "changeRate",
        "energyCapacity", "healthPercentage"]
      for (var i = 0; i < flags.length; i++) {
        var flag = value[flags[i]]
        if (typeof flag !== "boolean") return null
        result[flags[i]] = flag
      }
      for (var n = 0; n < numbers.length; n++) {
        var number = value[numbers[n]]
        if (typeof number !== "number" || !isFinite(number) || number < 0) return null
        result[numbers[n]] = number
      }
      if (Math.floor(result.state) !== result.state || result.state > 6) return null
      return result
    } catch (error) { return null }
  }

  Item {
    id: batteryBackend
    // Native objects stay in this private child, never on the service facade.
    readonly property var device: root.ready && !root.overridden ? UPower.displayDevice : null
    readonly property var snapshot: !root.ready ? null
      : root.overridden ? root.copyBattery(root.batterySnapshotOverride)
      : device && device.ready ? ({
        isPresent: device.isPresent, isLaptopBattery: device.isLaptopBattery,
        onBattery: UPower.onBattery, percentage: device.percentage, state: device.state,
        timeToEmpty: device.timeToEmpty, timeToFull: device.timeToFull,
        changeRate: device.changeRate, energyCapacity: device.energyCapacity,
        healthSupported: device.healthSupported, healthPercentage: device.healthPercentage
      }) : null
  }

  function commandFor(kind, nativeCommand, argument) {
    if (!ready) return null
    if (!overridden) return nativeCommand
    var owner = commandOverrides
    var lease = admissionLease
    try {
      if (!owner || typeof owner !== "object") return null
      var keys = ["profiles", "activeProfile", "battery", "setProfile"]
      var commands = ({})
      for (var i = 0; i < keys.length; i++) {
        var input = owner[keys[i]]
        if (!Array.isArray(input) || input.length === 0 || input.length > 31) return null
        var argv = []
        for (var j = 0; j < input.length; j++) {
          var word = input[j]
          if (typeof word !== "string" || word.length > 8192 || word.indexOf("\u0000") !== -1) return null
          argv.push(word)
        }
        commands[keys[i]] = argv
      }
      if (!ready || admissionLease !== lease || owner !== commandOverrides) return null
      if (kind === "setProfile") commands[kind].push(argument)
      return commands[kind]
    } catch (error) { return null }
  }

  function acquireProfiles() {
    if (!ready) return false
    profileConsumers++
    if (profilesReady) refreshActiveProfile()
    else refreshProfiles()
    return true
  }
  function releaseProfiles() {
    profileConsumers = Math.max(0, profileConsumers - 1)
    if (profileConsumers === 0) {
      profileRefreshPending = false
      activeProfileRefreshPending = false
      profilesProc.cancel()
      activeProfileProc.cancel()
    }
  }
  function acquireBatteryDetails() {
    if (!ready || !hasBattery) return false
    detailConsumers++
    refreshBatteryDetails()
    return true
  }
  function releaseBatteryDetails() {
    detailConsumers = Math.max(0, detailConsumers - 1)
    if (detailConsumers === 0) {
      detailRefreshPending = false
      batteryProc.cancel()
    }
  }

  function refreshProfiles() {
    if (!ready) return false
    if (profilesProc.busy) { profileRefreshPending = true; return true }
    var command = commandFor("profiles", ["omarchy-powerprofiles-list", "--active-state"])
    return command !== null && profilesProc.start(command)
  }
  function refreshActiveProfile() {
    if (!ready) return false
    if (activeProfileProc.busy) { activeProfileRefreshPending = true; return true }
    var command = commandFor("activeProfile", ["busctl", "--system", "get-property",
      "org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles",
      "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"])
    return command !== null && activeProfileProc.start(command)
  }
  function refreshBatteryDetails() {
    if (!ready || !hasBattery) return false
    if (batteryProc.busy) { detailRefreshPending = true; return true }
    var command = commandFor("battery", ["bash", "-c",
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
      + "printf 'health\\t%s\\n' \"$health\"; fi"])
    return command !== null && batteryProc.start(command)
  }
  function setProfile(profile) {
    if (!ready || !profilesReady || profileActionRunning) return false
    var value
    try { value = String(profile || "") } catch (error) { return false }
    if (!ready || profiles.indexOf(value) < 0) return false
    var command = commandFor("setProfile", ["powerprofilesctl", "set", value], value)
    if (command === null || !profileAction.start(command)) return false
    profileError = ""
    return true
  }
  function cycleProfile() {
    if (!ready || !profilesReady || profiles.length === 0) return false
    var index = profiles.indexOf(activeProfile)
    return setProfile(profiles[(Math.max(0, index) + 1) % profiles.length])
  }
  function profileLabel(profile) { return PowerModel.profileLabel(profile) }

  // Keep queued demand revocable until dispatch. Clearing it at settlement
  // would let a callback survive release or scope loss followed by re-admission.
  function flushProfileRefresh() {
    if (!profileRefreshPending) return
    profileRefreshPending = false
    refreshProfiles()
  }
  function flushActiveProfileRefresh() {
    if (!activeProfileRefreshPending) return
    activeProfileRefreshPending = false
    refreshActiveProfile()
  }
  function flushDetailRefresh() {
    if (!detailRefreshPending) return
    detailRefreshPending = false
    refreshBatteryDetails()
  }

  function resumeDemand() {
    if (!ready) return
    if (profileConsumers > 0) refreshProfiles()
    if (detailConsumers > 0 && hasBattery) refreshBatteryDetails()
  }
  function invalidateWork() {
    if (!completed) return
    operationGeneration++
    profileRefreshPending = false
    activeProfileRefreshPending = false
    detailRefreshPending = false
    profilesProc.cancel()
    activeProfileProc.cancel()
    batteryProc.cancel()
    profileAction.cancel()
    profiles = []
    profilesReady = false
    activeProfile = ""
    batteryInfo = ({})
    profileError = ""
    Qt.callLater(resumeDemand)
  }
  onAdmissionLeaseChanged: invalidateWork()
  onCommandOverridesChanged: invalidateWork()
  onBatterySnapshotOverrideChanged: invalidateWork()
  onHasBatteryChanged: {
    if (!completed) return
    if (!hasBattery) { batteryInfo = ({}); detailRefreshPending = false; batteryProc.cancel() }
    else if (detailConsumers > 0) refreshBatteryDetails()
  }
  Component.onCompleted: completed = true
  Component.onDestruction: {
    stopping = true
    runtimeProvider.owner = null
  }

  PowerCommand {
    id: profilesProc
    admitted: root.ready
    lease: root.admissionLease
    generation: root.operationGeneration
    timeoutMs: root.commandTimeoutMs
    onCompleted: function(output, ok) {
      if (!ok) return
      var parsed = PowerModel.parseProfiles(output)
      if (parsed.profiles.length > 0) {
        root.profiles = parsed.profiles
        root.profilesReady = true
        if (parsed.activeProfile) root.activeProfile = parsed.activeProfile
      }
    }
    onSettled: if (root.profileRefreshPending) Qt.callLater(root.flushProfileRefresh)
  }
  PowerCommand {
    id: activeProfileProc
    admitted: root.ready
    lease: root.admissionLease
    generation: root.operationGeneration
    timeoutMs: root.commandTimeoutMs
    onCompleted: function(output, ok) {
      if (!ok) return
      var match = String(output || "").match(/^s\s+"([^"]+)"/)
      if (match && root.profiles.indexOf(match[1]) >= 0) root.activeProfile = match[1]
    }
    onSettled: if (root.activeProfileRefreshPending) Qt.callLater(root.flushActiveProfileRefresh)
  }
  PowerCommand {
    id: batteryProc
    admitted: root.ready && root.hasBattery
    lease: root.admissionLease
    generation: root.operationGeneration
    timeoutMs: root.commandTimeoutMs
    onCompleted: function(output, ok) {
      if (!ok) return
      var parsed = PowerModel.parseKeyValue(output)
      if (Object.keys(parsed).length > 0) root.batteryInfo = parsed
    }
    onSettled: if (root.detailRefreshPending) Qt.callLater(root.flushDetailRefresh)
  }
  PowerCommand {
    id: profileAction
    admitted: root.ready
    lease: root.admissionLease
    generation: root.operationGeneration
    timeoutMs: root.commandTimeoutMs
    onCompleted: function(output, ok) {
      if (!ok) root.profileError = "Could not change power profile"
      root.profileRefreshPending = true
      Qt.callLater(root.flushProfileRefresh)
    }
  }

  Timer {
    interval: 5000
    running: root.ready && root.profileConsumers > 0
    repeat: true
    onTriggered: root.refreshActiveProfile()
  }
  Timer {
    interval: 5 * 60 * 1000
    running: root.ready && root.profileConsumers > 0
    repeat: true
    onTriggered: root.refreshProfiles()
  }
  Timer {
    interval: 5000
    running: root.ready && root.detailConsumers > 0 && root.hasBattery
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshBatteryDetails()
  }
}
