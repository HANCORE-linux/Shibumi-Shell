import QtQuick

// Actual Bar restoration controller, explicit asynchronous State signals and
// inert output-local panels. No windows, helpers, native writes or host actions.
Item {
  id: root
  required property var bar
  required property var stateOwner
  property bool started: false
  property bool done: false
  property int phase: 0
  property double began: 0
  property var savedSlots: []
  readonly property string pluginId: "hancore.shibumi.control-center"

  function check(value, message) {
    if (value) return
    console.error("state-restore:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  component Panel: QtObject {
    property bool opened: false
    property bool panelLoaded: true
    property var panelItem: ({settingsPage: "bars"})
    property int opens: 0
    property var afterOpen: null
    function openPage(page) {
      opens++
      panelItem = {settingsPage: page}
      opened = true
      const action = afterOpen
      afterOpen = null
      if (action) action()
    }
    function open() { openPage("bars") }
    function close() { opened = false }
  }
  Panel { id: oldA; opened: true }
  Panel { id: oldB; opened: true }
  Panel { id: newA }
  Panel { id: newB }

  function queue(owner, screen) {
    return bar.runWithControlCenterRestore(function() {
      stateOwner.writeSerial++
      stateOwner.writePending = true
      return true
    }, "bars", true, owner, screen)
  }
  function settle(serial, result, changed, pending) {
    if (changed) stateOwner.revision++
    stateOwner.writePending = pending === true
    stateOwner.persistenceSettled(serial, result)
  }
  function cancel(owner, screen) { bar.cancelWidgetRestore(pluginId, owner, screen) }
  function pending(screen) { return bar.widgetRestorePendingForOutput(pluginId, null, screen) }
  function preflight() {
    bar.scheduleWidgetRestore(pluginId, "bars", false, oldA, "DP-A")
    const originalId = bar.pendingWidgetRestores[0].restoreId
    bar.pendingWidgetRestores[0].attempts = 19
    oldA.panelItem = {settingsPage: "icons"}
    check(!bar.runWithControlCenterRestore(function() { return false }, "icons", true, oldA, "DP-A"),
      "rejected callback accepted")
    let record = bar.pendingWidgetRestores[0]
    check(record.restoreId === originalId && record.attempts === 19
      && record.page === "bars" && !record.needsReplacement,
      "rejected callback changed an existing restore")
    let caught = false
    try {
      bar.runWithControlCenterRestore(function() { throw new Error("fixture callback") },
        "icons", true, oldA, "DP-A")
    } catch (error) { caught = true }
    record = bar.pendingWidgetRestores[0]
    check(caught && record.page === "bars" && !record.needsReplacement && record.attempts === 19,
      "throwing callback changed an existing restore")
    bar.runWithControlCenterRestore(function() {
      bar.trackWidgetRestorePage(pluginId, "health", oldA, "DP-A")
      return false
    }, "icons", true, oldA, "DP-A")
    record = bar.pendingWidgetRestores[0]
    check(record.page === "health", "rejection erased newer navigation")
    check(!record.needsReplacement && record.attempts === 19,
      "navigation retained rejected replacement or retry reset")
    bar.runWithControlCenterRestore(function() {
      cancel(oldA, "DP-A")
      bar.scheduleWidgetRestore(pluginId, "catalog", false, oldA, "DP-A")
      return false
    }, "icons", true, oldA, "DP-A")
    record = bar.pendingWidgetRestores[0]
    check(record.restoreId !== originalId && record.page === "catalog" && !record.needsReplacement,
      "rejection cancelled a newer restore identity")
    record.attempts = 19
    bar.scheduleWidgetRestore(pluginId, "bars", true, oldA, "DP-A")
    check(bar.pendingWidgetRestores[0].attempts === 0, "new handoff inherited expired retry window")
    cancel(oldA, "DP-A")
    oldA.panelItem = {settingsPage: "bars"}
    check(bar.runWithControlCenterRestore(function() {
      stateOwner.writeSerial++
      settle(stateOwner.writeSerial, "confirmed", true, false)
      return true
    }, "bars", true, oldA, "DP-A"), "synchronous confirmed request refused")
    record = bar.pendingWidgetRestores[0]
    check(record && record.restoreConfirmed && record.waitingWrites.length === 0,
      "synchronous settlement lost before enrollment")
    cancel(oldA, "DP-A")
    check(queue(oldA, "DP-A"), "Bar revocation request")
    bar.scheduleWidgetRestore("fixture.other", "", false, oldB, "DP-B")
    const serial = stateOwner.writeSerial
    bar.hostReady = false
    check(stateOwner.ready && bar.pendingWidgetRestores.length === 0,
      "Bar revocation with ready State retained restores")
    check(!queue(oldA, "DP-A") && stateOwner.writeSerial === serial,
      "revoked Bar admitted a callback")
    bar.hostReady = true
    settle(serial, "confirmed", true, false)
    check(bar.pendingWidgetRestores.length === 0, "recovered Bar revived old restore")
    // Overlapping outgoing/replacement owners still represent a single output.
    bar.moduleSlots = [
      {moduleName: pluginId, screenName: "", activeItem: oldA},
      {moduleName: pluginId, screenName: "", activeItem: oldB}
    ]
    oldA.panelItem = {settingsPage: "icons"}
    oldB.panelItem = {settingsPage: "health"}
    bar.scheduleWidgetRestore(pluginId, "bars", false, oldA, "")
    bar.pendingWidgetRestores[0].attempts = 19
    const refs = bar.scheduleOpenControlCenterRestores("bars", true, oldB, "", true)
    check(refs.length === 1 && bar.pendingWidgetRestores.length === 1
      && bar.pendingWidgetRestores[0].page === "health", "one output enrolled twice or lost preferred page")
    bar.cancelCreatedWidgetRestores(refs)
    record = bar.pendingWidgetRestores[0]
    check(record.page === "bars" && !record.needsReplacement && record.attempts === 19,
      "overlapping owners retained rejected provisional layer")
    cancel(oldA, "")
    check(!bar.runWithControlCenterRestore(function() { return false }, "bars", true, oldB, "")
      && bar.pendingWidgetRestores.length === 0, "rejected overlapping owners left a new restore")
    bar.moduleSlots = []
    oldA.panelItem = {settingsPage: "bars"}
    oldB.panelItem = {settingsPage: "bars"}
    stateOwner.writeSerial = 0 // Independent fake-State case; no outstanding request.
  }
  function start() {
    if (started) return
    started = true
    savedSlots = bar.moduleSlots
    bar.moduleSlots = []
    preflight()
    check(queue(oldA, "DP-A") && queue(oldB, "DP-B"), "requests not queued")
    bar.moduleSlots = [
      {moduleName: pluginId, screenName: "DP-A", activeItem: newA},
      {moduleName: pluginId, screenName: "DP-B", activeItem: newB}
    ]
    check(bar.pendingWidgetRestores.length === 2, "outputs shared a restore record")
    began = Date.now()
    poll.start()
  }
  Timer {
    id: poll
    interval: 10; repeat: true
    onTriggered: {
      root.check(Date.now() - root.began < 5000, "deadline phase " + root.phase)
      if (root.phase === 0) {
        if (Date.now() - root.began < 1800) return
        root.check(root.bar.pendingWidgetRestores.length === 2 && newA.opens === 0 && newB.opens === 0
          && root.bar.pendingWidgetRestores.every(record => record.attempts === 0),
          "pending write spent restore window or reopened a panel")
        root.settle(1, "confirmed", true, true)
        root.phase++
      } else if (root.phase === 1) {
        if (!newA.opened) return
        root.check(newB.opens === 0 && root.pending("DP-B"), "first settlement restored another output")
        newA.close(); root.cancel(newA, "DP-A")
        root.settle(2, "refused", false, false)
        root.check(root.bar.pendingWidgetRestores.length === 0, "refused request retained restore")
        root.bar.moduleSlots = []
        root.check(root.queue(oldA, "DP-A"), "no-op request")
        root.settle(3, "unchanged", false, false)
        root.check(!root.pending("DP-A"), "pure no-op retained restore")
        root.check(root.queue(oldA, "DP-A"), "revocation request")
        root.stateOwner.ready = false
        root.check(!root.pending("DP-A"), "revocation retained restore")
        root.stateOwner.ready = true
        root.settle(4, "confirmed", true, false)
        root.check(!root.pending("DP-A"), "old settlement revived restore")
        root.check(root.queue(oldA, "DP-A"), "user-close request")
        root.cancel(oldA, "DP-A")
        root.settle(5, "confirmed", true, false)
        root.check(!root.pending("DP-A"), "settlement revived user-closed panel")
        root.check(root.queue(oldA, "DP-A"), "first applied request")
        root.settle(6, "confirmed", true, false)
        root.check(root.queue(oldA, "DP-A"), "later refused request")
        root.settle(7, "refused", false, false)
        root.check(root.pending("DP-A"), "later refusal erased earlier applied restore")
        root.bar.moduleSlots = [{moduleName: root.pluginId, screenName: "DP-A", activeItem: newA}]
        root.phase++
      } else if (root.phase === 2) {
        if (!newA.opened) return
        root.check(newA.opens === 2 && newB.opens === 0, "confirmed restore did not resume")
        root.cancel(newA, "DP-A"); newA.close()
        newA.afterOpen = function() {
          root.cancel(newA, "DP-A")
          root.bar.scheduleWidgetRestore(root.pluginId, "bars", true, oldB, "DP-B")
        }
        root.bar.moduleSlots = [
          {moduleName: root.pluginId, screenName: "DP-A", activeItem: newA},
          {moduleName: root.pluginId, screenName: "DP-B", activeItem: newB}
        ]
        root.bar.scheduleWidgetRestore(root.pluginId, "bars", true, oldA, "DP-A")
        root.phase++
      } else if (root.phase === 3) {
        if (newA.opens < 3) return
        root.check(!root.pending("DP-A") && root.pending("DP-B"),
          "timer revived cancelled restore or lost reentrant scheduling")
        root.cancel(newB, "DP-B")
        root.bar.moduleSlots = root.savedSlots
        root.check(root.bar.pendingWidgetRestores.length === 0, "restore fixture did not clean up")
        root.done = true
        stop()
        console.log("asynchronous output-local State restoration passed")
      }
    }
  }
}
