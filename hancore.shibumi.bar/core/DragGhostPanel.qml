pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root

  required property var bar
  required property var layoutSession
  property var targetScreen: null
  readonly property bool active: ghost.active

  screen: targetScreen
  visible: active
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "shibumi-bar-drag-ghost"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // The visual follows the active pointer grab without taking input itself.
  mask: Region {}

  DragGhostVisual {
    id: ghost
    bar: root.bar
    layoutSession: root.layoutSession
  }
}
