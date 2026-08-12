pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// One process-wide provider owner. Official Claude/Codex scanners are loaded
// only when their local data exists; OpenCode uses the plugin-local read-only
// SQLite adapter. Per-output widgets render this shared state only.
Item {
  id: root

  required property var bar

  property bool detectionReady: false
  property bool claudeAvailable: false
  property bool codexAvailable: false
  property bool openCodeAvailable: false
  property int providerRevision: 0

  readonly property string modelUsageSource: bar
    && typeof bar.registeredWidgetSource === "function"
    ? String(bar.registeredWidgetSource("omarchy.model-usage") || "") : ""
  readonly property url claudeSource: providerUrl("Claude.qml")
  readonly property url codexSource: providerUrl("Codex.qml")
  readonly property var settings: bar
    && typeof bar.widgetSettings === "function"
    ? bar.widgetSettings("G7", "hancore.shibumi.ai") : ({})
  readonly property string requestedTool: String(
    settings.aiTool || settings.tool || "claude").toLowerCase()
  readonly property var providers: {
    void(providerRevision)
    const result = []
    if (claudeLoader.item) result.push(claudeLoader.item)
    if (codexLoader.item) result.push(codexLoader.item)
    if (openCodeProvider.enabled) result.push(openCodeProvider)
    return result
  }
  readonly property string selectedTool: resolveTool(requestedTool)
  readonly property var selectedProvider: providerFor(selectedTool)
  readonly property bool refreshing: providers.some(function(provider) {
    return provider && provider.refreshing === true
  })

  function providerUrl(fileName) {
    const source = String(modelUsageSource || "")
    const slash = source.lastIndexOf("/")
    if (slash < 0) return ""
    return source.slice(0, slash + 1) + "providers/" + fileName
  }

  function providerFor(id) {
    const target = String(id || "")
    for (let index = 0; index < providers.length; index++) {
      if (String(providers[index].providerId || "") === target)
        return providers[index]
    }
    return null
  }

  function resolveTool(preferred) {
    const requested = String(preferred || "")
    if (providerFor(requested)) return requested
    const order = ["claude", "codex", "opencode"]
    for (let index = 0; index < order.length; index++) {
      if (providerFor(order[index])) return order[index]
    }
    return ""
  }

  function selectTool(id) {
    const target = String(id || "")
    if (!providerFor(target) || !bar
        || typeof bar.setWidgetSetting !== "function") return false
    return bar.setWidgetSetting("G7", "hancore.shibumi.ai", "aiTool", target)
  }

  function cycleTool(direction) {
    if (providers.length < 2) return false
    let index = providers.indexOf(selectedProvider)
    if (index < 0) index = 0
    const step = Number(direction) < 0 ? -1 : 1
    const next = providers[(index + step + providers.length) % providers.length]
    return selectTool(next.providerId)
  }

  function refreshAll(force) {
    for (let index = 0; index < providers.length; index++) {
      const provider = providers[index]
      if (provider && typeof provider.refresh === "function") provider.refresh(force === true)
    }
  }

  function usagePercent(provider) {
    if (!provider) return -1
    const primary = displayPercent(provider, provider.rateLimitPercent)
    const secondary = displayPercent(provider, provider.secondaryRateLimitPercent)
    if (isFinite(primary) && primary >= 0) return Math.round(primary)
    if (isFinite(secondary) && secondary >= 0) return Math.round(secondary)
    return -1
  }

  function displayPercent(provider, value) {
    const number = Number(value)
    if (!isFinite(number) || number < 0) return -1
    const providerId = provider ? String(provider.providerId || "") : ""
    // The official Claude and Codex providers expose utilization as a 0..1
    // fraction. OpenCode is normalized to 0..100 by its local adapter.
    if ((providerId === "claude" || providerId === "codex") && number <= 1)
      return Math.min(100, number * 100)
    return Math.min(100, number)
  }

  function displayTierLabel(value) {
    const label = String(value || "")
    if (label.toLowerCase() === "prolite") return "Pro Lite"
    return label
  }

  function resetText(provider, timestamp) {
    if (!provider || !timestamp || typeof provider.formatResetTime !== "function") return ""
    return String(provider.formatResetTime(timestamp) || "")
  }

  function providerReportsFiveHour(provider) {
    if (!provider) return false
    const labels = [provider.rateLimitLabel, provider.secondaryRateLimitLabel]
    for (let index = 0; index < labels.length; index++) {
      const label = String(labels[index] || "").toLowerCase()
      if (label.indexOf("5h") >= 0
          || (label.indexOf("5") >= 0 && label.indexOf("hour") >= 0))
        return true
    }
    return false
  }

  function tooltipText() {
    if (providers.length === 0) return "No AI usage providers detected"
    const lines = []
    for (let index = 0; index < providers.length; index++) {
      const provider = providers[index]
      if (lines.length) lines.push("")
      let heading = String(provider.providerName || provider.providerId || "AI")
      if (displayTierLabel(provider.tierLabel))
        heading += " (" + displayTierLabel(provider.tierLabel) + ")"
      lines.push(heading)
      if (Number(provider.rateLimitPercent) >= 0) {
        const reset = resetText(provider, provider.rateLimitResetAt)
        lines.push(String(provider.rateLimitLabel || "Primary") + ": "
          + Math.round(displayPercent(provider, provider.rateLimitPercent)) + "%"
          + (reset ? " · resets in " + reset : ""))
      }
      if (Number(provider.secondaryRateLimitPercent) >= 0) {
        const reset = resetText(provider, provider.secondaryRateLimitResetAt)
        lines.push(String(provider.secondaryRateLimitLabel || "Secondary") + ": "
          + Math.round(displayPercent(provider,
            provider.secondaryRateLimitPercent)) + "%"
          + (reset ? " · resets in " + reset : ""))
      }
      if (String(provider.providerId || "") === "codex"
          && !providerReportsFiveHour(provider))
        lines.push("5h: not reported by Codex RPC")
      if (String(provider.usageStatusText || "")
          && String(provider.providerId || "") === "codex")
        lines.push("General limit: " + String(provider.usageStatusText))
      const providerId = String(provider.providerId || "")
      if (providerId === "opencode") {
        if (Number(provider.windowTokens) > 0)
          lines.push("5h tokens: " + formatTokens(provider.windowTokens))
        if (Number(provider.hourlyTokens) > 0)
          lines.push("1h rate: " + formatTokens(provider.hourlyTokens) + "/h")
      } else if (Number(provider.windowTokens) > 0) {
        let activity = formatTokens(provider.windowTokens) + " tokens"
        if (Number(provider.hourlyTokens) > 0)
          activity += " · " + formatTokens(provider.hourlyTokens) + "/h"
        lines.push(activity)
      } else if (Number(provider.hourlyTokens) > 0) {
        lines.push("Rate: " + formatTokens(provider.hourlyTokens) + "/h")
      }
      if (provider.todayTotalTokens !== undefined
          && Number(provider.todayTotalTokens) > 0)
        lines.push("Today: " + formatTokens(provider.todayTotalTokens) + " tokens")
      if (String(provider.latestModel || ""))
        lines.push((providerId === "opencode" ? "Latest today: " : "")
          + String(provider.latestModel))
    }
    return lines.join("\n")
  }

  function formatTokens(value) {
    const count = Math.max(0, Number(value) || 0)
    if (count >= 1000000) return (count / 1000000).toFixed(2) + "M"
    if (count >= 1000) return (count / 1000).toFixed(1) + "K"
    return String(Math.round(count))
  }

  function applyDetection(raw) {
    try {
      const result = JSON.parse(String(raw || "{}"))
      claudeAvailable = result.claude === true
      codexAvailable = result.codex === true
      openCodeAvailable = result.opencode === true
      detectionReady = true
      providerRevision++
    } catch (_error) {
      detectionReady = true
    }
  }

  Process {
    id: detectionProc
    command: ["bash", "-c", [
      "home=${HOME:?}",
      "claude=false",
      "codex=false",
      "opencode=false",
      "[[ -s \"$home/.claude/.credentials.json\" || -s \"$home/.claude/stats-cache.json\" || -s \"$home/.claude/history.jsonl\" ]] && claude=true",
      "[[ -d \"$home/.codex/sessions\" || -s \"$home/.codex/auth.json\" ]] && codex=true",
      "[[ -s \"$home/.local/share/opencode/opencode.db\" ]] && opencode=true",
      "printf '{\"claude\":%s,\"codex\":%s,\"opencode\":%s}\\n' \"$claude\" \"$codex\" \"$opencode\""
    ].join("; ")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDetection(text)
    }
  }

  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!detectionProc.running) detectionProc.running = true
  }

  Loader {
    id: claudeLoader
    active: root.detectionReady && root.claudeAvailable && String(root.claudeSource)
    source: active ? root.claudeSource : ""
    onLoaded: {
      if (item) {
        item.providerSettings = root.settings.providers
          && root.settings.providers.claude ? root.settings.providers.claude : ({})
        item.enabled = true
      }
      root.providerRevision++
    }
    onItemChanged: root.providerRevision++
  }

  Loader {
    id: codexLoader
    active: root.detectionReady && root.codexAvailable && String(root.codexSource)
    source: active ? root.codexSource : ""
    onLoaded: {
      if (item) {
        item.providerSettings = root.settings.providers
          && root.settings.providers.codex ? root.settings.providers.codex : ({})
        item.enabled = true
      }
      root.providerRevision++
    }
    onItemChanged: root.providerRevision++
  }

  OpenCodeProvider {
    id: openCodeProvider
    enabled: root.detectionReady && root.openCodeAvailable
    onReadyChanged: root.providerRevision++
  }
}
