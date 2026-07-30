pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

// V1 panel slider: the hit target is larger than the visible 8 px track and a
// restrained end handle communicates that the track is interactive.
Item {
  id: root

  required property var bar
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  property bool muted: false
  property bool interactive: true
  property bool dragging: false
  property real liveValue: value
  property int trackHeight: Commons.Style.space(8)
  property int handleSize: Commons.Style.space(14)
  readonly property var tokens: bar && "visualTokens" in bar
    ? bar.visualTokens : null
  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1,
    (liveValue - minimum) / range))
  readonly property color fallbackAccent: bar
    ? bar.urgent : Commons.Color.accent
  readonly property color trackColor: tokens
    && tokens.fillActive !== undefined
    ? tokens.fillActive : Commons.Util.alpha(fallbackAccent, 0.18)
  readonly property color activeColor: tokens && tokens.seal !== undefined
    ? tokens.seal : fallbackAccent
  readonly property bool hot: interaction.containsMouse || dragging

  signal moved(real value)
  signal released(real value)

  implicitWidth: Commons.Style.space(200)
  implicitHeight: trackHeight

  onValueChanged: if (!dragging) liveValue = value

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: root.trackColor

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.progress
      radius: parent.radius
      color: root.muted
        ? Commons.Util.alpha(root.activeColor, 0.4) : root.activeColor

      Behavior on width {
        enabled: !root.dragging
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }

  Rectangle {
    id: handle
    z: 1
    width: root.handleSize
    height: root.handleSize
    x: Math.max(0, Math.min(root.width - width,
      root.width * root.progress - width / 2))
    anchors.verticalCenter: parent.verticalCenter
    radius: width / 2
    color: root.muted
      ? Commons.Util.alpha(root.activeColor, 0.55) : root.activeColor
    border.width: 2
    border.color: root.tokens && root.tokens.paper !== undefined
      ? root.tokens.paper : root.trackColor
    opacity: root.enabled ? 1 : 0.5
    scale: root.hot ? 1.15 : 1

    Behavior on x {
      enabled: !root.dragging
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Behavior on scale {
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    id: interaction
    x: 0
    y: -Commons.Style.space(8)
    width: parent.width
    height: parent.height + Commons.Style.space(12)
    enabled: root.interactive && root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton

    function valueFromX(position) {
      const clamped = Math.max(0, Math.min(root.width, position))
      let candidate = root.minimum + (clamped / root.width) * root.range
      if (root.integer) candidate = Math.round(candidate)
      return Math.max(root.minimum, Math.min(root.maximum, candidate))
    }

    onPressed: function(mouse) {
      root.dragging = true
      root.liveValue = valueFromX(mouse.x)
      root.moved(root.liveValue)
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      root.liveValue = valueFromX(mouse.x)
      root.moved(root.liveValue)
    }
    onReleased: {
      root.dragging = false
      root.released(root.liveValue)
      root.liveValue = root.value
    }
    onWheel: function(wheel) {
      const delta = wheel.angleDelta.y > 0 ? root.step : -root.step
      let candidate = Math.max(root.minimum,
        Math.min(root.maximum, root.liveValue + delta))
      if (root.integer) candidate = Math.round(candidate)
      root.liveValue = candidate
      root.moved(candidate)
      root.released(candidate)
    }
  }
}
