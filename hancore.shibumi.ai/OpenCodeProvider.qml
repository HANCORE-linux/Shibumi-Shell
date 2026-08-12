pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false

  property string providerId: "opencode"
  property string providerName: "OpenCode"
  property bool enabled: false
  property var scannerCommandOverride: []
  property int scanGeneration: 0
  property bool ready: false
  property bool refreshing: false
  property bool midnightRefreshPending: false
  property double lastRefreshedAtMs: 0

  property real rateLimitPercent: -1
  property string rateLimitLabel: "5h soft cap"
  property string rateLimitResetAt: ""
  property real secondaryRateLimitPercent: -1
  property string secondaryRateLimitLabel: "7d soft cap"
  property string secondaryRateLimitResetAt: ""

  property real todayTotalTokens: 0
  property real windowTokens: 0
  property real hourlyTokens: 0
  property var models: []
  property string latestModel: ""
  property string dataDay: ""
  property string tierLabel: "Local messages"
  property string usageStatusText: ""
  property string authHelpText: "OpenCode usage is read from its local database."
  property bool hasLocalStats: true

  readonly property string scannerPath: String(
    Qt.resolvedUrl("scripts/opencode-usage")).replace("file://", "")
  readonly property bool scannerRunning: usageScanner.running

  function clampPercent(value) {
    const number = Number(value)
    if (!isFinite(number)) return -1
    return Math.max(0, Math.min(100, number * 100))
  }

  function localDay() {
    return Qt.formatDateTime(new Date(), "yyyy-MM-dd")
  }

  function millisecondsUntilNextLocalMidnight() {
    const now = new Date()
    const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
    return Math.max(1, next.getTime() - now.getTime())
  }

  function clearCurrentDayData() {
    todayTotalTokens = 0
    latestModel = ""
    models = []
    dataDay = ""
  }

  function clearScannerData() {
    ready = false
    rateLimitPercent = -1
    secondaryRateLimitPercent = -1
    windowTokens = 0
    hourlyTokens = 0
    clearCurrentDayData()
  }

  function scheduleMidnightInvalidation() {
    if (!enabled) {
      midnightTimer.stop()
      return
    }
    midnightTimer.interval = millisecondsUntilNextLocalMidnight()
    midnightTimer.restart()
  }

  function handleLocalMidnight() {
    clearCurrentDayData()
    if (usageScanner.running) midnightRefreshPending = true
    else refresh(true)
    scheduleMidnightInvalidation()
  }

  function refresh(_force) {
    if (!enabled || usageScanner.running) return
    refreshing = true
    usageScanner.running = true
    scanGeneration++
  }

  function stopScanner() {
    if (usageScanner.running) usageScanner.running = false
    refreshing = false
  }

  function finishScanner() {
    refreshing = false
    lastRefreshedAtMs = Date.now()
    if (midnightRefreshPending) {
      midnightRefreshPending = false
      Qt.callLater(function() { root.refresh(true) })
    }
  }

  function parseScannerOutput(output) {
    const raw = String(output || "").trim()
    if (!raw) {
      clearScannerData()
      usageStatusText = "OpenCode data unavailable"
      return
    }
    try {
      const data = JSON.parse(raw.split("\n").pop())
      ready = data.ready === true
      if (!ready) {
        clearScannerData()
        usageStatusText = "OpenCode data unavailable"
        return
      }
      rateLimitPercent = clampPercent(data["5h-utilization"])
      secondaryRateLimitPercent = clampPercent(data["7d-utilization"])
      windowTokens = Math.max(0, Number(data._tokens_used) || 0)
      hourlyTokens = Math.max(0, Number(data._rate_per_hour) || 0)
      const scanDay = String(data._day || "")
      if (scanDay === localDay()) {
        todayTotalTokens = Math.max(0, Number(data._today_tokens) || 0)
        latestModel = String(data._model || "")
        models = Array.isArray(data._models) ? data._models : []
        dataDay = scanDay
      } else {
        clearCurrentDayData()
      }
      tierLabel = String(data._plan || "Local messages")
      usageStatusText = String(data.status || "allowed") === "allowed_warning"
        ? "Approaching local soft cap" : "Local activity"
    } catch (error) {
      clearScannerData()
      usageStatusText = "OpenCode scan failed"
      authHelpText = String(error)
    }
  }

  function formatResetTime(_timestamp) { return "" }

  Process {
    id: usageScanner
    command: Array.isArray(root.scannerCommandOverride)
      && root.scannerCommandOverride.length > 0
      ? root.scannerCommandOverride : ["python3", root.scannerPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseScannerOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim())
        console.warn("shibumi/opencode", String(text).trim())
    }
    onExited: root.finishScanner()
  }

  Timer {
    id: refreshTimer
    interval: 5 * 60 * 1000
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  // UI-only day data expires exactly at the next local midnight. This timer
  // exists only while OpenCode is enabled and is rescheduled after each fire;
  // it owns no worker and the shared five-minute scanner remains unchanged.
  Timer {
    id: midnightTimer
    repeat: false
    onTriggered: root.handleLocalMidnight()
  }

  onEnabledChanged: {
    if (!enabled) {
      midnightRefreshPending = false
      stopScanner()
      midnightTimer.stop()
    } else {
      scheduleMidnightInvalidation()
    }
  }
  Component.onCompleted: scheduleMidnightInvalidation()
  Component.onDestruction: {
    midnightRefreshPending = false
    midnightTimer.stop()
    stopScanner()
  }
}
