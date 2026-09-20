import QtQuick
import Quickshell
import "audio" as Audio
import "fixtures" as Fixtures
import "hancore.shibumi.state/runtime" as SuiteRuntime

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property var savedPanel: null
  property real originalRadius: 0
  property var audioManifest: ({id: "hancore.shibumi.audio",
    version: "0.1.1-beta.15", kinds: ["service", "bar-widget"]})
  function check(value, message) {
    if (value) return
    console.error("audio-runtime-smoke:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  QtObject {
    id: scopedHost
    property string pluginId: "hancore.shibumi.audio"
    property bool accepts: true
    property int calls: 0
    property int rawLookups: 0
    property string lastMethod: ""
    function serviceFor(id) { rawLookups++; return null }
    function summon(id, payload) {
      root.check(id === pluginId && payload === "", "wrong scoped summon")
      calls++; lastMethod = "summon"; return accepts
    }
    function hide(id) {
      root.check(id === pluginId, "wrong scoped hide")
      calls++; lastMethod = "hide"; return accepts
    }
    function toggle(id, payload) {
      root.check(id === pluginId && payload === "", "wrong scoped toggle")
      calls++; lastMethod = "toggle"; return accepts
    }
  }
  QtObject { id: stateHost; property string pluginId: "hancore.shibumi.state" }
  QtObject {
    id: tokenState
    property var config: ({presentation: {radius: "small"}})
  }
  SuiteRuntime.Provider {
    id: stateProvider
    pluginId: "hancore.shibumi.state"
    implementationVersion: "0.1.1-beta.15"
    owner: tokenState
    manifest: ({id: "hancore.shibumi.state", version: "0.1.1-beta.15", kinds: ["service"]})
  }
  Fixtures.AudioRuntimeBackend { id: backend }
  Audio.Service { id: service; nativeBackendOverride: backend }

  component LocalBar: QtObject {
    property var shell: scopedHost
    property bool vertical: false
    property int barSize: 35
    property int sizeHorizontal: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color background: "#111111"
    property color foreground: "#eeeeee"
    readonly property color barForeground: foreground
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: []
    function registerClickTarget(target) { clickTargets = clickTargets.concat([target]) }
    function unregisterClickTarget(target) {
      clickTargets = clickTargets.filter(function(item) { return item !== target })
    }
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
  }
  LocalBar { id: barA }
  LocalBar { id: barB; position: "bottom"; barSize: 45 }
  LocalBar { id: replacementBar; position: "bottom" }
  Item {
    width: 800; height: 100
    Audio.BarWidget { id: widgetA; bar: barA; settings: ({}) }
    Audio.BarWidget { id: widgetB; x: 300; bar: barB; settings: ({}) }
  }

  Timer {
    interval: 40
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      root.check(root.ticks < 130, "deadline at phase " + root.phase)
      if (root.phase === 0) {
        if (root.ticks < 3) return
        root.check(!service.backendAdmitted && !service.nativeBackendReady
          && !widgetA.audioReady && !widgetB.audioReady, "pre-injection backend activated")
        root.check(!service.nativeSetOutputVolume(0.7).ok
          && !service.openPanel() && scopedHost.calls === 0, "pre-injection action accepted")
        root.originalRadius = widgetA.tokens.pillRadius
        root.check(widgetA.tokens.stateService === null, "tokens had an unregistered State")
        service.shell = scopedHost
        root.phase++
      } else if (root.phase === 1) {
        root.check(!service.backendAdmitted && !service.nativeBackendReady,
          "host alone admitted backend")
        service.manifest = root.audioManifest
        stateProvider.host = stateHost
        root.phase++
      } else if (root.phase === 2) {
        if (!service.nativeBackendReady || !widgetA.audioReady || !widgetB.audioReady) return
        root.check(widgetA.tokens.stateService === tokenState
          && widgetB.tokens.stateService === tokenState
          && widgetA.tokens.pillRadius < root.originalRadius
          && widgetB.tokens.pillRadius === widgetA.tokens.pillRadius
          && widgetA.tokens.barHeight === barA.barSize && widgetB.tokens.barHeight === barB.barSize
          && widgetA.tokens.paper === barA.background, "late State tokens or local bar geometry lost")
        root.check(widgetA.audioStateService === service && widgetB.audioStateService === service
          && scopedHost.rawLookups === 0 && service.reports.length === 2,
          "widgets did not share admitted owner without raw fallback")
        root.check(service.openPanel() && scopedHost.lastMethod === "summon"
          && service.closePanel() && scopedHost.lastMethod === "hide"
          && service.togglePanel() && scopedHost.lastMethod === "toggle", "scoped presentation route")
        scopedHost.accepts = false
        root.check(!service.openPanel() && !service.closePanel() && !service.togglePanel(),
          "scoped refusal became success")
        tokenState.config = {presentation: {radius: "normal"}}
        widgetA.open(); widgetB.open()
        root.phase++
      } else if (root.phase === 3) {
        if (!widgetA.panelLoaded || !widgetB.panelLoaded) return
        root.check(widgetA.tokens.pillRadius === root.originalRadius
          && widgetB.tokens.pillRadius === root.originalRadius,
          "State token mutation stayed stale")
        root.check(widgetA.panelItem.open && widgetB.panelItem.open
          && service.peakMonitorClients === 2, "two local panels did not lease one owner")
        const result = widgetA.panelItem.audioBackend.setOutputVolume(0.61)
        root.check(result.ok && Math.abs(backend.volume - 0.61) < 0.001,
          "panel action did not reach admitted fake backend")
        root.savedPanel = widgetA.panelItem
        widgetA.bar = replacementBar
        stateProvider.host = null
        root.phase++
      } else if (root.phase === 4) {
        root.check(widgetA.tokens.stateService === null && widgetB.tokens.stateService === null,
          "revoked State retained token authority")
        stateProvider.host = stateHost
        tokenState.config = {presentation: {radius: "small"}}
        root.check(widgetA.panelItem === root.savedPanel
          && widgetA.panelItem.bar === replacementBar && widgetA.panelItem.open
          && service.peakMonitorClients === 2, "open panel lost reactive bar/peak lease")
        widgetB.close()
        root.phase++
      } else if (root.phase === 5) {
        root.check(widgetA.tokens.stateService === tokenState
          && widgetB.tokens.stateService === tokenState
          && widgetA.tokens.pillRadius < root.originalRadius
          && widgetB.tokens.pillRadius === widgetA.tokens.pillRadius,
          "State token recovery stayed unavailable")
        root.check(!widgetB.panelLoaded && widgetA.panelLoaded
          && service.peakMonitorClients === 1, "closing sibling released wrong peak lease")
        service.shell = null
        root.phase++
      } else if (root.phase === 6) {
        root.check(!service.backendAdmitted && !service.nativeBackendReady
          && !widgetA.audioReady && !widgetA.panelLoaded
          && service.peakMonitorClients === 0 && service.reports.length === 0,
          "scope loss retained backend, panel or consumer")
        const volume = backend.volume
        root.check(!service.nativeSetOutputVolume(0.9).ok && backend.volume === volume
          && !service.acquirePeakMonitoring() && !service.openPanel(), "revoked owner still acted")
        service.shell = scopedHost
        root.phase++
      } else if (root.phase === 7) {
        if (!widgetA.audioReady) return
        root.check(service.reports.length === 2, "restored service reports missing")
        widgetA.open()
        root.phase++
      } else if (root.phase === 8) {
        if (!widgetA.panelLoaded) return
        root.check(service.peakMonitorClients === 1, "restored panel peak lease")
        backend.ready = false
        root.phase++
      } else if (root.phase === 9) {
        root.check(!widgetA.audioReady && !widgetA.panelLoaded
          && service.peakMonitorClients === 0, "backend disconnect retained panel work")
        backend.ready = true
        root.phase++
      } else {
        if (!widgetA.audioReady) return
        root.check(service.nativeBackendReady && !widgetA.opened
          && service.peakMonitorClients === 0, "backend reconnect reopened closed panel")
        service.shell = null
        console.log("audio runtime smoke passed")
        Qt.exit(0)
      }
    }
  }
}
