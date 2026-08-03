pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var notificationService
  readonly property int pendingCount: notificationService
    && notificationService.pendingModel
    ? notificationService.pendingModel.count : 0
  readonly property int recentCount: notificationService
    && notificationService.pastModel
    ? notificationService.pastModel.count : 0
  readonly property int activeCount: pendingCount + recentCount
  readonly property var activeRows: {
    const rows = []
    function append(model, bucket) {
      if (!model) return
      for (let index = 0; index < model.count; index++) {
        const entry = model.get(index)
        if (!entry) continue
        rows.push({
          bucket: bucket,
          sourceIndex: index,
          app: String(entry.app || ""),
          appIcon: String(entry.appIcon || ""),
          summary: String(entry.summary || ""),
          body: String(entry.body || "")
        })
      }
    }
    append(notificationService ? notificationService.pendingModel : null,
      "pending")
    append(notificationService ? notificationService.pastModel : null,
      "past")
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
    if (typeof notificationService.clearPending === "function")
      notificationService.clearPending()
    if (typeof notificationService.clearPast === "function")
      notificationService.clearPast()
  }

  function openNotification(bucket, index) {
    if (!notificationService) {
      closePanel()
      return
    }
    const model = bucket === "past" ? notificationService.pastModel
      : notificationService.pendingModel
    if (!model || index < 0 || index >= model.count) {
      closePanel()
      return
    }
    const entry = model.get(index)
    if (entry && typeof notificationService.focusApp === "function")
      notificationService.focusApp(entry)
    closePanel()
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
    if (!chromium) return text
    return text
      .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
      .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
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
          text: panel.activeCount > 0
            ? "Notifications · " + panel.activeCount : "Notifications"
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

      Item {
        id: listViewport
        width: parent.width
        height: notificationList.count > 0
          ? Math.min(notificationList.contentHeight, 420)
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
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: panel.openNotification(notificationRow.bucket,
                notificationRow.sourceIndex)
            }

            Column {
              id: rowContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 8
              anchors.rightMargin: 26
              spacing: 3

              Text {
                width: parent.width
                text: notificationRow.app || "App"
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
              width: 18
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
                font.pixelSize: 10
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
          text: "No notifications"
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
        visible: panel.activeCount > 0
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

    IconText {
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

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
