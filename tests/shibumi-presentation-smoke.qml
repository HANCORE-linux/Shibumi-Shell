import QtQuick
import Quickshell
import "services" as Services
import "styles/shibumi" as ShibumiStyle
import "widgets" as Widgets

ShellRoot {
  id: root

  Services.SystemTelemetry { id: telemetry }

  QtObject {
    id: actions
    function openSystemMonitor() { return true }
  }

  QtObject {
    id: fakeStateService
    property var config: ({
      presentation: {
        border: true,
        shadow: false,
        frost: false,
        radius: "large",
        shellStyle: "shibumi"
      }
    })
    property color selectedColor: "#88aaff"
  }

  QtObject {
    id: dynamicTooltipTarget
    property string tooltipText: "Audio 90%"
  }

  QtObject {
    id: fakeShell
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.state" ? fakeStateService : null
    }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: style.sizeHorizontal
    property string position: "top"
    property string fontFamily: style.fontFamily
    property color foreground: style.foreground
    property color barForeground: style.barForeground
    property color background: style.background
    property color urgent: style.urgent
    property var visualTokens: style.visualTokens
    property var shell: fakeShell
    property var activePopout: null
    property var tooltipTarget: dynamicTooltipTarget
    property string tooltipText: "stale snapshot"
    property var systemTelemetry: telemetry
    property var gpuTelemetry: null
    property var systemActions: actions

    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(owner, direction) { return false }
  }

  ShibumiStyle.Style {
    id: style
    bar: fakeBar
  }

  Loader {
    id: tooltipSurface
    sourceComponent: style.tooltipSurfaceComponent
  }

  Widgets.MemoryWidget {
    id: memoryFull
    bar: fakeBar
    settings: ({ compact: false })
  }

  Widgets.MemoryWidget {
    id: memoryCompact
    bar: fakeBar
    settings: ({ compact: true })
  }

  Widgets.CpuWidget {
    id: cpuFull
    bar: fakeBar
    settings: ({ compact: false })
  }

  Widgets.PillSurface {
    id: pillProbe
    width: 100
    height: 24
    bar: fakeBar
  }

  Widgets.CpuWidget {
    id: cpuCompact
    bar: fakeBar
    settings: ({ compact: true })
  }

  function fail(message) {
    console.error("shibumi-presentation-smoke:", message)
    Qt.exit(1)
  }

  Timer {
    interval: 1000
    running: true
    onTriggered: {
      if (style.sizeHorizontal !== 35 || style.exclusiveSizeHorizontal !== 38)
        return root.fail("V1 bar geometry contract changed")
      if (style.visualTokens.islandHeight !== 32
          || style.visualTokens.pillHeight !== 24
          || style.visualTokens.pillRadius !== 12
          || style.visualTokens.panelRadius !== 12
          || style.visualTokens.panelBorderWidth !== 1
          || style.visualTokens.panelBackground.a < 0.93
          || style.visualTokens.panelBackground.a > 0.95
          || style.visualTokens.islandInsetX !== 5
          || style.visualTokens.islandContentInsetX !== 4
          || style.visualTokens.tooltipRadius !== 6
          || style.visualTokens.tooltipPaddingX !== 10
          || style.visualTokens.tooltipPaddingY !== 4
          || style.tooltipGap !== 6)
        return root.fail("V1 surface token contract changed")
      if (memoryCompact.implicitWidth >= memoryFull.implicitWidth)
        return root.fail("memory compact presentation did not reduce width")
      if (cpuCompact.implicitWidth >= cpuFull.implicitWidth)
        return root.fail("CPU compact presentation did not reduce width")
      if (memoryFull.implicitHeight !== 35 || cpuFull.implicitHeight !== 35)
        return root.fail("widgets do not follow Shibumi bar height")
      if (pillProbe.renderedSurfaceCount !== 1
          || !pillProbe.shellPillVisible)
        return root.fail("V1 widget pill is missing")
      fakeStateService.config = ({
        presentation: {
          border: true,
          shadow: false,
          frost: false,
          radius: "large",
          shellStyle: "full"
        }
      })
      if (pillProbe.renderedSurfaceCount !== 0
          || pillProbe.shellPillVisible)
        return root.fail("V1 widget pill leaked into V2 shell")
      if (style.sizeHorizontal !== 33
          || style.exclusiveSizeHorizontal !== 36
          || style.visualTokens.panelRadius !== 6
          || style.visualTokens.tileRadius !== 10
          || style.visualTokens.shellFitRadius !== 6
          || style.visualTokens.shellDockRadius !== 8)
        return root.fail("V2 shell geometry contract changed")
      fakeStateService.config = ({
        presentation: {
          border: true,
          shadow: false,
          frost: false,
          radius: "large",
          shellStyle: "shibumi"
        }
      })
      if (!tooltipSurface.item || tooltipSurface.item.resolvedText !== "Audio 90%")
        return root.fail("dynamic tooltip target was not resolved")
      dynamicTooltipTarget.tooltipText = "Audio 100%"
      if (tooltipSurface.item.resolvedText !== "Audio 100%")
        return root.fail("visible tooltip did not update reactively")
      console.log("shibumi presentation smoke passed")
      Qt.exit(0)
    }
  }
}
