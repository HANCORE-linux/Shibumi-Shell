pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "ai" as Ai

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property var clickTargets: []
  property var iconMatrix: [
    { providerId: "claude", v2Shell: false, customFill: false, baseOpacity: 0.25 },
    { providerId: "codex", v2Shell: false, customFill: false, baseOpacity: 0.65 },
    { providerId: "opencode", v2Shell: false, customFill: false, baseOpacity: 0.5 },
    { providerId: "claude", v2Shell: false, customFill: true, baseOpacity: 0.25 },
    { providerId: "codex", v2Shell: false, customFill: true, baseOpacity: 0.65 },
    { providerId: "opencode", v2Shell: false, customFill: true, baseOpacity: 0.5 },
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

  function iconContractMatches(widget, expected) {
    const customFillActive = expected.v2Shell && expected.customFill
    const expectedBase = customFillActive
      ? fakeBar.background : fakeBar.foreground
    const expectedUsage = customFillActive
      ? fakeBar.background : fakeBar.urgent
    const customBaseContrast = root.contrastRatio(
      root.composite(expectedBase, fakeBar.customFill, expected.baseOpacity),
      fakeBar.customFill)
    return widget.providerId === expected.providerId
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
    property color customFill: "#929292"
    property color urgent: "#dd7788"
    property bool foregroundAnimationEnabled: false
    property bool v2ShellMode: false
    property bool customFillEnabled: false
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
      if (!first || (root.phase <= root.iconMatrix.length + 1 && !second)) {
        if (root.ticks >= 10) root.fail("widget loaders did not resolve")
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
              || first.tooltipText.indexOf("5h: not reported by Codex RPC") < 0
              || first.tooltipText.indexOf("Codex (Pro Lite)") < 0
              || first.tooltipText.indexOf("2.3K tokens · 180/h") < 0
              || first.tooltipText.indexOf("local-test") < 0))
          return root.fail("Claude percentage scaling/provider metadata")

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
