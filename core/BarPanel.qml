pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: barWindow

  required property var bar
  readonly property bool validScreen: screen !== null
    && screen.name !== ""
    && screen.width > 0
    && screen.height > 0
  readonly property var layoutSession: dragSession
  readonly property real surfaceWidth: barSurfaceLoader.item
    ? Number(barSurfaceLoader.item.width) || 0 : 0
  readonly property int responsiveStage: barSurfaceLoader.item
    && "responsiveStage" in barSurfaceLoader.item
      ? Number(barSurfaceLoader.item.responsiveStage) || 0 : 0
  readonly property var responsiveProbe: barSurfaceLoader.item
    && "responsiveProbe" in barSurfaceLoader.item
      ? barSurfaceLoader.item.responsiveProbe : ({})

  visible: bar.hostReady && bar.styleReady && validScreen && !bar.barHidden
  implicitWidth: bar.vertical ? bar.barSize : 0
  // Keep the horizontal layer surface stable like V1. Edit mode expands only
  // the input mask; resizing a bottom-anchored surface during interaction can
  // invalidate the compositor-side pointer sequence.
  implicitHeight: bar.vertical ? 0
    : validScreen ? screen.height : bar.barSize
  color: bar.vertical && !bar.transparent ? bar.background : "transparent"
  surfaceFormat.opaque: false

  anchors {
    top: bar.position === "top" || bar.vertical
    bottom: bar.position === "bottom" || bar.vertical
    left: bar.position === "left" || !bar.vertical
    right: bar.position === "right" || !bar.vertical
  }

  WlrLayershell.namespace: "shibumi-bar"
  WlrLayershell.layer: WlrLayer.Top
  exclusiveZone: bar.barExclusiveSize
  WlrLayershell.keyboardFocus: dragSession.editing
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  mask: Region {
    x: 0
    y: barWindow.bar.vertical || dragSession.editing
      || barWindow.bar.position === "top"
      ? 0 : Math.max(0, barWindow.height - barWindow.bar.barSize)
    width: barWindow.width
    height: dragSession.editing ? barWindow.height
      : barWindow.bar.vertical ? barWindow.height : barWindow.bar.barSize
  }

  WindowRecovery {
    targetWindow: barWindow
    targetScreen: barWindow.screen
    recoveryAllowed: barWindow.bar.hostReady
      && barWindow.bar.styleReady
      && !barWindow.bar.barHidden
  }

  DragSession {
    id: dragSession
    layoutController: barWindow.bar.layoutController
    screenName: barWindow.screen ? String(barWindow.screen.name || "") : ""
  }

  Component.onCompleted: bar.registerLayoutSession(dragSession)
  Component.onDestruction: bar.unregisterLayoutSession(dragSession)

  Rectangle {
    anchors.fill: parent
    visible: !barWindow.bar.vertical && dragSession.editing
    color: "#000000"
    opacity: visible ? 0.34 : 0
    z: 0

    Behavior on opacity { NumberAnimation { duration: 160 } }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onClicked: dragSession.setEditing(false)
    }
  }

  Loader {
    id: barSurfaceLoader

    width: barWindow.bar.vertical ? barWindow.bar.barSize : parent.width
    height: barWindow.bar.vertical ? parent.height : barWindow.bar.barSize
    anchors.left: parent.left
    y: !barWindow.bar.vertical && barWindow.bar.position === "bottom"
      ? Math.max(0, parent.height - height) : 0
    active: barWindow.bar.hostReady && barWindow.bar.styleReady
      && barWindow.bar.visualTokens !== null
    sourceComponent: active ? barWindow.bar.activeStyle.barSurfaceComponent : null
    z: 10
    onLoaded: {
      if (item && "layoutSession" in item) item.layoutSession = dragSession
      if (item && "screenName" in item)
        item.screenName = barWindow.screen ? String(barWindow.screen.name || "") : ""
    }
  }

  PopupWindow {
    id: tooltipWindow

    visible: barWindow.bar.styleReady
      && barWindow.bar.tooltipShown
      && barWindow.bar.targetBelongsToWindow(barWindow.bar.tooltipTarget, barWindow)
    color: "transparent"
    implicitWidth: tooltipSurfaceLoader.item
      ? Math.ceil(tooltipSurfaceLoader.item.implicitWidth)
      : 0
    implicitHeight: tooltipSurfaceLoader.item
      ? Math.ceil(tooltipSurfaceLoader.item.implicitHeight)
      : 0

    anchor {
      window: barWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        const target = barWindow.bar.tooltipTarget
        if (!barWindow.bar.targetBelongsToWindow(target, barWindow)) return

        let localX = target.width / 2 - tooltipWindow.implicitWidth / 2
        const gap = barWindow.bar.activeStyle.tooltipGap
        let localY = target.height + gap
        if (barWindow.bar.position === "bottom")
          localY = -tooltipWindow.implicitHeight - gap
        else if (barWindow.bar.position === "left") {
          localX = target.width + gap
          localY = target.height / 2 - tooltipWindow.implicitHeight / 2
        } else if (barWindow.bar.position === "right") {
          localX = -tooltipWindow.implicitWidth - gap
          localY = target.height / 2 - tooltipWindow.implicitHeight / 2
        }

        const point = barWindow.contentItem.mapFromItem(target, localX, localY)
        tooltipWindow.anchor.rect.x = Math.round(point.x)
        tooltipWindow.anchor.rect.y = Math.round(point.y)
      }
    }

    Loader {
      id: tooltipSurfaceLoader

      anchors.fill: parent
      active: barWindow.bar.styleReady
        && barWindow.bar.visualTokens !== null
      sourceComponent: active ? barWindow.bar.activeStyle.tooltipSurfaceComponent : null
    }
  }
}
