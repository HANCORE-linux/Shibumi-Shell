pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/lib/presentation" as Presentation

// Layout derived from MIT-licensed Omarchy v4.0.4 plugins/agents/Panel.qml.
// See Omarchy-LICENSE. Shibumi retains its own data, selection and lifecycle.
ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var aiService
  readonly property var provider: aiService ? aiService.selectedProvider : null
  readonly property int renderedProviderCount: providerTabs.count
  readonly property var limitWindows: aiService ? aiService.limitWindows(provider) : []
  readonly property var headline: aiService ? aiService.bindingWindow(provider) : null
  readonly property bool headlineAlarm: !!headline && headline.percent >= 90
  readonly property color headlineColor: !providerReady ? panel.controlMuted
    : headlineAlarm ? Commons.Color.urgent : panel.controlForeground
  readonly property var providerLogo: heroMark
  readonly property string heroTitle: heroName.text
  readonly property string heroTier: heroPlan.text
  readonly property bool providerSwitchVisible: providerRow.visible
  readonly property bool balanceVisible: balanceSection.visible
  readonly property var balance: provider && provider.balance
    && typeof provider.balance.remaining === "number" && isFinite(provider.balance.remaining)
    && provider.balance.remaining >= 0 ? provider.balance : null
  readonly property real balanceRatio: balance && typeof balance.funded === "number"
    && isFinite(balance.funded) && balance.funded > 0 ? Math.min(1, balance.remaining / balance.funded) : -1
  readonly property string balanceDetail: balanceRatio >= 0 && typeof balance.spent === "number"
    && isFinite(balance.spent) && balance.spent >= 0
    ? money(balance.spent) + " spent of " + money(balance.funded) + " funded" + (balance.estimated === true ? " · estimated" : "") : ""
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
  contentWidth: fittedContentWidth(Commons.Style.space(380))
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    Commons.Style.space(640))

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

  function dayLabel(date) {
    const day = new Date(date + "T00:00:00"), today = new Date(nowMs)
    return day.toDateString() === today.toDateString() ? "Today"
      : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day.getDay()] || date
  }

  function money(value) {
    const currency = String(balance ? balance.currency || "USD" : "USD")
    return ({USD: "$", EUR: "€", GBP: "£"}[currency] || currency + " ") + Number(value).toFixed(2)
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
        spacing: Commons.Style.space(12)

        Item {
          id: header
          width: parent.width
          height: Commons.Style.space(52)

          Item {
            width: Commons.Style.space(36); height: width
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            Image {
              id: heroMark
              anchors.fill: parent
              readonly property string hostBase: {
                const id = panel.provider ? String(panel.provider.providerId || "") : "", root = panel.aiService ? String(panel.aiService.omarchyPath || "") : ""
                return /^[A-Za-z0-9_-]{1,64}$/.test(id) && /^\/(?!\/)/.test(root) && id !== "codex" && id !== "opencode" ? root.replace(/\/$/, "") + "/shell/plugins/agents/assets/" + id : ""
              }
              property FolderListModel hostMarks: FolderListModel {
                folder: heroMark.hostBase ? Commons.Util.fileUrl(heroMark.hostBase.slice(0, heroMark.hostBase.lastIndexOf("/"))) : Qt.resolvedUrl("assets")
                nameFilters: ["*.svg"]; showDirs: false }
              readonly property color surface: panel.shibumiTokens ? panel.shibumiTokens.panelBackground : Commons.Color.popups.background
              readonly property bool light: [surface.r, surface.g, surface.b].map(c => c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4))
                .reduce((sum, c, i) => sum + c * [0.2126, 0.7152, 0.0722][i], 0) >= 0.5
              visible: status === Image.Ready
              source: panel.provider && panel.provider.providerId === "codex" ? Qt.resolvedUrl("assets/codex.svg")
                : panel.provider && panel.provider.providerId === "opencode" ? Qt.resolvedUrl("assets/opencode-mark.svg") : !hostBase || hostMarks.status !== FolderListModel.Ready ? ""
                : hostMarks.count && light && hostMarks.indexOf(Commons.Util.fileUrl(hostBase + "-light.svg")) >= 0 ? Commons.Util.fileUrl(hostBase + "-light.svg")
                : hostMarks.count && hostMarks.indexOf(Commons.Util.fileUrl(hostBase + ".svg")) >= 0 ? Commons.Util.fileUrl(hostBase + ".svg") : ""
              fillMode: Image.PreserveAspectFit
              layer.enabled: hostBase === ""
              layer.effect: MultiEffect { colorization: 1; colorizationColor: panel.controlForeground }
            }
            Presentation.IconText {
              anchors.centerIn: parent
              visible: heroMark.status !== Image.Ready
              text: "smart_toy"
              color: panel.controlForeground
              font.pixelSize: Commons.Style.font.display
            }
          }

          Text {
            id: heroName
            anchors.left: parent.left
            anchors.leftMargin: Commons.Style.space(48)
            anchors.top: parent.top
            anchors.topMargin: Commons.Style.space(6)
            width: parent.width - actionRow.width - Commons.Style.space(56)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: panel.provider ? panel.providerHeading(panel.provider) : "AI USAGE"
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.subtitle
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
          }

          Text {
            id: heroPlan
            anchors.left: heroName.left; anchors.top: heroName.bottom
            width: heroName.width; elide: Text.ElideRight
            textFormat: Text.PlainText
            text: panel.tierLabel(panel.provider)
            color: panel.controlMutedHigh
            font.family: heroName.font.family
            font.pixelSize: Commons.Style.font.bodySmall
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
          visible: providerTabs.count > 1
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

        Text {
          visible: panel.providerEmptyStateText !== "" && !panel.balance
          width: parent.width
          text: panel.providerEmptyStateText
          wrapMode: Text.WordWrap
          color: panel.controlMutedHigh
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Rectangle {
          visible: !!panel.provider
          width: parent.width; height: statusRow.height + Commons.Style.space(16)
          radius: panel.controlRadius; color: panel.controlFillColor
          border.width: panel.controlBorderWidth; border.color: panel.controlBorderColor
          DetailRow {
            id: statusRow
            anchors.centerIn: parent; width: parent.width - Commons.Style.space(16)
            label: "Status"
            value: panel.provider ? String(panel.provider.usageStatusText || panel.providerStatusLabel) : ""
            wrapValue: true
          }
        }
        Column {
          id: balanceSection
          visible: !!panel.balance
          width: parent.width; spacing: Commons.Style.space(6)
          DetailRow { label: "BALANCE"; value: "" }
          DetailRow { label: "Prepaid credits"; value: panel.balance ? panel.money(panel.balance.remaining) : "" }
          Rectangle {
            width: parent.width; height: Commons.Style.space(4); radius: height / 2
            visible: panel.balanceRatio >= 0
            color: panel.controlActiveFillColor
            Rectangle {
              height: parent.height; radius: parent.radius
              width: parent.width * Math.max(0, panel.balanceRatio)
              color: width <= parent.width * 0.1 ? Commons.Color.urgent : panel.controlForeground
            }
          }
        }
        DetailRow { visible: panel.balanceDetail !== ""; label: ""; value: panel.balanceDetail; wrapValue: true }
        DetailRow { visible: panel.limitWindows.length > 0; label: "LIMITS"; value: "" }
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
          visible: panel.provider && !panel.providerHasUsage && !panel.balance
          label: "Limits"
          value: "Unavailable"
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
            daily: true
            entry: ({ name: panel.dayLabel(modelData.date), totalLabel: panel.aiService.formatTokens(modelData.messageCount),
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
            text: "TOKENS BY MODEL"
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
      : value >= 90 ? Commons.Color.urgent : panel.controlForeground
    width: parent.width
    height: Commons.Style.space(30)

    Text {
      id: usageLabel
      anchors.left: parent.left
      anchors.top: parent.top
      text: usageRow.label
      textFormat: Text.PlainText
      width: parent.width - usageValue.width - Commons.Style.space(8)
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
      anchors.top: parent.top
      text: Math.round(usageRow.value) + "%"
      color: usageRow.usageColor
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.bodySmall
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Commons.Style.space(4)
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
    property bool daily: false
    height: Commons.Style.space(daily ? 20 : 30)
    readonly property real percent: Math.max(0, Math.min(100,
      Number(entry && entry.pct) || 0))

    Text {
      id: modelName
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: modelRow.daily ? 0 : Commons.Style.space(8)
      width: modelRow.daily ? Commons.Style.space(52) : parent.width * 0.68
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
      id: modelValue
      anchors.right: parent.right
      anchors.rightMargin: modelRow.daily ? 0 : Commons.Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: String(modelRow.entry && modelRow.entry.totalLabel || "")
      color: panel.controlAccent
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }

    Rectangle {
      z: -1
      anchors.left: modelRow.daily ? modelName.right : parent.left
      anchors.right: modelRow.daily ? modelValue.left : parent.right
      anchors.margins: modelRow.daily ? Commons.Style.space(8) : 0
      anchors.verticalCenter: parent.verticalCenter
      height: modelRow.daily ? Commons.Style.space(4) : parent.height
      radius: height / 2
      color: Commons.Util.alpha(panel.controlAccent, 0.14)

      Rectangle {
        width: parent.width * modelRow.percent / 100
        height: parent.height
        radius: height / 2
        color: modelRow.daily ? panel.controlForeground : panel.controlActiveFillColor
        Behavior on width { NumberAnimation { duration: 300 } }
      }
    }

    MouseArea { id: modelHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    Presentation.ShibumiPillToolTip {
      panel: panel
      visible: !modelRow.daily && modelHover.containsMouse && text !== ""
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
    }
  }
}
