pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "catalog" as Catalog

Scope {
  id: root
  property int stage: 0
  property int calls: 0
  property int stageTicks: 0
  onStageChanged: stageTicks = 0
  property var first: null
  property var second: null
  property var token: null
  property var other: null
  property var observed: null
  property var duplicate: null
  property bool revokeCount: false
  Component { id: holderFactory; QtObject {} }
  QtObject {
    id: firstShell
    property string pluginId: "hancore.shibumi.control-center"
    property var barConfig: ({})
  }
  QtObject {
    id: secondShell
    property string pluginId: "hancore.shibumi.control-center"
    property var barConfig: ({})
  }
  QtObject { id: widgetRegistry; property int revision: 0 }
  QtObject { id: incomplete }
  QtObject {
    id: backend
    property bool busy: false
    property int serial: 0
    property int calls: 0
    signal completed(int serial, string output, bool ok)
    signal drained(int serial)
    function start(value) { if (busy) return false; serial = value; busy = true; calls++; return true }
    function cancel() { busy = false; drained(serial) }
    function finish() { busy = false; completed(serial, '[]', true); drained(serial) }
  }
  Catalog.PluginUpdateService {
    id: service
    barWidgetRegistry: widgetRegistry
    _catalogBackendOverride: backend
    onCatalogConsumerCountChanged: if (catalogConsumerCount > 0 && root.revokeCount) {
      root.revokeCount = false
      manifest = root.manifest(false)
    }
  }
  Component {
    id: duplicateFactory
    Catalog.PluginUpdateService {
      shell: firstShell
      manifest: root.manifest(true)
      _catalogBackendOverride: incomplete
    }
  }
  function manifest(valid) {
    return {id: "hancore.shibumi.control-center", version: valid ? "0.1.1-beta.14" : "invalid",
      kinds: ["service", "bar-widget"]}
  }
  function assert(value, message) {
    if (value) return
    console.error("catalog-service-smoke:", stage, message)
    Qt.exit(1)
    throw new Error(message)
  }
  function quiet() {
    assert(!service.catalogNativeConstructed && service.consumerCount === 0 && !service.running,
      "catalog interest started native fallback or update scan")
  }
  Timer {
    interval: 15; repeat: true; running: true
    onTriggered: {
      root.stageTicks++
      switch (root.stage) {
      case 0:
        root.quiet()
        root.assert(!service.available && service.catalogConsumerCount === 0 && backend.calls === 0,
          "unadmitted catalog started")
        root.first = holderFactory.createObject(root); root.second = holderFactory.createObject(root)
        root.token = service.acquireCatalogConsumer(root.first)
        root.other = service.acquireCatalogConsumer(root.second)
        root.assert(root.token && root.other && root.token !== root.other
          && service.acquireCatalogConsumer(root.first) === root.token && service.catalogConsumerCount === 2,
          "multiple consumer identities lost")
        root.assert(!service.requestCatalogRefresh(root.token) && !service.catalogObservation(root.token)
          && !service.requestCatalogRefresh({}), "interest became admission")
        root.assert(!("catalog" in service) && !("backend" in service)
          && !("installedPlugins" in service), "raw catalog authority exported")
        service.shell = firstShell
        root.stage = 1; break
      case 1:
        root.assert(!service.available && backend.calls === 0, "partial injection admitted")
        service.manifest = root.manifest(true)
        root.stage = 2; break
      case 2:
        if (!service.available) break
        root.assert(backend.calls === 0 && !service.catalogReady, "missing native path admitted")
        service._catalogBackendOverride = incomplete
        service.omarchyPath = "/fixture/catalog"
        root.stage = 3; break
      case 3:
        root.quiet()
        root.assert(backend.calls === 0 && !service.catalogReady, "incomplete override admitted")
        service._catalogBackendOverride = ({ start: function() { throw new Error("must not run") } })
        root.stage = 4; break
      case 4:
        root.quiet()
        root.assert(!service.catalogReady && backend.calls === 0, "plain override admitted")
        service._catalogBackendOverride = backend
        root.stage = 5; break
      case 5:
        if (!backend.busy) break
        root.quiet()
        backend.finish()
        root.stage = 6; break
      case 6:
        if (!service.catalogReady || service.catalogRefreshing) break
        root.observed = service.catalogObservation(root.token)
        root.assert(root.observed && root.observed.snapshot.entries.length === 0
          && service.catalogSnapshot === root.observed.snapshot
          && service.isCatalogObservationCurrent(root.other, root.observed)
          && !service.catalogObservation({}), "observation facade mismatch")
        root.calls = backend.calls
        root.assert(service.requestCatalogRefresh(root.token) && service.requestCatalogRefresh(root.other)
          && backend.calls === root.calls, "refresh not queued/coalesced")
        root.stage = 7; break
      case 7:
        if (!backend.busy) break
        root.assert(backend.calls === root.calls + 1, "same-turn refresh did not coalesce")
        root.assert(service.requestCatalogRefresh(root.token) && service.requestCatalogRefresh(root.other),
          "busy request lost intent")
        backend.finish()
        root.stage = 8; break
      case 8:
        if (!backend.busy) break
        root.assert(backend.calls === root.calls + 2, "busy follow-up not coalesced")
        backend.finish()
        root.stage = 9; break
      case 9:
        if (service.catalogRefreshing) break
        root.assert(service.catalogReady && !service.isCatalogObservationCurrent(root.token, root.observed),
          "old read identity survived publication")
        root.observed = service.catalogObservation(root.token)
        root.calls = backend.calls
        firstShell.barConfig = ({fixture: 1})
        root.stage = 10; break
      case 10:
        if (!backend.busy) {
          root.assert(root.stageTicks < 20, "public shell hint did not refresh")
          break
        }
        root.assert(backend.calls === root.calls + 1, "native hints failed to coalesce")
        backend.finish()
        root.stage = 27; break
      case 27:
        if (service.catalogRefreshing) break
        root.calls = backend.calls
        widgetRegistry.revision++
        root.stage = 28; break
      case 28:
        if (!backend.busy) {
          root.assert(root.stageTicks < 20, "widget hint did not refresh")
          break
        }
        root.assert(backend.calls === root.calls + 1, "widget hint did not coalesce")
        backend.finish()
        root.stage = 11; break
      case 11:
        if (service.catalogRefreshing) break
        root.assert(service.releaseCatalogConsumer(root.token) && service.catalogConsumerCount === 1
          && !service.catalogObservation(root.token) && service.catalogObservation(root.other),
          "selective release lost remaining reader")
        root.assert(service.requestCatalogRefresh(root.other), "remaining consumer cannot refresh")
        root.stage = 12; break
      case 12:
        if (!backend.busy) break
        root.observed = service.catalogObservation(root.other)
        service.shell = secondShell
        root.assert(!service.catalogObservation(root.other)
          && !service.isCatalogObservationCurrent(root.other, root.observed)
          && service.hasCatalogConsumer(root.other), "source loss retained observation or lost interest")
        backend.completed(backend.serial, '[]', true)
        root.stage = 13; break
      case 13:
        if (!backend.busy) break
        backend.finish()
        root.stage = 14; break
      case 14:
        if (!service.catalogReady || service.catalogRefreshing) break
        service.manifest = root.manifest(false)
        root.stage = 15; break
      case 15:
        root.assert(!service.available && !service.catalogObservation(root.other)
          && !service.requestCatalogRefresh(root.other) && service.catalogConsumerCount === 1,
          "provider loss retained read authority")
        root.calls = backend.calls
        service.manifest = root.manifest(true)
        root.stage = 16; break
      case 16:
        if (!backend.busy) break
        root.assert(backend.calls === root.calls + 1, "provider recovery did not refresh")
        backend.finish()
        root.stage = 17; break
      case 17:
        if (!service.catalogReady || service.catalogRefreshing) break
        root.duplicate = duplicateFactory.createObject(root)
        root.stage = 18; break
      case 18:
        root.assert(!service.available && !service.catalogObservation(root.other), "duplicate provider retained authority")
        root.duplicate.destroy()
        root.stage = 19; break
      case 19:
        if (!backend.busy) break
        backend.finish()
        root.stage = 20; break
      case 20:
        if (!service.catalogReady || service.catalogRefreshing) break
        root.second.destroy()
        root.stage = 21; break
      case 21:
        root.quiet()
        root.assert(service.catalogConsumerCount === 0 && !service.catalogReady
          && !service.hasCatalogConsumer(root.other), "destroyed last consumer retained catalog")
        root.calls = backend.calls
        firstShell.barConfig = ({fixture: 2}); secondShell.barConfig = ({fixture: 2})
        widgetRegistry.revision++
        root.stage = 22; break
      case 22:
        root.assert(backend.calls === root.calls, "hints acquired hidden demand")
        root.revokeCount = true
        root.token = service.acquireCatalogConsumer(root.first)
        root.stage = 23; break
      case 23:
        root.assert(root.token && service.hasCatalogConsumer(root.token) && !service.available
          && backend.calls === root.calls, "reentrant admission loss dispatched")
        service.releaseCatalogConsumer(root.token)
        service.manifest = root.manifest(true)
        root.stage = 24; break
      case 24:
        if (!service.available) break
        root.assert(service.acquireConsumer(), "inert update scan refused")
        root.token = service.acquireCatalogConsumer(root.first)
        root.stage = 25; break
      case 25:
        if (!backend.busy) break
        root.assert(service.running && service.consumerCount === 1, "catalog stopped update scanner")
        service.releaseCatalogConsumer(root.token)
        root.assert(service.running && service.consumerCount === 1 && !service.cancellationRequested,
          "catalog release cancelled update scanner")
        root.stage = 26; break
      case 26:
        if (service.running) break
        root.assert(service.checked && service.error === "" && service.catalogConsumerCount === 0,
          "separate update scan did not finish")
        service.releaseConsumer()
        root.first.destroy()
        console.log("production catalog service leases/admission/hints passed; inert backend")
        Qt.quit()
      }
    }
  }
  Timer { interval: 8000; running: true; onTriggered: root.assert(false, "deadline") }
}
