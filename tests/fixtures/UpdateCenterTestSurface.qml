import QtQuick

Item {
  id: root

  required property Item anchorItem
  required property var bar
  default property alias panelContent: content.children
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  property real contentWidth: 0
  property real contentHeight: 0
  readonly property var shibumiTokens: null
  readonly property color controlForeground: "#eeeeee"
  readonly property color controlMuted: "#909090"
  readonly property color controlMutedHigh: "#b0b0b0"
  readonly property color controlAccent: "#d75f5f"
  readonly property color controlFillColor: "#181818"
  readonly property color controlHoverFillColor: "#242424"
  readonly property color controlActiveFillColor: "#302020"
  readonly property color controlPrimaryHoverColor: "#e87070"
  readonly property color controlBorderColor: "#404040"
  readonly property color controlHoverBorderColor: "#d75f5f"
  readonly property color dividerColor: "#303030"
  readonly property real controlBorderWidth: 1
  readonly property real controlRadius: 6

  width: contentWidth
  height: contentHeight

  function fittedContentWidth(value) { return Number(value) || 0 }
  function cappedContentHeight(value) { return Number(value) || 0 }

  Item {
    id: content
    anchors.fill: parent
  }
}
