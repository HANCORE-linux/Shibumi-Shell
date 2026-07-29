import QtQuick
import Quickshell
import "widgets" as Widgets

ShellRoot {
  id: root

  property string changedGroup: ""
  property string changedModule: ""
  property string changedKey: ""
  property var changedValue: null
  property string command: ""

  function fail(message) {
    console.error("clock widget smoke failed: " + message)
    Qt.exit(1)
  }

  QtObject {
    id: sharedClock
    property date date: new Date(2026, 6, 16, 13, 5, 0)
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 35
    property string fontFamily: "monospace"
    property color foreground: "#f0f0f0"
    property color barForeground: foreground
    property color urgent: "#ff7a90"
    property bool foregroundAnimationEnabled: false
    property var clockService: sharedClock
    property var visualTokens: ({ labelSize: 12 })

    function setWidgetSetting(group, module, key, value) {
      root.changedGroup = group
      root.changedModule = module
      root.changedKey = key
      root.changedValue = value
      return true
    }
    function run(value) { root.command = value }
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
  }

  Widgets.ClockWidget {
    id: firstClock
    bar: fakeBar
    settings: ({ clock12h: false })
  }

  Widgets.ClockWidget {
    id: secondClock
    bar: fakeBar
    settings: ({ clock12h: false })
  }

  Timer {
    interval: 50
    running: true
    onTriggered: {
      if (firstClock.clock !== sharedClock || secondClock.clock !== sharedClock)
        return root.fail("widgets do not share the root clock")
      if (firstClock.timeText !== "13:05" || firstClock.implicitHeight !== 35)
        return root.fail("V1 24-hour presentation")
      if (firstClock.tooltipText.indexOf("2026") < 0)
        return root.fail("date tooltip")
      if (!firstClock.toggleFormat()
          || root.changedGroup !== "G8"
          || root.changedModule !== "omarchy.clock"
          || root.changedKey !== "clock12h"
          || root.changedValue !== true)
        return root.fail("host-owned format persistence")

      firstClock.settings = ({ clock12h: true })
      if (firstClock.timeText !== "1:05 PM")
        return root.fail("V1 12-hour presentation")
      if (!firstClock.openTimezoneMenu()
          || root.command !== "omarchy-menu-timezone")
        return root.fail("Quattro timezone action")

      fakeBar.vertical = true
      if (firstClock.implicitWidth !== 35)
        return root.fail("vertical defensive geometry")

      console.log("clock widget smoke passed")
      Qt.quit()
    }
  }
}
