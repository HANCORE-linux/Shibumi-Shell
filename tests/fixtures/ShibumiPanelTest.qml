import QtQuick

Item {
  id: root

  required property Item anchorItem
  required property var bar
  default property alias panelContent: content.children
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  property int focusRequestCount: 0
  property bool centerOnBar: false
  property real centerOnBarOffset: 0
  property int padding: 0
  property real contentWidth: 0
  property real contentHeight: 0
  readonly property string shellStyle: "shibumi"
  readonly property color renderedSurfaceColor: "#181818"
  readonly property color controlForeground: "#eeeeee"
  readonly property color controlFillColor: "transparent"
  readonly property color controlAccent: "#d75f5f"
  readonly property color controlMuted: "#777777"
  readonly property color controlMutedHigh: "#a0a0a0"
  readonly property color controlBorderColor: "transparent"
  readonly property color controlHoverBorderColor: "transparent"
  readonly property color controlHoverFillColor: "#202020"
  readonly property color controlActiveFillColor: "#282828"
  readonly property color controlPrimaryHoverColor: "#ef7777"
  readonly property color dividerColor: controlBorderColor
  readonly property real controlBorderWidth: 0
  readonly property real controlRadius: 6
  readonly property var shibumiTokens: ({
    paper: "#181818",
    separator: "#404040",
    fillIdle: "#202020",
    fillHover: "#282828",
    fillActive: "#303030"
  })

  width: contentWidth
  height: contentHeight

  function fittedContentWidth(value, cap) {
    const desired = Number(value) || 0
    return cap ? Math.min(desired, Number(cap)) : desired
  }
  function fittedContentHeight(value, cap) {
    const desired = (Number(value) || 0) + padding * 2
    return cap ? Math.min(desired, Number(cap)) : desired
  }
  function requestKeyboardFocus(target) {
    if (!open || !target) return
    focusRequestCount++
    Qt.callLater(function() {
      if (root.open && target) target.forceActiveFocus()
    })
  }
  function syncPopout() {
    if (!bar || !owner) return
    if (open) bar.requestPopout(owner)
    else bar.releasePopout(owner)
  }

  onOpenChanged: syncPopout()
  Component.onCompleted: syncPopout()
  Component.onDestruction: if (bar && owner) bar.releasePopout(owner)

  Item {
    id: content
    anchors.fill: parent
  }
}
