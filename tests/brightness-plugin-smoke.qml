import QtQuick
import Quickshell
import "brightness" as Brightness
import "fixtures" as Fixtures

ShellRoot {
  id: root

  property int phase: 0
  property int phaseTicks: 0
  property real fullWidth: 0
  property var clickTargets: []
  property int summonCount: 0

  function fail(message) {
    console.error("brightness-widget-smoke:", message)
    Qt.exit(1)
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
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: root.clickTargets
    property var shell: null
    property var barWidgetRegistry: null
    property var monitorService: sharedMonitorService
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

    function registeredWidgetSource(_id) { return "" }
    function registeredWidgetComponent(_id) { return null }
    function widgetSettings(group, module) {
      return group === "G13" && module === "omarchy.monitor"
        ? ({ testSetting: "retained" }) : ({})
    }
    function registerClickTarget(target) {
      if (root.clickTargets.indexOf(target) < 0)
        root.clickTargets = root.clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      root.clickTargets = root.clickTargets.filter(item => item !== target)
    }
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
    function summonBarWidget(id) {
      if (id !== "omarchy.monitor") return false
      root.summonCount++
      return true
    }
  }

  Component {
    id: monitorPanelComponent
    Fixtures.MonitorTestPanel {}
  }

  Brightness.Service {
    id: sharedMonitorService
    bar: fakeBar
    panelComponent: monitorPanelComponent
  }

  QtObject {
    id: unavailableService
    property bool ready: false
    property bool brightnessAvailable: false
    property int brightnessPercent: 0
    property var displays: []
  }

  Loader {
    id: firstLoader
    active: true
    sourceComponent: Component {
      Brightness.BarWidget {
        bar: fakeBar
        settings: ({ compact: false })
        monitorServiceOverride: sharedMonitorService
        popupSource: Qt.resolvedUrl("fixtures/MonitorTestView.qml")
      }
    }
  }

  Loader {
    id: secondLoader
    active: true
    sourceComponent: Component {
      Brightness.BarWidget {
        bar: fakeBar
        settings: ({ compact: false })
        monitorServiceOverride: sharedMonitorService
        popupSource: Qt.resolvedUrl("fixtures/MonitorTestView.qml")
      }
    }
  }

  Brightness.BarWidget {
    id: unavailableBrightness
    bar: fakeBar
    monitorServiceOverride: unavailableService
  }

  Timer {
    interval: 80
    repeat: true
    running: true
    onTriggered: {
      root.phaseTicks++
      const first = firstLoader.item
      const second = secondLoader.item
      const backend = sharedMonitorService.backend

      if (root.phase === 0) {
        if (!first || !second || !backend || !sharedMonitorService.ready
            || root.phaseTicks < 3) return
        if (first.monitorService !== second.monitorService
            || first.monitorService !== sharedMonitorService
            || !first.brightnessAvailable || first.percent !== 64
            || first.displayCount !== 2 || first.implicitHeight !== 35
            || !sharedMonitorService.textSizeAvailable
            || sharedMonitorService.textSizePx !== 12
            || sharedMonitorService.textSizeIndex !== 3
            || unavailableBrightness.visible)
          return root.fail("shared backend readiness/state/geometry")
        if (backend.opacity !== 0 || backend.manageIpc !== false
            || backend.settings.testSetting !== "retained")
          return root.fail("hidden official owner/settings")
        if (first.childPanelWidget("omarchy.monitor") !== first
            || second.childPanelWidget("omarchy.monitor") !== second
            || !first.ownsPanelWidget(first))
          return root.fail("screen-local alias routing")
        if (root.clickTargets.length !== 2)
          return root.fail("duplicate official click target")

        root.fullWidth = first.implicitWidth
        first.settings = ({ compact: true })
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 1) {
        if (root.phaseTicks < 3) return
        if (!first.compact || !first.compactValueVisible
            || first.implicitWidth >= root.fullWidth)
          return root.fail("V1 compact icon/value presentation")

        backend.open()
        if (root.summonCount !== 1)
          return root.fail("legacy monitor IPC redirect")
        first.interactionTarget.wheelMoved(120)
        if (sharedMonitorService.brightnessPercent !== 69 || backend.setCount !== 1)
          return root.fail("wheel brightness forwarding")
        sharedMonitorService.previewBrightness(71)
        sharedMonitorService.setScale("1.6")
        sharedMonitorService.setTextSize(14)
        sharedMonitorService.adjustTextSize(1)
        sharedMonitorService.toggleDisplay("DP-1", true)
        if (backend.previewCount !== 1 || backend.scaleCount !== 1
            || backend.textSizeSetCount !== 2 || backend.textSizePx !== 16
            || backend.toggleCount !== 1 || sharedMonitorService.monitorScale !== "1.6"
            || sharedMonitorService.enabledDisplayCount !== 1)
          return root.fail("monitor action forwarding")

        first.interactionTarget.triggerPress(Qt.LeftButton)
        second.open()
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 2) {
        if (root.phaseTicks < 3) return
        if (!first.opened || !second.opened || !first.panelLoaded
            || !second.panelLoaded || backend.viewLoadCount !== 2
            || backend.refreshCount !== 2 || fakeBar.activePopout !== second)
          return root.fail("two-output lazy local panels: first=" + first.opened
            + " second=" + second.opened + " firstLoaded=" + first.panelLoaded
            + " secondLoaded=" + second.panelLoaded + " views="
            + backend.viewLoadCount + " refreshes=" + backend.refreshCount
            + " activeSecond=" + (fakeBar.activePopout === second))
        if (backend.opened)
          return root.fail("hidden official popup remained open")

        backend.brightnessAvailable = false
        backend.internalMonitor = ""
        backend.displays = [
          { name: "DP-1", enabled: true, focused: true }
        ]
        root.phase++
        root.phaseTicks = 0
      } else if (root.phase === 3) {
        if (root.phaseTicks < 2) return
        if (!first.visible || first.brightnessAvailable || first.internalDisplay
            || first.tooltipText !== "Display controls" || first.implicitWidth <= 0)
          return root.fail("display controls fallback without backlight")
        first.close()
        secondLoader.active = false
        root.phase++
        root.phaseTicks = 0
      } else {
        if (first.panelLoaded || root.clickTargets.length !== 1
            || fakeBar.activePopout !== null)
          return root.fail("local panel teardown")
        firstLoader.active = false
        Qt.callLater(function() {
          if (root.clickTargets.length !== 0)
            return root.fail("click target destruction cleanup")
          console.log("brightness plugin smoke passed")
          Qt.quit()
        })
        stop()
      }
    }
  }
}
