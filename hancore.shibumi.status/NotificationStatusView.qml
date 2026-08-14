pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var bar
  property color contentColor: bar
    ? bar.urgent : Commons.Color.accent
  property bool customToneActive: false
  property color badgeContrastColor: bar
    ? bar.background : Commons.Color.background
  property real slotWidth: Commons.Style.space(26)
  readonly property real iconHorizontalOffset: Commons.Style.space(1)
  property var notificationService: null
  readonly property int pendingCount: notificationService
    && notificationService.pendingModel
    ? Math.max(0, Number(notificationService.pendingModel.count) || 0) : 0
  readonly property int recentCount: notificationService
    && notificationService.pastModel
    ? Math.max(0, Number(notificationService.pastModel.count) || 0) : 0
  readonly property int notificationCount: pendingCount + recentCount
  readonly property bool presented: notificationService !== null
  readonly property color badgeFillColor: notificationBadge.color
  readonly property color badgeTextColor: badgeText.color
  readonly property real badgeLayer: notificationBadge.z
  signal toggleRequested()
  signal dndRequested()
  property bool registered: false

  visible: presented
  implicitWidth: presented ? slotWidth : 0
  implicitHeight: bar ? bar.barSize : Commons.Style.space(35)
  width: implicitWidth
  height: implicitHeight

  function syncRegistration() {
    if (!bar) return
    if (visible && !registered) {
      bar.registerClickTarget(root)
      registered = true
    } else if (!visible && registered) {
      bar.unregisterClickTarget(root)
      registered = false
    }
  }

  onVisibleChanged: syncRegistration()
  Component.onCompleted: syncRegistration()
  Component.onDestruction: if (bar && registered) bar.unregisterClickTarget(root)

  IconText {
    id: bellIcon
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.iconHorizontalOffset
    text: "\uE7F4"
    font.pixelSize: 15
    color: root.notificationCount > 0
      ? root.contentColor
      : Qt.rgba(root.contentColor.r, root.contentColor.g,
          root.contentColor.b, 0.4)

    Behavior on color { ColorAnimation { duration: 150 } }
  }

  Rectangle {
    id: notificationBadge
    visible: root.notificationCount > 0
    width: Math.max(Commons.Style.space(12), badgeText.implicitWidth + 6)
    height: Commons.Style.space(12)
    radius: height / 2
    color: root.contentColor
    border.width: 0
    border.color: "transparent"
    z: 10
    anchors.verticalCenter: bellIcon.verticalCenter
    anchors.verticalCenterOffset: -6
    anchors.horizontalCenter: bellIcon.horizontalCenter
    anchors.horizontalCenterOffset: 7

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.notificationCount > 99 ? "99"
        : String(root.notificationCount)
      color: root.customToneActive
        ? root.badgeContrastColor
        : root.bar ? root.bar.background : Commons.Color.background
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: 7
      font.weight: Font.Bold
    }
  }

  MouseArea {
    id: notificationMouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root,
      root.notificationCount > 0
        ? root.notificationCount + (root.notificationCount === 1
          ? " notification" : " notifications")
        : "No notifications")
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      if (mouse.button === Qt.RightButton) root.dndRequested()
      else root.toggleRequested()
    }
  }

  readonly property bool tooltipHovered: visible && notificationMouse.containsMouse
}
