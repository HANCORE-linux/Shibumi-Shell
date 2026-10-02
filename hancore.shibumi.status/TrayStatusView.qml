pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "../hancore.shibumi.state/lib/presentation" as Presentation

Item {
  id: root

  required property var bar
  property var trayBackend: null
  property bool customToneActive: false
  property color contentColor: bar
    ? bar.foreground : Commons.Color.foreground
  property color badgeContrastColor: bar
    ? bar.background : Commons.Color.background
  readonly property color drawerIconColor: moreIcon.color
  readonly property color drawerBadgeColor: badgePaint.color
  readonly property color drawerBadgeTextColor: badgeValue.color
  readonly property real badgeLayer: drawerBadge.z
  readonly property var pinnedItems: trayBackend
    && Array.isArray(trayBackend.pinnedItems) ? trayBackend.pinnedItems : []
  readonly property int drawerCount: trayBackend
    && trayBackend.drawerCount !== undefined
    ? Math.max(0, Number(trayBackend.drawerCount) || 0) : 0
  readonly property int pinnedCount: pinnedItems.length
  readonly property int totalCount: pinnedItems.length + drawerCount
  readonly property string drawerTooltipText: totalCount
    + (totalCount === 1 ? " app" : " apps")
    + (drawerCount > 0 ? " \u00b7 " + drawerCount + " hidden" : "")
  readonly property bool presented: pinnedItems.length > 0 || drawerCount > 0
  readonly property int visibleItemCount: pinnedCount + (drawerCount > 0 ? 1 : 0)
  readonly property real itemGap: Commons.Style.space(2)
  readonly property real pinnedIconHorizontalOffset: Commons.Style.space(1)
  signal drawerRequested()

  visible: presented
  implicitWidth: presented
    ? pinnedCount * Commons.Style.space(18)
      + (drawerCount > 0 ? Commons.Style.space(22) : 0)
      + Math.max(0, visibleItemCount - 1) * itemGap
    : 0
  implicitHeight: bar ? bar.barSize : Commons.Style.space(35)
  width: implicitWidth
  height: implicitHeight

  function itemId(item) {
    return item ? String(item.id || "") : ""
  }

  function tooltip(item) {
    if (!item) return "Tray application"
    if (trayBackend && typeof trayBackend.trayTooltip === "function")
      return String(trayBackend.trayTooltip(item) || "Tray application")
    return String(item.tooltipTitle || item.title || item.id || "Tray application")
  }

  function openMenu(item, anchor, mouse) {
    if (!trayBackend || typeof trayBackend.openTrayMenu !== "function") return false
    trayBackend.openTrayMenu(item, anchor, mouse)
    return true
  }

  function togglePin(item) {
    const id = itemId(item)
    if (!id || !trayBackend || typeof trayBackend.togglePin !== "function")
      return false
    trayBackend.togglePin(id)
    return true
  }

  Row {
    id: trayRow
    anchors.centerIn: parent
    spacing: root.itemGap

    Repeater {
      model: root.pinnedItems

      delegate: Item {
        id: trayDelegate
        required property var modelData

        implicitWidth: Commons.Style.space(18)
        implicitHeight: root.implicitHeight
        width: implicitWidth
        height: implicitHeight

        Component.onCompleted: if (root.bar) root.bar.registerClickTarget(trayDelegate)
        Component.onDestruction: {
          if (root.bar) root.bar.unregisterClickTarget(trayDelegate)
        }

        Presentation.BarGlyph {
          anchors.centerIn: parent
          anchors.horizontalCenterOffset: root.pinnedIconHorizontalOffset
          text: "󰀻"
          font.family: Commons.Style.font.family
          color: root.contentColor
          width: Commons.Style.space(14)
          height: Commons.Style.space(14)
        }

        MouseArea {
          id: trayMouse
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: if (root.bar)
            root.bar.showTooltip(trayDelegate, root.tooltip(trayDelegate.modelData))
          onExited: if (root.bar) root.bar.hideTooltip(trayDelegate)
          onClicked: function(mouse) {
            if (root.bar) root.bar.hideTooltip(trayDelegate)
            if (mouse.button === Qt.RightButton) {
              root.togglePin(trayDelegate.modelData)
            } else if (mouse.button === Qt.MiddleButton
                || trayDelegate.modelData.onlyMenu === true) {
              root.openMenu(trayDelegate.modelData, trayDelegate, mouse)
            } else if (typeof trayDelegate.modelData.activate === "function") {
              trayDelegate.modelData.activate()
            }
          }
          onWheel: function(wheel) {
            if (typeof trayDelegate.modelData.scroll === "function")
              trayDelegate.modelData.scroll(wheel.angleDelta.y, false)
          }
        }

        readonly property bool tooltipHovered: visible && trayMouse.containsMouse
      }
    }

    Item {
      id: drawerToggle
      property bool registered: false
      visible: root.drawerCount > 0
      implicitWidth: visible ? Commons.Style.space(22) : 0
      implicitHeight: root.implicitHeight
      width: implicitWidth
      height: implicitHeight

      function syncRegistration() {
        if (!root.bar) return
        if (visible && !registered) {
          root.bar.registerClickTarget(drawerToggle)
          registered = true
        } else if (!visible && registered) {
          root.bar.unregisterClickTarget(drawerToggle)
          registered = false
        }
      }

      onVisibleChanged: syncRegistration()
      Component.onCompleted: syncRegistration()
      Component.onDestruction: {
        if (root.bar && registered) root.bar.unregisterClickTarget(drawerToggle)
      }

      Presentation.BarGlyph {
        id: moreIcon
        optical: !root.bar || !root.bar.vertical
        anchors.centerIn: parent
        text: "\uE5D3"
        font.pixelSize: 16
        color: drawerMouse.containsMouse
          ? root.contentColor
          : Qt.rgba(root.contentColor.r, root.contentColor.g,
            root.contentColor.b, root.contentColor.a * 0.7)

        Behavior on color { ColorAnimation { duration: 150 } }
      }

      Presentation.BarInk { id: badgePlacement; target: drawerBadge }

      Rectangle {
        id: drawerBadge
        visible: root.drawerCount > 0
        width: Math.floor(Math.max(Commons.Style.space(12), badgeText.implicitWidth + 6))
        height: Commons.Style.space(12)
        radius: height / 2
        color: "transparent"
        border.width: 0
        border.color: "transparent"
        z: 10
        x: moreIcon.x + moreIcon.badgeLeft
        y: moreIcon.badgeY(root, drawerBadge)
        anchors.verticalCenter: !moreIcon.optical ? moreIcon.verticalCenter : undefined
        anchors.verticalCenterOffset: -6
        anchors.horizontalCenter: !moreIcon.optical ? moreIcon.horizontalCenter : undefined
        anchors.horizontalCenterOffset: 7

        Text {
          id: badgeText
          visible: false
          anchors.centerIn: parent
          text: root.drawerCount > 99 ? "99" : String(root.drawerCount)
          color: root.customToneActive
            ? root.badgeContrastColor
            : root.bar ? root.bar.background : Commons.Color.background
          font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 7
          font.weight: Font.Bold
        }

        // Paint only; the original badge still reserves its layout and anchor.
        Rectangle {
          id: badgePaint
          readonly property real pixel: 1 / badgePlacement.dpr
          readonly property real diameter: Math.max(1,
            Math.round(Commons.Style.space(10) * badgePlacement.dpr)) * pixel
          width: Math.floor(Math.max(diameter, badgeValue.implicitWidth + Commons.Style.space(6)) / pixel) * pixel
          height: diameter
          radius: height / 2
          color: root.customToneActive
            ? root.contentColor
            : root.bar ? root.bar.urgent : Commons.Color.accent
          x: {
            const origin = badgePlacement.origin
            const slot = drawerToggle.mapToItem(drawerBadge, 0, 0)
            const first = Math.ceil((origin.x + slot.x) / pixel) * pixel - origin.x
            // Keep the single-digit circle anchored; extra width grows right.
            const last = Math.floor((origin.x + slot.x + drawerToggle.width) / pixel) * pixel - origin.x - diameter
            return Math.max(first, Math.min(last, badgePlacement.snapX(0)))
          }
          y: {
            const origin = badgePlacement.origin
            const slot = drawerToggle.mapToItem(drawerBadge, 0, 0)
            const first = Math.ceil((origin.y + slot.y) / pixel) * pixel - origin.y
            const last = Math.floor((origin.y + slot.y + drawerToggle.height) / pixel) * pixel - origin.y - height
            return Math.max(first, Math.min(last,
              badgePlacement.snapY((drawerBadge.height - height) / 2)))
          }

          Presentation.BarInk { id: valuePlacement; target: badgePaint }
          TextMetrics {
            id: valueInk
            text: badgeValue.text
            font: Qt.font({family: badgeValue.font.family,
              pixelSize: badgeValue.font.pixelSize * valuePlacement.metricScale,
              weight: badgeValue.font.weight, hintingPreference: Font.PreferNoHinting})
          }
          Text {
            id: badgeValue
            text: root.drawerCount > 99 ? "99+" : String(root.drawerCount)
            x: valuePlacement.snapX(parent.width / 2
              - (valueInk.tightBoundingRect.x + valueInk.tightBoundingRect.width / 2) / valuePlacement.metricScale)
            y: valuePlacement.snapY(parent.height / 2
              - (valueInk.tightBoundingRect.y + valueInk.tightBoundingRect.height / 2) / valuePlacement.metricScale) - baselineOffset
            color: badgeText.color
            font.family: badgeText.font.family
            font.pixelSize: Commons.Style.space(7)
            font.bold: true
          }
        }
      }

      MouseArea {
        id: drawerMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root.bar)
          root.bar.showTooltip(drawerToggle, root.drawerTooltipText)
        onExited: if (root.bar) root.bar.hideTooltip(drawerToggle)
        onClicked: function(mouse) {
          if (root.bar) root.bar.hideTooltip(drawerToggle)
          if (mouse.button === Qt.RightButton && root.trayBackend
              && root.trayBackend.managePopupOpen !== undefined) {
            root.trayBackend.managePopupOpen = !root.trayBackend.managePopupOpen
          } else {
            root.drawerRequested()
          }
        }
      }

      readonly property bool tooltipHovered: visible && drawerMouse.containsMouse
    }
  }
}
