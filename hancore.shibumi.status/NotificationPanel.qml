pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/lib/presentation" as Presentation

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var notificationService
  readonly property bool liveAvailable: notificationService
    && notificationService.liveAvailable === true
  property bool showingRecent: !liveAvailable
  property double nowMs: Date.now()
  onOpenChanged: if (open) nowMs = Date.now()
  property Timer relativeClock: Timer {
    interval: 60000
    repeat: true
    running: panel.open
    onTriggered: panel.nowMs = Date.now()
  }
  readonly property bool historyAvailable: notificationService
    && notificationService.historyAvailable === true
  function paletteColor(id, fallback) {
    const shell = panel.bar && panel.bar.shell
    const state = shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor("hancore.shibumi.state") : null
    return state && typeof state.paletteColor === "function"
      ? state.paletteColor(id) : fallback
  }

  readonly property color liveHighlight: paletteColor("color03",
    panel.controlAccent)
  readonly property color recentHighlight: paletteColor("color04",
    panel.controlAccent)
  readonly property int pendingCount: notificationService
    && notificationService.pendingModel
    ? notificationService.pendingModel.count : 0
  readonly property int recentCount: notificationService
    && notificationService.pastModel
    ? notificationService.pastModel.count : 0
  readonly property int activeCount: pendingCount + recentCount
  readonly property int displayedCount: showingRecent
    ? recentCount : pendingCount
  // Omarchy 4.0.3 exposes no history model. The adapter reads the same
  // host-owned compact JSON directory independently of this panel.
  readonly property var notificationListView: notificationList
  readonly property var activeRows: {
    const groups = new Map()
    function append(model, bucket) {
      if (!model) return
      for (let index = 0; index < model.count; index++) {
        const entry = model.get(index)
        if (!entry) continue
        const app = String(entry.app || "").trim()
        if (!groups.has(app)) groups.set(app, [])
        groups.get(app).push({
          bucket: bucket,
          sourceIndex: index,
          app: app,
          appIcon: String(entry.appIcon || ""),
          summary: String(entry.summary || ""),
          body: String(entry.body || ""),
          details: rowDetails(entry),
          liveToken: bucket === "pending" ? String(entry.liveToken || "") : ""
        })
      }
    }
    const model = showingRecent
      ? (notificationService ? notificationService.pastModel : null)
      : (notificationService ? notificationService.pendingModel : null)
    append(model, showingRecent ? "past" : "pending")
    const rows = []
    groups.forEach(group => group.forEach((row, index) =>
      rows.push(Object.assign(row, { groupCount: group.length, groupStart: index === 0 }))))
    return rows
  }

  owner: ownerWidget
  open: ownerWidget.notificationPanelOpen && notificationService !== null
  focusTarget: keyCatcher
  padding: 12
  contentWidth: fittedContentWidth(320)
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    540)

  function closePanel() {
    ownerWidget.closeNotificationPanel()
  }

  function selectTab(tab) {
    const recent = String(tab || "") === "recent"
    if (recent && (!historyAvailable || !showHistory())) return false
    if (!recent && !liveAvailable) return false
    showingRecent = recent
    return true
  }

  Component.onCompleted: if (showingRecent) showHistory()

  function showHistory() {
    if (!notificationService || !historyAvailable
        || typeof notificationService.showHistory !== "function")
      return false
    return notificationService.showHistory() !== false
  }

  function setDnd(value) {
    if (notificationService
        && typeof notificationService.setDoNotDisturb === "function")
      notificationService.setDoNotDisturb(value === true)
  }

  function dismiss(bucket, index) {
    if (!notificationService) return
    if (bucket === "past"
        && typeof notificationService.dismissPast === "function")
      notificationService.dismissPast(index)
    else if (bucket === "pending"
        && typeof notificationService.dismissPending === "function")
      notificationService.dismissPending(index)
  }

  function clearActive() {
    if (!notificationService) return
    if (showingRecent
        && typeof notificationService.clearPast === "function")
      notificationService.clearPast()
    else if (!showingRecent
        && typeof notificationService.clearPending === "function")
      notificationService.clearPending()
  }

  // The entry is the identity captured on press, never a current model index.
  function openNotification(bucket, entry) {
    if (bucket === "pending" && entry && notificationService
        && notificationService.invokeLive(entry)) closePanel()
    else if (bucket === "past" && typeof entry === "string"
        && entry.trim() && !/[\x00-\x1f\x7f]/.test(entry)
        && notificationService && notificationService.focusApp({ app: entry.trim() }, true)) closePanel()
  }

  function safeIconSource(icon) {
    let value = String(icon || "")
    if (value.startsWith("file:///")) {
      try { value = decodeURIComponent(value.slice(7)) } catch (_error) { return "" }
    }
    return /^(?:[a-z0-9][a-z0-9._-]*|\/[^\x00-\x1f?#]+)$/i.test(value)
      ? Quickshell.iconPath(value, true) : ""
  }

  function relativeTime(timestamp) {
    const stamp = Number(timestamp), age = nowMs - stamp
    if (!(stamp > 0) || !isFinite(age) || age < 0) return ""
    if (age < 60000) return "now"
    if (age < 3600000) return Math.floor(age / 60000) + "m ago"
    if (age < 86400000) return Math.floor(age / 3600000) + "h ago"
    if (age < 604800000) return Math.floor(age / 86400000) + "d ago"
    const date = new Date(stamp)
    return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][date.getMonth()]
      + " " + date.getDate() + (date.getFullYear() === new Date(nowMs).getFullYear() ? "" : ", " + date.getFullYear())
  }

  function rowDetails(entry) {
    return [relativeTime(entry.timestamp), ["Low", "Normal", "Critical"][entry.urgency] || ""].filter(Boolean).join(" · ")
  }

  function sanitizedBody(body, app, appIcon) {
    let text = String(body || "").replace(/<img[^>]*>/gi, "")
    const source = (String(app || "") + "\n"
      + String(appIcon || "")).toLowerCase()
    const chromium = source.indexOf("chrom") >= 0
      || source.indexOf("brave") >= 0
      || source.indexOf("vivaldi") >= 0
      || source.indexOf("microsoft-edge") >= 0
      || source.indexOf("opera") >= 0
    if (chromium) text = text
      .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
      .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
    return text.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "")
      .replace(/&(amp|lt|gt|quot|apos|nbsp);/g, (_match, key) =>
        ({ amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " })[key]).trim()
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.closePanel()
    onTabRequested: function(direction) {
      if (panel.ownerWidget
          && typeof panel.ownerWidget.switchPanel === "function")
        panel.ownerWidget.switchPanel(direction)
    }

    Column {
      id: contentColumn
      width: parent.width
      spacing: 8

      Item {
        width: parent.width
        height: 24

        Text {
          anchors.left: parent.left
          anchors.right: panel.shellStyle === "shibumi"
            ? closeText.left : closeAction.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: panel.showingRecent
            ? (panel.displayedCount > 0
              ? "Recent notifications · " + panel.displayedCount
              : "Recent notifications")
            : panel.displayedCount > 0
              ? "Live notifications · " + panel.displayedCount
              : "Live notifications"
          color: panel.controlForeground
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 13
          font.letterSpacing: 2
          font.weight: Font.Medium
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Text {
          id: closeText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: panel.shellStyle === "shibumi"
          text: "\u2715"
          color: closeMouse.containsMouse
            ? panel.controlAccent : panel.controlMuted
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 12
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 120 } }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.closePanel()
          }
        }

        IconAction {
          id: closeAction
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: panel.shellStyle !== "shibumi"
          icon: "close"
          tooltip: "Close"
          onClicked: panel.closePanel()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Row {
        id: tabRow
        visible: panel.liveAvailable
        width: parent.width
        height: visible ? 28 : 0
        spacing: 6

        Rectangle {
          width: panel.liveAvailable
            ? (parent.width - parent.spacing) / 2 : parent.width
          height: parent.height
          radius: panel.controlRadius
          color: panel.showingRecent
            ? Commons.Util.alpha(panel.recentHighlight, 0.16)
            : panel.controlFillColor
          border.width: panel.controlBorderWidth
          border.color: panel.showingRecent
            ? panel.recentHighlight : panel.controlBorderColor

          Text {
            anchors.centerIn: parent
            text: "Recent"
            color: panel.recentHighlight
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.selectTab("recent")
          }
        }

        Rectangle {
          visible: panel.liveAvailable
          width: visible ? (parent.width - parent.spacing) / 2 : 0
          height: parent.height
          radius: panel.controlRadius
          color: !panel.showingRecent
            ? Commons.Util.alpha(panel.liveHighlight, 0.16)
            : panel.controlFillColor
          border.width: panel.controlBorderWidth
          border.color: !panel.showingRecent
            ? panel.liveHighlight : panel.controlBorderColor

          Text {
            anchors.centerIn: parent
            text: "Live"
            color: panel.liveHighlight
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 11
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.selectTab("live")
          }
        }
      }

      Item {
        id: listViewport
        width: parent.width
        height: notificationList.count > 0
          ? Math.min(notificationList.contentHeight, 384)
          : emptyLabel.implicitHeight

        ListView {
          id: notificationList
          anchors.fill: parent
          visible: count > 0
          clip: true
          spacing: 6
          boundsBehavior: Flickable.StopAtBounds
          model: panel.activeRows

          delegate: Rectangle {
            id: notificationRow
            required property int index
            required property string bucket
            required property int sourceIndex
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string liveToken
            required property string details
            required property int groupCount
            required property bool groupStart

            readonly property string cleanBody: panel.sanitizedBody(
              body, app, appIcon)

            width: ListView.view ? ListView.view.width : 0
            height: rowContent.implicitHeight + 16
            radius: panel.controlRadius
            color: rowHover.containsMouse
              ? panel.controlHoverFillColor : panel.controlFillColor
            border.width: panel.controlBorderWidth
            border.color: rowHover.containsMouse
              ? panel.controlHoverBorderColor : panel.controlBorderColor

            MouseArea {
              id: rowHover
              property string pressedToken: ""
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPressed: pressedToken = notificationRow.bucket === "pending"
                ? notificationRow.liveToken : notificationRow.app
              onClicked: panel.openNotification(notificationRow.bucket, pressedToken)
            }

            Image {
              id: appImage
              anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 8
              width: 18; height: 18
              source: panel.safeIconSource(notificationRow.appIcon)
              visible: status === Image.Ready
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }

            Column {
              id: rowContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 8
              anchors.rightMargin: 26
              anchors.leftMargin: appImage.visible ? 32 : 8
              spacing: 3

              Text {
                width: parent.width
                text: (notificationRow.bucket === "past" ? "RECENT" : "LIVE")
                  + (notificationRow.details ? " · " + notificationRow.details : "")
                elide: Text.ElideRight
                color: notificationRow.bucket === "past"
                  ? panel.recentHighlight : panel.liveHighlight
                font.family: panel.bar ? panel.bar.fontFamily
                  : Commons.Style.font.family
                font.pixelSize: 9
                font.letterSpacing: 1.2
                font.weight: Font.Medium
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                visible: notificationRow.groupStart
                text: (notificationRow.app || "App") + " · " + notificationRow.groupCount
                textFormat: Text.PlainText
                color: panel.controlMutedHigh
                font.family: panel.bar ? panel.bar.fontFamily
                  : Commons.Style.font.family
                font.pixelSize: 10
                font.letterSpacing: 0.5
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                visible: text.length > 0
                text: notificationRow.summary
                textFormat: Text.PlainText
                color: panel.controlForeground
                font.family: panel.bar ? panel.bar.fontFamily
                  : Commons.Style.font.family
                font.pixelSize: 11
                elide: Text.ElideRight
                renderType: Text.NativeRendering
              }

              Text {
                width: parent.width
                visible: text.length > 0
                text: notificationRow.cleanBody
                color: Commons.Util.alpha(panel.controlForeground, 0.6)
                font.family: panel.bar ? panel.bar.fontFamily
                  : Commons.Style.font.family
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
              }
            }

            Item {
              visible: notificationRow.bucket === "pending"
                || notificationService.pastDismissAvailable === true
              width: visible ? 18 : 0
              height: 18
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: 4
              z: 2

              Text {
                anchors.centerIn: parent
                text: "✕"
                color: dismissMouse.containsMouse
                  ? panel.controlAccent
                  : Commons.Util.alpha(panel.controlForeground, 0.45)
                font.family: panel.bar ? panel.bar.fontFamily
                  : Commons.Style.font.family
                font.pixelSize: 12
                renderType: Text.NativeRendering
              }

              MouseArea {
                id: dismissMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.dismiss(notificationRow.bucket,
                  notificationRow.sourceIndex)
              }
            }
          }
        }

        Text {
          id: emptyLabel
          anchors.centerIn: parent
          visible: notificationList.count === 0
          text: panel.showingRecent && notificationService.historyState !== "ready"
            ? notificationService.historyState === "loading" ? "Loading recent notifications…"
              : "Recent notifications unavailable" : "No notifications"
          color: Commons.Util.alpha(panel.controlForeground, 0.3)
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }
      }

      Rectangle {
        width: parent.width
        height: 28
        visible: panel.showingRecent
          ? panel.recentCount > 0
            && notificationService.pastClearAvailable === true
          : panel.pendingCount > 0
        radius: panel.controlRadius
        color: clearMouse.containsMouse
          ? panel.controlHoverFillColor : panel.controlFillColor
        border.width: panel.controlBorderWidth
        border.color: clearMouse.containsMouse
          ? panel.controlHoverBorderColor : panel.controlBorderColor

        Text {
          anchors.centerIn: parent
          text: "Clear all"
          color: clearMouse.containsMouse
            ? panel.controlAccent : panel.controlMutedHigh
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: clearMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.clearActive()
        }
      }
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

    Presentation.IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    Presentation.ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
