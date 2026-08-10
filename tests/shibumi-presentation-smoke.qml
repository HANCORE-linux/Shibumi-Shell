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

    function paletteColor(id) {
      return id === "color05" ? selectedColor : "#ffffff"
    }

    function paletteContrastColor(id) {
      return id === "color05" ? "#111111" : "#ffffff"
    }
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
    settings: ({ color: "color05", colorMode: "fill" })
  }

  Widgets.PillSurface {
    id: v1FillProbe
    width: 100
    height: 24
    bar: fakeBar
    v1AppearanceEnabled: true
    settings: ({
      color: "color05",
      colorMode: "fill",
      tone: "background",
      surfaceOpacity: 0.4
    })
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
      const outlineSettings = {
        colorMode: "border",
        color: "color01",
        widgetBorder: true,
        widgetBorderColor: "color05"
      }
      if (style.visualTokens.widgetBorderColor(outlineSettings)
          !== fakeStateService.selectedColor)
        return root.fail("widget outline ignored its selected palette color")
      if (style.visualTokens.widgetBorderColor({
            colorMode: "border",
            color: "color05",
            widgetBorder: true
          }) !== style.visualTokens.panelBorder)
        return root.fail("widget outline used the surface color without consent")
      if (style.visualTokens.widgetBorderColor({
            colorMode: "border",
            color: "inherit",
            widgetBorder: true,
            widgetBorderColor: "inherit"
          }) !== style.visualTokens.panelBorder)
        return root.fail("inherited widget outline lost the panel border token")
      if (style.visualTokens.widgetBorderColor({
            colorMode: "border",
            color: "color05",
            widgetBorder: true,
            widgetBorderUsesSurfaceColor: true
          }) !== fakeStateService.selectedColor)
        return root.fail("legacy coupled widget outline lost compatibility")
      if (style.visualTokens.widgetBorderWidth({
            widgetBorderWidth: 1.5
          }) !== 1.5)
        return root.fail("half-pixel widget outline width was rounded away")
      if (style.visualTokens.widgetBorderWidth({
            widgetBorderWidth: 0.5
          }) !== 0.5)
        return root.fail("minimum widget outline width was clamped away")
      if (style.visualTokens.widgetSurfaceOpacity({
            surfaceOpacity: 0.4
          }) !== 0.4)
        return root.fail("40 percent widget opacity was clamped away")
      if (memoryCompact.implicitWidth >= memoryFull.implicitWidth)
        return root.fail("memory compact presentation did not reduce width")
      if (cpuCompact.implicitWidth >= cpuFull.implicitWidth)
        return root.fail("CPU compact presentation did not reduce width")
      if (memoryFull.implicitHeight !== 35 || cpuFull.implicitHeight !== 35)
        return root.fail("widgets do not follow Shibumi bar height")
      if (pillProbe.renderedSurfaceCount !== 1
          || pillProbe.renderedShadowCount !== 0
          || !pillProbe.shellPillVisible
          || pillProbe.v1CustomFill
          || pillProbe.renderedFillColor !== style.visualTokens.pill)
        return root.fail("non-opted V1 pill did not retain its surface")
      if (!v1FillProbe.v1CustomFill
          || v1FillProbe.renderedSurfaceCount !== 1
          || Math.abs(v1FillProbe.v1FillOpacity - 0.4) > 0.001
          || Math.abs(v1FillProbe.renderedFillColor.r
            - fakeStateService.selectedColor.r) > 0.001
          || Math.abs(v1FillProbe.renderedFillColor.g
            - fakeStateService.selectedColor.g) > 0.001
          || Math.abs(v1FillProbe.renderedFillColor.b
            - fakeStateService.selectedColor.b) > 0.001
          || Math.abs(v1FillProbe.renderedFillColor.a - 0.4) > 0.001)
        return root.fail("V1 fill did not reach the native pill surface")
      const staleV2SurfaceSettings = {
        color: "color05",
        colorMode: "border",
        tone: "background"
      }
      if (!style.visualTokens.widgetHasFill(staleV2SurfaceSettings)
          || style.visualTokens.widgetContentColor(
            staleV2SurfaceSettings, "#ffffff") !== style.visualTokens.paper)
        return root.fail("hidden V2 surface state disabled V1 appearance")
      fakeStateService.config = ({
        presentation: {
          border: true,
          shadow: true,
          frost: true,
          radius: "large",
          shellStyle: "shibumi"
        }
      })
      if (pillProbe.renderedShadowCount !== 1
          || style.visualTokens.barBackground.a < 0.67
          || style.visualTokens.barBackground.a > 0.69
          || style.visualTokens.pill.a < 0.17
          || style.visualTokens.pill.a > 0.19
          || style.visualTokens.panelBackground.a < 0.93
          || style.visualTokens.panelBackground.a > 0.95)
        return root.fail("V1 Shadow or reference Frost alpha did not apply")
      fakeStateService.config = ({
        presentation: {
          border: true,
          shadow: true,
          frost: true,
          radius: "large",
          shellStyle: "full"
        }
      })
      if (pillProbe.renderedSurfaceCount !== 0
          || pillProbe.renderedShadowCount !== 0
          || pillProbe.shellPillVisible
          || v1FillProbe.v1CustomFill
          || style.visualTokens.widgetHasFill(staleV2SurfaceSettings))
        return root.fail("V1 widget appearance leaked into V2 shell")
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
