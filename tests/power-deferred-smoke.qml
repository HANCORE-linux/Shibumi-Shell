pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "powerState" as PowerState

// Controlled settlement/completion signals on the owned, fully fake service.
// This observes deferred dispatch, not native helper/compositor scheduling.
ShellRoot {
  id: root
  property bool allowed: true
  property int index: 0
  property int ticks: 0
  property bool waiting: false
  property double dispatchedAt: 0
  property string before: ""
  property var slots: []
  readonly property string directory: Quickshell.env("SHIBUMI_POWER_SCOPE_DIR")
  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("fixtures/power-runtime-helper.py")).substring(7))
  readonly property var cases: [
    {slot: 0, flag: "profileRefreshPending", kind: "profiles", loss: "release"},
    {slot: 1, flag: "activeProfileRefreshPending", kind: "activeProfile", loss: "release"},
    {slot: 2, flag: "detailRefreshPending", kind: "battery", loss: "release"},
    {slot: 0, flag: "profileRefreshPending", kind: "profiles", loss: "scope"},
    {slot: 1, flag: "activeProfileRefreshPending", kind: "activeProfile", loss: "scope"},
    {slot: 2, flag: "detailRefreshPending", kind: "battery", loss: "scope"},
    {slot: 2, flag: "detailRefreshPending", kind: "battery", loss: "battery"},
    {slot: 3, kind: "profiles", loss: "scope"},
    {slot: 3, kind: "profiles", loss: "release"},
    {slot: 0, flag: "profileRefreshPending", kind: "profiles", loss: "none"},
    {slot: 1, flag: "activeProfileRefreshPending", kind: "activeProfile", loss: "none"},
    {slot: 2, flag: "detailRefreshPending", kind: "battery", loss: "none"},
    {slot: 3, kind: "profiles", loss: "none"}
  ]
  function check(value, message) {
    if (value) return
    console.error("power-deferred:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  QtObject { id: host; property string pluginId: "hancore.shibumi.power-state" }
  QtObject {
    id: battery
    property bool ready: true
    property bool isPresent: true
    property bool isLaptopBattery: true
    property bool onBattery: true
    property bool healthSupported: true
    property real percentage: 0.67
    property int state: 2
    property real timeToEmpty: 4200
    property real timeToFull: 0
    property real changeRate: 12.5
    property real energyCapacity: 50
    property real healthPercentage: 0.96
  }
  PowerState.Service {
    id: power
    shell: host
    manifest: root.allowed ? ({id: "hancore.shibumi.power-state", version: "0.1.1-beta.15", kinds: ["service"]}) : null
    batterySnapshotOverride: battery
    commandOverrides: ({
      profiles: ["/usr/bin/python3", "-I", root.helper, root.directory, "profiles"],
      activeProfile: ["/usr/bin/python3", "-I", root.helper, root.directory, "activeProfile"],
      battery: ["/usr/bin/python3", "-I", root.helper, root.directory, "battery"],
      setProfile: ["/usr/bin/python3", "-I", root.helper, root.directory, "setProfile"]
    })
  }
  FileView { id: trace; path: root.directory + "/trace"; blockLoading: true; printErrors: false }
  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.check(++root.ticks < 260, "deadline case " + root.index)
      if (!power.ready) return
      if (root.slots.length === 0) {
        var slots = []
        // Only inspect our private fixture's visual children, never a host tree.
        for (var i = 0; i < power.children.length; i++) {
          var child = power.children[i]
          if (typeof child.settled === "function" && typeof child.start === "function") slots.push(child)
        }
        root.check(slots.length === 4, "expected exactly four owned operation slots")
        root.slots = slots
      }
      if (root.index === root.cases.length) {
        root.check(power.profileConsumers === 0 && power.detailConsumers === 0 && power.busyWorkers === 0,
          "final demand or worker leak")
        console.log("power deferred smoke passed")
        Qt.quit()
        return
      }
      var test = root.cases[root.index]
      trace.reload()
      if (!root.waiting) {
        root.check(power.busyWorkers === 0, "unexpected operation before case")
        root.before = trace.text()
        if (test.slot === 3) root.slots[3].completed("", true)
        else {
          power[test.flag] = true
          root.slots[test.slot].settled()
        }
        if (test.loss === "release") {
          // Model the final outstanding lease without starting another probe.
          if (test.slot === 2) { power.detailConsumers = 1; power.releaseBatteryDetails() }
          else { power.profileConsumers = 1; power.releaseProfiles() }
        } else if (test.loss === "scope") {
          root.allowed = false
          root.check(!power.ready, "scope revocation missing")
          root.allowed = true
          root.check(power.ready, "scope re-admission missing")
        } else if (test.loss === "battery") {
          battery.ready = false
          root.check(!power.hasBattery, "battery loss missing")
          battery.ready = true
          root.check(power.hasBattery, "battery recovery missing")
        }
        root.dispatchedAt = Date.now()
        root.waiting = true
        return
      }
      if (test.loss !== "none") {
        root.check(power.busyWorkers === 0 && trace.text() === root.before,
          "cancelled deferred " + test.kind + " revived after " + test.loss)
        if (Date.now() - root.dispatchedAt < 250) return
      } else {
        if (power.busyWorkers > 0 || trace.text() === root.before) return
        root.check(trace.text() === root.before + test.kind + "\n", "manual deferred request was not coalesced")
      }
      root.waiting = false
      root.index++
    }
  }
}
