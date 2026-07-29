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
  readonly property color controlFillColor: "transparent"
  readonly property color controlBorderColor: "transparent"
  readonly property color controlHoverBorderColor: "transparent"
  readonly property real controlBorderWidth: 0
  readonly property real controlRadius: 6

  width: contentWidth
  height: contentHeight

  function fittedContentWidth(value) { return Number(value) || 0 }
  function fittedContentHeight(value) { return Number(value) || 0 }
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
