pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons

PanelWindow {
  id: root

  required property var bar
  required property var layoutSession
  property var targetScreen: null

  readonly property bool active: layoutSession
    && (layoutSession.active || layoutSession.returning)
    && layoutSession.sourceItem
  readonly property real barOriginX: bar.position === "right"
    ? Math.max(0, width - bar.barSize) : 0
  readonly property real barOriginY: bar.position === "bottom"
    ? Math.max(0, height - bar.barSize) : 0

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

  Item {
    id: ghost

    visible: root.active
    x: root.barOriginX + root.layoutSession.ghostX
    y: root.barOriginY + root.layoutSession.ghostY
    width: root.layoutSession.ghostWidth
    height: root.layoutSession.ghostHeight

    Behavior on x {
      enabled: root.layoutSession.returning
      NumberAnimation {
        duration: root.bar.visualTokens.invalidDropDuration
        easing.type: Easing.OutCubic
      }
    }

    Behavior on y {
      enabled: root.layoutSession.returning
      NumberAnimation {
        duration: root.bar.visualTokens.invalidDropDuration
        easing.type: Easing.OutCubic
      }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: -Commons.Style.space(1)
      radius: Math.min(height / 2, root.bar.visualTokens.pillRadius)
      color: root.layoutSession.targetGroupId !== ""
        ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g, root.bar.urgent.b, 0.2)
        : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.1)
      border.width: 1
      border.color: root.layoutSession.targetGroupId !== ""
        ? root.bar.urgent : root.bar.foreground
    }

    Image {
      anchors.fill: parent
      source: root.layoutSession.ghostImageUrl
      fillMode: Image.Stretch
      smooth: true
      opacity: root.layoutSession.active
        ? (root.layoutSession.targetGroupId !== "" ? 0.95 : 0.45) : 0.92
      scale: root.layoutSession.active ? 1.06 : 1

      Behavior on opacity { NumberAnimation { duration: 120 } }
      Behavior on scale { NumberAnimation { duration: 120 } }
    }
  }

  Timer {
    interval: root.bar.visualTokens.returnCleanupDuration
    running: root.layoutSession.returning
    repeat: false
    onTriggered: {
      if (root.layoutSession
          && typeof root.layoutSession.finishReturn === "function")
        root.layoutSession.finishReturn()
    }
  }
}
