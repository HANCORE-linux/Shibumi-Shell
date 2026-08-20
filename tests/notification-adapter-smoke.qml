import QtQuick
import Quickshell
import "status" as Status

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property bool focused: false

  function fail(message) {
    console.error("notification-adapter-smoke:", message)
    Qt.exit(1)
  }

  ListModel {
    id: hostPopupModel

    ListElement {
      originalId: 7
      app: "Adapter fixture"
      appIcon: ""
      summary: "Current notification"
      body: "Primitive host row"
      image: ""
      glyph: ""
      exec: ""
      urgency: 1
      expireTimeout: 8000
      timestamp: 100
    }
  }

  ListModel {
    id: legacyPendingModel

    ListElement {
      originalId: 17
      app: "Legacy fixture"
      appIcon: ""
      summary: "Legacy pending"
      body: "Legacy model row"
      image: ""
      urgency: 1
      expireTimeout: 8000
      timestamp: 200
    }
  }

  ListModel {
    id: legacyPastModel

    ListElement {
      originalId: 18
      app: "Legacy fixture"
      appIcon: ""
      summary: "Legacy recent"
      body: "Legacy history row"
      image: ""
      urgency: 1
      expireTimeout: 0
      timestamp: 201
    }
  }

  QtObject {
    id: fakeHost

    property var popupModel: hostPopupModel
    property bool doNotDisturb: false
    property int dismissCount: 0
    property int clearCount: 0
    property bool delayHistory: false
    property bool historyQueued: false
    property double replayTimestamp: 0
    property string focusedSummary: ""

    function setDoNotDisturb(value) {
      doNotDisturb = value === true
    }

    function dismissPopup(index) {
      if (index < 0 || index >= popupModel.count) return
      dismissCount++
      popupModel.remove(index)
    }

    function clearPopups() {
      clearCount++
      popupModel.clear()
    }

    function replayHistory() {
      // Simulate a notification arriving after replay was requested but before
      // the host clears and rebuilds its popup model.
      popupModel.append({
        id: 21, originalId: 21, app: "Adapter fixture", appIcon: "",
        summary: "Late live notification", body: "Arrived during replay",
        image: "", glyph: "", exec: "", urgency: 1,
        expireTimeout: 8000,
        timestamp: replayTimestamp || Date.now()
      })
      popupModel.clear()
      popupModel.append({
        id: 19, originalId: 19, app: "Adapter fixture", appIcon: "",
        summary: "History notification", body: "Saved during DND",
        image: "", glyph: "", exec: "", urgency: 1,
        expireTimeout: 0, timestamp: 300
      })
    }

    function showRecentHistory() {
      replayTimestamp = Date.now()
      if (delayHistory) {
        historyQueued = true
        return
      }
      replayHistory()
    }

    function finishHistoryReplay() {
      if (!historyQueued) return
      historyQueued = false
      replayHistory()
    }

    function focusApp(entry) {
      focusedSummary = String(entry && entry.summary || "")
    }
  }

  QtObject {
    id: fakeShell

    function firstPartyServiceFor(_id) {
      return fakeHost
    }
  }

  Status.NotificationAdapter {
    id: adapter
  }

  Status.NotificationAdapter {
    id: unavailableAdapter
  }

  QtObject {
    id: legacyHost

    property var popupModel: hostPopupModel
    property var pendingModel: legacyPendingModel
    property var pastModel: legacyPastModel
  }

  QtObject {
    id: legacyShell

    function firstPartyServiceFor(_id) {
      return legacyHost
    }
  }

  Status.NotificationAdapter {
    id: legacyAdapter
  }

  Component.onCompleted: {
    adapter.attachShell(fakeShell)
    legacyAdapter.attachShell(legacyShell)
    unavailableAdapter.attachShell(null)
  }

  Timer {
    interval: 20
    repeat: true
    running: true

    onTriggered: {
      root.ticks++
      if (root.phase === 0) {
        if (root.ticks < 3 || adapter.pendingModel.count !== 1) return
        const row = adapter.pendingModel.get(0)
        if (!adapter.available || !adapter.historyAvailable
            || adapter.pastModel.count !== 0
            || row.summary !== "Current notification"
            || row.body !== "Primitive host row"
            || adapter.pendingCount !== 1
            || legacyAdapter.pendingModel.count !== 1
            || legacyAdapter.pendingModel.get(0).summary
              !== "Legacy pending"
            || legacyAdapter.pastModel.count !== 1
            || legacyAdapter.pastModel.get(0).summary
              !== "Legacy recent"
            || unavailableAdapter.available
            || unavailableAdapter.pendingModel.count !== 0)
          return root.fail("current host popup was not normalized")
        hostPopupModel.append({
          id: -1, originalId: -1, app: "omarchy-action", appIcon: "",
          summary: "No recent notifications", body: "", image: "",
          urgency: 0, expireTimeout: 0, timestamp: Date.now()
        })
        if (adapter.pendingModel.count !== 1)
          return root.fail("host history sentinel leaked into live rows")
        hostPopupModel.remove(hostPopupModel.count - 1)
        legacyPastModel.append({
          originalId: 20, app: "Legacy fixture", appIcon: "",
          summary: "Legacy appended", body: "Updated history", image: "",
          urgency: 1, expireTimeout: 0, timestamp: 202
        })
        adapter.attachShell(null)
        root.phase = 1
        root.ticks = 0
      } else if (root.phase === 1) {
        if (adapter.available || adapter.pendingModel.count !== 0
            || legacyAdapter.pastModel.count !== 2) return
        adapter.attachShell(fakeShell)
        root.phase = 2
        root.ticks = 0
      } else if (root.phase === 2) {
        if (adapter.pendingModel.count !== 1) return
        hostPopupModel.append({
          id: 8, originalId: 8, app: "Adapter fixture", appIcon: "",
          summary: "Second notification", body: "Updated model",
          image: "", glyph: "", exec: "", urgency: 1,
          expireTimeout: 8000, timestamp: 101
        })
        root.phase = 3
        root.ticks = 0
      } else if (root.phase === 3) {
        if (adapter.pendingModel.count !== 2) return
        if (!adapter.setDoNotDisturb(true) || !adapter.doNotDisturb
            || !adapter.dismissPending(0) || fakeHost.dismissCount !== 1) {
          return root.fail("DND or pending dismiss bypassed the host adapter")
        }
        root.phase = 4
        root.ticks = 0
      } else if (root.phase === 4) {
        if (adapter.pendingModel.count !== 1) return
        if (!adapter.focusApp(adapter.pendingModel.get(0))
            || fakeHost.focusedSummary !== "Second notification"
            || !adapter.clearPending() || fakeHost.clearCount !== 1) {
          return root.fail("focus or clear action bypassed the host adapter")
        }
        root.phase = 5
        root.ticks = 0
      } else if (root.phase === 5) {
        if (adapter.pendingModel.count !== 0) return
        if (!adapter.showHistory())
          return root.fail("host history action was not exposed")
        root.phase = 6
        root.ticks = 0
      } else if (root.phase === 6) {
        if (adapter.pastModel.count !== 1) return
        if (adapter.pastModel.get(0).summary !== "History notification"
            || adapter.pendingModel.count !== 1
            || adapter.pendingModel.get(0).summary
              !== "Late live notification")
          return root.fail("late live row was lost during history replay")
        hostPopupModel.append({
          id: 20, originalId: 20, app: "Adapter fixture", appIcon: "",
          summary: "New live notification", body: "Arrived after history",
          image: "", glyph: "", exec: "", urgency: 1,
          expireTimeout: 8000, timestamp: Date.now()
        })
        root.phase = 7
        root.ticks = 0
      } else if (root.phase === 7) {
        if (adapter.pendingModel.count !== 2
            || adapter.pendingModel.get(1).summary
              !== "New live notification"
            || adapter.pastModel.count !== 1) return
        if (!adapter.dismissPending(0)
            || adapter.pendingModel.count !== 1
            || adapter.pendingModel.get(0).summary
              !== "New live notification")
          return root.fail("late live row was resurrected after dismiss")
        if (!adapter.pastDismissAvailable || !adapter.dismissPast(0)
            || adapter.pastModel.count !== 0)
          return root.fail("current-host history dismiss was not reflected")
        if (!adapter.clearPending())
          return root.fail("current-host replay rows could not be cleared")
        root.phase = 8
        root.ticks = 0
      } else if (root.phase === 8) {
        if (adapter.pendingModel.count !== 0 || adapter.pastModel.count !== 0)
          return
        fakeHost.delayHistory = true
        if (!adapter.showHistory() || !adapter.clearPending())
          return root.fail("in-flight history clear was not accepted")
        fakeHost.finishHistoryReplay()
        root.phase = 9
        root.ticks = 0
      } else if (root.phase === 9) {
        if (adapter.pendingModel.count !== 0 || adapter.pastModel.count !== 0)
          return
        hostPopupModel.append({
          id: 22, originalId: 22, app: "Adapter fixture", appIcon: "",
          summary: "Post-clear live", body: "New after clear",
          image: "", glyph: "", exec: "", urgency: 1,
          expireTimeout: 8000, timestamp: Date.now()
        })
        root.phase = 10
        root.ticks = 0
      } else if (root.phase === 10) {
        if (adapter.pendingModel.count !== 1
            || adapter.pendingModel.get(0).summary !== "Post-clear live"
            || adapter.pastModel.count !== 0) return
        console.log("notification adapter smoke passed")
        Qt.exit(0)
      }
      if (root.ticks > 100) root.fail("adapter smoke timed out")
    }
  }
}
