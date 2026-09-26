pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/lib/presentation" as Presentation

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var aiService
  readonly property var provider: aiService ? aiService.selectedProvider : null
  readonly property int renderedProviderCount: providerTabs.count
  readonly property var limitWindows: aiService ? aiService.limitWindows(provider) : []
  readonly property var headline: aiService ? aiService.bindingWindow(provider) : null
  readonly property bool headlineAlarm: !!headline && headline.percent >= 90
  readonly property color headlineColor: headlineUsage.usageColor
  readonly property bool primaryUsageVisible: limitWindows.length > 0
  readonly property bool secondaryUsageVisible: limitWindows.length > 1
  readonly property var days: provider ? provider.recentDays || [] : []
  readonly property int renderedDayCount: dayRepeater.count
  readonly property bool clockRunning: panelClock.running
  property double nowMs: Date.now()
  onOpenChanged: if (open) nowMs = Date.now()
  property Timer presentationClock: Timer {
    id: panelClock
    interval: 30000; repeat: true; running: panel.open
    onTriggered: panel.nowMs = Date.now()
  }
  readonly property bool limitsUnavailableVisible: limitsUnavailable.visible
  readonly property string todaySummary: provider && aiService ? [
    Number(provider.todayTotalTokens) > 0
      ? aiService.formatTokens(provider.todayTotalTokens) + " tokens" : "",
    Number(provider.todayPrompts) > 0 ? Math.round(Number(provider.todayPrompts))
      + (Number(provider.todayPrompts) === 1 ? " prompt" : " prompts") : "",
    Number(provider.todaySessions) > 0 ? Math.round(Number(provider.todaySessions))
      + (Number(provider.todaySessions) === 1 ? " session" : " sessions") : ""
  ].filter(value => value !== "").join(" · ") : ""
  readonly property var providerModels: provider
    && Array.isArray(provider.models) ? provider.models : []
  readonly property int renderedModelCount: modelRepeater.count
  readonly property bool providerReady: provider && provider.ready !== undefined
    ? provider.ready === true : true
  readonly property string providerStatusLabel: provider && aiService
    && typeof aiService.providerStatusText === "function"
    ? aiService.providerStatusText(provider)
    : providerReady ? "live" : "stale"
  readonly property bool providerHasUsage: provider
    && (Number(provider.rateLimitPercent) >= 0
      || Number(provider.secondaryRateLimitPercent) >= 0)
  readonly property bool providerHasCurrentData: provider && aiService
    && typeof aiService.providerHasCurrentData === "function"
    ? aiService.providerHasCurrentData(provider)
    : provider && (providerHasUsage
      || Number(provider.todayTotalTokens) > 0
      || Number(provider.todayPrompts) > 0
      || Number(provider.todaySessions) > 0
      || providerModels.length > 0)
  readonly property string providerEmptyStateText: !provider
    ? "No supported AI usage data was found."
    : providerHasCurrentData ? ""
      : aiService && typeof aiService.providerCurrentDataMessage === "function"
        ? aiService.providerCurrentDataMessage(provider)
        : String(provider.authHelpText || "")
          || "No current usage or limit data."

  owner: ownerWidget
  open: ownerWidget.opened
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(360))
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    Commons.Style.space(560))

  function moveProvider(direction) {
    if (aiService) aiService.cycleTool(direction)
  }

  function resetText(timestamp) {
    return provider && aiService
      ? aiService.resetText(provider, timestamp, nowMs) : ""
  }

  function paceText(limit) {
    const label = String(limit.label || "") + " " + String(limit.title || "")
    const match = /\b(\d+(?:\.\d+)?)\s*-?\s*(hours?|h|days?|d)\b/i.exec(label)
    const span = match ? Number(match[1]) * (/^h/i.test(match[2]) ? 3600000 : 86400000)
      : /\bweekly\b/i.test(label) ? 604800000 : /\bmonthly\b/i.test(label) ? 2592000000 : 0
    const remaining = Date.parse(limit.resetsAt) - nowMs, elapsed = span - remaining
    return providerReady && span > 0 && remaining > 0 && elapsed > 0
      ? "Pace: " + (limit.percent / 100 * span / elapsed).toFixed(1) + "×" : ""
  }

  function providerTabLabel(providerValue) {
    if (!providerValue) return "AI"
    const id = String(providerValue.providerId || "")
    if (id === "claude") return "Claude"
    if (id === "codex") return "Codex"
    if (id === "opencode") return "OpenCode"
    return String(providerValue.providerName || id || "AI")
  }

  function providerHeading(providerValue) {
    if (!providerValue) return "AI"
    const id = String(providerValue.providerId || "")
    if (id === "claude") return "Claude Code"
    if (id === "codex") return "OpenAI Codex"
    if (id === "opencode") return "OpenCode"
    return String(providerValue.providerName || id || "AI")
  }

  function tierLabel(providerValue) {
    if (!providerValue) return ""
    return aiService && typeof aiService.displayTierLabel === "function"
      ? aiService.displayTierLabel(providerValue.tierLabel)
      : String(providerValue.tierLabel || "")
  }

  function displayPercent(providerValue, value) {
    return aiService && typeof aiService.displayPercent === "function"
      ? aiService.displayPercent(providerValue, value) : Number(value)
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }
    onMoveRequested: function(dx, _dy) { if (dx !== 0) panel.moveProvider(dx) }

    Flickable {
      id: scroller
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: scroller.width
        spacing: Commons.Style.space(8)

        Item {
          id: header
          width: parent.width
          height: Commons.Style.space(28)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - actionRow.width - Commons.Style.space(8)
            elide: Text.ElideRight
            text: panel.provider ? panel.providerHeading(panel.provider)
              + " · " + panel.providerStatusLabel : "AI USAGE"
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.subtitle
            font.letterSpacing: 2
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          Row {
            id: actionRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Commons.Style.space(2)

            IconAction {
              icon: panel.aiService && panel.aiService.refreshing
                ? "sync" : "refresh"
              tooltip: panel.aiService && panel.aiService.refreshing
                ? "Refreshing usage" : "Refresh usage"
              action: function() { panel.aiService.refreshAll(true) }
            }

            IconAction {
              icon: "close"
              tooltip: "Close"
              action: function() { panel.ownerWidget.close() }
            }
          }
        }

        Row {
          id: providerRow
          width: parent.width
          height: Commons.Style.space(28)
          spacing: Commons.Style.space(6)

          Repeater {
            id: providerTabs
            model: panel.aiService ? panel.aiService.providers : []

            Rectangle {
              id: providerTab
              required property var modelData
              readonly property bool selected:
                panel.aiService.selectedTool === modelData.providerId
              readonly property bool hovered: tabMouse.containsMouse
              width: (providerRow.width - Math.max(0,
                (panel.aiService.providers.length - 1) * providerRow.spacing))
                / Math.max(1, panel.aiService.providers.length)
              height: parent.height
              radius: panel.controlRadius
              color: selected ? panel.controlActiveFillColor
                : hovered ? panel.controlHoverFillColor : panel.controlFillColor
              border.width: panel.controlBorderWidth
              border.color: selected || hovered ? panel.controlAccent
                : panel.controlBorderColor

              Behavior on color { ColorAnimation { duration: 100 } }
              Behavior on border.color { ColorAnimation { duration: 100 } }

              Text {
                anchors.centerIn: parent
                text: panel.providerTabLabel(providerTab.modelData)
                color: providerTab.selected || providerTab.hovered
                  ? panel.controlAccent : panel.controlForeground
                font.family: panel.bar ? panel.bar.fontFamily
                  : Commons.Style.font.family
                font.pixelSize: Commons.Style.font.bodySmall
                font.weight: providerTab.selected ? Font.Medium : Font.Normal
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.aiService.selectTool(providerTab.modelData.providerId)
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: panel.dividerColor
        }

        Item {
          visible: panel.tierLabel(panel.provider) !== ""
          width: parent.width
          height: visible ? Commons.Style.space(16) : 0

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.tierLabel(panel.provider)
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }
        }

        Text {
          visible: panel.providerEmptyStateText !== ""
          width: parent.width
          text: panel.providerEmptyStateText
          wrapMode: Text.WordWrap
          color: panel.controlMutedHigh
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        UsageRow {
          id: headlineUsage
          visible: !!panel.headline
          label: panel.headline ? panel.headline.title : ""
          value: panel.headline ? panel.headline.percent : 0
          dimmed: !panel.providerReady
        }
        Repeater {
          model: panel.limitWindows
          delegate: Column {
            id: windowRow
            required property var modelData
            width: contentColumn.width
            spacing: Commons.Style.space(4)
            UsageRow {
              label: windowRow.modelData.title
              value: windowRow.modelData.percent
              dimmed: !panel.providerReady
            }
            DetailRow {
              label: panel.resetText(windowRow.modelData.resetsAt) ? "Resets in" : ""
              value: [panel.resetText(windowRow.modelData.resetsAt), panel.paceText(windowRow.modelData)].filter(Boolean).join(" · ")
              wrapValue: true
            }
          }
        }
        DetailRow {
          id: limitsUnavailable
          visible: panel.provider && !panel.providerHasUsage
          label: "Limits"
          value: "Unavailable"
        }
        DetailRow {
          visible: panel.provider && String(panel.provider.usageStatusText || "") !== ""
          label: panel.provider && String(panel.provider.providerId || "") === "codex"
            ? "General limit" : "Status"
          value: panel.provider ? String(panel.provider.usageStatusText || "") : ""
        }
        DetailRow {
          visible: panel.provider && Number(panel.provider.windowTokens) > 0
          label: panel.provider && String(panel.provider.providerId || "")
            === "opencode" ? "5h tokens" : "Tokens"
          value: visible && panel.aiService
            ? panel.aiService.formatTokens(panel.provider.windowTokens) : ""
        }
        DetailRow {
          visible: panel.provider && Number(panel.provider.hourlyTokens) > 0
          label: panel.provider && String(panel.provider.providerId || "")
            === "opencode" ? "1h rate" : "Rate"
          value: visible && panel.aiService
            ? panel.aiService.formatTokens(panel.provider.hourlyTokens) + "/h" : ""
        }
        DetailRow {
          visible: panel.todaySummary !== ""
          label: "Today"
          value: panel.todaySummary
          wrapValue: true
        }
        DetailRow {
          visible: panel.provider && String(panel.provider.latestModel || "") !== ""
          label: panel.provider && String(panel.provider.providerId || "")
            === "opencode" ? "Latest today" : "Latest"
          value: panel.provider ? String(panel.provider.latestModel || "") : ""
        }

        DetailRow {
          visible: panel.days.length > 0
          label: "TOKENS BY DAY"
          value: ""
        }
        Repeater {
          id: dayRepeater
          model: panel.days
          delegate: ModelUsageRow {
            required property var modelData
            width: contentColumn.width
            entry: ({ name: modelData.date, totalLabel: panel.aiService.formatTokens(modelData.messageCount),
              pct: modelData.messageCount / Math.max(1, ...panel.days.map(day => day.messageCount)) * 100, detail: "" })
          }
        }
        Item {
          visible: panel.providerModels.length > 0
          width: parent.width
          height: visible ? Commons.Style.space(16) : 0

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "MODELS"
            color: panel.controlMutedHigh
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            font.letterSpacing: 1
            renderType: Text.NativeRendering
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: panel.provider && String(panel.provider.providerId || "")
              === "opencode" ? "today" : panel.provider && panel.provider.backend === "omarchy.agents" ? "all time" : "recent"
            color: panel.controlMuted
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            renderType: Text.NativeRendering
          }
        }

        Repeater {
          id: modelRepeater
          model: panel.providerModels
          delegate: ModelUsageRow {
            required property var modelData
            width: contentColumn.width
            entry: modelData
          }
        }
      }
    }
  }

  component IconAction: Ui.CursorSurface {
    id: iconAction
    required property string icon
    required property string tooltip
    required property var action
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

    Presentation.IconText {
      anchors.centerIn: parent
      text: iconAction.icon
      color: iconAction.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: iconAction.hasCursor = containsMouse
      onClicked: iconAction.action()
    }

    Presentation.ShibumiPillToolTip {
      panel: panel
      visible: iconAction.tooltip !== "" && actionMouse.containsMouse
      text: iconAction.tooltip
    }
  }

  component UsageRow: Item {
    id: usageRow
    required property string label
    required property real value
    property bool dimmed: false
    readonly property color usageColor: dimmed ? panel.controlMuted
      : value >= 90 ? Commons.Color.urgent : panel.controlAccent
    width: parent.width
    height: Commons.Style.space(16)

    Text {
      id: usageLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: usageRow.label
      textFormat: Text.PlainText
      width: Math.min(implicitWidth, parent.width * 0.45)
      elide: Text.ElideRight
      color: panel.controlMutedHigh
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.bodySmall
      font.letterSpacing: 1
      renderType: Text.NativeRendering
    }

    Text {
      id: usageValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: Math.round(usageRow.value) + "%"
      color: usageRow.usageColor
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.bodySmall
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }

    Rectangle {
      anchors.left: usageLabel.right
      anchors.leftMargin: Commons.Style.space(8)
      anchors.right: usageValue.left
      anchors.rightMargin: Commons.Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      height: Commons.Style.space(8)
      radius: height / 2
      color: Commons.Util.alpha(panel.controlAccent, 0.15)
      Rectangle {
        width: parent.width * Math.max(0, Math.min(100, usageRow.value)) / 100
        height: parent.height
        radius: height / 2
        color: usageRow.usageColor
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
      }
    }
  }

  component DetailRow: Row {
    required property string label
    required property string value
    property bool wrapValue: false
    width: parent.width
    height: wrapValue ? Math.max(Commons.Style.space(16), detailValue.implicitHeight)
      : Commons.Style.space(16)

    Text {
      width: parent.width * 0.45
      text: parent.label
      color: panel.controlMutedHigh
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.bodySmall
      renderType: Text.NativeRendering
    }
    Text {
      id: detailValue
      width: parent.width * 0.55
      wrapMode: parent.wrapValue ? Text.WordWrap : Text.NoWrap
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
      text: parent.value
      color: panel.controlForeground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.bodySmall
      renderType: Text.NativeRendering
    }
  }

  component ModelUsageRow: Item {
    id: modelRow
    required property var entry
    height: Commons.Style.space(42)
    readonly property real percent: Math.max(0, Math.min(100,
      Number(entry && entry.pct) || 0))

    Text {
      id: modelName
      anchors.left: parent.left
      anchors.top: parent.top
      width: parent.width * 0.68
      text: String(modelRow.entry && modelRow.entry.name || "")
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: panel.controlForeground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }

    Text {
      anchors.right: parent.right
      anchors.top: parent.top
      text: String(modelRow.entry && modelRow.entry.totalLabel || "")
      color: panel.controlAccent
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: modelName.bottom
      anchors.topMargin: Commons.Style.space(5)
      height: Commons.Style.space(6)
      radius: height / 2
      color: Commons.Util.alpha(panel.controlAccent, 0.14)

      Rectangle {
        width: parent.width * modelRow.percent / 100
        height: parent.height
        radius: height / 2
        color: panel.controlAccent
        Behavior on width { NumberAnimation { duration: 300 } }
      }
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      text: modelRow.entry && modelRow.entry.detail !== undefined ? modelRow.entry.detail
        : "I " + String(modelRow.entry && modelRow.entry.inputLabel || "0")
        + "  O " + String(modelRow.entry && modelRow.entry.outputLabel || "0")
        + (String(modelRow.entry && modelRow.entry.reasoningLabel || "0") !== "0"
          ? "  R " + String(modelRow.entry.reasoningLabel) : "")
        + (String(modelRow.entry && modelRow.entry.cacheReadLabel || "0") !== "0"
          ? "  CR " + String(modelRow.entry.cacheReadLabel) : "")
        + (String(modelRow.entry && modelRow.entry.cacheWriteLabel || "0") !== "0"
          ? "  CW " + String(modelRow.entry.cacheWriteLabel) : "")
        + (String(modelRow.entry && modelRow.entry.todayLabel || "0") !== "0"
          ? "  today " + String(modelRow.entry.todayLabel) : "")
      elide: Text.ElideRight
      color: panel.controlMutedHigh
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.space(9)
      renderType: Text.NativeRendering
    }
  }
}
