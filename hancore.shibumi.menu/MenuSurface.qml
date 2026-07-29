pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons
import "MenuGeometry.js" as MenuGeometry

PanelWindow {
  id: root

  required property var controller
  readonly property int outerGap: Commons.Style.gapsOut
  readonly property bool validTargetScreen: controller.targetScreen !== null

  screen: controller.targetScreen
  visible: controller.opened && validTargetScreen
  color: "transparent"
  anchors {
    top: true
    right: true
    bottom: true
    left: true
  }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "shibumi-menu"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  function cardX() {
    return MenuGeometry.cardX(
      root.controller.barPosition, root.width, card.width,
      root.outerGap, root.controller.barSize, Commons.Style.space(248))
  }

  function cardY() {
    return MenuGeometry.cardY(
      root.controller.barPosition, root.height, card.height,
      root.outerGap, root.controller.barSize)
  }

  function focusSearch() {
    card.focusSearch()
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.menu.scrim
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.BackButton
    onClicked: function(mouse) {
      if ((mouse.button === Qt.RightButton || mouse.button === Qt.BackButton)
          && root.controller.goBack()) return
      root.controller.dismiss()
    }
  }

  RectangularShadow {
    x: card.x
    y: card.y
    width: card.width
    height: card.height
    visible: card.tokens && card.tokens.shadowEnabled
    radius: card.radius
    blur: 8
    spread: 0
    offset: Qt.vector2d(0,
      root.controller.barPosition === "bottom" ? -1 : 1)
    color: card.tokens ? card.tokens.pillShadow : "transparent"
  }

  MenuCard {
    id: card
    x: root.cardX()
    y: root.cardY()
    controller: root.controller
    availableWidth: root.width - root.outerGap * 2
    availableHeight: root.height - root.outerGap * 2
  }
}
