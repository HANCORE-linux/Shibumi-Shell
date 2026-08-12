import QtQuick

// Offscreen host for loading the production AiUsagePanel content without a
// LayerShell backend. The test replaces only ShibumiPanel's window/chrome;
// AiUsagePanel.qml and all of its bindings remain the production source.
Item {
  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  property int contentWidth: 360
  property int contentHeight: 560
  readonly property var shibumiTokens: bar && "visualTokens" in bar
    ? bar.visualTokens : null
  readonly property real controlRadius: 8
  readonly property color controlForeground: bar ? bar.foreground : "white"
  readonly property color controlAccent: bar ? bar.urgent : "red"
  readonly property color controlMuted: "#888888"
  readonly property color controlMutedHigh: "#aaaaaa"
  readonly property color controlBorderColor: "#555555"
  readonly property real controlBorderWidth: 1
  readonly property color controlFillColor: "#222222"
  readonly property color controlHoverFillColor: "#333333"
  readonly property color controlActiveFillColor: "#442222"
  readonly property color dividerColor: controlBorderColor

  default property alias panelContent: content.data

  function fittedContentWidth(preferred) { return preferred }
  function fittedContentHeight(preferred, maximum) {
    return Math.min(preferred, maximum)
  }

  Item {
    id: content
    width: parent.contentWidth
    height: parent.contentHeight
  }
}
