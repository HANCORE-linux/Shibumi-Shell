import QtQuick
import Quickshell
import "update" as Update

ShellRoot {
  id: root

  property int phase: 0

  function fail(message) {
    console.error("update-center-owner-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeState
    property var config: ({ widgets: ({ G3: ({}) }) })
    function setWidgetSetting(_group, _module, _key, _value) { return true }
  }

  QtObject {
    id: fakeUpdate
    property int totalUpdateCount: 1
    property int packageCount: 1
    property int themeCount: 0
    property bool packageRefreshing: false
    property bool themeRefreshing: false
    property bool needsAttention: false
    property string packageError: ""
    property string themeError: ""
    property string actionKind: ""
    property var packageState: ({
      state: "updates",
      checkedEpoch: Math.floor(Date.now() / 1000),
      packages: [{ name: "linux", installed: "1", target: "2" }]
    })
    property var themeState: ({
      checkedEpoch: Math.floor(Date.now() / 1000),
      degraded: false,
      review: 0,
      themes: []
    })
    function preferredTab() { return "packages" }
    function refreshAll() {}
    function refreshPackages() {}
    function launchPackageUpdate() {}
  }

  QtObject {
    id: fakeShell
    function serviceFor(moduleName) {
      if (moduleName === "hancore.shibumi.update-center") return fakeUpdate
      if (moduleName === "hancore.shibumi.state") return fakeState
      return null
    }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 35
    property string position: "top"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#d75f5f"
    property string fontFamily: "monospace"
    property bool foregroundAnimationEnabled: false
    property var shell: fakeShell
    property var activePopout: null
    property int releaseCalls: 0
    property int clearCalls: 0
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout !== owner) return
      releaseCalls++
      activePopout = null
    }
    function publishConnectedPanel(_owner, _screen, _x, _reveal) {}
    function clearConnectedPanel(_owner) { clearCalls++ }
  }

  Update.BarWidget {
    id: widget
    width: implicitWidth
    height: implicitHeight
    bar: fakeBar
    contentColor: fakeBar.background
    customToneActive: true
    badgeContrastColor: "#cc8844"
  }

  Timer {
    interval: 40
    repeat: true
    running: true
    onTriggered: {
      if (root.phase === 0) {
        if (!Qt.colorEqual(widget.badgeFillColor, fakeBar.background)
            || !Qt.colorEqual(widget.badgeTextColor, "#cc8844")
            || widget.badgeLayer !== 10)
          return root.fail("custom content tone badge")
        widget.open()
      } else if (root.phase === 1
          && (!widget.opened || !widget.panelLoaded)) {
        return root.fail("widget or panel did not open")
      } else if (root.phase === 1) {
        fakeBar.activePopout = widget
        widget.close()
      } else if (root.phase === 2
          && (widget.opened || widget.panelLoaded)) {
        return root.fail("widget or panel did not close")
      } else if (root.phase === 2
          && (fakeBar.activePopout !== null
            || fakeBar.releaseCalls !== 1 || fakeBar.clearCalls < 1)) {
        return root.fail("panel coordination was not released on close")
      } else {
        console.log("update center owner smoke passed")
        Qt.quit()
      }
      root.phase++
    }
  }
}
