pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "powerState" as PowerState
import "battery" as Battery
import "powerProfile" as PowerProfile
import "hancore.shibumi.state/runtime" as SuiteRuntime

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property bool stateEnabled: false
  property bool serviceEnabled: true
  property var serviceHost: null
  property var serviceManifest: null
  property var panelA: null
  property var panelB: null
  property var cachedSet: null
  property var cachedRefresh: null
  property int traceBefore: 0
  property double lossAt: 0
  readonly property var power: serviceLoader.item
  readonly property string fixturePath: Quickshell.env("SHIBUMI_POWER_SCOPE_DIR")
  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("fixtures/power-runtime-helper.py")).substring(7))
  readonly property var validManifest: ({ id: "hancore.shibumi.power-state", version: "0.1.1-beta.13", kinds: ["service"], entryPoints: { service: "Service.qml" } })
  readonly property var fakeCommands: ({
    profiles: ["/usr/bin/python3", "-I", helper, fixturePath, "profiles"],
    activeProfile: ["/usr/bin/python3", "-I", helper, fixturePath, "activeProfile"],
    battery: ["/usr/bin/python3", "-I", helper, fixturePath, "battery"],
    setProfile: ["/usr/bin/python3", "-I", helper, fixturePath, "setProfile"]
  })
  function check(value, message) {
    if (value) return
    console.error("power-runtime:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  FileView { id: trace; path: root.fixturePath + "/trace"; blockLoading: true; printErrors: false; watchChanges: true; onFileChanged: reload() }
  FileView { id: barrier; path: root.fixturePath + "/barrier"; blockLoading: true; blockWrites: true; printErrors: false; watchChanges: true; onFileChanged: reload() }
  FileView { id: profileFile; path: root.fixturePath + "/profile"; blockLoading: true; printErrors: false; watchChanges: true; onFileChanged: reload() }
  QtObject { id: host; property string pluginId: "hancore.shibumi.power-state" }
  QtObject {
    id: widgetHost
    property string pluginId: "fixture.widget"
    function serviceFor(id) { root.check(false, "raw scoped lookup: " + id); return null }
  }
  QtObject { id: stateHost; property string pluginId: "hancore.shibumi.state" }
  QtObject {
    id: state
    property var config: ({ presentation: { radius: "small" } })
    property color selectedColor: "#ee8888"
    function paletteColor(id) { return "#ee8888" }
  }
  SuiteRuntime.Provider {
    pluginId: "hancore.shibumi.state"
    implementationVersion: "0.1.1-beta.13"
    owner: state
    host: root.stateEnabled ? stateHost : null
    manifest: ({ id: "hancore.shibumi.state", version: "0.1.1-beta.13", kinds: ["service"] })
  }
  QtObject {
    id: battery
    property bool ready: false
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
  Loader {
    id: serviceLoader
    active: root.serviceEnabled
    sourceComponent: PowerState.Service {
      shell: root.serviceHost
      manifest: root.serviceManifest
      batterySnapshotOverride: battery
      commandOverrides: root.fakeCommands
    }
  }
  PowerState.Service { id: duplicate; batterySnapshotOverride: battery; commandOverrides: root.fakeCommands }
  component LocalBar: QtObject {
    property var shell: widgetHost
    property bool vertical: false
    property int barSize: 28
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#181818"
    property color urgent: "#ee8888"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
  }
  LocalBar { id: barA }
  LocalBar { id: barB; position: "bottom"; barSize: 36 }
  LocalBar { id: barC; barSize: 32 }
  Loader {
    id: views
    active: true
    sourceComponent: Item {
      property alias batA: batA
      property alias batB: batB
      property alias pwrA: pwrA
      property alias pwrB: pwrB
      Battery.BarWidget { id: batA; bar: barA }
      Battery.BarWidget { id: batB; bar: barB }
      PowerProfile.BarWidget { id: pwrA; bar: barA }
      PowerProfile.BarWidget { id: pwrB; bar: barB }
    }
  }
  function unavailable(message) {
    var v = views.item
    root.check(!v.batA.powerService && !v.pwrA.powerService && !v.batA.visible && !v.pwrA.visible
      && !v.batA.opened && !v.batB.opened && !v.pwrA.opened && !v.pwrB.opened
      && !v.batA.panelItem && !v.batB.panelItem && !v.pwrA.panelItem && !v.pwrB.panelItem,
      message)
  }
  Timer {
    interval: 30; running: true; repeat: true
    onTriggered: {
      root.check(++root.ticks < 240, "phase deadline " + root.phase)
      if (!SuiteRuntime.Runtime.ready || !views.item) return
      var p = root.power
      var v = views.item
      if (root.phase === 0) {
        root.check(!p.ready && p.busyWorkers === 0 && !p.acquireProfiles()
          && !p.refreshProfiles() && !p.setProfile("balanced") && !p.hasBattery
          && !("batteryDevice" in p), "early backend or native export")
        root.unavailable("pre-injection view")
        root.serviceHost = host
      } else if (root.phase === 1) {
        root.check(!p.ready && p.busyWorkers === 0 && !p.refreshActiveProfile(), "partial admission")
        root.serviceManifest = root.validManifest
      } else if (root.phase === 2) {
        if (!p.profileAvailable || p.busyWorkers !== 0) return
        root.check(p.ready && p.profileConsumers === 2 && v.pwrA.powerService === p
          && v.pwrB.powerService === p && v.pwrA.visible && !v.batA.visible
          && !p.batteryReady && !p.hasBattery && !p.refreshBatteryDetails(), "battery readiness or shared profiles")
        battery.ready = true
        root.stateEnabled = true
      } else if (root.phase === 3) {
        root.check(p.batteryReady && p.hasBattery && p.percent === 67 && p.discharging
          && v.batA.visible && v.batB.visible && v.batA.tokens.stateService === state
          && v.batB.tokens.stateService === state && v.pwrA.tokens.stateService === state
          && v.pwrB.tokens.stateService === state, "late battery/State tokens")
        v.batA.open(); v.pwrB.open()
      } else if (root.phase === 4) {
        if (!v.batA.panelItem || !v.pwrB.panelItem || p.batteryId !== "BATfixture" || p.busyWorkers) return
        root.panelA = v.batA.panelItem; root.panelB = v.pwrB.panelItem
        root.check(p.detailConsumers === 1 && panelA.powerService === p && panelB.powerService === p
          && panelA !== panelB && panelA.bar === barA && panelB.bar === barB
          && panelA.anchorItem !== panelB.anchorItem, "actual panels or exact detail lease")
        v.batA.bar = barC
      } else if (root.phase === 5) {
        root.check(v.batA.panelItem === panelA && panelA.bar === barC && panelB.bar === barB,
          "stale open local panel bar")
        panelB.selectedIndex = 2
        panelB.activateSelected()
      } else if (root.phase === 6) {
        if (p.profileActionRunning || p.activeProfile !== "performance" || p.busyWorkers) return
        root.check(!v.pwrB.opened && !v.pwrB.panelItem && v.batA.panelItem === panelA
          && profileFile.text().trim() === "performance", "panel action or selective close")
        root.cachedSet = p.setProfile; root.cachedRefresh = p.refreshProfiles
        barrier.setText("")
        root.check(p.setProfile("power-saver"), "held fake action refused")
      } else if (root.phase === 7) {
        if (barrier.text() !== "ready") return
        root.check(p.profileActionRunning, "helper barrier without operation")
        root.serviceHost = null
        root.lossAt = Date.now()
      } else if (root.phase === 8) {
        root.unavailable("scope loss kept panels")
        root.check(!p.ready && !root.cachedSet("balanced") && !root.cachedRefresh()
          && !p.acquireProfiles() && !p.acquireBatteryDetails(), "cached action admitted after loss")
        if (p.busyWorkers || Date.now() - root.lossAt < 1200) return
        root.check(p.profileConsumers === 0 && p.detailConsumers === 0 && !p.profilesReady
          && p.profiles.length === 0 && profileFile.text().trim() === "performance", "scope loss stale publication/action")
        root.serviceHost = host
      } else if (root.phase === 9) {
        if (!p.profileAvailable || p.busyWorkers) return
        root.check(p.profileConsumers === 2 && p.activeProfile === "performance", "readmission")
        v.batA.open(); v.pwrB.open()
        duplicate.shell = host; duplicate.manifest = root.validManifest
      } else if (root.phase === 10) {
        root.unavailable("duplicate retained view")
        root.check(!p.ready && !duplicate.ready && !root.cachedSet("balanced") && !duplicate.refreshProfiles(), "duplicate action")
        if (p.busyWorkers || duplicate.busyWorkers) return
        duplicate.manifest = null
      } else if (root.phase === 11) {
        if (!p.profileAvailable || p.busyWorkers) return
        root.serviceManifest = { id: "hancore.shibumi.power-state", version: "wrong", kinds: ["service"] }
      } else if (root.phase === 12) {
        root.unavailable("invalid manifest retained view")
        root.check(!p.ready && !p.refreshProfiles(), "invalid manifest action")
        root.serviceManifest = root.validManifest
      } else if (root.phase === 13) {
        if (!p.profileAvailable || p.busyWorkers) return
        p.commandOverrides = ({})
      } else if (root.phase === 14) {
        if (p.busyWorkers) return
        root.check(!p.refreshProfiles() && !p.refreshActiveProfile() && !p.refreshBatteryDetails()
          && !p.setProfile("performance"), "incomplete fake fell through")
        p.commandOverrides = null
      } else if (root.phase === 15) {
        root.check(!p.refreshProfiles() && !p.setProfile("performance") && p.busyWorkers === 0,
          "battery-only fake dispatched native commands")
        p.commandOverrides = root.fakeCommands
      } else if (root.phase === 16) {
        if (!p.profileAvailable || p.busyWorkers) return
        battery.ready = false
      } else if (root.phase === 17) {
        root.check(!p.batteryReady && !p.hasBattery && !v.batA.visible && v.pwrA.visible,
          "UPower readiness loss hid desktop profiles or retained battery")
        battery.ready = true
        v.batA.open(); v.pwrB.open()
      } else if (root.phase === 18) {
        if (!v.batA.panelItem || !v.pwrB.panelItem || p.busyWorkers) return
        barrier.setText("")
        root.check(p.setProfile("power-saver"), "destruction action refused")
      } else if (root.phase === 19) {
        if (barrier.text() !== "ready") return
        root.serviceEnabled = false
        root.lossAt = Date.now()
      } else if (root.phase === 20) {
        root.unavailable("service destruction retained panels")
        root.check(!p, "service object retained")
        if (Date.now() - root.lossAt < 1200) return
        root.check(profileFile.text().trim() === "performance", "destroyed service left helper action live")
        root.serviceEnabled = true
      } else if (root.phase === 21) {
        if (!p || !p.profileAvailable || p.busyWorkers) return
        root.check(p.profileConsumers === 2 && p.detailConsumers === 0, "replacement leases")
        views.active = false
        root.phase++
        return
      } else {
        root.check(false, "unexpected phase")
      }
      root.phase++
    }
  }
  Timer {
    interval: 30; repeat: true; running: root.phase === 22
    onTriggered: {
      root.check(++root.ticks < 240, "final cleanup deadline")
      if (root.power.busyWorkers) return
      root.check(root.power.profileConsumers === 0 && root.power.detailConsumers === 0,
        "view destruction leaked leases")
      console.log("power runtime smoke passed")
      Qt.exit(0)
    }
  }
}
