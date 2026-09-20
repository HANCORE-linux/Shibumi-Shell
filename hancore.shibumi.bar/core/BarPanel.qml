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
    && windowRecovery.recoveryVisible
  // Keep the anchor window edge-local in every presentation and while editing.
  // The reserved desktop area remains the independent exclusiveZone below.
  implicitWidth: bar.vertical && validScreen ? bar.barSize : 0
  implicitHeight: !bar.vertical && validScreen ? bar.barSize : 0
  color: "transparent"
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

  WindowRecovery {
    id: windowRecovery
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
    originX: barWindow.bar.vertical && barWindow.bar.position === "right"
      && barWindow.validScreen
        ? Math.max(0, barWindow.screen.width - barWindow.bar.barSize) : 0
    originY: !barWindow.bar.vertical && barWindow.bar.position === "bottom"
      && barWindow.validScreen
        ? Math.max(0, barWindow.screen.height - barWindow.bar.barSize) : 0
    geometryKey: JSON.stringify([
      barWindow.screen ? String(barWindow.screen.name || "") : "",
      barWindow.screen ? Number(barWindow.screen.width) || 0 : 0,
      barWindow.screen ? Number(barWindow.screen.height) || 0 : 0,
      barWindow.screen ? Number(barWindow.screen.devicePixelRatio) || 1 : 1,
      String(barWindow.bar.position || ""),
      Number(barWindow.bar.barSize) || 0
    ])
  }

  Component.onCompleted: bar.registerLayoutSession(dragSession)
  Component.onDestruction: {
    if (typeof bar.releasePopoutsForScreen === "function")
      bar.releasePopoutsForScreen(dragSession.screenName)
    bar.unregisterLayoutSession(dragSession)
  }

  DragGhostPanel {
    bar: barWindow.bar
    layoutSession: dragSession
    targetScreen: barWindow.screen
  }

  HostedPanelConnector {
    bar: barWindow.bar
    targetScreen: barWindow.screen
  }

  Loader {
    id: editBackdropLoader

    active: dragSession.editing
      && barWindow.visible && barWindow.backingWindowVisible
      && barWindow.bar.hostReady && barWindow.bar.styleReady
      && barWindow.validScreen && !barWindow.bar.barHidden
      && windowRecovery.recoveryVisible
    sourceComponent: Component {
      EditBackdropPanel {
        bar: barWindow.bar
        layoutSession: dragSession
        targetScreen: barWindow.screen
        barVisible: barWindow.visible && barWindow.backingWindowVisible
          && windowRecovery.recoveryVisible
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: dragSession.editing
    color: "#000000"
    opacity: 0.34
    z: 1
  }

  Loader {
    id: barSurfaceLoader

    anchors.fill: parent
    active: barWindow.bar.hostReady && barWindow.bar.styleReady
      && barWindow.validScreen && barWindow.bar.visualTokens !== null
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
