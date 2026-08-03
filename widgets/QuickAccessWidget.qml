pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons as Commons

Item {
  id: root

  property var bar: null
  property string moduleName: "hancore.shibumi.quick-access"
  property var settings: ({})
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property var picker: bar ? bar.pickerService : null
  readonly property var targetScreen: root.QsWindow && root.QsWindow.window
    ? root.QsWindow.window.screen : null
  readonly property bool opened: picker && picker.opened
    && picker.activeScreenName === (targetScreen ? String(targetScreen.name || "") : "")
  readonly property bool panelLoaded: opened

  visible: bar !== null && tokens !== null && picker !== null
  implicitWidth: visible ? actionRow.implicitWidth + 2 * tokens.pillPaddingX : 0
  implicitHeight: visible ? bar.barSize : 0

  function showTip(owner, text) {
    if (bar) bar.showTooltip(owner, text)
  }

  function hideTip(owner) {
    if (bar) bar.hideTooltip(owner)
  }

  function openMode(mode) {
    if (!picker) return false
    if (bar) bar.requestPopout(root)
    return picker.openMode(mode, targetScreen)
  }

  function toggleMode(mode) {
    if (!picker) return false
    if (picker.opened && picker.mode === mode) {
      picker.close()
      return true
    }
    return openMode(mode)
  }

  function open() { return openMode("wallpaper") }
  function close() { if (picker) picker.close() }
  function toggle() { return toggleMode("wallpaper") }
  function closeForPopoutSwitch() { close() }

  function childPanelWidget(pluginId) {
    const id = String(pluginId || "")
    return id === "hancore.shibumi.picker" || id === "hancore.shibumi.media-browser"
      ? root : null
  }

  onOpenedChanged: {
    if (!opened && bar) bar.releasePopout(root)
  }
  Component.onDestruction: {
    if (opened) close()
    if (bar) bar.releasePopout(root)
  }

  PillSurface {
    anchors.fill: parent
    anchors.topMargin: root.bar && !root.bar.vertical
      ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
    anchors.bottomMargin: anchors.topMargin
    bar: root.bar
  }

  Row {
    id: actionRow
    anchors.centerIn: parent
    spacing: Commons.Style.space(4)

    ActionIcon {
      icon: root.bar && root.bar.idleInhibited
        ? String.fromCodePoint(0xF06E8) : String.fromCodePoint(0xF06E9)
      nerdGlyph: true
      inactiveOpacity: 0.45
      active: root.bar && root.bar.idleInhibited
      tooltip: active ? "Idle inhibited: ON" : "Idle inhibited: OFF"
      onTriggered: if (root.bar) root.bar.idleInhibited = !root.bar.idleInhibited
    }

    ActionIcon {
      icon: "collections"
      active: root.picker && root.picker.opened && root.picker.mediaMode
      tooltip: "Left: Screenshots  Right: Videos"
      onTriggered: function(button) {
        root.toggleMode(button === Qt.RightButton ? "videos" : "screenshots")
      }
    }

    ActionIcon {
      icon: "palette"
      active: root.picker && root.picker.opened && root.picker.imageMode
      tooltip: "Left: Themes  Right: Wallpapers"
      onTriggered: function(button) {
        root.toggleMode(button === Qt.RightButton ? "wallpaper" : "theme")
      }
    }
  }

  component ActionIcon: Item {
    id: action
    required property string icon
    required property bool active
    required property string tooltip
    property bool nerdGlyph: false
    property real inactiveOpacity: 0.62
    readonly property color iconColor: root.bar
      ? (active ? root.bar.urgent
        : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, inactiveOpacity)) : Commons.Color.foreground
    signal triggered(int button)

    implicitWidth: Commons.Style.space(22)
    implicitHeight: root.tokens ? root.tokens.slotHeight : Commons.Style.space(28)

    IconText {
      anchors.centerIn: parent
      visible: !action.nerdGlyph
      text: action.icon
      color: action.iconColor
      font.pixelSize: 14
      font.weight: Font.Medium
      fill: action.active ? 1 : 0
      Behavior on color { ColorAnimation { duration: 150 } }
    }

    Text {
      anchors.centerIn: parent
      visible: action.nerdGlyph
      text: action.icon
      color: action.iconColor
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.space(14)
      renderType: Text.QtRendering
      Behavior on color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.showTip(action, action.tooltip)
      onExited: root.hideTip(action)
      onClicked: function(mouse) {
        root.hideTip(action)
        action.triggered(mouse.button)
      }
    }
  }
}
