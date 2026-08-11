pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  required property var updateService
  required property var panel

  property string confirmAction: ""
  property string confirmThemeName: ""

  readonly property var themeStatus: updateService
    ? updateService.themeState : Model.emptyThemeState()
  readonly property var themes: themeStatus
    && Array.isArray(themeStatus.themes) ? themeStatus.themes : []
  readonly property var currentTheme: updateService
    ? updateService.currentTheme() : null
  readonly property bool actionIdle: updateService
    && updateService.actionKind === "" && !updateService.themeRefreshing
  readonly property color foreground: panel.controlForeground
  readonly property color dim: panel.controlMuted
  readonly property color urgent: panel.bar
    ? panel.bar.urgent : panel.controlAccent
  readonly property string fontFamily: panel.bar
    ? String(panel.bar.fontFamily || Commons.Style.font.family)
    : Commons.Style.font.family

  function summaryText() {
    if (!updateService) return "Update service is loading"
    if (updateService.themeRefreshing) return "Checking user Git themes…"
    if (updateService.themeError !== "") return updateService.themeError
    if (Number(themeStatus.checkedEpoch || 0) <= 0)
      return "User themes have not been checked"
    if (themeStatus.total === 0) return "No user Git themes installed"
    if (themeStatus.outdated === 0 && themeStatus.review === 0)
      return themeStatus.total + " user theme"
        + (themeStatus.total === 1 ? " is" : "s are") + " up to date"
    const parts = []
    if (themeStatus.actionable > 0)
      parts.push(themeStatus.actionable + " ready")
    if (themeStatus.blocked > 0)
      parts.push(themeStatus.blocked + " blocked")
    const otherReview = Math.max(0,
      Number(themeStatus.review || 0) - Number(themeStatus.blocked || 0))
    if (otherReview > 0)
      parts.push(otherReview + (otherReview === 1
        ? " needs review" : " need review"))
    return parts.join(" · ")
  }

  function stateLabel(theme) {
    if (!theme) return "unknown"
    if (updateService.actionName === theme.name) {
      if (updateService.actionKind === "remove") return "removing"
      if (updateService.actionKind === "reinstall") return "reinstalling"
      if (updateService.actionKind === "reapply") return "re-applying"
      return "updating"
    }
    if (theme.state === "update") return "ready"
    if (theme.state === "clean") return "clean"
    if (theme.state === "unreachable") return "offline"
    if (theme.state === "local-edits") {
      if (theme.reason === "untracked-conflict") return "conflict"
      if (theme.reason === "tracked-edits") return "edits"
      return "changes"
    }
    if (theme.state === "local-commits") return "commits"
    if (theme.state === "diverged") return "diverged"
    return "review"
  }

  function stateColor(theme) {
    if (!theme) return dim
    if (theme.state === "update") return panel.controlAccent
    if (theme.state === "clean") return dim
    if (theme.state === "unreachable" || theme.state === "invalid")
      return urgent
    return foreground
  }

  function canReview(theme) {
    return theme && Number(theme.behind || 0) > 0
      && String(theme.targetCommit || "") !== ""
  }

  function canUpdate(theme) {
    return theme && theme.state === "update"
      && String(theme.targetCommit || "") !== ""
  }

  function canReinstall(theme) {
    return theme && theme.current !== true && Model.canReinstallTheme(theme)
  }

  function canRemove(theme) {
    return theme && theme.current !== true
      && /^[A-Za-z0-9._-]+$/.test(String(theme.name || ""))
  }

  function openThemeReview(theme) {
    if (!updateService.viewThemeChanges(theme)) return false
    if (panel.ownerWidget
        && typeof panel.ownerWidget.close === "function")
      panel.ownerWidget.close()
    return true
  }

  function armAction(kind, theme) {
    if (!actionIdle || !theme) return
    confirmAction = String(kind || "")
    confirmThemeName = String(theme.name || "")
  }

  function cancelAction() {
    confirmAction = ""
    confirmThemeName = ""
  }

  function confirmActionFor(theme) {
    if (!theme || String(theme.name || "") !== confirmThemeName) return
    let started = false
    if (confirmAction === "reinstall")
      started = updateService.reinstallTheme(theme)
    else if (confirmAction === "remove")
      started = updateService.removeTheme(theme.name)
    if (started) cancelAction()
  }

  onThemesChanged: {
    if (confirmThemeName === "") return
    for (let index = 0; index < themes.length; index++)
      if (themes[index].name === confirmThemeName) return
    cancelAction()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Commons.Style.space(7)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 1

      Text {
        Layout.fillWidth: true
        text: root.summaryText()
        color: root.updateService.themeError !== ""
          ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.bodySmall
        font.weight: root.themeStatus.actionable > 0
          ? Font.Medium : Font.Normal
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        text: Model.checkedLabel(root.themeStatus.checkedEpoch)
          + (root.themeStatus.degraded ? " · check incomplete" : "")
        color: root.themeStatus.degraded ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        Layout.fillWidth: true
        visible: root.updateService.actionStatus !== ""
          || root.updateService.actionError !== ""
        text: root.updateService.actionError !== ""
          ? root.updateService.actionError : root.updateService.actionStatus
        color: root.updateService.actionError !== ""
          ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: root.panel.dividerColor
    }

    Row {
      Layout.fillWidth: true
      Layout.preferredHeight: Commons.Style.space(16)
      spacing: Commons.Style.space(6)
      visible: root.themes.length > 0

      HeaderText {
        width: parent.width - Commons.Style.space(282)
        text: "THEME"
      }
      Item { width: Commons.Style.space(132); height: 1 }
      HeaderText {
        width: Commons.Style.space(60)
        text: "BEHIND"
      }
      HeaderText {
        width: Commons.Style.space(72)
        text: "STATE"
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ListView {
        id: themeList
        anchors.fill: parent
        anchors.rightMargin: overflowThumb.visible
          ? Commons.Style.space(7) : 0
        clip: true
        spacing: 0
        model: root.themes
        visible: root.themes.length > 0
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
          id: themeRow
          required property var modelData
          required property int index
          width: ListView.view.width
          height: confirming ? Commons.Style.space(50)
            : Commons.Style.space(26)
          readonly property bool confirming:
            root.confirmThemeName === modelData.name
              && root.confirmAction !== ""

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Commons.Style.space(26)
            spacing: Commons.Style.space(6)

            Text {
              width: parent.width - Commons.Style.space(282)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: modelData.current
                ? root.panel.controlAccent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.bodySmall
              font.weight: modelData.current ? Font.Medium : Font.Normal
              elide: Text.ElideRight
            }

            Row {
              width: Commons.Style.space(132)
              height: parent.height
              spacing: Commons.Style.space(3)

              PanelButton {
                width: Commons.Style.space(22)
                panel: root.panel
                iconText: "\uf06e"
                controlHeight: Commons.Style.space(20)
                horizontalPadding: 0
                enabled: root.canReview(modelData) && root.actionIdle
                tooltipText: enabled
                  ? "View pinned changes" : "No reviewed changes"
                onClicked: root.openThemeReview(modelData)
              }

              PanelButton {
                width: Commons.Style.space(52)
                panel: root.panel
                text: "update"
                primary: root.canUpdate(modelData)
                controlHeight: Commons.Style.space(20)
                horizontalPadding: Commons.Style.space(3)
                fontSize: Commons.Style.font.caption
                enabled: root.canUpdate(modelData) && root.actionIdle
                tooltipText: enabled
                  ? "Install the pinned commit"
                  : Model.themeStateDetail(modelData)
                onClicked: root.updateService.updateTheme(modelData)
              }

              PanelButton {
                width: Commons.Style.space(22)
                panel: root.panel
                iconText: "\uf2f9"
                controlHeight: Commons.Style.space(20)
                horizontalPadding: 0
                enabled: root.canReinstall(modelData) && root.actionIdle
                tooltipText: modelData.current
                  ? "Re-Apply the active theme below"
                  : enabled ? "Reinstall from recorded origin"
                    : "Theme origin cannot be verified"
                onClicked: root.armAction("reinstall", modelData)
              }

              PanelButton {
                width: Commons.Style.space(22)
                panel: root.panel
                iconText: "\ue872"
                materialIcon: true
                fontSize: 12
                destructive: true
                controlHeight: Commons.Style.space(20)
                horizontalPadding: 0
                enabled: root.canRemove(modelData) && root.actionIdle
                tooltipText: modelData.current
                  ? "Select another theme before removing this one"
                  : "Remove user theme"
                onClicked: root.armAction("remove", modelData)
              }
            }

            Item {
              width: Commons.Style.space(60)
              height: parent.height

              Text {
                anchors.fill: parent
                text: Number(modelData.behind || 0) > 0
                  ? String(modelData.behind) : "—"
                color: behindMouse.containsMouse && root.canReview(modelData)
                  ? root.panel.controlAccent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Commons.Style.font.caption
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }

              MouseArea {
                id: behindMouse
                anchors.fill: parent
                hoverEnabled: root.canReview(modelData)
                enabled: root.canReview(modelData) && root.actionIdle
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.openThemeReview(modelData)
              }
            }

            Item {
              width: Commons.Style.space(72)
              height: parent.height

              Text {
                anchors.fill: parent
                anchors.rightMargin: Commons.Style.space(4)
                text: root.stateLabel(modelData)
                color: root.stateColor(modelData)
                font.family: root.fontFamily
                font.pixelSize: Commons.Style.font.caption
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }

              MouseArea {
                id: stateMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }

              ShibumiPanelToolTip {
                panel: root.panel
                visible: stateMouse.containsMouse
                text: Model.themeStateDetail(modelData)
              }
            }
          }

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Commons.Style.space(24)
            visible: themeRow.confirming
            spacing: Commons.Style.space(5)

            Text {
              width: parent.width - cancelButton.width - confirmButton.width
                - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              text: root.confirmAction === "remove"
                ? "Remove " + modelData.name + "?"
                : "Reinstall " + modelData.name + " from origin?"
              color: root.confirmAction === "remove"
                ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.caption
              elide: Text.ElideRight
            }

            PanelButton {
              id: cancelButton
              width: Commons.Style.space(62)
              panel: root.panel
              text: "Cancel"
              controlHeight: Commons.Style.space(20)
              fontSize: Commons.Style.font.caption
              onClicked: root.cancelAction()
            }

            PanelButton {
              id: confirmButton
              width: Commons.Style.space(72)
              panel: root.panel
              text: root.confirmAction === "remove" ? "Remove" : "Reinstall"
              primary: true
              destructive: root.confirmAction === "remove"
              controlHeight: Commons.Style.space(20)
              fontSize: Commons.Style.font.caption
              onClicked: root.confirmActionFor(modelData)
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            visible: index < root.themes.length - 1
              && !themeRow.confirming
            color: Qt.rgba(root.foreground.r, root.foreground.g,
              root.foreground.b, 0.08)
          }
        }
      }

      Item {
        id: overflowThumb
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Commons.Style.space(7)
        visible: themeList.contentHeight > themeList.height + 1

        Rectangle {
          width: themeDrag.containsMouse || themeDrag.pressed ? 5 : 3
          height: themeList.contentHeight > 0
            ? Math.max(Commons.Style.space(22),
              overflowThumb.height * overflowThumb.height
                / themeList.contentHeight) : 0
          x: (overflowThumb.width - width) / 2
          y: themeList.contentHeight > themeList.height
            ? (overflowThumb.height - height)
              * themeList.contentY
              / (themeList.contentHeight - themeList.height) : 0
          radius: width / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g,
            root.foreground.b,
            themeDrag.containsMouse || themeDrag.pressed ? 0.5 : 0.28)
        }

        MouseArea {
          id: themeDrag
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          property real startY: 0
          property real startContentY: 0
          onPressed: function(mouse) {
            startY = mouse.y
            startContentY = themeList.contentY
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            const scrollable = themeList.contentHeight - themeList.height
            if (scrollable <= 0) return
            themeList.contentY = Math.max(0, Math.min(scrollable,
              startContentY + (mouse.y - startY)
                * scrollable / Math.max(1, height)))
          }
        }
      }

      Column {
        anchors.centerIn: parent
        visible: root.themes.length === 0
        spacing: Commons.Style.space(6)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.updateService.themeRefreshing ? "\uf021" : "\uf1fc"
          color: root.updateService.themeError !== ""
            ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.display
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.summaryText()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.bodySmall
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: root.panel.dividerColor
    }

    Row {
      objectName: "themeFooterActions"
      Layout.fillWidth: true
      Layout.preferredHeight: Commons.Style.space(28)
      spacing: Commons.Style.space(6)

      PanelButton {
        objectName: "themeFooterReapply"
        width: (parent.width - parent.spacing * 2) / 3
        visible: root.currentTheme !== null
        panel: root.panel
        text: root.updateService.currentThemeNeedsReapply
          ? "Re-Apply current" : "Re-Apply"
        selected: root.updateService.currentThemeNeedsReapply
        enabled: root.actionIdle
        controlHeight: Commons.Style.space(28)
        tooltipText: "Re-Apply the active user theme"
        onClicked: root.updateService.reapplyCurrentTheme()
      }

      PanelButton {
        objectName: "themeFooterCheck"
        width: root.currentTheme !== null
          ? (parent.width - parent.spacing * 2) / 3
          : (parent.width - parent.spacing) / 2
        panel: root.panel
        text: root.updateService.themeRefreshing ? "Checking…" : "Check themes"
        enabled: root.actionIdle
        controlHeight: Commons.Style.space(28)
        onClicked: root.updateService.refreshThemes()
      }

      PanelButton {
        objectName: "themeFooterUpdate"
        width: root.currentTheme !== null
          ? (parent.width - parent.spacing * 2) / 3
          : (parent.width - parent.spacing) / 2
        panel: root.panel
        text: root.updateService.themeRefreshing ? "Checking…"
          : Number(root.themeStatus.actionable || 0) > 0
            ? (Number(root.themeStatus.blocked || 0) > 0
                ? "Update clean (" : "Update all (")
              + root.themeStatus.actionable + ")"
            : Number(root.themeStatus.outdated || 0) > 0
              ? "Review first" : "No updates"
        iconText: "\uf019"
        primary: Number(root.themeStatus.actionable || 0) > 0
        enabled: root.actionIdle
          && Number(root.themeStatus.actionable || 0) > 0
        controlHeight: Commons.Style.space(28)
        onClicked: root.updateService.updateAllThemes()
      }
    }

    Text {
      Layout.fillWidth: true
      text: "Stock themes are maintained through package updates"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  component HeaderText: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.weight: Font.Medium
    font.letterSpacing: 1
    elide: Text.ElideRight
  }
}
