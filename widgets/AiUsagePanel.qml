pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var aiService
  readonly property var provider: aiService ? aiService.selectedProvider : null
  readonly property int renderedProviderCount: providerTabs.count
  readonly property bool primaryUsageVisible: primaryUsage.visible
  readonly property bool secondaryUsageVisible: secondaryUsage.visible
  readonly property var providerModels: provider
    && Array.isArray(provider.models) ? provider.models : []
  readonly property int renderedModelCount: modelRepeater.count
  readonly property bool providerReady: provider && provider.ready !== undefined
    ? provider.ready === true : true
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
      ? aiService.resetText(provider, timestamp) : ""
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
            text: "AI USAGE"
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
          visible: panel.provider !== null
          width: parent.width
          height: visible ? Commons.Style.space(16) : 0

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.provider ? panel.providerHeading(panel.provider)
              + (panel.tierLabel(panel.provider) !== ""
                ? "  · " + panel.tierLabel(panel.provider) : "") : ""
            color: panel.controlForeground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: panel.providerReady ? "live" : "stale"
            color: panel.providerReady ? panel.controlMuted
              : panel.controlAccent
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
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
          id: primaryUsage
          visible: panel.provider && Number(panel.provider.rateLimitPercent) >= 0
          label: panel.provider ? String(panel.provider.rateLimitLabel || "Primary") : ""
          value: panel.provider ? panel.displayPercent(panel.provider,
            panel.provider.rateLimitPercent) : 0
          dimmed: !panel.providerReady
        }

        UsageRow {
          id: secondaryUsage
          visible: panel.provider && Number(panel.provider.secondaryRateLimitPercent) >= 0
          label: panel.provider
            ? String(panel.provider.secondaryRateLimitLabel || "Secondary") : ""
          value: panel.provider ? panel.displayPercent(panel.provider,
            panel.provider.secondaryRateLimitPercent) : 0
          dimmed: !panel.providerReady
        }

        DetailRow {
          visible: primaryUsage.visible && panel.resetText(
            panel.provider.rateLimitResetAt) !== ""
          label: primaryUsage.label + " resets in"
          value: visible ? panel.resetText(panel.provider.rateLimitResetAt) : ""
        }
        DetailRow {
          visible: secondaryUsage.visible && panel.resetText(
            panel.provider.secondaryRateLimitResetAt) !== ""
          label: secondaryUsage.label + " resets in"
          value: visible ? panel.resetText(
            panel.provider.secondaryRateLimitResetAt) : ""
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
          visible: panel.provider && Number(panel.provider.todayTotalTokens) > 0
          label: "Today"
          value: visible && panel.aiService
            ? panel.aiService.formatTokens(panel.provider.todayTotalTokens) + " tokens" : ""
        }
        DetailRow {
          visible: panel.provider && Number(panel.provider.todayPrompts) > 0
          label: "Today prompts"
          value: visible ? String(Math.round(
            Number(panel.provider.todayPrompts) || 0)) : ""
        }
        DetailRow {
          visible: panel.provider && Number(panel.provider.todaySessions) > 0
          label: "Today sessions"
          value: visible ? String(Math.round(
            Number(panel.provider.todaySessions) || 0)) : ""
        }
        DetailRow {
          visible: panel.provider && String(panel.provider.latestModel || "") !== ""
          label: panel.provider && String(panel.provider.providerId || "")
            === "opencode" ? "Latest today" : "Latest"
          value: panel.provider ? String(panel.provider.latestModel || "") : ""
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
              === "opencode" ? "today" : "recent"
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

    IconText {
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

    ShibumiPanelToolTip {
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
    width: parent.width
    height: Commons.Style.space(16)

    Text {
      id: usageLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: usageRow.label
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
      color: usageRow.dimmed ? panel.controlMuted : panel.controlAccent
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
        color: panel.controlAccent
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
      }
    }
  }

  component DetailRow: Row {
    required property string label
    required property string value
    width: parent.width
    height: Commons.Style.space(16)

    Text {
      width: parent.width * 0.45
      text: parent.label
      color: panel.controlMutedHigh
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.bodySmall
      renderType: Text.NativeRendering
    }
    Text {
      width: parent.width * 0.55
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
      text: "I " + String(modelRow.entry && modelRow.entry.inputLabel || "0")
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
