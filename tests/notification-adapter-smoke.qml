import QtQuick
import Quickshell
import "status" as Status

ShellRoot {
  id: root

  property int ticks: 0
  readonly property int expectedHistoryCount: Number(
    Quickshell.env("SHIBUMI_EXPECTED_HISTORY_COUNT") || 0)
  readonly property string historyRace:
    Quickshell.env("SHIBUMI_HISTORY_RACE")

  function fail(message) {
    console.error("notification-adapter-smoke:", message)
    Qt.exit(1)
  }

  ListModel {
    id: liveRows
    ListElement {
      originalId: 7
      app: "Live fixture"
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
    id: legacyPastRows
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
    id: currentHost
    property var popupModel: liveRows
    property bool doNotDisturb: false
    property int dismissCount: 0
    property int clearCount: 0
    property string focusedSummary: ""
    function setDoNotDisturb(value) { doNotDisturb = value === true }
    function dismissPopup(index) {
      if (index < 0 || index >= popupModel.count) return
      dismissCount++
      popupModel.remove(index)
    }
    function clearPopups() { clearCount++; popupModel.clear() }
    function focusApp(entry) {
      focusedSummary = String(entry && entry.summary || "")
    }
  }

  // The 4.0.3 host proxy can expose DND while withholding popupModel.
  QtObject {
    id: dndOnlyHost
    property bool doNotDisturb: true
    function setDoNotDisturb(value) { doNotDisturb = value === true }
  }

  QtObject {
    id: legacyHost
    property var popupModel: liveRows
    property var pendingModel: liveRows
    property var pastModel: legacyPastRows
  }

  QtObject {
    id: currentShell
    function firstPartyServiceFor(_id) { return currentHost }
  }
  QtObject {
    id: dndOnlyShell
    function firstPartyServiceFor(_id) { return dndOnlyHost }
  }
  QtObject {
    id: legacyShell
    function firstPartyServiceFor(_id) { return legacyHost }
  }

  Status.NotificationAdapter { id: adapter }
  Status.NotificationAdapter { id: dndOnlyAdapter }
  Status.NotificationAdapter { id: legacyAdapter }
  Status.NotificationAdapter { id: unavailableAdapter }

  Component.onCompleted: {
    adapter.attachShell(currentShell)
    dndOnlyAdapter.attachShell(dndOnlyShell)
    legacyAdapter.attachShell(legacyShell)
    unavailableAdapter.attachShell(null)
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks === 2) {
        if (!adapter.available || !adapter.liveAvailable
            || !adapter.historyAvailable || adapter.pendingCount !== 1
            || !dndOnlyAdapter.available || dndOnlyAdapter.liveAvailable
            || !dndOnlyAdapter.historyAvailable
            || dndOnlyAdapter.pendingCount !== 0
            || legacyAdapter.pastModel.count !== 1
            || unavailableAdapter.available
            || unavailableAdapter.historyAvailable)
          return root.fail("capabilities do not match the host models")
        if (!dndOnlyAdapter.showHistory())
          return root.fail("Recent did not start the private history read")
        if (root.historyRace === "refresh") {
          dndOnlyAdapter.attachShell(currentShell)
          if (!dndOnlyAdapter.showHistory())
            return root.fail("replacement host refresh was not accepted")
        } else if (root.historyRace === "same-refresh") {
          if (!dndOnlyAdapter.showHistory())
            return root.fail("same-host refresh was not accepted")
          dndOnlyAdapter.attachShell(dndOnlyShell)
        } else {
          if (!adapter.showHistory())
            return root.fail("live-host history read was not accepted")
          if (root.historyRace === "detach") {
            dndOnlyAdapter.attachShell(null)
            if (dndOnlyAdapter.available || dndOnlyAdapter.recentCount !== 0)
              return root.fail("detach did not clean up history immediately")
          } else if (root.historyRace === "replace") {
            dndOnlyAdapter.attachShell(legacyShell)
          }
        }
      }
      if (root.ticks < (root.historyRace ? 40 : 12)) return
      if (root.historyRace) {
        const refresh = root.historyRace === "refresh"
          || root.historyRace === "same-refresh"
        const expected = root.historyRace === "replace" || refresh ? 1 : 0
        const summary = refresh ? "New host history" : "Legacy recent"
        if (adapter.recentCount !== (refresh ? 0 : root.expectedHistoryCount)
            || dndOnlyAdapter.recentCount !== expected
            || (expected && dndOnlyAdapter.pastModel.get(0).summary
              !== summary)
            || (root.historyRace === "detach" && dndOnlyAdapter.available))
          return root.fail("stale history crossed " + root.historyRace)
        console.log("notification history " + root.historyRace
          + " race passed")
        Qt.exit(0)
        return
      }
      if (dndOnlyAdapter.pastModel.count !== root.expectedHistoryCount
          || adapter.pastModel.count !== root.expectedHistoryCount)
        return root.fail("history read did not produce the expected rows")
      if (root.expectedHistoryCount > 0
          && (dndOnlyAdapter.pastModel.get(0).summary !== "History 12"
            || dndOnlyAdapter.pastModel.get(9).summary !== "History 3"))
        return root.fail("history rows were not sorted and limited to ten")
      if (adapter.pendingCount !== 1
          || adapter.pendingModel.get(0).summary !== "Current notification")
        return root.fail("history read mutated the live popup model")
      if (!dndOnlyAdapter.setDoNotDisturb(false)
          || dndOnlyAdapter.doNotDisturb)
        return root.fail("DND-only proxy action failed")
      if (dndOnlyAdapter.pastDismissAvailable
          || dndOnlyAdapter.pastClearAvailable
          || dndOnlyAdapter.dismissPast(0)
          || dndOnlyAdapter.clearPast())
        return root.fail("read-only history exposed a mutation action")
      liveRows.append({
        id: 8, originalId: 8, app: "Live fixture", appIcon: "",
        summary: "Second notification", body: "Reactive row", image: "",
        glyph: "", exec: "", urgency: 1, expireTimeout: 8000,
        timestamp: 101
      })
      if (adapter.pendingCount !== 2
          || !adapter.focusApp(adapter.pendingModel.get(0))
          || currentHost.focusedSummary !== "Current notification"
          || !adapter.dismissPending(0) || currentHost.dismissCount !== 1
          || adapter.pendingCount !== 1
          || !adapter.clearPending() || currentHost.clearCount !== 1
          || adapter.pendingCount !== 0)
        return root.fail("live model or actions did not remain reactive")
      adapter.attachShell(null)
      if (adapter.available || adapter.pendingCount !== 0
          || adapter.recentCount !== 0)
        return root.fail("host replacement did not clear primitive rows")
      console.log("notification adapter smoke passed")
      Qt.exit(0)
    }
  }
}
