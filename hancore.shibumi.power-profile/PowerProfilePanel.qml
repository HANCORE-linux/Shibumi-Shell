pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var powerService
  property int selectedIndex: 0

  owner: ownerWidget
  open: ownerWidget.opened && powerService.profileAvailable
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(220))
  contentHeight: fittedContentHeight(column.implicitHeight)

  function syncSelection() {
    var index = powerService.profiles.indexOf(powerService.activeProfile)
    selectedIndex = index >= 0 ? index : 0
  }

  function moveSelection(delta) {
    var count = powerService.profiles.length
    if (count <= 0) return
    selectedIndex = (selectedIndex + delta + count) % count
  }

  function activateSelected() {
    if (selectedIndex < 0 || selectedIndex >= powerService.profiles.length) return
    if (powerService.setProfile(powerService.profiles[selectedIndex]))
      ownerWidget.close()
  }

  onOpenChanged: if (open) {
    powerService.refreshProfiles()
    syncSelection()
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
      panel.moveSelection(dx !== 0 ? dx : dy)
    }
    onActivateRequested: panel.activateSelected()
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }

    Column {
      id: column
      width: parent.width
      spacing: Commons.Style.space(5)

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)
        Text {
          width: parent.width - closeAction.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          text: "Power Profile"
          color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.heading
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
        color: panel.bar ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
          panel.bar.foreground.b, 0.18) : Commons.Color.popups.border
      }

      Repeater {
        model: panel.powerService.profiles
        delegate: Item {
          id: profileRow
          required property string modelData
          required property int index
          readonly property bool active: panel.powerService.activeProfile === modelData
          readonly property bool selected: panel.selectedIndex === index
          width: column.width
          height: Commons.Style.space(32)

          Rectangle {
            anchors.fill: parent
            radius: panel.controlRadius
            color: profileMouse.containsMouse || profileRow.selected
              ? panel.bar ? Qt.rgba(panel.bar.urgent.r, panel.bar.urgent.g,
                panel.bar.urgent.b, 0.18) : Commons.Color.background
              : panel.controlFillColor
            border.width: panel.controlBorderWidth
            border.color: profileRow.active && panel.bar
              ? panel.bar.urgent : profileMouse.containsMouse || profileRow.selected
                ? panel.controlHoverBorderColor : panel.controlBorderColor
          }

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Commons.Style.space(8)
            anchors.rightMargin: Commons.Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Commons.Style.space(8)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: profileRow.modelData === "power-saver" ? "\uF06C"
                : profileRow.modelData === "performance" ? "\uF0E7" : "\uF24E"
              color: panel.bar ? panel.bar.urgent : Commons.Color.accent
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.heading
              renderType: Text.QtRendering
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: panel.powerService.profileLabel(profileRow.modelData)
              color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.body
              font.weight: profileRow.active ? Font.DemiBold : Font.Normal
            }
          }

          MouseArea {
            id: profileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !panel.powerService.profileActionRunning
            onEntered: panel.selectedIndex = profileRow.index
            onClicked: {
              if (panel.powerService.setProfile(profileRow.modelData))
                panel.ownerWidget.close()
            }
          }
        }
      }

      Text {
        visible: panel.powerService.profileActionRunning
          || panel.powerService.profileError !== ""
        width: parent.width
        text: panel.powerService.profileError !== ""
          ? panel.powerService.profileError : "Applying profile…"
        color: panel.powerService.profileError !== "" && panel.bar
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
