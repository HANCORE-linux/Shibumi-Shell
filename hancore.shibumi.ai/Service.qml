pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "AgentUsageModel.js" as AgentUsageModel

// One process-wide provider owner. Current Omarchy agent collectors publish
// primitive JSON records which this service normalizes for every output. On
// pinned older hosts, the legacy model-usage providers remain an exclusive
// fallback. No host panel or screen-local worker is instantiated.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property bool runtimeProbesEnabled: true
  property var providerOverrides: []
  property string agentsSourceOverride: ""
  property string agentsUsageDirOverride: ""
  property string modelUsageSourceOverride: ""

  readonly property var bar: shell ? shell.bar : null
  readonly property var stateService: shell
    && typeof shell.serviceFor === "function"
    ? shell.serviceFor("hancore.shibumi.state") : null

  property bool detectionReady: false
  // Wall-clock expiry is rechecked at this bounded interval while Agents
  // records exist. This also handles suspend/resume and system-time jumps.
  property int agentRecordExpiryCheckIntervalMs: 60 * 1000
  property bool claudeAvailable: false
  property bool codexAvailable: false
  property bool openCodeAvailable: false
  property var agentsClaudeRecord: null
  property var agentsCodexRecord: null
  readonly property double nextAgentRecordExpiryAtMs: {
    const expiries = []
    if (agentsClaudeRecord && Number(agentsClaudeRecord.expiresAtMs) > 0)
      expiries.push(Number(agentsClaudeRecord.expiresAtMs))
    if (agentsCodexRecord && Number(agentsCodexRecord.expiresAtMs) > 0)
      expiries.push(Number(agentsCodexRecord.expiresAtMs))
    return expiries.length > 0 ? Math.min.apply(null, expiries) : 0
  }
  property bool agentsUpdateHealthy: false
  property int providerRevision: 0
  property string backendProcessKind: ""
  property string backendOutput: ""
  property string backendError: ""
  property bool pendingBackendRefresh: false
  property bool pendingBackendForce: false
  property bool providerSettingsReady: false
  property int providerSettingsGeneration: 0
  property int runningSettingsGeneration: 0
  readonly property bool backendRunning: backendProcess.running

  readonly property string agentsSource: String(agentsSourceOverride || "")
    || standardWidgetSource("omarchy.agents")
  readonly property bool agentsBackendActive: agentsSource !== ""
  readonly property string agentsUsageDir: String(agentsUsageDirOverride || "")
    || (Quickshell.env("XDG_STATE_HOME")
      || (Quickshell.env("HOME") || "") + "/.local/state")
      + "/omarchy/agents/usage"
  readonly property string modelUsageSource: !agentsBackendActive
    ? String(modelUsageSourceOverride || "")
      || (bar && typeof bar.registeredWidgetSource === "function"
        ? String(bar.registeredWidgetSource("omarchy.model-usage") || "") : "")
      || standardWidgetSource("omarchy.model-usage")
    : ""
  readonly property url claudeSource: providerUrl("Claude.qml")
  readonly property url codexSource: providerUrl("Codex.qml")
  readonly property var settings: {
    if (stateService) void(stateService.revision)
    if (shell && "shellConfig" in shell) void(shell.shellConfig)
    const aliasId = agentsBackendActive
      ? "omarchy.agents" : "omarchy.model-usage"
    const aliasSettings = bar && typeof bar.widgetSettings === "function"
      ? bar.widgetSettings("G7", aliasId)
      : configuredEntrySettings(aliasId)
    const localSettings = bar && typeof bar.widgetSettings === "function"
      ? bar.widgetSettings("G7", "hancore.shibumi.ai")
      : configuredEntrySettings("hancore.shibumi.ai")
    return mergeSettings(aliasSettings, localSettings)
  }
  readonly property string requestedTool: String(
    settings.aiTool || settings.tool || "claude").toLowerCase()
  readonly property int agentsRefreshInterval: Math.max(30,
    Number(settings.refreshIntervalSec) || 900) * 1000
  readonly property string agentsUpdateScript: String(
    Qt.resolvedUrl("scripts/agents-update")).replace("file://", "")
  readonly property bool serviceActive: {
    if (stateService && "revision" in stateService)
      void(stateService.revision)
    return stateService && typeof stateService.groupEnabled === "function"
      ? stateService.groupEnabled("G7") : false
  }
  readonly property string providerEnablementSignature:
    JSON.stringify({
      claude: providerEnabled("claude"),
      codex: providerEnabled("codex"),
      opencode: providerEnabled("opencode"),
      active: serviceActive,
      probes: runtimeProbesEnabled,
      agentsSource: agentsSource,
      legacySource: modelUsageSource
    })
  readonly property bool anyProviderEnabled:
    providerEnabled("claude") || providerEnabled("codex")
      || providerEnabled("opencode")
  readonly property var providers: {
    void(providerRevision)
    void(settings)
    const result = []
    if (!serviceActive) return result
    if (Array.isArray(providerOverrides) && providerOverrides.length > 0) {
      appendProviderSnapshots(result, providerOverrides)
      return result
    }
    if (agentsBackendActive) {
      appendProviderSnapshot(result, agentsClaudeRecord)
      appendProviderSnapshot(result, agentsCodexRecord)
    } else {
      appendProviderSnapshot(result, claudeLoader.item)
      appendProviderSnapshot(result, codexLoader.item)
    }
    if (openCodeProvider.enabled) appendProviderSnapshot(result, openCodeProvider)
    return result
  }
  readonly property string selectedTool: resolveTool(requestedTool)
  readonly property var selectedProvider: providerFor(selectedTool)
  readonly property bool refreshing: {
    void(providerRevision)
    if (backendProcess.running) return true
    const sources = Array.isArray(providerOverrides)
      && providerOverrides.length > 0
        ? providerOverrides : [claudeLoader.item, codexLoader.item,
          openCodeProvider]
    for (let index = 0; index < sources.length; index++) {
      if (sources[index] && sources[index].refreshing === true) return true
    }
    return false
  }

  function copyObject(value) {
    const source = value && typeof value === "object"
      && !Array.isArray(value) ? value : ({})
    const result = ({})
    for (const key in source) result[key] = source[key]
    return result
  }

  function mergeSettings(aliasSettings, localSettings) {
    const result = copyObject(aliasSettings)
    const local = copyObject(localSettings)
    const providers = copyObject(result.providers)
    const localProviders = copyObject(local.providers)
    for (const id in localProviders) {
      const mergedProvider = copyObject(providers[id])
      const localProvider = copyObject(localProviders[id])
      for (const key in localProvider) mergedProvider[key] = localProvider[key]
      providers[id] = mergedProvider
    }
    if (Object.keys(providers).length > 0) result.providers = providers
    for (const key in local) {
      if (key !== "providers") result[key] = local[key]
    }
    return result
  }

  function configuredEntrySettings(id) {
    const config = shell && "shellConfig" in shell
      ? shell.shellConfig : null
    const layout = config && config.bar && config.bar.layout
      ? config.bar.layout : null
    if (!layout || typeof layout !== "object") return ({})
    const regions = ["left", "center", "right"]
    for (let regionIndex = 0; regionIndex < regions.length; regionIndex++) {
      const entries = Array.isArray(layout[regions[regionIndex]])
        ? layout[regions[regionIndex]] : []
      for (let index = 0; index < entries.length; index++) {
        const entry = entries[index]
        const entryId = typeof entry === "string"
          ? entry : entry && typeof entry === "object"
            ? String(entry.id || "") : ""
        if (entryId !== String(id || "")
            || !entry || typeof entry !== "object") continue
        const result = copyObject(entry)
        delete result.id
        delete result.shibumiModule
        return result
      }
    }
    return ({})
  }

  function standardWidgetSource(id) {
    const registry = shell && "pluginRegistry" in shell
      ? shell.pluginRegistry : null
    const pluginManifest = registry && registry.installedPlugins
      ? registry.installedPlugins[String(id || "")] : null
    return registry && typeof registry.entryPointUrl === "function"
      ? String(registry.entryPointUrl(
          pluginManifest, "barWidget") || "") : ""
  }

  function providerUrl(fileName) {
    const source = String(modelUsageSource || "")
    const slash = source.lastIndexOf("/")
    if (slash < 0) return ""
    return source.slice(0, slash + 1) + "providers/" + fileName
  }

  function providerEnabled(id) {
    const providersSettings = settings && settings.providers
      ? settings.providers : ({})
    const providerSettings = providersSettings[String(id || "")]
    return !providerSettings || providerSettings.enabled !== false
  }

  function cloneModels(value) {
    if (!Array.isArray(value)) return []
    const result = []
    for (let index = 0; index < value.length && index < 16; index++) {
      const entry = value[index]
      if (!entry || typeof entry !== "object") continue
      result.push({
        name: String(entry.name || "").slice(0, 512),
        totalLabel: String(entry.totalLabel || "0").slice(0, 64),
        inputLabel: String(entry.inputLabel || "0").slice(0, 64),
        outputLabel: String(entry.outputLabel || "0").slice(0, 64),
        reasoningLabel: String(entry.reasoningLabel || "0").slice(0, 64),
        cacheReadLabel: String(entry.cacheReadLabel || "0").slice(0, 64),
        cacheWriteLabel: String(entry.cacheWriteLabel || "0").slice(0, 64),
        todayLabel: String(entry.todayLabel || "0").slice(0, 64),
        pct: Math.max(0, Math.min(100, Number(entry.pct) || 0))
      })
    }
    return result
  }

  function agentRecordFresh(record, nowMs) {
    if (!record || String(record.backend || "") !== "omarchy.agents")
      return true
    const currentMs = isFinite(Number(nowMs)) ? Number(nowMs) : Date.now()
    const updatedAtMs = Number(record.updatedAtMs)
    const expiresAtMs = Number(record.expiresAtMs)
    return isFinite(updatedAtMs) && isFinite(expiresAtMs)
      && updatedAtMs <= currentMs && expiresAtMs >= currentMs
  }

  function providerSnapshot(provider, nowMs) {
    if (!provider || !agentRecordFresh(provider, nowMs)) return null
    const id = String(provider.providerId || "")
    if (!id || !providerEnabled(id)) return null
    return {
      providerId: id,
      providerName: String(provider.providerName || id).slice(0, 512),
      ready: (provider.ready !== undefined ? provider.ready === true : true)
        && (String(provider.backend || "") !== "omarchy.agents"
          || agentsUpdateHealthy),
      rateLimitPercent: Number(provider.rateLimitPercent) >= 0
        ? Number(provider.rateLimitPercent) : -1,
      rateLimitLabel: String(provider.rateLimitLabel || "").slice(0, 512),
      rateLimitResetAt: String(provider.rateLimitResetAt || "").slice(0, 512),
      secondaryRateLimitPercent:
        Number(provider.secondaryRateLimitPercent) >= 0
          ? Number(provider.secondaryRateLimitPercent) : -1,
      secondaryRateLimitLabel:
        String(provider.secondaryRateLimitLabel || "").slice(0, 512),
      secondaryRateLimitResetAt:
        String(provider.secondaryRateLimitResetAt || "").slice(0, 512),
      todayTotalTokens: Math.max(0, Number(provider.todayTotalTokens) || 0),
      todayPrompts: Math.max(0, Number(provider.todayPrompts) || 0),
      todaySessions: Math.max(0, Number(provider.todaySessions) || 0),
      windowTokens: Math.max(0, Number(provider.windowTokens) || 0),
      hourlyTokens: Math.max(0, Number(provider.hourlyTokens) || 0),
      models: cloneModels(provider.models),
      tierLabel: String(provider.tierLabel || "").slice(0, 512),
      usageStatusText: String(provider.usageStatusText || "").slice(0, 512),
      authHelpText: String(provider.authHelpText || "").slice(0, 512),
      latestModel: String(provider.latestModel || "").slice(0, 512),
      refreshing: provider.refreshing === true,
      backend: String(provider.backend || "")
    }
  }

  function appendProviderSnapshot(target, provider) {
    const snapshot = providerSnapshot(provider)
    if (snapshot) target.push(snapshot)
  }

  function appendProviderSnapshots(target, source) {
    for (let index = 0; index < source.length; index++)
      appendProviderSnapshot(target, source[index])
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
    if (!providerFor(target) || !stateService
        || typeof stateService.setWidgetSetting !== "function") return false
    return stateService.setWidgetSetting(
      "G7", "hancore.shibumi.ai", "aiTool", target)
  }

  function cycleTool(direction) {
    if (providers.length < 2) return false
    let index = 0
    for (let current = 0; current < providers.length; current++) {
      if (String(providers[current].providerId || "") === selectedTool) {
        index = current
        break
      }
    }
    const step = Number(direction) < 0 ? -1 : 1
    const next = providers[(index + step + providers.length) % providers.length]
    return selectTool(next.providerId)
  }

  function refreshSources(sources, force) {
    for (let index = 0; index < sources.length; index++) {
      const provider = sources[index]
      if (provider && typeof provider.refresh === "function")
        provider.refresh(force === true)
    }
  }

  function refreshAll(force) {
    if (Array.isArray(providerOverrides) && providerOverrides.length > 0) {
      refreshSources(providerOverrides, force)
      return
    }
    if (agentsBackendActive) requestAgentsUpdate(force === true)
    else refreshSources([claudeLoader.item, codexLoader.item], force)
    if (openCodeProvider.enabled) openCodeProvider.refresh(force === true)
  }

  function usagePercent(provider) {
    if (!provider || provider.ready === false) return -1
    const primary = displayPercent(provider, provider.rateLimitPercent)
    const secondary = displayPercent(provider, provider.secondaryRateLimitPercent)
    if (isFinite(primary) && primary >= 0) return Math.round(primary)
    if (isFinite(secondary) && secondary >= 0) return Math.round(secondary)
    return -1
  }

  function providerHasCurrentData(provider) {
    if (!provider) return false
    return Number(provider.rateLimitPercent) >= 0
      || Number(provider.secondaryRateLimitPercent) >= 0
      || Number(provider.todayTotalTokens) > 0
      || Number(provider.todayPrompts) > 0
      || Number(provider.todaySessions) > 0
      || Number(provider.windowTokens) > 0
      || Number(provider.hourlyTokens) > 0
      || (Array.isArray(provider.models) && provider.models.length > 0)
      || String(provider.latestModel || "") !== ""
  }

  function providerCurrentDataMessage(provider) {
    if (!provider || providerHasCurrentData(provider)) return ""
    const authHelp = String(provider.authHelpText || "").trim()
    return authHelp || "No current usage or limit data."
  }

  function displayPercent(provider, value) {
    const number = Number(value)
    if (!isFinite(number) || number < 0) return -1
    const providerId = provider ? String(provider.providerId || "") : ""
    if ((providerId === "claude" || providerId === "codex") && number <= 1)
      return Math.min(100, number * 100)
    return Math.min(100, number)
  }

  function displayTierLabel(value) {
    const label = String(value || "")
    if (label.toLowerCase() === "prolite") return "Pro Lite"
    return label
  }

  function resetText(_provider, timestamp) {
    if (!timestamp) return ""
    const reset = new Date(timestamp)
    const diffMs = reset.getTime() - Date.now()
    if (!isFinite(diffMs)) return ""
    if (diffMs <= 0) return "now"
    const hours = Math.floor(diffMs / 3600000)
    const mins = Math.floor((diffMs % 3600000) / 60000)
    if (hours > 24) return Math.floor(hours / 24) + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + mins + "m"
    return mins + "m"
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
      if (provider.ready === false) heading += " · stale"
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
      const todayPrompts = Math.max(0, Number(provider.todayPrompts) || 0)
      const todaySessions = Math.max(0, Number(provider.todaySessions) || 0)
      if (todayPrompts > 0 || todaySessions > 0) {
        const activity = []
        if (todayPrompts > 0)
          activity.push(todayPrompts + (todayPrompts === 1 ? " prompt" : " prompts"))
        if (todaySessions > 0)
          activity.push(todaySessions + (todaySessions === 1 ? " session" : " sessions"))
        lines.push("Today activity: " + activity.join(" · "))
      }
      if (String(provider.latestModel || ""))
        lines.push((providerId === "opencode" ? "Latest today: " : "")
          + String(provider.latestModel))
      const currentDataMessage = providerCurrentDataMessage(provider)
      if (currentDataMessage) lines.push(currentDataMessage)
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
      claudeAvailable = false
      codexAvailable = false
      openCodeAvailable = false
      detectionReady = true
      providerRevision++
    }
  }

  function applyAgentRecord(expectedId, raw, nowMs) {
    const record = AgentUsageModel.parseRecord(raw, expectedId, nowMs)
    if (expectedId === "claude") agentsClaudeRecord = record
    else if (expectedId === "codex") agentsCodexRecord = record
    providerRevision++
  }

  function expireAgentRecords(nowMs) {
    const currentMs = isFinite(Number(nowMs)) ? Number(nowMs) : Date.now()
    let changed = false
    if (agentsClaudeRecord && !agentRecordFresh(agentsClaudeRecord, currentMs)) {
      agentsClaudeRecord = null
      changed = true
    }
    if (agentsCodexRecord && !agentRecordFresh(agentsCodexRecord, currentMs)) {
      agentsCodexRecord = null
      changed = true
    }
    if (changed) providerRevision++
    return changed
  }

  function clearAgentRecord(expectedId) {
    if (expectedId === "claude") agentsClaudeRecord = null
    else if (expectedId === "codex") agentsCodexRecord = null
    providerRevision++
  }

  function legacyDetectionCommand() {
    return ["bash", "-c", [
      "home=${HOME:?}",
      "claude=false",
      "codex=false",
      "opencode=false",
      "[[ -s \"$home/.claude/.credentials.json\" || -s \"$home/.claude/stats-cache.json\" || -s \"$home/.claude/history.jsonl\" ]] && claude=true",
      "[[ -d \"$home/.codex/sessions\" || -s \"$home/.codex/auth.json\" ]] && codex=true",
      "[[ -s \"$home/.local/share/opencode/opencode.db\" ]] && opencode=true",
      "printf '{\"claude\":%s,\"codex\":%s,\"opencode\":%s}\\n' \"$claude\" \"$codex\" \"$opencode\""
    ].join("; ")]
  }

  function agentsUpdateCommand(force) {
    const command = [agentsUpdateScript, String(omarchyPath || "")]
    if (!providerEnabled("claude") && !providerEnabled("codex")) {
      command.push("--probe-only")
      return command
    }
    if (force === true) command.push("--force")
    if (providerEnabled("claude")) command.push("claude")
    if (providerEnabled("codex")) command.push("codex")
    return command
  }

  function startBackendProcess(kind, command) {
    if (!runtimeProbesEnabled || !serviceActive
        || backendProcess.running || backendProcessKind !== "") return false
    backendProcessKind = kind
    runningSettingsGeneration = providerSettingsGeneration
    backendOutput = ""
    backendError = ""
    backendProcess.command = command
    backendProcess.running = true
    providerRevision++
    return true
  }

  function requestLegacyDetection() {
    if (agentsBackendActive || !runtimeProbesEnabled
        || !serviceActive) return false
    if (backendProcess.running || backendProcessKind !== "") {
      pendingBackendRefresh = true
      return true
    }
    return startBackendProcess("legacy-detection", legacyDetectionCommand())
  }

  function requestAgentsUpdate(force) {
    if (!agentsBackendActive || !runtimeProbesEnabled
        || !serviceActive) return false
    if (backendProcess.running || backendProcessKind !== "") {
      pendingBackendRefresh = true
      pendingBackendForce = pendingBackendForce || force === true
      return true
    }
    return startBackendProcess("agents-update", agentsUpdateCommand(force))
  }

  function requestCurrentBackend(force) {
    if (!runtimeProbesEnabled || !serviceActive || !anyProviderEnabled)
      return false
    return agentsBackendActive
      ? requestAgentsUpdate(force === true) : requestLegacyDetection()
  }

  function reconcileBackendLifecycle(force) {
    providerSettingsGeneration++
    agentsUpdateHealthy = false
    pendingBackendRefresh = false
    pendingBackendForce = false
    if (!runtimeProbesEnabled || !serviceActive || !anyProviderEnabled) {
      if (backendProcess.running) backendProcess.running = false
    } else if (backendProcess.running || backendProcessKind !== "") {
      pendingBackendRefresh = true
      pendingBackendForce = force === true
      if (backendProcess.running) backendProcess.running = false
    } else {
      requestCurrentBackend(force === true)
    }
    providerRevision++
  }

  function applyBackendOutput(raw) {
    backendOutput = String(raw || "")
    if (backendProcessKind === "legacy-detection") {
      applyDetection(backendOutput)
    } else if (backendProcessKind === "agents-update") {
      try {
        const detection = JSON.parse(backendOutput.split("\n")[0])
        openCodeAvailable = detection.opencode === true
      } catch (_error) {
        openCodeAvailable = false
      }
    }
  }

  function finishBackendProcess(exitCode) {
    const completedKind = backendProcessKind
    const error = backendError
    backendProcessKind = ""
    if (completedKind === "agents-update") {
      agentsUpdateHealthy = Number(exitCode) === 0
        && runningSettingsGeneration === providerSettingsGeneration
        && !pendingBackendRefresh
      agentsClaudeFile.reload()
      agentsCodexFile.reload()
      if (Number(exitCode) !== 0 && error !== "")
        console.warn("Shibumi AI agents update failed:", error.slice(0, 512))
    }
    providerRevision++
    if (pendingBackendRefresh) {
      const force = pendingBackendForce
      pendingBackendRefresh = false
      pendingBackendForce = false
      if (agentsBackendActive) requestAgentsUpdate(force)
      else requestLegacyDetection()
    }
  }

  Process {
    id: backendProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyBackendOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.backendError = String(text || "").trim()
    }
    onExited: function(exitCode, _exitStatus) {
      root.finishBackendProcess(exitCode)
    }
  }

  Timer {
    id: agentRecordExpiryTimer
    interval: Math.max(10, root.agentRecordExpiryCheckIntervalMs)
    running: root.serviceActive && root.agentsBackendActive
      && root.nextAgentRecordExpiryAtMs > 0
    repeat: true
    onTriggered: root.expireAgentRecords(Date.now())
  }

  Timer {
    id: backendTimer
    interval: root.agentsBackendActive
      ? root.agentsRefreshInterval : 60 * 1000
    running: root.runtimeProbesEnabled && root.serviceActive
      && root.anyProviderEnabled
    repeat: true
    onTriggered: {
      root.providerRevision++
      root.requestCurrentBackend(false)
    }
  }

  FileView {
    id: agentsClaudeFile
    path: root.serviceActive && root.agentsBackendActive
        && root.providerEnabled("claude")
      ? root.agentsUsageDir + "/claude.json" : ""
    watchChanges: root.serviceActive && root.agentsBackendActive
      && root.providerEnabled("claude")
    printErrors: false
    onLoaded: root.applyAgentRecord("claude", text())
    onFileChanged: reload()
    onLoadFailed: root.clearAgentRecord("claude")
  }

  FileView {
    id: agentsCodexFile
    path: root.serviceActive && root.agentsBackendActive
        && root.providerEnabled("codex")
      ? root.agentsUsageDir + "/codex.json" : ""
    watchChanges: root.serviceActive && root.agentsBackendActive
      && root.providerEnabled("codex")
    printErrors: false
    onLoaded: root.applyAgentRecord("codex", text())
    onFileChanged: reload()
    onLoadFailed: root.clearAgentRecord("codex")
  }

  Loader {
    id: claudeLoader
    active: root.serviceActive && !root.agentsBackendActive
      && root.runtimeProbesEnabled && root.providerEnabled("claude")
      && root.detectionReady && root.claudeAvailable
      && String(root.claudeSource)
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
    active: root.serviceActive && !root.agentsBackendActive
      && root.runtimeProbesEnabled && root.providerEnabled("codex")
      && root.detectionReady && root.codexAvailable
      && String(root.codexSource)
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
    enabled: root.serviceActive && root.runtimeProbesEnabled
      && root.providerEnabled("opencode") && (root.agentsBackendActive
        ? root.openCodeAvailable : root.detectionReady && root.openCodeAvailable)
    onReadyChanged: root.providerRevision++
  }

  onProviderEnablementSignatureChanged: {
    if (providerSettingsReady) reconcileBackendLifecycle(true)
  }

  Component.onCompleted: {
    providerSettingsReady = true
    reconcileBackendLifecycle(false)
  }

  Component.onDestruction: {
    agentRecordExpiryTimer.stop()
    backendTimer.stop()
    if (backendProcess.running) backendProcess.running = false
  }
}
