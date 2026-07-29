import QtQuick
import Quickshell
import "widgets" as Widgets

ShellRoot {
  id: root

  function fail(message) {
    console.error("workspace-panel-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeBar
    property string position: "top"
    property int barSize: 28
    property string fontFamily: "monospace"
    property color foreground: "#e8e8e8"
    property color urgent: "#88bbee"
    property var activePopout: null
    property var clickTargets: []
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return false }
  }

  QtObject {
    id: owner
    property bool opened: true
    function close() { opened = false }
    function switchPanel(_direction) { return false }
  }

  QtObject {
    id: workspaceState
    property var entries: [
      { id: 2, windowCount: 1, focused: true, occupied: true },
      { id: 8, windowCount: 2, focused: false, occupied: true }
    ]
    property string mode: "10"
    property string style: "default"
    property int focusedId: 2
    property int focusCount: 0
    function focusWorkspace(_id) { focusCount++; return true }
    function setPreference(name, value) {
      if (name === "mode") mode = String(value)
      else if (name === "style") style = String(value)
      else return false
      return true
    }
  }

  QtObject {
    id: controller
    property var bar: fakeBar
    property var ownerWidget: owner
    property var workspaceService: workspaceState
    property var rows: workspaceState.entries
    property int cursorIndex: 0
    property string shellStyle: "shibumi"
    property real controlRadius: 10
    property real controlBorderWidth: 1
    property color controlFillColor: "#181818"
    property color controlHoverFillColor: "#223344"
    property color controlActiveFillColor: "#284866"
    property color controlBorderColor: "#505050"
    property color controlAccent: "#88bbee"
    property color controlMuted: "#707070"
    property color controlMutedHigh: "#a0a0a0"
    function moveCursor(delta) {
      cursorIndex = (cursorIndex + delta + rows.length) % rows.length
      return true
    }
    function activateCursor() {
      if (!workspaceState.focusWorkspace(rows[cursorIndex].id)) return false
      owner.close()
      return true
    }
  }

  Widgets.WorkspacePanelContent {
    id: panel
    width: 240
    height: implicitHeight
    controller: controller
  }

  Timer {
    interval: 180
    running: true
    onTriggered: {
      if (panel.renderedRowCount !== 2 || !panel.controlsFitWidth
          || panel.width !== 240 || panel.height <= 0)
        return root.fail("panel content contract: rows=" + panel.renderedRowCount
          + " fit=" + panel.controlsFitWidth + " width=" + panel.width
          + " height=" + panel.height)
      if (!controller.moveCursor(1) || controller.cursorIndex !== 1
          || !controller.activateCursor() || workspaceState.focusCount !== 1
          || owner.opened)
        return root.fail("panel keyboard action contract")
      console.log("workspace panel smoke passed")
      Qt.quit()
    }
  }
}
