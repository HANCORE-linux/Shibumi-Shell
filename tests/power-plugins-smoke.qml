pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "battery" as Battery
import "powerProfile" as PowerProfile
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property real batteryFullWidth: 0
  property real profileFullWidth: 0
  property var clickTargets: []

  function fail(message) {
    console.error("power-plugins-smoke:", message)
    Qt.exit(1)
  }

  Fixtures.PowerTestService { id: power }

  QtObject {
    id: fakeShell
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.power-state" ? power : null
    }
  }

  Item {
    id: fakeBar
    visible: false
    width: 0
    height: 0
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
    property var shell: fakeShell
    property int runCalls: 0
    property string lastCommand: ""
    property var visualTokens: ({
      shellStyle: "shibumi",
      v2Shell: false,
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
      iconSize: 15,
      widgetHasFill: function(settings) {
        if (!settings || settings.color !== "color05") return false
        return this.v2Shell !== true
          || settings.colorMode === "fill" || settings.colorMode === "both"
      },
      widgetFillColor: function(settings) {
        return settings && settings.color === "color05"
          ? "#cc8844" : "transparent"
      },
      widgetSurfaceOpacity: function(settings) {
        return settings && settings.surfaceOpacity !== undefined
          ? Number(settings.surfaceOpacity) : 1
      },
      widgetContentColor: function(settings, fallback) {
        if (!settings || settings.color !== "color05") return fallback
        const active = this.v2Shell !== true
          || settings.colorMode === "fill" || settings.colorMode === "both"
        return active && settings.tone === "background"
          ? fakeBar.background : fallback
      }
    })

    function registeredWidgetSource(_id) { return "" }
    function registeredWidgetComponent(_id) { return null }
    function widgetSettings(_group, _module) { return ({}) }
    function registerClickTarget(target) {
      if (root.clickTargets.indexOf(target) < 0)
        root.clickTargets = root.clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      root.clickTargets = root.clickTargets.filter(item => item !== target)
    }
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) {
      const previous = activePopout
      activePopout = owner
      if (previous && previous !== owner && typeof previous.close === "function")
        previous.close()
    }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
    function run(command) { runCalls++; lastCommand = String(command || "") }
  }

  Loader {
    id: batteryA
    active: true
    sourceComponent: Component {
      Battery.BarWidget {
        bar: fakeBar
        settings: ({
          displayMode: "full",
          color: "color05",
          colorMode: "border",
          tone: "background",
          surfaceOpacity: 0.6
        })
        panelSource: Qt.resolvedUrl("fixtures/PowerTestPanel.qml")
      }
    }
  }
  Loader {
    id: batteryB
    active: true
    sourceComponent: Component {
      Battery.BarWidget {
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
      PowerProfile.BarWidget {
        bar: fakeBar
        settings: ({ compact: false })
      }
    }
  }
  Loader {
    id: profileB
    active: true
    sourceComponent: Component {
      PowerProfile.BarWidget {
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
      const batA = batteryA.item
      const batB = batteryB.item
      const pwrA = profileA.item
      const pwrB = profileB.item
      if (!batA || !batB || !pwrA || !pwrB) return

      if (root.phase === 0) {
        if (root.ticks < 3) return
        if (batA.visible || batA.implicitWidth !== 0
            || !pwrA.visible || pwrA.implicitWidth <= 0
            || power.profileConsumers !== 2)
          return root.fail("desktop without battery must retain both profile views")
        if (batA.powerService !== power || batB.powerService !== power
            || pwrA.powerService !== power || pwrB.powerService !== power)
          return root.fail("widgets did not resolve the shared power-state service")
        if (!batA.v1CustomToneActive || batB.v1CustomToneActive
            || !Qt.colorEqual(batA.widgetInk, fakeBar.background)
            || !Qt.colorEqual(batA.chargingDetailColor, "#cc8844")
            || Math.abs(batA.chargingShimmerColor.r - 204 / 255) > 0.001
            || Math.abs(batA.chargingShimmerColor.g - 136 / 255) > 0.001
            || Math.abs(batA.chargingShimmerColor.b - 68 / 255) > 0.001
            || Math.abs(batA.chargingShimmerColor.a - 0.18) > 0.001
            || !Qt.colorEqual(batB.chargingDetailColor, fakeBar.background)
            || Math.abs(batB.chargingShimmerColor.r - 1) > 0.001
            || Math.abs(batB.chargingShimmerColor.g - 1) > 0.001
            || Math.abs(batB.chargingShimmerColor.b - 1) > 0.001
            || Math.abs(batB.chargingShimmerColor.a - 0.18) > 0.001)
          return root.fail("V1 battery charging content tone")
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
        if (!batB.compact || !batB.compactValueVisible
            || batB.implicitWidth >= root.batteryFullWidth)
          return root.fail("V1 battery compact gauge/value presentation")
        if (!batA.openSystemMonitor() || fakeBar.runCalls !== 1
            || fakeBar.lastCommand !== "omarchy-launch-or-focus-tui btop")
          return root.fail("battery system-monitor action did not use the host facade")
        batA.activate()
        const v2Tokens = ({})
        for (const key in fakeBar.visualTokens)
          v2Tokens[key] = fakeBar.visualTokens[key]
        v2Tokens.shellStyle = "full"
        v2Tokens.v2Shell = true
        fakeBar.visualTokens = v2Tokens
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (root.ticks < 3) return
        if (!batA.opened || !batA.panelItem || power.detailConsumers !== 1
            || fakeBar.activePopout !== batA)
          return root.fail("battery panel/detail lifecycle")
        if (batA.v1CustomToneActive
            || !Qt.colorEqual(batA.widgetInk, fakeBar.urgent)
            || !Qt.colorEqual(batA.chargingDetailColor, fakeBar.background)
            || Math.abs(batA.chargingShimmerColor.r - 1) > 0.001
            || Math.abs(batA.chargingShimmerColor.a - 0.18) > 0.001)
          return root.fail("V1 battery tone leaked into V2")
        pwrA.activate(Qt.LeftButton)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (root.ticks < 3) return
        if (batA.opened || power.detailConsumers !== 0 || !pwrA.opened
            || !pwrA.panelLoaded || !pwrA.panelItem
            || fakeBar.activePopout !== pwrA)
          return root.fail("cross-group popout ownership")
        pwrA.close()
        const before = power.setProfileCalls
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
        console.log("power plugins smoke passed")
        Qt.quit()
      }
    }
  }
}
