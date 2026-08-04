pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "ai" as Ai

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property var clickTargets: []

  function fail(message) {
    console.error("ai-plugin-smoke:", message)
    Qt.exit(1)
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
    function setWidgetSetting(groupId, moduleId, key, value) {
      if (groupId !== "G7" || moduleId !== "hancore.shibumi.ai"
          || key !== "aiTool") return false
      selectedTool = String(value || "")
      revision++
      return true
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
    property color urgent: "#dd7788"
    property bool foregroundAnimationEnabled: false
    property var shell: fakeShell
    property var activePopout: null
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
      fillPrimaryHover: "#ee8899"
    })
    function registeredWidgetSource(_id) { return "" }
    function widgetSettings(groupId, moduleId) {
      return groupId === "G7" && moduleId === "hancore.shibumi.ai"
        ? ({ aiTool: fakeState.selectedTool }) : ({})
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

  Ai.Service {
    id: aiService
    shell: fakeShell
    runtimeProbesEnabled: false
    providerOverrides: [claudeProvider, codexProvider, openCodeProvider]
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
      root.ticks++
      const first = firstLoader.item
      const second = secondLoader.item
      if (!first || (root.phase < 3 && !second)) {
        if (root.ticks >= 10) root.fail("widget loaders did not resolve")
        return
      }
      if (root.ticks < 3) return

      if (root.phase === 0) {
        if (!first.visible || !second.visible || first.aiService !== aiService
            || second.aiService !== aiService || first.providerId !== "claude"
            || first.usagePercent !== 3 || first.steppedPercent !== 5
            || aiService.providers.length !== 3
            || aiService.detectionReady
            || first.tooltipText.indexOf("5h: not reported by Codex RPC") < 0
            || first.tooltipText.indexOf("Codex (Pro Lite)") < 0
            || first.tooltipText.indexOf("2.3K tokens · 180/h") < 0
            || first.tooltipText.indexOf("local-test") < 0)
          return root.fail("Claude percentage scaling/fill threshold")
        aiService.selectTool("codex")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (first.providerId !== "codex" || second.providerId !== "codex"
            || first.usagePercent !== 13 || fakeState.selectedTool !== "codex"
            || fakeState.revision !== 1)
          return root.fail("shared provider owner/readiness")
        first.interactionTarget.triggerPress(Qt.MiddleButton)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (first.providerId !== "opencode" || second.providerId !== "opencode"
            || fakeState.selectedTool !== "opencode" || fakeState.revision !== 2)
          return root.fail("state-owned provider selection")
        first.interactionTarget.triggerPress(Qt.RightButton)
        first.open()
        second.open()
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
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
        if (first.panelLoaded || secondLoader.item !== null
            || root.clickTargets.length !== 1)
          return root.fail("panel/widget teardown")
        stop()
        watchdog.stop()
        console.log("ai plugin smoke passed")
        Qt.quit()
      }
    }
  }
}
