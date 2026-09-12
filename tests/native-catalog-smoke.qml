pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "catalog" as Catalog
import "catalog/NativeCatalogModel.js" as Model

Scope {
  id: root
  property int stage: 0
  property int ticks: 0
  property int savedSerial: 0
  property int savedCalls: 0
  property var savedSnapshot: null
  property bool revokeReady: false
  property bool revokeBusy: false
  property bool reenterSerial: false
  property var invalidPayloads: []
  property int invalidIndex: 0
  property var dyingBackend: null
  Component {
    id: transientFactory
    QtObject {
      property var busy: false
      property int serial: 0
      property int calls: 0
      property bool cancelThrows: false
      property int cancelErrors: 0
      signal completed(int serial, string output, bool ok)
      signal drained(int serial)
      function start(value) { serial = value; calls++; busy = true; return true }
      function cancel() {
        if (cancelThrows) { cancelErrors++; throw new Error("fixture cancel failure") }
        if (typeof busy === "boolean") busy = false
      }
    }
  }
  QtObject { id: firstOwner }
  QtObject { id: secondOwner }
  QtObject { id: incomplete }
  QtObject {
    id: transport
    property bool busy: false
    property int serial: 0
    property int calls: 0
    property bool inline: false
    property bool optimistic: false
    property bool deferDrain: false
    signal completed(int serial, string output, bool ok)
    signal drained(int serial)
    function start(value) {
      if (busy) return false
      serial = value
      calls++
      busy = true
      if (inline) {
        finish(root.payload(), true)
        optimistic = catalog.ready
      }
      return true
    }
    function cancel() { busy = false; if (!deferDrain) drained(serial) }
    function finish(raw, ok) {
      busy = false
      completed(serial, raw, ok)
      if (!deferDrain) drained(serial)
    }
  }
  QtObject {
    id: secondTransport
    property var busy: false
    property int serial: 0
    property int calls: 0
    signal completed(int serial, string output, bool ok)
    signal drained(int serial)
    function start(value) {
      serial = value; calls++
      completed(serial, root.payload(), true)
      drained(serial)
      return true
    }
    function cancel() { drained(serial) }
  }
  Catalog.NativeCatalog {
    id: catalog
    admitted: true
    sourceToken: firstOwner
    shellDirectory: "/nonexistent-native-catalog/shell"
    backendOverride: transport
    onReadyChanged: if (ready && root.revokeReady) admitted = false
    onRefreshingChanged: if (refreshing && root.revokeBusy) admitted = false
    onRequestSerialChanged: if (root.reenterSerial) {
      root.reenterSerial = false
      root.savedSerial = requestSerial + 1
      root.assert(catalog.refresh(), "nested request refused")
    }
  }

  function assert(value, message) {
    if (value) return
    console.error("native-catalog-smoke:", stage, message)
    Qt.exit(1)
    throw new Error(message)
  }
  function row(id, source) {
    return { id: id, name: id, kinds: ["bar-widget"], enabled: true, active: false,
      canDisable: true, firstParty: false, clonedFrom: source || "",
      description: "Description for " + id, author: "Fixture", version: "1.0.0",
      tags: ["fixture", id], barWidget: { displayName: id,
        description: "Widget " + id, category: "Fixture",
        semanticCapabilities: [], defaultSection: "right", allowMultiple: false } }
  }
  function payload() { return JSON.stringify([row("omarchy.audio"), row("user.audio", "omarchy.audio")]) }
  function bad(mutator) {
    var value = [row("omarchy.audio")]
    mutator(value[0], value)
    return Model.normalize(value) === null
  }
  function modelCases() {
    var parsed = Model.parse(payload())
    assert(parsed && parsed.catalogKind === "native-listPlugins", "valid catalog refused")
    assert(!("installedPlugins" in parsed) && !Model.entry(parsed, "constructor"), "fabricated registry or inherited entry")
    assert(JSON.stringify(Model.ancestry(parsed, "user.audio")) === '["user.audio","omarchy.audio"]', "ancestry failed")
    assert(Model.parse("[]") !== null, "empty ready catalog refused")
    assert(bad(function(_, a) { a.push(a[0]) }), "duplicate catalog admitted")
    for (var flag of ["enabled", "active", "canDisable", "firstParty"])
      assert(bad(function(r) { r[flag] = 1 }), "numeric Boolean admitted")
    assert(bad(function(r) { delete r.clonedFrom }), "missing ancestry field admitted")
    assert(bad(function(r) { r.manifest = {} }), "foreign manifest field admitted")
    assert(bad(function(r) { r.id = "a".repeat(161) }), "overlong id admitted")
    assert(bad(function(r) { r.id = "__proto__" }), "unsafe id admitted")
    assert(bad(function(r) { r.id = "a..b" }), "path id admitted")
    assert(bad(function(r) { r.name = "bad\nname" }), "control name admitted")
    assert(bad(function(r) { r.name = "\ud800" }), "surrogate admitted")
    assert(!bad(function(r) { r.name = "🌲".repeat(256) }), "UTF16 boundary refused")
    assert(bad(function(r) { r.name = "🌲".repeat(256) + "a" }), "UTF16 overbound admitted")
    assert(bad(function(r) { r.kinds = [] }), "empty kinds admitted")
    assert(bad(function(r) { r.kinds = ["service", "service"] }), "duplicate kind admitted")
    assert(bad(function(r) { r.kinds = ["bar"]; r.active = false; r.enabled = false }), "bar disable admitted")
    assert(!bad(function(r) { r.kinds = ["bar"]; r.active = true; r.canDisable = false }), "valid active bar refused")
    assert(Model.parse("x" + payload()) === null && Model.parse("\ufeff" + payload()) === null, "invalid framing admitted")
    var quoted = row("quoted")
    quoted.name = 'String containing {"id":1,"id":2} and \\"escaped\\" brackets []'
    assert(Model.parse(JSON.stringify([quoted])) !== null, "quoted data mistaken for duplicate keys")
    assert(Model.uniqueKeys("[".repeat(8) + "]".repeat(8))
      && !Model.uniqueKeys("[".repeat(9) + "]".repeat(9)), "structural depth bound failed")
    var padded = payload() + " ".repeat(Model.MaximumText - payload().length)
    assert(Model.parse(padded) && Model.parse(padded + " ") === null, "raw text boundary ignored")
    var rows = []
    for (var i = 0; i < 512; i++) rows.push(row("p" + i))
    assert(Model.normalize(rows) !== null, "512 entries refused")
    rows.push(row("overflow"))
    assert(Model.normalize(rows) === null, "513 entries admitted")
    rows = []
    for (var j = 0; j < 32; j++) rows.push(row("p" + j, j < 31 ? "p" + (j + 1) : ""))
    assert(Model.ancestry(Model.normalize(rows), "p0").length === 32, "32-entry ancestry refused")
    rows[31].clonedFrom = "p32"; rows.push(row("p32"))
    assert(Model.ancestry(Model.normalize(rows), "p0") === null, "33-entry ancestry admitted")
    rows[31].clonedFrom = "p0"
    assert(Model.ancestry(Model.normalize(rows), "p0") === null, "cycle admitted")
    assert(Model.ancestry(Model.normalize([row("p", "missing")]), "p") === null, "missing source admitted")
    assert(Model.ancestry(Model.normalize([row("p", "constructor")]), "p") === null, "inherited constructor source admitted")
    rows = [row("constructor", "omarchy.audio"), row("omarchy.audio")]
    parsed = Model.normalize(rows)
    assert(Model.ancestry(parsed, "constructor").length === 2, "own constructor source refused")
    rows[0].name = "changed"; rows[0].kinds.push("bar")
    assert(parsed.entries[0].name === "constructor" && parsed.entries[0].kinds.length === 1
      && Object.isFrozen(parsed.byId) && Object.isFrozen(parsed.entries[0].kinds), "snapshot was not detached/frozen")
  }

  Timer {
    interval: 10; repeat: true; running: true
    onTriggered: {
      root.ticks++
      switch (root.stage) {
      case 0:
        root.modelCases()
        root.assert(!catalog.nativeConstructed && !catalog.ready && transport.calls === 0, "inactive work")
        catalog.demand = true
        root.stage = 1; break
      case 1:
        if (!transport.busy) break
        root.assert(catalog.refreshing && !catalog.ready && !catalog.refresh(), "pending request not serialized")
        root.assert(!catalog.nativeConstructed, "explicit override constructed native")
        transport.busy = false
        transport.completed(transport.serial + 1, root.payload(), true)
        transport.drained(transport.serial)
        root.stage = 2; break
      case 2:
        root.assert(!catalog.ready && catalog.snapshot === null, "future result became ready")
        root.assert(catalog.refresh(), "wrong-serial recovery refused")
        transport.finish(root.payload(), true)
        root.stage = 3; break
      case 3:
        if (catalog.refreshing) break
        root.assert(catalog.ready && catalog.observation().serial === transport.serial, "valid result not published")
        root.savedSnapshot = catalog.snapshot
        root.assert(catalog.refresh(), "repeat refresh refused")
        root.assert(catalog.ready, "periodic refresh erased valid display")
        transport.finish(root.payload(), true)
        root.stage = 4; break
      case 4:
        if (catalog.refreshing) break
        root.assert(catalog.snapshot === root.savedSnapshot, "unchanged read rebuilt snapshot")
        root.invalidPayloads = ['[{}]',
          root.payload().replace('"id":"omarchy.audio"', '"id":"other","id":"omarchy.audio"'),
          root.payload().replace('"enabled":true', '"enabled":false,"enabled":true'),
          root.payload().replace('"id":"omarchy.audio"', '"\\u0069d":"other","id":"omarchy.audio"'),
          root.payload().replace('"name":"omarchy.audio"', '"name":{"key":1,"key":2}')]
        root.invalidIndex = 0
        root.assert(catalog.refresh(), "malformed refresh refused")
        transport.finish(root.invalidPayloads[root.invalidIndex], true)
        root.stage = 5; break
      case 5:
        if (catalog.refreshing) break
        root.assert(!catalog.ready && catalog.observation() === null && catalog.snapshot === null, "malformed override became ready")
        root.invalidIndex++
        if (root.invalidIndex < root.invalidPayloads.length) {
          root.assert(catalog.refresh(), "next malformed refresh refused")
          transport.finish(root.invalidPayloads[root.invalidIndex], true)
          break
        }
        root.assert(catalog.refresh(), "scope probe refused")
        root.savedSerial = transport.serial
        catalog.sourceToken = secondOwner
        transport.completed(root.savedSerial, root.payload(), true)
        root.stage = 6; break
      case 6:
        root.assert(!catalog.ready, "old owner result published")
        if (!transport.busy || transport.serial === root.savedSerial) break
        transport.finish(root.payload(), true)
        root.stage = 7; break
      case 7:
        if (catalog.refreshing) break
        root.assert(catalog.ready, "new owner did not recover")
        catalog.demand = false
        root.stage = 8; break
      case 8:
        root.assert(!catalog.ready && catalog.snapshot === null && !catalog.refreshing, "loss retained readiness")
        root.savedCalls = transport.calls
        catalog.backendOverride = incomplete
        catalog.demand = true
        root.stage = 9; break
      case 9:
        root.assert(!catalog.backendSupported && !catalog.ready && !catalog.nativeConstructed
          && transport.calls === root.savedCalls, "incomplete fake fell through")
        catalog.backendOverride = ({ start: function() { throw new Error("must not call") } })
        root.stage = 10; break
      case 10:
        root.assert(!catalog.backendSupported && !catalog.nativeConstructed, "plain fake fell through")
        catalog.demand = false
        catalog.backendOverride = transport
        transport.inline = true
        catalog.demand = true
        root.stage = 11; break
      case 11:
        if (catalog.refreshing || !catalog.ready) break
        root.assert(!transport.optimistic, "inline result published inside start")
        catalog.demand = false
        transport.inline = false
        root.revokeBusy = true
        root.savedCalls = transport.calls
        catalog.demand = true
        root.stage = 12; break
      case 12:
        root.assert(!catalog.ready && transport.calls === root.savedCalls, "busy revocation dispatched")
        root.revokeBusy = false
        catalog.admitted = true
        root.stage = 13; break
      case 13:
        if (!transport.busy) break
        root.revokeReady = true
        transport.finish(root.payload(), true)
        root.stage = 14; break
      case 14:
        root.assert(!catalog.ready && !catalog.observation() && !catalog.refreshing, "ready revocation republished")
        root.revokeReady = false
        catalog.admitted = true
        root.stage = 15; break
      case 15:
        if (!transport.busy) break
        transport.finish(root.payload(), true)
        root.stage = 16; break
      case 16:
        if (catalog.refreshing) break
        root.reenterSerial = true
        root.assert(!catalog.refresh(), "older serial request was accepted")
        root.assert(transport.serial === root.savedSerial && catalog.requestSerial === root.savedSerial,
          "older request replaced nested serial")
        transport.finish(root.payload(), true)
        root.stage = 17; break
      case 17:
        if (catalog.refreshing) break
        root.assert(catalog.ready && catalog.readSerial === root.savedSerial, "nested request did not settle")
        transport.deferDrain = true
        root.assert(catalog.refresh(), "delayed drain request refused")
        root.savedSerial = transport.serial
        root.savedCalls = transport.calls
        transport.finish(root.payload(), true)
        root.stage = 18; break
      case 18:
        root.assert(catalog.refreshing && catalog.readSerial !== root.savedSerial
          && !catalog.refresh() && transport.calls === root.savedCalls, "completion bypassed drain")
        catalog.admitted = false
        root.stage = 19; break
      case 19:
        root.assert(!catalog.ready && catalog.refreshing, "revocation bypassed drain")
        catalog.admitted = true
        root.stage = 20; break
      case 20:
        root.assert(transport.calls === root.savedCalls && !catalog.refresh(), "reentry reused undrained backend")
        transport.deferDrain = false
        transport.drained(root.savedSerial)
        root.stage = 21; break
      case 21:
        if (!transport.busy) break
        root.assert(transport.serial > root.savedSerial, "new request not reserved after drain")
        transport.finish(root.payload(), true)
        root.stage = 22; break
      case 22:
        if (catalog.refreshing) break
        root.assert(catalog.ready, "drained backend did not recover")
        transport.deferDrain = true
        root.assert(catalog.refresh(), "ABA request refused")
        root.savedSerial = transport.serial
        root.savedCalls = transport.calls
        transport.finish(root.payload(), true)
        catalog.backendOverride = secondTransport
        root.stage = 23; break
      case 23:
        root.assert(secondTransport.calls === 0 && catalog.refreshing, "replacement bypassed prior drain")
        catalog.backendOverride = transport
        root.stage = 24; break
      case 24:
        root.assert(transport.calls === root.savedCalls && !catalog.refresh(), "ABA reused undrained backend")
        catalog.backendOverride = secondTransport
        transport.deferDrain = false
        transport.drained(root.savedSerial)
        root.stage = 25; break
      case 25:
        if (catalog.refreshing || !catalog.ready) break
        root.assert(secondTransport.calls === 1, "old backend drain was disconnected")
        secondTransport.busy = "unknown"
        root.stage = 31; break
      case 31:
        root.assert(!catalog.backendSupported && !catalog.ready && catalog.observation() === null
          && !catalog.nativeConstructed, "incomplete backend retained authority")
        secondTransport.busy = false
        root.stage = 32; break
      case 32:
        if (catalog.refreshing || !catalog.ready) break
        root.assert(secondTransport.calls === 2, "completed backend did not recover")
        catalog.backendOverride = transport
        root.stage = 26; break
      case 26:
        if (!transport.busy) break
        transport.finish(root.payload(), true)
        root.stage = 27; break
      case 27:
        if (catalog.refreshing) break
        root.assert(catalog.ready && transport.calls === root.savedCalls + 1, "ABA recovery failed")
        root.savedCalls = transport.calls
        root.assert(catalog.requestRefresh() && catalog.requestRefresh()
          && transport.calls === root.savedCalls, "queued refresh dispatched synchronously")
        root.stage = 28; break
      case 28:
        if (!transport.busy) break
        root.assert(transport.calls === root.savedCalls + 1, "hint burst duplicated read")
        root.assert(catalog.requestRefresh() && catalog.requestRefresh(), "busy refresh intent lost")
        transport.finish(root.payload(), true)
        root.stage = 29; break
      case 29:
        if (!transport.busy) break
        root.assert(transport.calls === root.savedCalls + 2, "queued follow-up count wrong")
        transport.finish(root.payload(), true)
        root.stage = 30; break
      case 30:
        if (catalog.refreshing) break
        root.assert(catalog.ready && transport.calls === root.savedCalls + 2, "queued follow-up missing")
        root.dyingBackend = transientFactory.createObject(root)
        catalog.backendOverride = root.dyingBackend
        root.stage = 33; break
      case 33:
        if (!root.dyingBackend.busy) break
        catalog.backendOverride = transport
        root.stage = 34; break
      case 34:
        root.assert(catalog.refreshing && !transport.busy, "live undrained object released early")
        root.dyingBackend.destroy()
        root.dyingBackend = null
        root.stage = 35; break
      case 35:
        if (!transport.busy) break
        transport.finish(root.payload(), true)
        root.stage = 36; break
      case 36:
        if (catalog.refreshing) break
        root.assert(catalog.ready, "destroyed backend blocked replacement")
        root.dyingBackend = transientFactory.createObject(root)
        catalog.backendOverride = root.dyingBackend
        root.stage = 37; break
      case 37:
        if (!root.dyingBackend.busy) break
        root.dyingBackend.busy = "unknown"
        root.assert(!catalog.backendSupported && !catalog.ready, "active malformed backend kept authority")
        catalog.backendOverride = transport
        root.dyingBackend.drained(root.dyingBackend.serial)
        root.stage = 38; break
      case 38:
        if (!transport.busy) break
        root.dyingBackend.destroy()
        root.dyingBackend = null
        transport.finish(root.payload(), true)
        root.stage = 39; break
      case 39:
        if (catalog.refreshing) break
        root.dyingBackend = transientFactory.createObject(root, {cancelThrows: true})
        catalog.backendOverride = root.dyingBackend
        root.stage = 40; break
      case 40:
        if (!root.dyingBackend.busy) break
        try { catalog.invalidate() }
        catch (_) { root.assert(false, "throwing cancellation escaped invalidation") }
        root.assert(!catalog.ready && catalog.refreshing, "throwing cancellation counted as drain")
        catalog.backendOverride = transport
        root.dyingBackend.drained(root.dyingBackend.serial)
        root.stage = 41; break
      case 41:
        if (!transport.busy) break
        root.dyingBackend.destroy()
        root.dyingBackend = null
        transport.finish(root.payload(), true)
        root.stage = 42; break
      case 42:
        if (catalog.refreshing) break
        root.dyingBackend = transientFactory.createObject(root, {cancelThrows: true})
        root.revokeBusy = true
        catalog.backendOverride = root.dyingBackend
        root.stage = 43; break
      case 43:
        if (catalog.refreshing) break
        root.assert(!catalog.admitted && !catalog.ready && root.dyingBackend.calls === 0
          && root.dyingBackend.cancelErrors > 0, "pre-start throwing revocation did not settle")
        root.revokeBusy = false
        catalog.backendOverride = transport
        root.dyingBackend.destroy()
        root.dyingBackend = null
        catalog.admitted = true
        root.stage = 44; break
      case 44:
        if (!transport.busy) break
        transport.finish(root.payload(), true)
        root.stage = 45; break
      case 45:
        if (catalog.refreshing) break
        root.assert(catalog.ready, "throwing backend recovery failed")
        catalog.demand = false
        root.assert(!catalog.requestRefresh(), "inactive refresh accepted")
        console.log("native catalog parsing/lifetime passed; no family or desktop acceptance")
        Qt.quit()
      }
    }
  }
  Timer { interval: 7000; running: true; onTriggered: root.assert(false, root.stage === 35 ? "destroyed backend blocked replacement"
      : root.stage === 38 ? "drained malformed backend blocked replacement"
      : "deadline at stage " + root.stage) }
}
