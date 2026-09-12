pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

// Backend-free visual shared by the real layer window and render regressions.
// Session coordinates already use the full output window, including Bottom.
Item {
  id: root

  required property var bar
  property var layoutSession: null
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property color foreground: bar ? bar.foreground : "transparent"
  readonly property color urgent: bar ? bar.urgent : "transparent"
  readonly property bool active: !!(tokens && layoutSession
    && (layoutSession.active || layoutSession.returning) && layoutSession.sourceItem)
  readonly property bool imageReady: ghostImage.status === Image.Ready

  visible: active
  x: layoutSession ? layoutSession.ghostX : 0
  y: layoutSession ? layoutSession.ghostY : 0
  width: layoutSession ? layoutSession.ghostWidth : 0
  height: layoutSession ? layoutSession.ghostHeight : 0

  Behavior on x {
    enabled: root.layoutSession && root.layoutSession.returning
    NumberAnimation {
      duration: root.tokens ? root.tokens.invalidDropDuration : 0
      easing.type: Easing.OutCubic
    }
  }
  Behavior on y {
    enabled: root.layoutSession && root.layoutSession.returning
    NumberAnimation {
      duration: root.tokens ? root.tokens.invalidDropDuration : 0
      easing.type: Easing.OutCubic
    }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Commons.Style.space(1)
    radius: Math.min(height / 2, root.tokens ? root.tokens.pillRadius : 0)
    color: root.layoutSession && root.layoutSession.targetGroupId !== ""
      ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.2)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
    border.width: 1
    border.color: root.layoutSession && root.layoutSession.targetGroupId !== ""
      ? root.urgent : root.foreground
  }

  Image {
    id: ghostImage
    anchors.fill: parent
    source: root.layoutSession ? root.layoutSession.ghostImageUrl : ""
    fillMode: Image.Stretch
    smooth: true
    opacity: root.layoutSession && root.layoutSession.active
      ? (root.layoutSession.targetGroupId !== "" ? 0.95 : 0.45) : 0.92
    scale: root.layoutSession && root.layoutSession.active ? 1.06 : 1
    Behavior on opacity { NumberAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 120 } }
  }

  Timer {
    interval: root.tokens ? root.tokens.returnCleanupDuration : 0
    running: root.layoutSession && root.layoutSession.returning
    repeat: false
    onTriggered: {
      if (root.layoutSession && typeof root.layoutSession.finishReturn === "function")
        root.layoutSession.finishReturn()
    }
  }
}
