import QtQuick
import Quickshell
import "widgets" as Widgets

ShellRoot {
  id: root
  property int phase: 0
  property real stableProviderWidth: 0
  property var clickTargets: []

  function fail(message) {
    console.error("ai-usage-widget-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: claudeProvider
    property string providerId: "claude"
    property string providerName: "Claude"
    property real rateLimitPercent: 17
    property string rateLimitLabel: "Weekly"
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: -1
    property string secondaryRateLimitLabel: ""
    property string secondaryRateLimitResetAt: ""
    property real todayTotalTokens: 900
    property string tierLabel: "Pro"
    property string usageStatusText: "Allowed"
    property string latestModel: "claude-test"
  }

  QtObject {
    id: codexProvider
    property string providerId: "codex"
    property string providerName: "Codex"
    property real rateLimitPercent: 13
    property string rateLimitLabel: "Weekly"
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: -1
    property string secondaryRateLimitLabel: ""
    property string secondaryRateLimitResetAt: ""
    property real todayTotalTokens: 1200
    property string tierLabel: "Plus"
    property string usageStatusText: "Allowed"
    property string latestModel: "gpt-test"
  }

  QtObject {
    id: openCodeProvider
    property string providerId: "opencode"
    property string providerName: "OpenCode"
    property real rateLimitPercent: 22
    property string rateLimitLabel: "5h soft cap"
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: 8
    property string secondaryRateLimitLabel: "7d soft cap"
    property string secondaryRateLimitResetAt: ""
    property real todayTotalTokens: 400
    property string tierLabel: "Local messages"
    property string usageStatusText: "Local activity"
    property string latestModel: "local-test"
  }

  QtObject {
    id: sharedAi
    property var providers: [claudeProvider, codexProvider, openCodeProvider]
    property string selectedTool: "codex"
    readonly property var selectedProvider: selectedTool === "opencode"
      ? openCodeProvider : selectedTool === "claude"
        ? claudeProvider : codexProvider
    property bool refreshing: false
    property int refreshCount: 0
    property int cycleCount: 0
    function usagePercent(provider) { return Math.round(provider.rateLimitPercent) }
    function tooltipText() { return "Codex\nWeekly: 13%\n\nOpenCode\n5h: 22%" }
    function refreshAll(_force) { refreshCount++ }
    function cycleTool(direction) {
      cycleCount++
      selectedTool = direction < 0 ? "codex" : "opencode"
      return true
    }
    function selectTool(tool) { selectedTool = tool; return true }
    function resetText(_provider, _timestamp) { return "" }
    function formatTokens(value) { return String(value) }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#dd7788"
    property bool foregroundAnimationEnabled: false
    property var aiUsageService: sharedAi
    property var clickTargets: root.clickTargets
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
      labelSize: 12
    })
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
    function targetBelongsToWindow(_target, _window) { return false }
    property var activePopout: null
  }

  Widgets.AiUsageWidget {
    id: aiWidget
    bar: fakeBar
    aiServiceOverride: sharedAi
    panelSource: Qt.resolvedUrl("AiTestPanel.qml")
  }

  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      if (root.phase === 0) {
        if (!aiWidget.visible || aiWidget.providerId !== "codex"
            || aiWidget.usagePercent !== 13 || aiWidget.implicitWidth <= 0
            || aiWidget.providerIconSlotWidth !== 20
            || aiWidget.providerIconSlotHeight !== 16
            || aiWidget.claudeGlyphPixelSize !== 15
            || aiWidget.providerGlyphWidth !== 14
            || aiWidget.providerGlyphHeight !== 14
            || aiWidget.providerGlyphHorizontalOffset !== 0
            || aiWidget.providerContentHorizontalOffset !== -1
            || aiWidget.providerGlyphHorizontalOffset
              + aiWidget.providerContentHorizontalOffset !== -1
            || aiWidget.childPanelWidget("omarchy.agents") !== aiWidget
            || aiWidget.childPanelWidget("omarchy.model-usage") !== aiWidget)
          return root.fail("single-provider facade")
        root.stableProviderWidth = aiWidget.implicitWidth
        sharedAi.cycleTool(1)
        sharedAi.refreshAll(true)
        aiWidget.open()
      } else if (root.phase === 1) {
        if (aiWidget.providerId !== "opencode" || sharedAi.cycleCount !== 1
            || sharedAi.refreshCount !== 1 || !aiWidget.opened
            || !aiWidget.panelLoaded || !aiWidget.panelItem.ready
            || aiWidget.implicitWidth !== root.stableProviderWidth
            || aiWidget.providerGlyphWidth !== 20
            || aiWidget.providerGlyphHeight !== 12
            || aiWidget.providerGlyphHorizontalOffset !== 0
            || aiWidget.providerContentHorizontalOffset !== 0
            || aiWidget.providerGlyphHorizontalOffset
              + aiWidget.providerContentHorizontalOffset !== 0)
          return root.fail("provider switch/panel lifecycle")
        sharedAi.selectTool("claude")
      } else if (root.phase === 2) {
        if (aiWidget.providerId !== "claude"
            || aiWidget.implicitWidth !== root.stableProviderWidth
            || aiWidget.providerGlyphWidth !== 15
            || aiWidget.providerGlyphHeight !== 15
            || aiWidget.providerGlyphHorizontalOffset !== 0
            || aiWidget.providerContentHorizontalOffset !== 0
            || aiWidget.providerGlyphHorizontalOffset
              + aiWidget.providerContentHorizontalOffset !== 0)
          return root.fail("stable provider icon slot")
        aiWidget.close()
      } else {
        if (aiWidget.opened || aiWidget.panelLoaded)
          return root.fail("panel cleanup")
        stop()
        console.log("ai usage widget smoke passed")
        Qt.quit()
      }
      root.phase++
    }
  }
}
