import QtQuick
import Quickshell
import qs.Commons as Commons
import "widgets" as Widgets

ShellRoot {
  id: root

  QtObject {
    id: tokens
    property color panelBackground: "#191716"
    property color panelBorder: "#3f3d39"
    property int panelBorderWidth: 1
    property int panelRadius: 12
    property int tileRadius: 10
    property bool shadowEnabled: false
    property color pillShadow: "#88000000"
  }

  QtObject {
    id: fakeBar
    property string position: "top"
    property int barSize: 35
    property color foreground: "#eee9e4"
    property color urgent: "#e06c75"
    property var visualTokens: tokens
    property var activePopout: null
    property var clickTargets: []
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function targetBelongsToWindow(_target, _window) { return false }
  }

  Item { id: anchor; width: 24; height: 24 }

  QtObject {
    id: owner
    property bool opened: true
    function close() { opened = false }
  }

  Widgets.ShibumiPanel {
    id: panel
    anchorItem: anchor
    bar: fakeBar
    owner: owner
    open: owner.opened
    contentWidth: 180
    contentHeight: 96

    Item {
      objectName: "panelPayload"
      anchors.fill: parent
    }
  }

  Timer {
    id: verifyTimer
    property int phase: 0
    interval: 180
    running: true
    repeat: true
    onTriggered: {
      if (panel.renderedSurfaceColor.toString() !== tokens.panelBackground.toString()
          || panel.renderedSurfaceRadius !== tokens.panelRadius
          || panel.renderedBorderWidth !== 1
          || panel.renderedContentInset !== Commons.Style.spacing.popupPadding
          || panel.renderedContentCount !== 1
          || panel.renderedSurfaceCount !== 1
          || panel.controlRadius !== tokens.tileRadius) {
        console.error("panel surface smoke failed",
          panel.renderedSurfaceColor, panel.renderedSurfaceRadius,
          panel.renderedBorderWidth, panel.renderedContentCount,
          panel.renderedSurfaceCount, panel.controlRadius)
        Qt.exit(1)
        return
      }
      if (phase === 0) {
        phase = 1
        tokens.panelRadius = 6
        tokens.tileRadius = 4
        interval = 40
        return
      }
      stop()
      console.log("panel surface smoke passed")
      Qt.quit()
    }
  }
}
