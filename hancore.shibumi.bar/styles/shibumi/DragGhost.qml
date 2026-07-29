pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var bar
  property var layoutSession: null
  readonly property point surfaceOrigin: parent
    ? parent.mapToItem(null, 0, 0) : Qt.point(0, 0)

  visible: layoutSession && (layoutSession.active || layoutSession.returning)
    && layoutSession.sourceItem
  x: visible ? layoutSession.ghostX - surfaceOrigin.x : 0
  y: visible ? layoutSession.ghostY - surfaceOrigin.y : 0
  width: visible ? layoutSession.ghostWidth : 0
  height: visible ? layoutSession.ghostHeight : 0
  z: 100

  Behavior on x {
    enabled: root.layoutSession && root.layoutSession.returning
    NumberAnimation {
      duration: root.bar.visualTokens.invalidDropDuration
      easing.type: Easing.OutCubic
    }
  }

  Behavior on y {
    enabled: root.layoutSession && root.layoutSession.returning
    NumberAnimation {
      duration: root.bar.visualTokens.invalidDropDuration
      easing.type: Easing.OutCubic
    }
  }

  Timer {
    interval: root.bar.visualTokens.returnCleanupDuration
    running: root.layoutSession && root.layoutSession.returning
    repeat: false
    onTriggered: {
      if (root.layoutSession
          && typeof root.layoutSession.finishReturn === "function")
        root.layoutSession.finishReturn()
    }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Commons.Style.space(1)
    radius: Math.min(height / 2, root.bar.visualTokens.pillRadius)
    color: root.layoutSession && root.layoutSession.targetGroupId !== ""
      ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g, root.bar.urgent.b, 0.2)
      : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, 0.1)
    border.width: 1
    border.color: root.layoutSession && root.layoutSession.targetGroupId !== ""
      ? root.bar.urgent : root.bar.foreground
  }

  ShaderEffectSource {
    anchors.fill: parent
    sourceItem: root.visible ? root.layoutSession.sourceItem : null
    sourceRect: Qt.rect(0, 0, width, height)
    live: true
    recursive: true
    hideSource: false
    opacity: root.layoutSession && root.layoutSession.active
      ? (root.layoutSession.targetGroupId !== "" ? 0.95 : 0.45) : 0.92
    scale: root.layoutSession && root.layoutSession.active ? 1.06 : 1

    Behavior on opacity { NumberAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 120 } }
  }
}
