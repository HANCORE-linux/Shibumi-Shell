pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "ai" as Ai

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property real stableProviderWidth: 0
  property var clickTargets: []
  property bool waitingBackendTransition: false
  property bool waitingExpiryProbe: false
  property var expiryProbeRecord: null
  property bool midnightRacePassed: false
  property int midnightRaceStage: 0
  property int midnightRaceTicks: 0
  property var iconMatrix: [
    { providerId: "claude", v2Shell: false, customFill: false, baseOpacity: 0.25 },
    { providerId: "codex", v2Shell: false, customFill: false, baseOpacity: 0.65 },
    { providerId: "opencode", v2Shell: false, customFill: false, baseOpacity: 0.5 },
    { providerId: "claude", v2Shell: false, customFill: true, baseOpacity: 0.65 },
    { providerId: "codex", v2Shell: false, customFill: true, baseOpacity: 0.65 },
    { providerId: "opencode", v2Shell: false, customFill: true, baseOpacity: 0.65 },
    { providerId: "claude", v2Shell: true, customFill: false, baseOpacity: 0.25 },
    { providerId: "codex", v2Shell: true, customFill: false, baseOpacity: 0.65 },
    { providerId: "opencode", v2Shell: true, customFill: false, baseOpacity: 0.5 },
    { providerId: "claude", v2Shell: true, customFill: true, baseOpacity: 0.65 },
    { providerId: "codex", v2Shell: true, customFill: true, baseOpacity: 0.65 },
    { providerId: "opencode", v2Shell: true, customFill: true, baseOpacity: 0.65 }
  ]

  function fail(message) {
    console.error("ai-plugin-smoke:", message)
    Qt.exit(1)
  }

  function linearChannel(value) {
    return value <= 0.04045 ? value / 12.92
      : Math.pow((value + 0.055) / 1.055, 2.4)
  }

  function luminance(color) {
    return 0.2126 * linearChannel(color.r)
      + 0.7152 * linearChannel(color.g)
      + 0.0722 * linearChannel(color.b)
  }

  function contrastRatio(first, second) {
    const firstLuminance = luminance(first)
    const secondLuminance = luminance(second)
    return (Math.max(firstLuminance, secondLuminance) + 0.05)
      / (Math.min(firstLuminance, secondLuminance) + 0.05)
  }

  function composite(foreground, background, opacity) {
    return Qt.rgba(
      foreground.r * opacity + background.r * (1 - opacity),
      foreground.g * opacity + background.g * (1 - opacity),
      foreground.b * opacity + background.b * (1 - opacity), 1)
  }

  function agentsContractMatches() {
    if (!agentsService.agentsBackendActive
        || agentsService.modelUsageSource !== ""
        || agentsService.providers.length !== 2
        || agentsService.selectedTool !== fakeState.selectedTool) return false
    const claude = agentsService.providerFor("claude")
    const codex = agentsService.providerFor("codex")
    return claude && codex
      && claude.backend === "omarchy.agents"
      && codex.backend === "omarchy.agents"
      && agentsService.usagePercent(claude) === -1
      && agentsService.usagePercent(codex) === 24
      && claude.rateLimitPercent === -1
      && claude.secondaryRateLimitPercent === -1
      && claude.models.length === 0
      && codex.models.length === 0
      && codex.todayTotalTokens === 1031649
      && codex.latestModel === ""
      && claude.ready && codex.ready
      && !agentsService.providerHasCurrentData(claude)
      && agentsService.providerCurrentDataMessage(claude)
        === "Run `claude auth login` to restore authoritative usage."
      && agentsService.agentsRefreshInterval === 42000
      && agentsService.providerEnabled("fireworks") === false
      && agentsService.providerEnabled("claude") === true
      && agentsService.resetText(claude, claude.rateLimitResetAt) === ""
      && typeof claude.refresh !== "function"
      && typeof codex.refresh !== "function"
  }

  function readyRecordWithoutCurrentDataAccepted() {
    const recordNow = Date.now()
    const currentUpdatedAt = new Date(recordNow).toISOString()
    const futureUpdatedAt = new Date(recordNow + 1).toISOString()
    const staleUpdatedAt = new Date(
      recordNow - 24 * 60 * 60 * 1000 - 1).toISOString()
    const current = JSON.stringify({
      schemaVersion: 1,
      id: "claude",
      name: "Claude Code",
      ready: true,
      updatedAt: currentUpdatedAt,
      limits: [],
      todayPrompts: 0,
      todaySessions: 0,
      todayTotalTokens: 0,
      totalPrompts: 20,
      totalSessions: 2,
      activeDays: 4,
      modelUsage: { "historical-model": { inputTokens: 5000 } },
      authHelpText: "Authenticate Claude"
    })
    agentsService.applyAgentRecord("claude", current, recordNow)
    const provider = agentsService.providerFor("claude")
    const accepted = provider && provider.ready
      && agentsService.usagePercent(provider) === -1
      && provider.models.length === 0
      && provider.latestModel === ""
      && agentsService.providerCurrentDataMessage(provider)
        === "Authenticate Claude"

    const expiredSnapshotRejected = agentsService.providerSnapshot(
      agentsService.agentsClaudeRecord,
      recordNow + 24 * 60 * 60 * 1000 + 1) === null

    agentsService.applyAgentRecord("claude", JSON.stringify({
      schemaVersion: 1,
      id: "claude",
      name: "Claude Code",
      ready: true,
      updatedAt: staleUpdatedAt,
      limits: [],
      todayPrompts: 0,
      todaySessions: 0,
      todayTotalTokens: 0,
      totalPrompts: 20,
      totalSessions: 2,
      activeDays: 4,
      modelUsage: {}
    }), recordNow)
    const staleRejected = agentsService.providerFor("claude") === null

    agentsService.applyAgentRecord("claude", JSON.stringify({
      schemaVersion: 1,
      id: "claude",
      name: "Claude Code",
      ready: true,
      updatedAt: futureUpdatedAt,
      limits: [],
      todayPrompts: 0,
      todaySessions: 0,
      todayTotalTokens: 0,
      totalPrompts: 20,
      totalSessions: 2,
      activeDays: 4,
      modelUsage: {}
    }), recordNow)
    const futureRejected = agentsService.providerFor("claude") === null

    agentsService.applyAgentRecord("claude", JSON.stringify({
      schemaVersion: 1,
      id: "claude",
      name: "Claude Code",
      ready: true,
      updatedAt: currentUpdatedAt,
      limits: [],
      modelUsage: {}
    }), recordNow)
    const incompleteRejected = agentsService.providerFor("claude") === null

    agentsService.applyAgentRecord("claude", JSON.stringify({
      schemaVersion: 1,
      id: "claude",
      name: "Claude Code",
      ready: "true",
      updatedAt: currentUpdatedAt,
      limits: {},
      todayPrompts: 0,
      todaySessions: 0,
      todayTotalTokens: 0,
      totalPrompts: 20,
      totalSessions: 2,
      activeDays: 4,
      modelUsage: {}
    }), recordNow)
    const malformedRejected = agentsService.providerFor("claude") === null

    const invalidCounter = JSON.parse(current)
    invalidCounter.todayPrompts = 0.5
    agentsService.applyAgentRecord("claude",
      JSON.stringify(invalidCounter), recordNow)
    const fractionalCounterRejected =
      agentsService.providerFor("claude") === null

    const invalidHelp = JSON.parse(current)
    invalidHelp.authHelpText = { command: "claude auth login" }
    agentsService.applyAgentRecord("claude",
      JSON.stringify(invalidHelp), recordNow)
    const invalidHelpRejected = agentsService.providerFor("claude") === null

    const invalidDate = JSON.parse(current)
    invalidDate.updatedAt = "2026-02-30T12:00:00Z"
    agentsService.applyAgentRecord("claude",
      JSON.stringify(invalidDate), recordNow)
    const invalidCalendarDateRejected =
      agentsService.providerFor("claude") === null

    const emptyNeverUsed = JSON.stringify({
      schemaVersion: 1,
      id: "claude",
      name: "Claude Code",
      ready: true,
      updatedAt: currentUpdatedAt,
      limits: [],
      todayPrompts: 0,
      todaySessions: 0,
      todayTotalTokens: 0,
      totalPrompts: 0,
      totalSessions: 0,
      activeDays: 0,
      modelUsage: {}
    })
    agentsService.applyAgentRecord("claude", emptyNeverUsed, recordNow)
    const neverUsedRejected = agentsService.providerFor("claude") === null

    const promptOnly = JSON.stringify({
      schemaVersion: 1,
      id: "claude",
      name: "Claude Code",
      ready: true,
      updatedAt: currentUpdatedAt,
      limits: [],
      todayPrompts: 1,
      todaySessions: 1,
      todayTotalTokens: 0,
      totalPrompts: 20,
      totalSessions: 2,
      activeDays: 4,
      modelUsage: {}
    })
    agentsService.applyAgentRecord("claude", promptOnly, recordNow)
    const promptProvider = agentsService.providerFor("claude")
    const promptOnlyAccepted = promptProvider
      && promptProvider.todayPrompts === 1
      && promptProvider.todaySessions === 1
      && agentsService.providerHasCurrentData(promptProvider)
      && agentsService.providerCurrentDataMessage(promptProvider) === ""

    let invalidLimitsRejected = true
    const invalidPercents = [-0.1, 2, "0.2"]
    for (let index = 0; index < invalidPercents.length; index++) {
      const invalidLimit = JSON.stringify({
        schemaVersion: 1,
        id: "claude",
        name: "Claude Code",
        ready: true,
        updatedAt: currentUpdatedAt,
        limits: [{ label: "Session (5-hour)",
          percent: invalidPercents[index], resetsAt: "" }],
        todayPrompts: 0,
        todaySessions: 0,
        todayTotalTokens: 0,
        totalPrompts: 20,
        totalSessions: 2,
        activeDays: 4,
        modelUsage: {}
      })
      agentsService.applyAgentRecord("claude", invalidLimit, recordNow)
      if (agentsService.providerFor("claude") !== null)
        invalidLimitsRejected = false
    }

    agentsService.applyAgentRecord("claude", current, recordNow)
    return accepted && expiredSnapshotRejected && staleRejected && futureRejected
      && incompleteRejected && malformedRejected && fractionalCounterRejected
      && invalidHelpRejected && invalidCalendarDateRejected && neverUsedRejected
      && promptOnlyAccepted && invalidLimitsRejected
  }

  function openCodeParserContract() {
    const currentDay = openCodeParserProbe.localDay()
    const success = JSON.stringify({
      ready: true,
      "5h-utilization": "0.25",
      "7d-utilization": "0.10",
      _day: currentDay,
      _today_tokens: 150,
      _tokens_used: 200,
      _rate_per_hour: 50,
      _model: "current-model",
      _models: [{ name: "current-model", total: 150, pct: 100 }],
      _plan: "local messages",
      status: "allowed"
    })
    openCodeParserProbe.parseScannerOutput(success)
    const loaded = openCodeParserProbe.ready
      && openCodeParserProbe.todayTotalTokens === 150
      && openCodeParserProbe.windowTokens === 200
      && openCodeParserProbe.hourlyTokens === 50
      && openCodeParserProbe.latestModel === "current-model"
      && openCodeParserProbe.models.length === 1
      && openCodeParserProbe.dataDay === currentDay

    openCodeParserProbe.handleLocalMidnight()
    const midnightCleared = openCodeParserProbe.todayTotalTokens === 0
      && openCodeParserProbe.latestModel === ""
      && openCodeParserProbe.models.length === 0
      && openCodeParserProbe.dataDay === ""
      && openCodeParserProbe.windowTokens === 200
      && !openCodeParserProbe.midnightRefreshPending

    openCodeParserProbe.parseScannerOutput(success)
    openCodeParserProbe.parseScannerOutput('{"ready":false}')
    const unavailableCleared = !openCodeParserProbe.ready
      && openCodeParserProbe.rateLimitPercent === -1
      && openCodeParserProbe.secondaryRateLimitPercent === -1
      && openCodeParserProbe.todayTotalTokens === 0
      && openCodeParserProbe.windowTokens === 0
      && openCodeParserProbe.hourlyTokens === 0
      && openCodeParserProbe.latestModel === ""
      && openCodeParserProbe.models.length === 0

    openCodeParserProbe.parseScannerOutput(success)
    openCodeParserProbe.parseScannerOutput("not-json")
    const malformedCleared = !openCodeParserProbe.ready
      && openCodeParserProbe.todayTotalTokens === 0
      && openCodeParserProbe.windowTokens === 0
      && openCodeParserProbe.latestModel === ""
      && openCodeParserProbe.models.length === 0
    return loaded && midnightCleared && unavailableCleared && malformedCleared
  }

  function legacyContractMatches() {
    if (legacyService.agentsBackendActive
        || legacyService.modelUsageSource === ""
        || legacyService.providers.length !== 2) return false
    const claude = legacyService.providerFor("claude")
    const codex = legacyService.providerFor("codex")
    return claude && codex
      && claude.providerName === "Legacy Claude"
      && codex.providerName === "Legacy Codex"
      && legacyService.usagePercent(claude) === 10
      && legacyService.usagePercent(codex) === 20
  }

  function iconContractMatches(widget, expected) {
    const customFillActive = expected.customFill
    const expectedBase = customFillActive
      ? fakeBar.background : fakeBar.foreground
    const expectedUsage = customFillActive
      ? fakeBar.background : fakeBar.urgent
    const customBaseContrast = root.contrastRatio(
      root.composite(expectedBase, fakeBar.customFill, expected.baseOpacity),
      fakeBar.customFill)
    const glyphWidth = expected.providerId === "opencode" ? 20
      : expected.providerId === "codex" ? 14 : 15
    const glyphHeight = expected.providerId === "opencode" ? 12
      : expected.providerId === "codex" ? 14 : 15
    const glyphOffset = 0
    const contentOffset = expected.providerId === "codex" ? -1 : 0
    return widget.providerId === expected.providerId
      && widget.providerIconSlotWidth === 20
      && widget.providerIconSlotHeight === 16
      && widget.claudeGlyphPixelSize === 15
      && widget.providerGlyphWidth === glyphWidth
      && widget.providerGlyphHeight === glyphHeight
      && widget.providerGlyphHorizontalOffset === glyphOffset
      && widget.providerContentHorizontalOffset === contentOffset
      && widget.providerGlyphHorizontalOffset
        + widget.providerContentHorizontalOffset === contentOffset
      && widget.tokens.v2Shell === expected.v2Shell
      && widget.customFillActive === customFillActive
      && Math.abs(Number(widget.baseIconOpacity) - expected.baseOpacity) < 0.001
      && Qt.colorEqual(widget.baseIconColor, expectedBase)
      && Qt.colorEqual(widget.usageIconColor, expectedUsage)
      && (!customFillActive || customBaseContrast >= 3)
      && (expected.providerId !== "claude"
        || widget.claudeLayersAligned === true)
  }

  QtObject {
    id: claudeProvider
    property string providerId: "claude"
    property string providerName: "Claude Code"
    property bool ready: true
    property real rateLimitPercent: 0.025
    property string rateLimitLabel: "Session (5-hour)"
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: -1
    property string secondaryRateLimitLabel: ""
    property string secondaryRateLimitResetAt: ""
    property real todayTotalTokens: 0
    property real windowTokens: 0
    property real hourlyTokens: 0
    property var models: []
    property string tierLabel: "Max 5x"
    property string usageStatusText: ""
    property string latestModel: ""
    property int refreshCount: 0
    function refresh(_force) { refreshCount++ }
    function formatResetTime(_timestamp) { return "" }
  }

  QtObject {
    id: codexProvider
    property string providerId: "codex"
    property string providerName: "Codex"
    property bool ready: true
    property real rateLimitPercent: 0.13
    property string rateLimitLabel: "Weekly"
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: -1
    property string secondaryRateLimitLabel: ""
    property string secondaryRateLimitResetAt: ""
    property real todayTotalTokens: 1200
    property real windowTokens: 0
    property real hourlyTokens: 0
    property var models: []
    property string tierLabel: "prolite"
    property string usageStatusText: "Allowed"
    property string latestModel: "gpt-test"
    property int refreshCount: 0
    function refresh(_force) { refreshCount++ }
    function formatResetTime(_timestamp) { return "" }
  }

  QtObject {
    id: openCodeProvider
    property string providerId: "opencode"
    property string providerName: "OpenCode"
    property bool ready: true
    property real rateLimitPercent: 22
    property string rateLimitLabel: "5h soft cap"
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: 8
    property string secondaryRateLimitLabel: "7d soft cap"
    property string secondaryRateLimitResetAt: ""
    property real todayTotalTokens: 400
    property real windowTokens: 2300
    property real hourlyTokens: 180
    property var models: [
      ({ name: "test/model-a", totalLabel: "2.3K", inputLabel: "1.4K",
        outputLabel: "700", reasoningLabel: "200", cacheReadLabel: "80",
        cacheWriteLabel: "20", todayLabel: "900", pct: 100 }),
      ({ name: "test/model-b", totalLabel: "1.1K", inputLabel: "700",
        outputLabel: "400", reasoningLabel: "0", cacheReadLabel: "0",
        cacheWriteLabel: "0", todayLabel: "300", pct: 48 })
    ]
    property string tierLabel: "Local messages"
    property string usageStatusText: "Local activity"
    property string latestModel: "local-test"
    property int refreshCount: 0
    function refresh(_force) { refreshCount++ }
    function formatResetTime(_timestamp) { return "" }
  }

  QtObject {
    id: fakeState
    property int revision: 0
    property string selectedTool: "claude"
    property bool g7Enabled: true
    function groupEnabled(groupId) {
      return groupId === "G7" ? g7Enabled : true
    }
    function setWidgetSetting(groupId, moduleId, key, value) {
      if (groupId !== "G7" || moduleId !== "hancore.shibumi.ai"
          || key !== "aiTool") return false
      selectedTool = String(value || "")
      revision++
      return true
    }
  }

  QtObject {
    id: agentsState
    property int revision: 0
    property bool g7Enabled: true
    function groupEnabled(groupId) {
      return groupId === "G7" ? g7Enabled : true
    }
    function setWidgetSetting(groupId, moduleId, key, value) {
      return fakeState.setWidgetSetting(groupId, moduleId, key, value)
    }
  }

  QtObject {
    id: agentsShell
    property var bar: fakeBar
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.state" ? agentsState : null
    }
  }

  QtObject {
    id: missingStateShell
    property var bar: genericBar
    function serviceFor(_pluginId) { return null }
  }

  QtObject {
    id: genericBar
  }

  QtObject {
    id: genericShell
    property var bar: genericBar
    property var shellConfig: ({
      bar: {
        layout: {
          left: [
            { id: "omarchy.agents", refreshIntervalSec: 31,
              providers: { claude: { enabled: false } } },
            { id: "hancore.shibumi.ai", refreshIntervalSec: 33,
              providers: { claude: { enabled: true },
                codex: { enabled: false } } }
          ],
          center: [],
          right: []
        }
      }
    })
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.state" ? agentsState : null
    }
  }

  QtObject {
    id: fakeShell
    property var bar: fakeBar
    function serviceFor(pluginId) {
      if (pluginId === "hancore.shibumi.state") return fakeState
      if (pluginId === "hancore.shibumi.ai") return aiService
      return null
    }
  }

  QtObject {
    id: legacyBar
    function registeredWidgetSource(_id) { return "" }
    function widgetSettings(groupId, moduleId) {
      if (groupId !== "G7" || moduleId !== "hancore.shibumi.ai") return ({})
      return ({ aiTool: fakeState.selectedTool,
        providers: { claude: { enabled: true }, codex: { enabled: true } } })
    }
  }

  QtObject {
    id: legacyShell
    property var bar: legacyBar
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.state" ? fakeState : null
    }
  }

  Item {
    id: fakeBar
    visible: false
    width: 0
    height: 0
    property bool vertical: false
    property int barSize: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color customFill: "#929292"
    property color urgent: "#dd7788"
    property bool foregroundAnimationEnabled: false
    property bool v2ShellMode: false
    property bool customFillEnabled: false
    property bool agentsDisabled: false
    property var shell: fakeShell
    property var activePopout: null
    function widgetHasFill(_settings) {
      return fakeBar.customFillEnabled
    }
    function widgetContentColor(_settings, fallback) {
      return fakeBar.customFillEnabled ? fakeBar.background : fallback
    }
    property var visualTokens: ({
      slotHeight: 28,
      pillHeight: 24,
      pillRadius: 12,
      pillPaddingX: 9,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      compactGap: 5,
      labelSize: 12,
      panelBackground: "#181616",
      panelBorder: "#555050",
      panelBorderWidth: 1,
      panelRadius: 12,
      tileRadius: 10,
      sumi: "#999999",
      sumiHi: "#bbbbbb",
      separator: "#555555",
      fillIdle: "#221f1f",
      fillHover: "#33282a",
      fillActive: "#443034",
      fillPrimaryHover: "#ee8899",
      ink: fakeBar.foreground,
      seal: fakeBar.urgent,
      v2Shell: fakeBar.v2ShellMode,
      widgetHasFill: fakeBar.widgetHasFill,
      widgetContentColor: fakeBar.widgetContentColor
    })
    function registeredWidgetSource(_id) { return "" }
    function widgetSettings(groupId, moduleId) {
      if (groupId !== "G7") return ({})
      if (moduleId === "omarchy.agents") return ({
        refreshIntervalSec: 42,
        providers: {
          claude: { enabled: false },
          codex: { enabled: !fakeBar.agentsDisabled },
          fireworks: { enabled: false }
        }
      })
      return moduleId === "hancore.shibumi.ai" ? ({
        aiTool: fakeState.selectedTool,
        providers: { claude: { enabled: !fakeBar.agentsDisabled } }
      }) : ({})
    }
    function registerClickTarget(target) {
      if (root.clickTargets.indexOf(target) < 0)
        root.clickTargets = root.clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      root.clickTargets = root.clickTargets.filter(item => item !== target)
    }
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
  }

  Ai.OpenCodeProvider {
    id: openCodeParserProbe
    enabled: false
  }

  Ai.OpenCodeProvider {
    id: midnightRaceProbe
    enabled: true
    scannerCommandOverride: ["/bin/sh", "-c",
      "sleep 0.5; printf '{\"ready\":false}\\n'"]
    onScanGenerationChanged: root.midnightRaceStage = scanGeneration
  }

  Ai.Service {
    id: aiService
    shell: fakeShell
    runtimeProbesEnabled: false
    providerOverrides: [claudeProvider, codexProvider, openCodeProvider]
  }

  Ai.Service {
    id: agentsService
    shell: agentsShell
    agentRecordExpiryCheckIntervalMs: 20
    omarchyPath: Quickshell.env("SHIBUMI_TEST_OMARCHY_PATH")
    agentsSourceOverride: "file:///fixture/agents/Panel.qml"
    agentsUsageDirOverride: Quickshell.env("SHIBUMI_TEST_AGENT_USAGE_DIR")
  }

  Ai.Service {
    id: missingStateService
    shell: missingStateShell
    agentsSourceOverride: "file:///fixture/agents/Panel.qml"
    agentsUsageDirOverride: Quickshell.env("SHIBUMI_TEST_AGENT_USAGE_DIR")
  }

  Ai.Service {
    id: genericService
    shell: genericShell
    runtimeProbesEnabled: false
    agentsSourceOverride: "file:///fixture/agents/Panel.qml"
    agentsUsageDirOverride: Quickshell.env("SHIBUMI_TEST_AGENT_USAGE_DIR")
  }

  Ai.Service {
    id: legacyService
    shell: legacyShell
    modelUsageSourceOverride:
      Quickshell.env("SHIBUMI_TEST_MODEL_USAGE_SOURCE")
  }

  Item {
    id: emptyPanelAnchor
    visible: false
    width: 1
    height: 1
  }

  QtObject {
    id: emptyPanelOwner
    property bool opened: false
    function close() { opened = false }
    function switchPanel(_direction) { return false }
  }

  Ai.AiUsagePanel {
    id: emptyAgentsPanel
    anchorItem: emptyPanelAnchor
    bar: fakeBar
    ownerWidget: emptyPanelOwner
    aiService: agentsService
  }

  Loader {
    id: firstLoader
    active: true
    sourceComponent: Component {
      Ai.BarWidget {
        bar: fakeBar
        panelSource: Qt.resolvedUrl("fixtures/AiTestPanel.qml")
      }
    }
  }

  Loader {
    id: secondLoader
    active: true
    sourceComponent: Component {
      Ai.BarWidget {
        bar: fakeBar
        panelSource: Qt.resolvedUrl("fixtures/AiTestPanel.qml")
      }
    }
  }

  Timer {
    id: watchdog
    interval: 6000
    running: true
    onTriggered: root.fail("timeout in phase " + root.phase
      + " first=" + firstLoader.item + " second=" + secondLoader.item)
  }

  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      if (!root.midnightRacePassed) {
        root.midnightRaceTicks++
        if (root.midnightRaceStage === 1
            && midnightRaceProbe.scannerRunning) {
          midnightRaceProbe.handleLocalMidnight()
          if (!midnightRaceProbe.midnightRefreshPending
              || midnightRaceProbe.scanGeneration !== 1)
            return root.fail("OpenCode midnight started a parallel scanner")
          root.midnightRaceStage = -1
        } else if (root.midnightRaceStage === 2
            && midnightRaceProbe.scannerRunning) {
          if (midnightRaceProbe.midnightRefreshPending)
            return root.fail("OpenCode pending midnight refresh stayed queued")
          root.midnightRacePassed = true
          midnightRaceProbe.enabled = false
        } else if (root.midnightRaceStage > 2) {
          return root.fail("OpenCode midnight queued more than one refresh")
        } else if (root.midnightRaceTicks >= 30) {
          return root.fail("OpenCode midnight refresh race timed out")
        }
      }
      root.ticks++
      const first = firstLoader.item
      const second = secondLoader.item
      if (!first || (root.phase <= root.iconMatrix.length + 1 && !second)
          || (!root.waitingExpiryProbe
            && agentsService.providers.length !== 2)
          || genericService.providers.length !== 1
          || legacyService.providers.length !== 2
          || !root.midnightRacePassed) {
        if (root.ticks >= 20)
          root.fail("widget/agents fixtures did not resolve")
        return
      }
      if (root.ticks < 3) return

      if (root.phase < root.iconMatrix.length) {
        const expected = root.iconMatrix[root.phase]
        if (!first.visible || !second.visible || first.aiService !== aiService
            || second.aiService !== aiService
            || !root.iconContractMatches(first, expected)
            || !root.iconContractMatches(second, expected)
            || fakeState.selectedTool !== expected.providerId
            || fakeState.revision !== root.phase)
          return root.fail("provider/variant/custom-fill matrix phase " + root.phase)
        if (root.phase === 0
            && (first.usagePercent !== 3 || first.steppedPercent !== 5
              || aiService.providers.length !== 3
              || aiService.detectionReady
              || !root.agentsContractMatches()
              || !root.legacyContractMatches()
              || missingStateService.serviceActive
              || missingStateService.providers.length !== 0
              || genericService.agentsRefreshInterval !== 33000
              || !genericService.providerEnabled("claude")
              || genericService.providerEnabled("codex")
              || genericService.providerFor("claude") === null
              || genericService.providerFor("codex") !== null
              || emptyAgentsPanel.renderedProviderCount !== 2
              || emptyAgentsPanel.providerEmptyStateText
                !== "Run `claude auth login` to restore authoritative usage."
              || emptyAgentsPanel.primaryUsageVisible
              || emptyAgentsPanel.secondaryUsageVisible
              || emptyAgentsPanel.renderedModelCount !== 0
              || first.childPanelWidget("omarchy.agents") !== first
              || first.tooltipText.indexOf("5h: not reported by Codex RPC") < 0
              || first.tooltipText.indexOf("Codex (Pro Lite)") < 0
              || first.tooltipText.indexOf("5h tokens: 2.3K") < 0
              || first.tooltipText.indexOf("1h rate: 180/h") < 0
              || first.tooltipText.indexOf("Latest today: local-test") < 0
              || !root.openCodeParserContract()))
          return root.fail("Claude/agents provider metadata")
        if (root.phase === 0) {
          agentsState.g7Enabled = false
          agentsState.revision++
          if (agentsService.serviceActive
              || agentsService.providers.length !== 0)
            return root.fail("disabled G7 retained backend work")
          agentsState.g7Enabled = true
          agentsState.revision++
          fakeBar.agentsDisabled = true
          const probeCommand = agentsService.agentsUpdateCommand(false)
          if (probeCommand[probeCommand.length - 1] !== "--probe-only")
            return root.fail("OpenCode probe depends on enabled agent collectors")
          fakeBar.agentsDisabled = false
          legacyService.refreshAll(true)
        }
        if (root.phase === 0) root.stableProviderWidth = first.implicitWidth
        else if (first.implicitWidth !== root.stableProviderWidth
            || second.implicitWidth !== root.stableProviderWidth)
          return root.fail("provider switch changed the stable icon slot width")

        const nextPhase = root.phase + 1
        if (nextPhase < root.iconMatrix.length) {
          const next = root.iconMatrix[nextPhase]
          fakeBar.v2ShellMode = next.v2Shell
          fakeBar.customFillEnabled = next.customFill
          aiService.selectTool(next.providerId)
        } else {
          fakeBar.customFillEnabled = false
          first.interactionTarget.triggerPress(Qt.MiddleButton)
        }
        root.phase++
        root.ticks = 0
      } else if (root.phase === root.iconMatrix.length) {
        if (first.providerId !== "claude" || second.providerId !== "claude"
            || fakeState.selectedTool !== "claude"
            || fakeState.revision !== root.iconMatrix.length)
          return root.fail("middle-click provider cycle")
        first.interactionTarget.triggerPress(Qt.RightButton)
        first.open()
        second.open()
        root.phase++
        root.ticks = 0
      } else if (root.phase === root.iconMatrix.length + 1) {
        if (claudeProvider.refreshCount !== 1 || codexProvider.refreshCount !== 1
            || openCodeProvider.refreshCount !== 1
            || !first.panelLoaded || !second.panelLoaded
            || first.panelItem === second.panelItem)
          return root.fail("refresh forwarding or screen-local panels")
        first.close()
        secondLoader.active = false
        root.phase++
        root.ticks = 0
      } else {
        if (root.waitingBackendTransition) {
          if (agentsService.backendRunning
              || agentsService.backendProcessKind !== ""
              || agentsService.pendingBackendRefresh) {
            if (root.ticks >= 20)
              return root.fail("queued backend transition did not complete")
            return
          }
          if (!agentsService.agentsUpdateHealthy
              || agentsService.runningSettingsGeneration
                !== agentsService.providerSettingsGeneration
              || agentsService.providerFor("claude") === null
              || agentsService.providerFor("codex") === null)
            return root.fail("queued Agents update did not become current")
          stop()
          watchdog.stop()
          console.log("ai plugin smoke passed")
          Qt.quit()
          return
        }
        if (first.panelLoaded || secondLoader.item !== null
            || root.clickTargets.length !== 1)
          return root.fail("panel/widget teardown")
        if (!root.waitingExpiryProbe) {
          if (!root.readyRecordWithoutCurrentDataAccepted())
            return root.fail("ready empty/stale agents record contract")
          root.expiryProbeRecord = agentsService.agentsClaudeRecord
          const expiringRecord = ({})
          for (const key in root.expiryProbeRecord)
            expiringRecord[key] = root.expiryProbeRecord[key]
          expiringRecord.expiresAtMs = Date.now() + 30
          agentsService.agentsClaudeRecord = expiringRecord
          agentsService.providerRevision++
          root.waitingExpiryProbe = true
          root.ticks = 0
          return
        }
        if (agentsService.providerFor("claude") !== null) {
          if (root.ticks >= 20)
            return root.fail("loaded agent record expiry timer")
          return
        }
        agentsService.agentsClaudeRecord = root.expiryProbeRecord
        agentsService.providerRevision++
        root.waitingExpiryProbe = false
        agentsService.agentsUpdateHealthy = false
        agentsService.providerRevision++
        if (agentsService.providerFor("claude").ready
            || agentsService.providerFor("codex").ready
            || agentsService.usagePercent(
              agentsService.providerFor("claude")) !== -1
            || agentsService.usagePercent(
              agentsService.providerFor("codex")) !== -1)
          return root.fail("failed agents update did not suppress live quota")
        const backendGeneration = agentsService.providerSettingsGeneration
        agentsService.modelUsageSourceOverride =
          Quickshell.env("SHIBUMI_TEST_MODEL_USAGE_SOURCE")
        agentsService.agentsSourceOverride = ""
        if (agentsService.agentsBackendActive
            || agentsService.modelUsageSource === ""
            || agentsService.providerSettingsGeneration <= backendGeneration
            || agentsService.backendProcessKind !== "legacy-detection")
          return root.fail("Agents to legacy transition was not reconciled")
        agentsService.agentsSourceOverride =
          "file:///fixture/agents/Panel.qml"
        if (!agentsService.agentsBackendActive
            || agentsService.modelUsageSource !== ""
            || !agentsService.pendingBackendRefresh)
          return root.fail("legacy to Agents transition was not reconciled")
        if (legacyService.providerFor("claude").usageStatusText !== "refreshed"
            || legacyService.providerFor("codex").usageStatusText !== "refreshed")
          return root.fail("legacy fallback did not forward refresh")
        agentsService.applyAgentRecord("claude",
          '{"schemaVersion":2,"id":"claude","updatedAt":"2099-08-12T00:00:00Z"}')
        agentsService.applyAgentRecord("codex",
          '{"schemaVersion":1,"id":"claude","updatedAt":"2099-08-12T00:00:00Z"}')
        if (agentsService.providerFor("claude") !== null
            || agentsService.providerFor("codex") !== null)
          return root.fail("malformed agents records did not fail closed")
        root.waitingBackendTransition = true
        root.ticks = 0
      }
    }
  }
}
