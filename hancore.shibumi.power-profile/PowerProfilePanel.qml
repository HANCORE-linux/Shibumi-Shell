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

  // Ui.Button animates its fill for 120ms after hover/cursor leaves. Derive
  // the label from that painted fill, not the already-cleared state flags.
  function profileForegroundRole(fill) {
    const surface = panel.renderedSurfaceColor
    const background = Qt.rgba(fill.r * fill.a + surface.r * (1 - fill.a),
      fill.g * fill.a + surface.g * (1 - fill.a),
      fill.b * fill.a + surface.b * (1 - fill.a), 1)
    function linear(value) {
      return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
    }
    function luminance(color) {
      return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }
    const light = luminance(background)
    function contrast(ink) {
      const painted = Qt.rgba(ink.r * ink.a + background.r * (1 - ink.a),
        ink.g * ink.a + background.g * (1 - ink.a),
        ink.b * ink.a + background.b * (1 - ink.a), 1)
      const value = luminance(painted)
      return (Math.max(light, value) + 0.05) / (Math.min(light, value) + 0.05)
    }
    const normal = panel.bar ? panel.bar.foreground : Commons.Color.foreground
    const filled = panel.bar ? panel.bar.background : Commons.Color.background
    const normalContrast = contrast(normal), filledContrast = contrast(filled)
    if (Math.max(normalContrast, filledContrast) >= 4.5)
      return normalContrast >= filledContrast ? 0 : 1
    // A fading mid-tone can contrast poorly with both theme colors.
    return light > 0.179 ? 2 : 3
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
            readonly property int labelRole: panel.profileForegroundRole(color)
            foreground: labelRole === 0
              ? panel.bar ? panel.bar.foreground : Commons.Color.foreground
              : labelRole === 1
                ? panel.bar ? panel.bar.background : Commons.Color.background
                : labelRole === 2 ? "#000000" : "#ffffff"
            fontFamily: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            horizontalPadding: Commons.Style.spacing.controlPaddingX
            verticalPadding: Commons.Style.spacing.controlPaddingY + Commons.Style.space(2)
            bordered: true
            active: panel.powerState.activeProfile === modelData
            hasCursor: panel.cursorActive && panel.selectedIndex === index
            enabled: !!panel.powerService && !panel.powerState.profileActionRunning
            // Preserve native fill/border inputs independently from the label,
            // including construction before the btop Binding takes ownership.
            readonly property color fillForeground: active || hot
              ? panel.bar ? panel.bar.background : Commons.Color.background
              : panel.bar ? panel.bar.foreground : Commons.Color.foreground
            color: hot ? Commons.Style.hoverFillFor(fillForeground, accent)
              : active ? Commons.Style.selectedFillFor(fillForeground, accent)
              : background
            borderSpec: Commons.Border.controlSpec("normal", fillForeground, accent)
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
