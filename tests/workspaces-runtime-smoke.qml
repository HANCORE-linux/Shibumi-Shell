pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "workspaces" as Workspaces
import "hancore.shibumi.state/runtime" as SuiteRuntime

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property bool stateEnabled: false
  property var panelA: null
  property var panelB: null
  property var cachedFocus: null
  property var cachedPreference: null
  property int callsBeforeLoss: 0
  property int writesBeforeLoss: 0
  readonly property var validManifest: ({id: "hancore.shibumi.workspaces", version: "0.1.1-beta.12", kinds: ["service"]})
  function check(value, message) {
    if (value) return
    console.error("workspaces-runtime:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  QtObject {
    id: host
    property string pluginId: "hancore.shibumi.workspaces"
    function serviceFor(id) { root.check(false, "raw scoped lookup: " + id); return null }
  }
  QtObject { id: stateHost; property string pluginId: "hancore.shibumi.state" }
  QtObject {
    id: state
    property var config: ({workspace: {version: 1, mode: "5", style: "numbers"}, presentation: {radius: "small"}})
    property int writes: 0
    property color selectedColor: "#ef7777"
    function paletteColor(id) { return "#ef7777" }
    function setWorkspacePreference(key, value) {
      const next = JSON.parse(JSON.stringify(config))
      next.workspace[key] = value
      config = next
      writes++
      return true
    }
  }
  SuiteRuntime.Provider {
    pluginId: "hancore.shibumi.state"
    implementationVersion: "0.1.1-beta.12"
    owner: state
    host: root.stateEnabled ? stateHost : null
    manifest: ({id: "hancore.shibumi.state", version: "0.1.1-beta.12", kinds: ["service"]})
  }
  QtObject {
    id: backend
    property int calls: 0
    property var focusedWorkspace: ({id: 2})
    property var workspaces: [
      {id: 2, toplevels: {values: [{}]}},
      {id: 4, toplevels: {values: [{}, {}]}}
    ]
    function focusWorkspace(id) { calls++; return true }
  }
  Workspaces.WorkspaceService { id: service; backendOverride: backend }
  Workspaces.WorkspaceService { id: duplicate; backendOverride: backend }
  component LocalBar: QtObject {
    property var shell: host
    property bool vertical: false
    property int barSize: 28
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#181818"
    property color urgent: "#ef7777"
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
  Workspaces.BarWidget { id: widgetA; bar: barA }
  Workspaces.BarWidget { id: widgetB; bar: barB }

  function refused(message) {
    root.check(service.focusWorkspace(2) === false
      && service.setPreference("mode", "active") === false
      && (!cachedFocus || cachedFocus(2) === false)
      && (!cachedPreference || cachedPreference("mode", "active") === false)
      && backend.calls === callsBeforeLoss && state.writes === writesBeforeLoss,
      message)
  }
  function unavailable(message) {
    root.check(!widgetA.workspaceService && !widgetB.workspaceService
      && !widgetA.visible && !widgetB.visible
      && widgetA.implicitWidth === 0 && widgetB.implicitWidth === 0
      && !widgetA.opened && !widgetB.opened && !widgetA.panelItem && !widgetB.panelItem,
      message)
  }
  Timer {
    interval: 30; running: true; repeat: true
    onTriggered: {
      root.check(++root.ticks < 200, "phase deadline: " + root.phase)
      if (!SuiteRuntime.Runtime.ready) return
      if (root.phase === 0) {
        root.check(!service.backendAdmitted && service.backendOverride === backend,
          "premature admission or fake replacement lost")
        root.check(!("actionAdapter" in service) && !("workspaceSource" in service)
          && !("focusedWorkspaceSource" in service), "native backend deliberately exported")
        root.refused("pre-injection action accepted")
        root.unavailable("pre-injection widget or panel available")
        service.shell = host
      } else if (root.phase === 1) {
        root.check(!service.backendAdmitted, "host alone granted admission")
        root.refused("partial-injection action accepted")
        service.manifest = root.validManifest
      } else if (root.phase === 2) {
        if (!service.backendAdmitted) return
        root.check(widgetA.workspaceService === service && widgetB.workspaceService === service
          && !service.stateService && service.setPreference("mode", "active") === false,
          "shared owner or missing-State refusal")
        root.check(service.focusWorkspace(2) === true && backend.calls === 1,
          "admitted focus did not reach explicit fake")
        widgetA.open(); widgetB.open()
      } else if (root.phase === 3) {
        if (!widgetA.panelItem || !widgetB.panelItem) return
        root.panelA = widgetA.panelItem; root.panelB = widgetB.panelItem
        root.check(root.panelA !== root.panelB && root.panelA.bar === barA && root.panelB.bar === barB
          && root.panelA.anchorItem !== root.panelB.anchorItem
          && root.panelA.workspaceService === service && root.panelA.rows.length === 2,
          "actual panel body or output locality lost")
        root.stateEnabled = true
      } else if (root.phase === 4) {
        if (!service.stateService) return
        root.check(service.stateService === state && widgetA.stateService === state
          && widgetB.stateService === state && widgetA.tokens.stateService === state
          && widgetB.tokens.stateService === state, "late State/token injection lost")
        root.check(service.setPreference("style", "rings") === true && state.writes === 1,
          "preference not applied by controlled State")
        widgetA.bar = barC
      } else if (root.phase === 5) {
        root.check(widgetA.panelItem === root.panelA && widgetB.panelItem === root.panelB
          && root.panelA.bar === barC && root.panelB.bar === barB
          && widgetA.workspaceStyle === "rings" && widgetB.workspaceStyle === "rings",
          "open panel lost reactive local bar or preference")
        root.check(root.panelA.activateCursor() === true && backend.calls === 2,
          "actual panel focus action missed admitted fake")
      } else if (root.phase === 6) {
        root.check(!widgetA.opened && !widgetA.panelItem && widgetB.panelItem === root.panelB,
          "selective close lost sibling panel")
        widgetA.open()
        root.cachedFocus = service.focusWorkspace
        root.cachedPreference = service.setPreference
        root.callsBeforeLoss = backend.calls; root.writesBeforeLoss = state.writes
        service.shell = null
      } else if (root.phase === 7) {
        root.check(!service.backendAdmitted, "host loss retained admission")
        root.refused("cached scope-lost action reached backend or State")
        root.unavailable("scope loss retained local panel")
        service.shell = host
      } else if (root.phase === 8) {
        if (!service.backendAdmitted) return
        widgetA.open(); widgetB.open()
        duplicate.shell = host; duplicate.manifest = root.validManifest
      } else if (root.phase === 9) {
        root.check(!service.backendAdmitted && !duplicate.backendAdmitted,
          "duplicate selected an owner")
        root.refused("duplicate retained stale action authority")
        root.unavailable("duplicate retained panel")
        duplicate.manifest = null
      } else if (root.phase === 10) {
        if (!service.backendAdmitted) return
        root.check(widgetA.workspaceService === service && widgetB.workspaceService === service,
          "unique-owner recovery failed")
        service.manifest = {id: "hancore.shibumi.workspaces", version: "wrong", kinds: ["service"]}
      } else if (root.phase === 11) {
        root.check(!service.backendAdmitted, "invalid manifest retained owner")
        root.refused("invalid manifest retained cached action")
        service.manifest = root.validManifest
      } else if (root.phase === 12) {
        if (!service.backendAdmitted) return
        root.stateEnabled = false
      } else if (root.phase === 13) {
        root.check(service.backendAdmitted && !service.stateService
          && !widgetA.stateService && !widgetB.tokens.stateService
          && service.setPreference("mode", "active") === false && state.writes === root.writesBeforeLoss,
          "State revocation retained write authority")
        for (const id of [0, -1, 1.5, 10000, "1; reboot"])
          root.check(service.focusWorkspace(id) === false && backend.calls === root.callsBeforeLoss,
            "invalid ID reached fake backend")
        service.backendOverride = ({focusWorkspace: function(id) { backend.calls++; return true }})
        root.check(service.focusWorkspace(2) === false && backend.calls === root.callsBeforeLoss,
          "action-only override accepted")
        const throwing = {workspaces: [], focusedWorkspace: null}
        Object.defineProperty(throwing, "focusWorkspace", {get: function() { throw new Error("controlled getter") }})
        service.backendOverride = throwing
        root.check(service.focusWorkspace(2) === false && backend.calls === root.callsBeforeLoss,
          "throwing override did not refuse")
        service.backendOverride = ({workspaces: [], focusedWorkspace: null})
        root.check(service.focusWorkspace(2) === false && backend.calls === root.callsBeforeLoss,
          "incomplete explicit fake reached native action fallback")
        root.check(service.entries.length === 0 && service.focusedId === 0,
          "incomplete fake fell through to native models")
        console.log("workspaces runtime smoke passed")
        Qt.exit(0)
        return
      }
      root.phase++
    }
  }
}
