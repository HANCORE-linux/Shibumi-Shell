pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false

  property string providerId: "opencode"
  property string providerName: "OpenCode"
  property bool enabled: false
  property bool ready: false
  property bool refreshing: false
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
  property string tierLabel: "Local messages"
  property string usageStatusText: ""
  property string authHelpText: "OpenCode usage is read from its local database."
  property bool hasLocalStats: true

  readonly property string scannerPath: String(
    Qt.resolvedUrl("scripts/opencode-usage")).replace("file://", "")

  function clampPercent(value) {
    const number = Number(value)
    if (!isFinite(number)) return -1
    return Math.max(0, Math.min(100, number * 100))
  }

  function refresh(_force) {
    if (!enabled || usageScanner.running) return
    refreshing = true
    usageScanner.running = true
  }

  function stopScanner() {
    if (usageScanner.running) usageScanner.running = false
    refreshing = false
  }

  function parseScannerOutput(output) {
    const raw = String(output || "").trim()
    if (!raw) {
      ready = false
      usageStatusText = "OpenCode data unavailable"
      return
    }
    try {
      const data = JSON.parse(raw.split("\n").pop())
      ready = data.ready === true
      if (!ready) {
        usageStatusText = "OpenCode data unavailable"
        rateLimitPercent = -1
        secondaryRateLimitPercent = -1
        return
      }
      rateLimitPercent = clampPercent(data["5h-utilization"])
      secondaryRateLimitPercent = clampPercent(data["7d-utilization"])
      todayTotalTokens = Math.max(0, Number(data._today_tokens) || 0)
      windowTokens = Math.max(0, Number(data._tokens_used) || 0)
      hourlyTokens = Math.max(0, Number(data._rate_per_hour) || 0)
      latestModel = String(data._model || "")
      models = Array.isArray(data._models) ? data._models : []
      tierLabel = String(data._plan || "Local messages")
      usageStatusText = String(data.status || "allowed") === "allowed_warning"
        ? "Approaching local soft cap" : "Local activity"
    } catch (error) {
      ready = false
      usageStatusText = "OpenCode scan failed"
      authHelpText = String(error)
    }
  }

  function formatResetTime(_timestamp) { return "" }

  Process {
    id: usageScanner
    command: ["python3", root.scannerPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseScannerOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim())
        console.warn("shibumi/opencode", String(text).trim())
    }
    onExited: {
      root.refreshing = false
      root.lastRefreshedAtMs = Date.now()
    }
  }

  Timer {
    interval: 5 * 60 * 1000
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  onEnabledChanged: if (!enabled) stopScanner()
  Component.onDestruction: stopScanner()
}
