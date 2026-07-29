import QtQuick
import Quickshell
import "status" as Status

ShellRoot {
  id: root

  QtObject {
    id: tokens
    property color panelBackground: "#191716"
    property color panelBorder: "#3f3d39"
    property int panelBorderWidth: 1
    property int panelRadius: 12
    property int tileRadius: 8
    property bool shadowEnabled: false
    property color pillShadow: "#88000000"
    property color sumi: "#77716b"
    property color sumiHi: "#aaa39b"
    property color separator: "#3f3d39"
    property color fillIdle: "#241f1d"
    property color fillHover: "#382e2b"
    property color fillActive: "#493834"
    property color fillPrimaryHover: "#d78870"
  }

  QtObject {
    id: fakeBar
    property string position: "top"
    property int barSize: 35
    property string fontFamily: "monospace"
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
    id: fakeOwner
    property bool trayAppMenuOpen: true
    property int closeCount: 0
    function close() {
      closeCount++
      trayAppMenuOpen = false
    }
    function closeTrayAppMenu() { trayAppMenuOpen = false }
    function trayItemName(_item) { return "Fixture App" }
  }

  QtObject {
    id: fakeTrayItem
    property var menu: null
    property string icon: ""
  }

  Status.TrayAppMenuPanel {
    id: panel
    ownerWidget: fakeOwner
    trayItem: fakeTrayItem
    anchorItem: anchor
    bar: fakeBar
  }

  Component.onCompleted: {
    fakeOwner.trayAppMenuOpen = false
    Qt.callLater(function() {
      fakeBar.activePopout = fakeOwner
      fakeOwner.trayAppMenuOpen = true
    })
  }

  Timer {
    id: verifyTimer
    property int phase: 0
    interval: 180
    running: true
    repeat: true
    onTriggered: {
      if (panel.renderedSurfaceCount !== 1
          || panel.renderedSurfaceRadius !== tokens.panelRadius
          || panel.controlRadius !== tokens.tileRadius
          || panel.appName !== "Fixture App") {
        console.error("tray app menu smoke failed",
          panel.renderedSurfaceCount, panel.renderedSurfaceRadius,
          panel.controlRadius, panel.appName)
        Qt.exit(1)
        return
      }
      if (phase === 0) {
        if (fakeOwner.closeCount !== 0 || !fakeOwner.trayAppMenuOpen) {
          console.error("tray app menu competed with drawer popout ownership")
          Qt.exit(1)
          return
        }
        phase = 1
        panel.closeMenu()
        interval = 40
        return
      }
      if (fakeOwner.trayAppMenuOpen) {
        console.error("tray app menu close contract failed")
        Qt.exit(1)
        return
      }
      stop()
      console.log("tray app menu smoke passed")
      Qt.quit()
    }
  }
}
