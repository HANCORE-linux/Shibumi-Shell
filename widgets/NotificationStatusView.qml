pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var bar
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
    color: root.notificationCount > 0 && root.bar
      ? root.bar.urgent
      : root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, 0.4) : Commons.Color.foreground

    Behavior on color { ColorAnimation { duration: 150 } }
  }

  Rectangle {
    visible: root.notificationCount > 0
    width: Math.max(Commons.Style.space(12), badgeText.implicitWidth + 6)
    height: Commons.Style.space(12)
    radius: height / 2
    color: root.bar ? root.bar.urgent : Commons.Color.accent
    anchors.verticalCenter: bellIcon.verticalCenter
    anchors.verticalCenterOffset: -6
    anchors.horizontalCenter: bellIcon.horizontalCenter
    anchors.horizontalCenterOffset: 7

    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.notificationCount > 99 ? "99"
        : String(root.notificationCount)
      color: root.bar ? root.bar.background : Commons.Color.background
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
