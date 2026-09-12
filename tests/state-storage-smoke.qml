import QtQuick
import Quickshell
import Quickshell.Io
import "state" as State

Item {
  id: root
  property int phase: 0
  property int ticks: 0
  property int calls: 0
  property string mode: "write"
  property var document: ({})
  property var saved: null
  property bool admitted: true
  property int cancellationTick: 0
  property var lease: fakeHost
  property var deferredDocument: null
  property int confirmations: 0
  property int confirmationsBefore: 0
  property bool revokeOnPending: false
  property bool revokeOnConfirmation: false
  property bool revokeOnValue: false
  property int overflowScope: 0
  QtObject { id: otherLease }
  Timer {
    id: delayedPublication
    interval: 150
    onTriggered: root.persist(root.deferredDocument)
  }
  function fail(message) { console.error("state-storage:", message); Qt.exit(1); throw new Error(message) }
  function check(value, message) { if (!value) fail(message) }
  function persist(value) { document = value; writer.setText(JSON.stringify(value)) }
  function publishOverflow() {
    const next = JSON.parse(JSON.stringify(saved))
    const scope = overflowScope % 3
    const target = scope === 0 ? next : scope === 1 ? next.plugins[0] : next.plugins[0].shibumi
    target.foreignOverflow = "__fixture_overflow__"
    const token = overflowScope < 3 ? "1e309" : overflowScope < 6 ? "-1e309" : "9".repeat(400)
    writer.setText(JSON.stringify(next).replace('"__fixture_overflow__"', token))
  }
  function change(group, key, value) {
    const next = storage.draft()
    if (!next.widgets[group]) next.widgets[group] = {}
    next.widgets[group][key] = value
    return storage.queue(next)
  }
  QtObject {
    id: fakeHost
    function updateEntryInline(id, entry) {
      root.calls++
      root.check(id === "hancore.shibumi.state", "foreign write")
      if (root.mode === "refuse") return false
      const next = JSON.parse(JSON.stringify(root.document))
      next.plugins[0] = entry
      if (root.mode === "queue-in-flight") {
        root.mode = "write"
        root.check(root.change("G6", "enabledV2", true), "in-flight setter refused")
      } else if (root.mode === "foreign-conflict") {
        root.check(root.change("G6", "enabledV2", false), "conflict follow-up not queued")
        next.plugins[0].concurrentForeignField = "preserve"
      } else if (root.mode === "delayed-false") {
        root.deferredDocument = next
        delayedPublication.start()
        return false
      } else if (root.mode === "revoke") {
        root.admitted = false
        return true
      }
      root.persist(next)
      return root.mode !== "converged"
    }
  }
  FileView {
    id: writer
    path: Quickshell.env("XDG_CONFIG_HOME") + "/omarchy/shell.json"
    atomicWrites: true
    printErrors: false
    onLoaded: { if (text().length) root.document = JSON.parse(text()) }
  }
  State.StateStorage {
    id: storage
    host: fakeHost
    authorityToken: root.lease
    enabled: root.admitted
    omarchyPath: Quickshell.env("OMARCHY_PATH")
    onPendingChanged: {
      if (pending && root.revokeOnPending) {
        root.revokeOnPending = false
        root.admitted = false
      }
    }
    onWriteStatusChanged: {
      if (writeStatus === "confirmed" && root.revokeOnConfirmation) {
        root.revokeOnConfirmation = false
        root.admitted = false
      }
    }
    onValueChanged: {
      if (root.revokeOnValue) {
        root.revokeOnValue = false
        root.admitted = false
      }
    }
    onSettled: function(serial, result) {
      if (result === "confirmed") root.confirmations++
    }
  }
  Timer {
    interval: 10; repeat: true; running: true
    onTriggered: {
      if (++root.ticks > 1000) root.fail("deadline phase " + root.phase + " status " + storage.writeStatus
        + " calls " + root.calls + " preparing " + storage._preparing
        + " flight " + (storage._flight !== null) + " entry " + JSON.stringify(storage._entry))
      if (root.phase === 0 && storage.ready && root.document.version === 1) {
        const before = JSON.stringify(storage.value)
        root.check(root.change("G4", "compact", true), "first request")
        root.check(root.change("G6", "enabledV2", false), "second request")
        root.check(JSON.stringify(storage.value) === before, "optimistic publication")
        const fresh = JSON.parse(JSON.stringify(root.document))
        fresh.plugins[0].foreignFuture = {keep: [1, false, "Malmö"]}
        root.persist(fresh)
        root.phase = 1
      } else if (root.phase === 1 && !storage.pending && storage.writeStatus === "confirmed") {
        root.check(root.calls === 1, "debounce did not coalesce")
        root.check(storage.value.widgets.G4.compact === true
          && storage.value.widgets.G6.enabledV2 === false, "rapid setter lost a key")
        root.check(root.document.plugins[0].foreignFuture.keep[2] === "Malmö", "fresh foreign field lost")
        root.check(root.document.plugins[1].opaque.value === 42, "other plugin changed")
        root.mode = "refuse"
        root.check(root.change("G4", "compact", false), "refused request not queued")
        root.phase = 2
      } else if (root.phase === 2 && !storage.pending && storage.writeStatus === "refused") {
        root.check(storage.value.widgets.G4.compact === true, "refusal published intent")
        root.mode = "converged"
        root.check(root.change("G4", "compact", false), "convergent request")
        root.phase = 3
      } else if (root.phase === 3 && !storage.pending && storage.writeStatus === "unchanged") {
        root.check(storage.value.widgets.G4.compact === false, "false return ignored matching readback")
        root.saved = JSON.parse(JSON.stringify(root.document))
        const corrupt = JSON.parse(JSON.stringify(root.document))
        corrupt.plugins[0].shibumiStateSchemaVersion = 2
        corrupt.bar.shibumi = {version: 1, widgets: {G4: {compact: true}}}
        root.persist(corrupt)
        root.phase = 4
      } else if (root.phase === 4 && !storage.ready) {
        root.check(!root.change("G4", "compact", true), "corrupt canonical allowed legacy write")
        root.persist(root.saved)
        root.phase = 5
      } else if (root.phase === 5 && storage.ready) {
        root.mode = "write"
        root.check(root.change("G4", "compact", true), "cancel request")
        root.admitted = false
        root.cancellationTick = root.ticks
        root.phase = 6
      } else if (root.phase === 6 && root.ticks > root.cancellationTick + 15) {
        root.check(root.calls === 3 && !storage.pending && !storage.ready, "revoked debounce dispatched")
        root.admitted = true
        root.phase = 7
      } else if (root.phase === 7 && storage.ready) {
        root.check(storage.value.widgets.G4.compact === false, "cancelled state revived")
        root.mode = "queue-in-flight"
        root.check(root.change("G4", "compact", true), "in-flight base request")
        root.phase = 8
      } else if (root.phase === 8 && !storage.pending && storage.writeStatus === "confirmed") {
        root.check(root.calls === 5 && storage.value.widgets.G4.compact === true
          && storage.value.widgets.G6.enabledV2 === true, "in-flight setter lost or unmerged")
        root.mode = "foreign-conflict"
        root.check(root.change("G4", "compact", false), "conflicting request")
        root.phase = 9
      } else if (root.phase === 9 && !storage.pending && storage.writeStatus === "conflict") {
        root.check(root.calls === 6 && storage.value.widgets.G6.enabledV2 === true
          && root.document.plugins[0].concurrentForeignField === "preserve", "conflict revived follow-up")
        root.mode = "delayed-false"
        root.check(root.change("G4", "compact", true), "delayed convergence request")
        root.phase = 10
      } else if (root.phase === 10 && !storage.pending && storage.writeStatus === "unchanged") {
        root.check(root.calls === 7 && storage.value.widgets.G4.compact === true,
          "delayed false result did not converge")
        root.mode = "revoke"
        root.confirmationsBefore = root.confirmations
        root.check(root.change("G4", "compact", false), "delegate revocation request")
        root.phase = 11
      } else if (root.phase === 11 && !root.admitted) {
        root.check(!storage.pending && !storage.ready && root.calls === 8
          && root.confirmations === root.confirmationsBefore, "revoked delegate settled")
        root.admitted = true
        root.phase = 12
      } else if (root.phase === 12 && storage.ready) {
        root.mode = "write"
        root.check(root.change("G4", "compact", false), "token revocation request")
        root.lease = otherLease
        root.cancellationTick = root.ticks
        root.phase = 13
      } else if (root.phase === 13 && storage.ready && root.ticks > root.cancellationTick + 15) {
        root.check(!storage.pending && root.calls === 8 && storage.value.widgets.G4.compact === true,
          "replacement token revived pending work")
        root.revokeOnPending = true
        root.check(!root.change("G4", "compact", false), "revoked queue reported acceptance")
        root.check(!storage.pending && !storage.ready, "revoked queue retained intent")
        root.admitted = true
        root.phase = 14
      } else if (root.phase === 14 && storage.ready) {
        root.confirmationsBefore = root.confirmations
        root.revokeOnConfirmation = true
        root.check(root.change("G4", "compact", false), "settlement revocation request")
        root.phase = 15
      } else if (root.phase === 15 && !root.admitted) {
        root.check(!storage.pending && !storage.ready && root.calls === 9
          && root.confirmations === root.confirmationsBefore, "revoked settlement published success")
        root.admitted = true
        root.phase = 16
      } else if (root.phase === 16 && storage.ready) {
        root.check(storage.value.widgets.G4.compact === false, "file truth lost after revocation")
        root.revokeOnValue = true
        root.check(root.change("G4", "compact", true), "value revocation request")
        root.phase = 17
      } else if (root.phase === 17 && !root.admitted) {
        root.check(!storage.pending && !storage.ready && root.calls === 10,
          "value callback republished revoked readiness")
        root.admitted = true
        root.phase = 18
      } else if (root.phase === 18 && storage.ready) {
        writer.setText("")
        root.phase = 19
      } else if (root.phase === 19 && storage.ready && storage._entry.defaultsSentinel === true) {
        root.check(root.calls === 10, "defaults fallback dispatched a write")
        root.saved = JSON.parse(JSON.stringify(root.document))
        root.publishOverflow()
        root.phase = 20
      } else if (root.phase === 20 && !storage.ready) {
        root.check(root.calls === 10 && !storage.pending && !root.change("G4", "compact", false),
          "overflow number admitted a write")
        root.persist(root.saved)
        root.phase = 21
      } else if (root.phase === 21 && storage.ready) {
        if (++root.overflowScope < 9) { root.publishOverflow(); root.phase = 20; return }
        console.log("state storage debounce/readback/refusal/convergence/revocation passed")
        Qt.exit(0)
      }
    }
  }
}
