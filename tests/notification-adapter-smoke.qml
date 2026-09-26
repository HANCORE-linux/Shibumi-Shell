import QtQuick
import Quickshell
import Quickshell.Io
import "status" as Status

ShellRoot {
  id: root

  property int ticks: 0
  readonly property int expectedHistoryCount: Number(
    Quickshell.env("SHIBUMI_EXPECTED_HISTORY_COUNT") || 0)
  readonly property string historyRace:
    Quickshell.env("SHIBUMI_HISTORY_RACE")
  readonly property string historyMutation:
    Quickshell.env("SHIBUMI_HISTORY_MUTATION")
  property int mutationPhase: 0
  property int mutationStartTick: 0

  function clickLive(token) { return typeof adapter.invokeLive === "function" ? adapter.invokeLive(token) : adapter.focusApp(adapter.pendingModel.get(0)) }
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
    property string clickResult: ""
    function invokePopupDefault(index) { if (clickResult === "error") throw Error("fixture action"); clickResult = popupModel.get(index).summary; focusApp(popupModel.get(index)) }
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
  Status.NotificationStatusView { id: counts; bar: null; notificationService: dndOnlyAdapter }
  Process { id: externalClear; command: ["sh", "-c", "rm -f \"$1\"/*.json", "--", dndOnlyAdapter.historyDir] }

  Component.onCompleted: {
    dndOnlyAdapter.attachShell(dndOnlyShell)
    adapter.attachShell(currentShell)
    legacyAdapter.attachShell(legacyShell)
    unavailableAdapter.attachShell(null)
    if (dndOnlyAdapter.historyState !== "loading" || counts.tooltipText !== "Live: Unavailable · Recent: Loading · DND")
      root.fail("initial history state is not loading without hover/open")
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
        if (root.historyRace && !dndOnlyAdapter.showHistory())
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
          if (root.historyRace && !adapter.showHistory())
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
      if (!root.historyRace && !root.mutationPhase
          && (adapter.historyState !== (Quickshell.env("SHIBUMI_HISTORY_MODE") === "missing" ? "unavailable" : "ready")
            || counts.tooltipText !== "Live: Unavailable · " + (adapter.historyState === "ready"
              ? root.expectedHistoryCount + " Recent" : "Recent: Unavailable") + " · DND"))
        return root.fail("eager snapshot/tooltip state without hover/open")
      if (root.historyRace && root.historyRace !== "mutation-replace") {
        const refresh = root.historyRace === "refresh"
          || root.historyRace === "same-refresh"
        const expected = root.historyRace === "replace" || refresh ? 1 : 0
        const summary = refresh ? "New host history" : "Legacy recent"
        if (adapter.recentCount !== (refresh ? 1 : root.expectedHistoryCount)
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
      if (root.mutationPhase === 1) {
        if (dndOnlyAdapter.pastModel.count !== root.expectedHistoryCount
            || dndOnlyAdapter.pastModel.get(0).summary !== "History 11") return
        console.log("notification history dismiss passed")
        Qt.exit(0)
        return
      }
      if (root.mutationPhase === 2) {
        if (dndOnlyAdapter.recentCount !== 0 || dndOnlyAdapter.historyState !== "ready") return
        console.log("notification history clear passed")
        Qt.exit(0)
        return
      }
      if (root.mutationPhase === 3) {
        if (root.ticks < root.mutationStartTick + 20) return
        if (dndOnlyAdapter.recentCount !== root.expectedHistoryCount
            || dndOnlyAdapter.pastModel.get(0).summary !== "History 11"
            || dndOnlyAdapter.pendingCount !== 1)
          return root.fail("stale mutation callback crossed host replacement")
        console.log("notification history mutation replace race passed")
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
      if (root.historyMutation === "external-clear") {
        externalClear.running = true
        root.mutationPhase = 2
        return
      }
      if (!dndOnlyAdapter.setDoNotDisturb(false)
          || dndOnlyAdapter.doNotDisturb)
        return root.fail("DND-only proxy action failed")
      if (!dndOnlyAdapter.pastDismissAvailable
          || !dndOnlyAdapter.pastClearAvailable)
        return root.fail("file-backed history did not expose mutation actions")
      for (const invalidName of ["../escape.json", "/tmp/escape.json",
          "control\n.json", "back\\slash.json", "not-json"]) {
        const invalidIndex = dndOnlyAdapter.pastModel.count
        dndOnlyAdapter.pastModel.append({
          fileName: invalidName, summary: "Invalid history path",
          timestamp: 999
        })
        if (dndOnlyAdapter.dismissPast(invalidIndex))
          return root.fail("malformed history filename reached the mutation")
        dndOnlyAdapter.pastModel.remove(invalidIndex)
      }
      if (root.historyMutation === "dismiss") {
        if (!dndOnlyAdapter.dismissPast(0))
          return root.fail("history dismiss was refused")
        root.mutationStartTick = root.ticks
        root.mutationPhase = root.historyRace === "mutation-replace" ? 3 : 1
        if (root.mutationPhase === 3) dndOnlyAdapter.attachShell(currentShell)
        return
      }
      if (root.historyMutation === "clear") {
        if (!dndOnlyAdapter.clearPast())
          return root.fail("history clear was refused")
        root.mutationPhase = 2
        return
      }
      counts.notificationService = adapter
      adapter.setDoNotDisturb(true)
      if (counts.tooltipText !== "1 Live · " + (adapter.historyState === "ready" ? root.expectedHistoryCount + " Recent" : "Recent: Unavailable") + " · DND")
        return root.fail("live/recent tooltip with DND")
      liveRows.append({
        id: 8, originalId: 8, app: "Live fixture", appIcon: "",
        summary: "Second notification", body: "Reactive row", image: "",
        glyph: "", exec: "", urgency: 1, expireTimeout: 8000,
        timestamp: 101
      })
      const token = String(adapter.pendingModel.get(0).liveToken || ""), checks = {}
      checks.defaultPath = clickLive(token) && currentHost.clickResult === "Current notification"
      liveRows.move(0, 1, 1); checks.reorder = !clickLive(token) && clickLive(String(adapter.pendingModel.get(1).liveToken || "")) && currentHost.clickResult === "Current notification"
      const reordered = String(adapter.pendingModel.get(1).liveToken || ""), replacement = adapter.primitiveEntry(liveRows.get(1)); liveRows.remove(1); liveRows.insert(1, replacement)
      checks.replacement = !clickLive(reordered) && JSON.stringify(adapter.primitiveEntry(liveRows.get(1))) === JSON.stringify(replacement)
      const latest = String(adapter.pendingModel.get(1).liveToken || ""); currentHost.clickResult = "error"; currentHost.focusedSummary = ""
      checks.error = !clickLive(latest) && currentHost.focusedSummary === ""; currentHost.clickResult = ""
      checks.fallback = clickLive(latest) && currentHost.focusedSummary === "Current notification"
      adapter.attachShell(null); adapter.attachShell(currentShell); checks.generation = !clickLive(latest)
      const dying = String(adapter.pendingModel.get(0).liveToken || ""), removed = adapter.primitiveEntry(liveRows.get(0)); liveRows.remove(0)
      checks.expiry = !clickLive(dying); checks.missing = !clickLive("missing"); liveRows.append(removed)
      console.log("235_LIVE_CLICK", JSON.stringify(checks)); if (Object.values(checks).some(ok => !ok)) return root.fail("live click identity/default/error")
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
