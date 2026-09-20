pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root

  required property var bar
  required property var layoutSession
  required property bool barVisible
  property var targetScreen: null

  readonly property bool validScreen: targetScreen !== null
    && String(targetScreen.name || "") !== ""
    && Number(targetScreen.width) > 0
    && Number(targetScreen.height) > 0
  readonly property bool horizontal: !bar.vertical
  readonly property real outsideX: bar.position === "left" ? bar.barSize : 0
  readonly property real outsideY: bar.position === "top" ? bar.barSize : 0
  readonly property real outsideWidth: horizontal
    ? width : Math.max(0, width - bar.barSize)
  readonly property real outsideHeight: horizontal
    ? Math.max(0, height - bar.barSize) : height

  screen: targetScreen
  visible: layoutSession.editing && barVisible
    && validScreen && bar.hostReady && bar.styleReady && !bar.barHidden
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "shibumi-bar-edit-backdrop"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  mask: Region { item: dismissArea }

  Rectangle {
    x: root.outsideX
    y: root.outsideY
    width: root.outsideWidth
    height: root.outsideHeight
    color: "#000000"
    opacity: 0.34

    MouseArea {
      id: dismissArea

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onClicked: root.layoutSession.setEditing(false)
    }
  }
}
