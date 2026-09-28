pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/lib/presentation" as Presentation

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var powerService
  property int selectedIndex: 0
  property bool cursorActive: false
  readonly property var powerState: powerService || ({ profiles: [], activeProfile: "",
    profileActionRunning: false, profileError: "" })

  owner: ownerWidget
  open: ownerWidget.opened && !!powerService && powerService.profileAvailable
  focusTarget: keyCatcher
  padding: 12
  contentWidth: fittedContentWidth(Commons.Style.space(380))
  contentHeight: fittedContentHeight(column.implicitHeight)

  function syncSelection() {
    var index = powerState.profiles.indexOf(powerState.activeProfile)
    selectedIndex = index >= 0 ? index : 0
  }

  function moveSelection(delta) {
    var count = powerState.profiles.length
    if (count <= 0) return
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta))
  }

  function activateSelected() {
    if (!powerService || selectedIndex < 0 || selectedIndex >= powerState.profiles.length) return
    if (powerService.setProfile(powerService.profiles[selectedIndex]))
      ownerWidget.close()
  }

  // The profile-to-glyph mapping from Omarchy 4.0.4's power Model.js.
  function profileIcon(name) {
    if (name === "power-saver") return "󰌪"
    if (name === "balanced") return "󰊚"
    if (name === "performance") return "󰓅"
    return "󰂄"
  }

  onPowerServiceChanged: syncSelection()
  onOpenChanged: if (open) {
    powerService.refreshProfiles()
    syncSelection()
    cursorActive = false
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent

    Connections {
      target: panel.powerService
      function onProfilesChanged() { panel.syncSelection() }
      function onActiveProfileChanged() { panel.syncSelection() }
    }

    onMoveRequested: function(dx, dy) {
      if (!panel.cursorActive) { panel.cursorActive = true; return }
      panel.moveSelection(dx !== 0 ? dx : dy)
    }
    onActivateRequested: if (panel.cursorActive) panel.activateSelected()
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }

    Column {
      id: column
      width: parent.width
      spacing: Commons.Style.space(8)

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)
        Text {
          width: parent.width - closeAction.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: "POWER PROFILE"
          color: panel.controlForeground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.title
          font.letterSpacing: 2
          font.weight: Font.Medium
        }
        IconAction {
          id: closeAction
          anchors.verticalCenter: parent.verticalCenter
          icon: "close"
          tooltip: "Close"
          onClicked: panel.ownerWidget.close()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Row {
        id: profileRow
        width: parent.width
        spacing: Commons.Style.space(6)
        readonly property real cellWidth: panel.powerState.profiles.length > 0
          ? (width - spacing * (panel.powerState.profiles.length - 1)) / panel.powerState.profiles.length : 0

        Repeater {
          model: panel.powerState.profiles
          Ui.Button {
            id: profileButton
            required property var modelData
            required property int index
            width: profileRow.cellWidth
            iconText: panel.profileIcon(String(modelData))
            iconSize: Commons.Style.font.title
            text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
            fontSize: Commons.Style.font.bodySmall
            foreground: active || hot
              ? panel.bar ? panel.bar.background : Commons.Color.background
              : panel.bar ? panel.bar.foreground : Commons.Color.foreground
            fontFamily: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            horizontalPadding: Commons.Style.spacing.controlPaddingX
            verticalPadding: Commons.Style.spacing.controlPaddingY + Commons.Style.space(2)
            bordered: true
            active: panel.powerState.activeProfile === modelData
            hasCursor: panel.cursorActive && panel.selectedIndex === index
            enabled: !!panel.powerService && !panel.powerState.profileActionRunning
            // Use Battery's Open btop colors for active and hover/cursor states.
            Binding {
              target: profileButton; property: "color"
              when: profileButton.active || profileButton.hot
              value: profileButton.hot && panel.bar ? Qt.lighter(panel.bar.urgent, 1.08)
                : panel.bar ? panel.bar.urgent : Commons.Color.accent
              restoreMode: Binding.RestoreBindingOrValue
            }
            states: State {
              name: "btop-colors"
              when: profileButton.active || profileButton.hot
              PropertyChanges {
                target: profileButton
                borderSpec: Commons.Border.none()
              }
            }
            onClicked: {
              if (panel.powerService && panel.powerService.setProfile(modelData))
                panel.ownerWidget.close()
            }
            onHovered: function(h) {
              if (h) { panel.cursorActive = true; panel.selectedIndex = index }
            }
          }
        }
      }

      Text {
        visible: panel.powerState.profileActionRunning || panel.powerState.profileError !== ""
        width: parent.width
        text: panel.powerState.profileError !== "" ? panel.powerState.profileError : "Applying profile…"
        color: panel.powerState.profileError !== "" && panel.bar
          ? panel.bar.urgent : panel.bar ? panel.bar.foreground : Commons.Color.foreground
        font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        horizontalAlignment: Text.AlignHCenter
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
    foreground: panel.controlForeground
    accent: panel.controlAccent

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
    Presentation.ShibumiPillToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
