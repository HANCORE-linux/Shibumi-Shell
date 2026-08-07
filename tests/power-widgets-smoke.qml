pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "widgets" as Widgets
import "fixtures" as Fixtures
import "services/PowerModel.js" as PowerModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property real batteryFullWidth: 0
  property real profileFullWidth: 0

  function fail(message) {
    console.error("power-widgets-smoke:", message)
    Qt.exit(1)
  }

  Fixtures.PowerTestService { id: power }

  QtObject {
    id: actions
    property int btopCalls: 0
    function openSystemMonitor() { btopCalls++; return true }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 35
    property int sizeHorizontal: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#191919"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var powerService: power
    property var systemActions: actions
    property var visualTokens: ({
      pillHeight: 24,
      pillRadius: 12,
      pillPaddingX: 9,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      slotHeight: 28,
      contentGap: 5,
      compactGap: 4,
      labelSize: 12,
      iconSize: 15
    })

    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) {
      var previous = activePopout
      activePopout = owner
      if (previous && previous !== owner && typeof previous.close === "function")
        previous.close()
    }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
  }

  Loader {
    id: batteryA
    active: true
    sourceComponent: Component {
      Widgets.BatteryWidget {
        bar: fakeBar
        settings: ({ compact: false })
        panelSource: Qt.resolvedUrl("fixtures/PowerTestPanel.qml")
      }
    }
  }
  Loader {
    id: batteryB
    active: true
    sourceComponent: Component {
      Widgets.BatteryWidget {
        bar: fakeBar
        settings: ({ compact: true })
        panelSource: Qt.resolvedUrl("fixtures/PowerTestPanel.qml")
      }
    }
  }
  Loader {
    id: profileA
    active: true
    sourceComponent: Component {
      Widgets.PowerProfileWidget {
        bar: fakeBar
        settings: ({ compact: false })
        panelSource: Qt.resolvedUrl("fixtures/PowerTestPanel.qml")
      }
    }
  }
  Loader {
    id: profileB
    active: true
    sourceComponent: Component {
      Widgets.PowerProfileWidget {
        bar: fakeBar
        settings: ({ compact: true })
        panelSource: Qt.resolvedUrl("fixtures/PowerTestPanel.qml")
      }
    }
  }

  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      var batA = batteryA.item
      var batB = batteryB.item
      var pwrA = profileA.item
      var pwrB = profileB.item
      if (!batA || !batB || !pwrA || !pwrB) return

      if (root.phase === 0) {
        if (root.ticks < 3) return
        var parsed = PowerModel.parseProfiles(
          "power-saver\t0\nbalanced\t1\nperformance\t0\ninvalid name\t1\n")
        if (parsed.profiles.length !== 3 || parsed.activeProfile !== "balanced"
            || PowerModel.clampPercent(0.2) !== 20
            || PowerModel.duration(4260) !== "1h 11m")
          return root.fail("power model parsing")
        if (batA.visible || batA.implicitWidth !== 0
            || !pwrA.visible || pwrA.implicitWidth <= 0
            || power.profileConsumers !== 2)
          return root.fail("desktop without battery must retain both profile views")
        root.profileFullWidth = pwrA.implicitWidth
        if (pwrB.implicitWidth >= root.profileFullWidth)
          return root.fail("power-profile compact width")
        power.hasBattery = true
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (root.ticks < 3) return
        if (!batA.visible || batA.implicitWidth <= 0 || batA.percent !== 20)
          return root.fail("laptop battery visibility/state")
        root.batteryFullWidth = batA.implicitWidth
        if (batB.implicitWidth >= root.batteryFullWidth)
          return root.fail("battery compact width")
        if (batA.powerService !== power || batB.powerService !== power
            || pwrA.powerService !== power || pwrB.powerService !== power)
          return root.fail("multi-output views do not share one service owner")
        if (typeof pwrA.childPanelWidget !== "function"
            || pwrA.childPanelWidget("omarchy.power") !== pwrA
            || typeof batA.childPanelWidget === "function"
              && batA.childPanelWidget("omarchy.power") !== null)
          return root.fail("canonical omarchy.power routing owner")
        batA.activate()
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.ticks < 3) return
        if (!batA.opened || !batA.panelItem || power.detailConsumers !== 1
            || fakeBar.activePopout !== batA)
          return root.fail("battery panel/detail lifecycle: opened=" + batA.opened
            + " panel=" + batA.panelItem + " details=" + power.detailConsumers
            + " active=" + fakeBar.activePopout + " expected=" + batA)
        pwrA.activate(Qt.LeftButton)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.ticks < 3) return
        if (batA.opened || power.detailConsumers !== 0 || !pwrA.opened
            || !pwrA.panelItem || fakeBar.activePopout !== pwrA)
          return root.fail("cross-group popout ownership")
        pwrA.close()
        var before = power.setProfileCalls
        if (!pwrA.activate(Qt.RightButton)
            || power.setProfileCalls !== before + 1
            || power.activeProfile !== "performance")
          return root.fail("right-click profile cycle")
        batB.activate()
        power.hasBattery = false
        root.phase++
        root.ticks = 0
      } else if (root.phase === 4) {
        if (root.ticks < 3) return
        if (batB.opened || power.detailConsumers !== 0
            || batA.visible || batB.visible || !pwrA.visible || !pwrB.visible)
          return root.fail("battery removal must not remove power profiles")
        stop()
        console.log("power widgets smoke passed")
        Qt.quit()
      }
    }
  }
}
