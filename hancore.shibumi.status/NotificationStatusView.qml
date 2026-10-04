pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "../hancore.shibumi.state/lib/presentation" as Presentation

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
  readonly property rect iconInk: bellIcon.mapToItem(root, bellIcon.symbolInk)
  property var notificationService: null
  readonly property int pendingCount: notificationService
    && notificationService.liveAvailable === true && notificationService.pendingModel
    ? Math.max(0, Number(notificationService.pendingModel.count) || 0) : 0
  readonly property int recentCount: notificationService
    && notificationService.pastModel
    ? Math.max(0, Number(notificationService.pastModel.count) || 0) : 0
  readonly property int notificationCount: pendingCount + recentCount
  readonly property bool countsKnown: notificationService
    && notificationService.historyState === "ready"
  readonly property string tooltipText: (notificationService && notificationService.liveAvailable === true
    ? pendingCount + " Live · " : "")
    + (notificationService && notificationService.historyState === "ready"
      ? recentCount + " Recent" : "Recent: " + (notificationService
        && notificationService.historyState === "loading" ? "Loading" : "Unavailable"))
    + (notificationService && notificationService.doNotDisturb ? " · DND" : "")
  onTooltipTextChanged: if (tooltipHovered && bar) bar.showTooltip(root, tooltipText)
  readonly property bool presented: notificationService !== null
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property color indicatorColor: stateService
    && typeof stateService.paletteColor === "function"
    ? stateService.paletteColor("color01") : Commons.Color.urgent
  readonly property color badgeFillColor: indicator.color
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

  Presentation.BarGlyph {
    id: bellIcon
    optical: !root.bar || !root.bar.vertical
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.iconHorizontalOffset
    text: "\uE7F4"
    nativeText: "\u{F009C}"
    font.pixelSize: 15
    color: root.notificationCount > 0
      ? root.contentColor
      : Qt.rgba(root.contentColor.r, root.contentColor.g,
          root.contentColor.b, 0.4)

    Behavior on color { ColorAnimation { duration: 150 } }
  }

  Presentation.BarInk { id: indicatorPlacement; target: notificationBadge }

  Rectangle {
    id: notificationBadge
    visible: root.notificationCount > 0 || !root.countsKnown
    width: Math.floor(Math.max(Commons.Style.space(12), badgeText.implicitWidth + 6))
    height: Commons.Style.space(12)
    radius: height / 2
    color: "transparent"
    border.width: 0
    border.color: "transparent"
    z: 10
    x: bellIcon.x + bellIcon.badgeLeft
    y: bellIcon.badgeY(root, notificationBadge)
    anchors.verticalCenter: !bellIcon.optical ? bellIcon.verticalCenter : undefined
    anchors.verticalCenterOffset: -6
    anchors.horizontalCenter: !bellIcon.optical ? bellIcon.horizontalCenter : undefined
    anchors.horizontalCenterOffset: 7

    // Retain the old reservation and ink-relative anchor, but never paint a
    // number. Update and tray badges keep their independent numeric views.
    Text {
      id: badgeText
      visible: false
      anchors.centerIn: parent
      text: !root.countsKnown ? (root.notificationService
        && root.notificationService.historyState === "loading" ? "…" : "?")
        : root.notificationCount > 99 ? "99" : String(root.notificationCount)
      color: root.customToneActive
        ? root.badgeContrastColor
        : root.bar ? root.bar.background : Commons.Color.background
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: 7
      font.weight: Font.Bold
    }

    Rectangle {
      id: indicatorHalo
      readonly property real pixel: 1 / indicatorPlacement.dpr
      readonly property real diameter: Math.max(1,
        Math.round(Commons.Style.space(5) * indicatorPlacement.dpr)) * pixel
      width: diameter + 2 * pixel
      height: width
      radius: width / 2
      color: root.bar ? root.bar.background : Commons.Color.background
      // Keep the narrow cutout, including its antialiased circle, inside the
      // owning slot. Both the circle extent and its scene origin are integral.
      x: {
        const origin = indicatorPlacement.origin
        const slot = root.mapToItem(notificationBadge, 0, 0)
        const first = Math.ceil((origin.x + slot.x) / pixel) * pixel - origin.x
        const last = Math.floor((origin.x + slot.x + root.width) / pixel) * pixel - origin.x - width
        return Math.max(first, Math.min(last, indicatorPlacement.snapX(0)))
      }
      y: indicatorPlacement.snapY((notificationBadge.height - height) / 2)

      Rectangle {
        id: indicator
        x: indicatorHalo.pixel
        y: indicatorHalo.pixel
        width: indicatorHalo.diameter
        height: width
        radius: width / 2
        color: root.countsKnown ? root.indicatorColor : "transparent"
        border.width: root.countsKnown ? 0 : indicatorHalo.pixel
        border.color: root.indicatorColor
      }
    }
  }

  MouseArea {
    id: notificationMouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      if (mouse.button === Qt.RightButton) root.dndRequested()
      else root.toggleRequested()
    }
  }

  readonly property bool tooltipHovered: visible && notificationMouse.containsMouse
}
