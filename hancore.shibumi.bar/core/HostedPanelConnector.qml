pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root

  required property var bar
  property var targetScreen: null

  readonly property string targetScreenName: targetScreen
    ? String(targetScreen.name || "") : ""
  readonly property var connectedPanelRecord: bar
    && typeof bar.connectedPanelForScreen === "function"
      ? bar.connectedPanelForScreen(targetScreenName) : ({
          owner: bar ? bar.connectedPanelOwner : null,
          screenName: bar ? bar.connectedPanelScreenName : "",
          reveal: bar ? bar.connectedPanelReveal : 0,
          hostCaret: bar ? bar.connectedPanelHostCaret : false,
          x: bar ? bar.connectedPanelX : 0,
          cardX: bar ? bar.connectedPanelCardX : 0,
          cardY: bar ? bar.connectedPanelCardY : 0,
          cardWidth: bar ? bar.connectedPanelCardWidth : 0,
          cardHeight: bar ? bar.connectedPanelCardHeight : 0
        })
  readonly property bool active: bar
    && connectedPanelRecord.hostCaret === true
    && connectedPanelRecord.screenName === targetScreenName
    && Number(connectedPanelRecord.reveal || 0) > 0.001
    && Number(connectedPanelRecord.cardWidth || 0) > 0
    && Number(connectedPanelRecord.cardHeight || 0) > 0
    && (bar.position === "top" || bar.position === "bottom")
  readonly property bool pointsUp: bar.position !== "bottom"
  readonly property real progress:
    Math.max(0, Math.min(1,
      Number(connectedPanelRecord.reveal) || 0))
  readonly property real cardX: Number(connectedPanelRecord.cardX) || 0
  readonly property real cardY: Number(connectedPanelRecord.cardY) || 0
  readonly property real cardWidth:
    Math.max(0, Number(connectedPanelRecord.cardWidth) || 0)
  readonly property real cardHeight:
    Math.max(0, Number(connectedPanelRecord.cardHeight) || 0)
  readonly property real centerX: Math.max(cardX + 10,
    Math.min(cardX + cardWidth - 10,
      Number(connectedPanelRecord.x) || 0))
  readonly property real maxDepth: 5
  readonly property real halfWidth: 6 * progress
  readonly property real depth: maxDepth * progress
  readonly property real tangentControl: 3.75 * progress
  readonly property real tipControl: 1.75 * progress
  readonly property real connectorY: pointsUp
    ? cardY - maxDepth : cardY + cardHeight - 1
  readonly property color surfaceColor: bar.visualTokens
    ? bar.visualTokens.panelBackground : "transparent"
  readonly property color strokeColor: bar.visualTokens
    && bar.visualTokens.panelBorderWidth > 0
    ? bar.visualTokens.panelBorder : "transparent"
  readonly property real strokeWidth: bar.visualTokens
    ? bar.visualTokens.panelBorderWidth : 0

  screen: targetScreen
  visible: active
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "shibumi-hosted-panel-connector"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  mask: Region {}

  Rectangle {
    x: Math.round(root.centerX - 13)
    y: root.pointsUp ? root.cardY : root.cardY + root.cardHeight - 2
    width: 26
    height: 2
    color: root.surfaceColor
    // First erase the foreign card's straight border beneath the connector.
    // The replacement edge is painted above this bridge as one continuous
    // path; reversing that order clips the lower caret shoulders.
    z: 1
  }

  Shape {
    id: connectorShape

    x: Math.round(root.centerX - 13)
    y: root.connectorY
    width: 26
    height: root.maxDepth + 1
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true
    layer.mipmap: true
    layer.textureSize: Qt.size(Math.ceil(width * 4),
      Math.ceil(height * 4))
    z: 2

    readonly property real baseY: root.pointsUp
      ? root.maxDepth + 0.5 : 0.5
    readonly property real tipY: root.pointsUp
      ? baseY - root.depth : baseY + root.depth
    readonly property real centerX: width / 2

    ShapePath {
      strokeColor: root.strokeColor
      strokeWidth: root.strokeWidth
      fillColor: root.surfaceColor
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.MiterJoin
      startX: 0
      startY: connectorShape.baseY
      PathLine {
        x: connectorShape.centerX - root.halfWidth
        y: connectorShape.baseY
      }
      PathCubic {
        x: connectorShape.centerX
        y: connectorShape.tipY
        control1X: connectorShape.centerX - root.tangentControl
        control1Y: connectorShape.baseY
        control2X: connectorShape.centerX - root.tipControl
        control2Y: connectorShape.tipY
      }
      PathCubic {
        x: connectorShape.centerX + root.halfWidth
        y: connectorShape.baseY
        control1X: connectorShape.centerX + root.tipControl
        control1Y: connectorShape.tipY
        control2X: connectorShape.centerX + root.tangentControl
        control2Y: connectorShape.baseY
      }
      PathLine {
        x: connectorShape.width
        y: connectorShape.baseY
      }
    }
  }
}
