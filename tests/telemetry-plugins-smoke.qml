pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "telemetry" as Telemetry
import "memory" as Memory
import "cpu" as Cpu
import "gpu" as Gpu
import "temperature" as Temperature

ShellRoot {
  id: root

  property int attempts: 0
  property int phase: 0

  Component.onCompleted:
    telemetryService.thermal.parseDetailed("55|63|90|105|44|82|90|39")

  function fail(message) {
    console.error("telemetry-plugins-smoke:", message)
    Qt.exit(1)
  }

  Telemetry.Service {
    id: telemetryService
  }

  Cpu.Service {
    id: cpuService
  }

  QtObject {
    id: fakeShell

    function serviceFor(pluginId) {
      if (pluginId === "hancore.shibumi.telemetry") return telemetryService
      if (pluginId === "hancore.shibumi.cpu") return cpuService
      if (pluginId === "hancore.shibumi.state") return fakeState
      return null
    }
  }

  QtObject {
    id: fakeState

    property string lastGroup: ""
    property string lastKey: ""
    property string lastValue: ""

    function setGroupSetting(group, key, value) {
      lastGroup = String(group)
      lastKey = String(key)
      lastValue = String(value)
      return true
    }
  }

  QtObject {
    id: fakeBar

    property var shell: fakeShell
    property bool vertical: false
    property int barSize: 28
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#88bbee"
    property int runCount: 0
    property string lastCommand: ""
    property var visualTokens: ({
      shellStyle: "shibumi",
      v2Shell: false,
      pillPaddingX: 9,
      slotHeight: 28,
      pillHeight: 24,
      pillRadius: 12,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      contentGap: 5,
      compactGap: 4,
      labelSize: 12,
      iconSize: 15,
      widgetHasFill: function(settings) {
        return settings && settings.color === "color05"
          && settings.colorMode === "fill"
      },
      widgetFillColor: function(settings) {
        return settings && settings.color === "color05"
          && settings.colorMode === "fill" ? "#cc8844" : "transparent"
      },
      widgetSurfaceOpacity: function(settings) {
        return settings && settings.surfaceOpacity !== undefined
          ? Number(settings.surfaceOpacity) : 1
      },
      widgetContentColor: function(settings, fallback) {
        return settings && settings.color === "color05"
          && settings.colorMode === "fill"
          && settings.tone === "background" ? "#111111" : fallback
      }
    })

    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(_owner) {}
    function releasePopout(_owner) {}
    function switchPanelFrom(_owner, _direction) { return false }
    function run(command) {
      lastCommand = String(command || "")
      runCount++
    }
  }

  Loader {
    id: memoryLoader
    active: true
    sourceComponent: Component {
      Memory.BarWidget {
        bar: fakeBar
        settings: ({ compact: true })
      }
    }
  }

  Loader {
    id: cpuLoader
    active: true
    sourceComponent: Component {
      Cpu.BarWidget {
        bar: fakeBar
        settings: ({ compact: false })
      }
    }
  }

  Loader {
    id: cpuCompactLoader
    active: true
    sourceComponent: Component {
      Cpu.BarWidget {
        bar: fakeBar
        settings: ({
          displayMode: "icon",
          color: "color05",
          colorMode: "border",
          tone: "background",
          surfaceOpacity: 0.4
        })
      }
    }
  }

  Loader {
    id: gpuLoader
    active: true
    sourceComponent: Component {
      Gpu.BarWidget {
        bar: fakeBar
        settings: ({ displayMode: "icon" })
      }
    }
  }

  Loader {
    id: temperatureLoader
    active: true
    sourceComponent: Component {
      Temperature.BarWidget {
        bar: fakeBar
        hostGroupId: "G:hancore.shibumi.temperature"
        settings: ({ displayMode: "full", source: "cpu" })
      }
    }
  }

  Timer {
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      root.attempts++
      const memory = memoryLoader.item
      const cpu = cpuLoader.item
      const cpuCompact = cpuCompactLoader.item
      const gpu = gpuLoader.item
      const temperature = temperatureLoader.item
      if (!memory || !cpu || !cpuCompact || !gpu || !temperature
          || root.attempts < 4) return
      if (root.attempts > 100) return root.fail("widgets did not become ready")

      if (root.phase === 1) {
        if (!gpu.opened) return
        gpu.close()
        root.phase = 2
        return
      }
      if (root.phase === 2) {
        if (gpu.opened) return
        memoryLoader.active = false
        cpuLoader.active = false
        cpuCompactLoader.active = false
        gpuLoader.active = false
        temperatureLoader.active = false
        releaseCheck.restart()
        stop()
        return
      }

      if (memory.telemetry !== telemetryService.system
          || cpu.telemetry !== telemetryService.system
          || cpuCompact.telemetry !== telemetryService.system
          || cpu.gpuTelemetry !== cpuService.gpu
          || cpuCompact.gpuTelemetry !== cpuService.gpu
          || gpu.gpu !== cpuService.gpu)
        return root.fail("service resolution crossed plugin ownership")
      if (!memory.compact || !memory.horizontalValueVisible
          || cpu.compact || !cpuCompact.compact
          || !cpuCompact.percentageVisible
          || !cpuCompact.v1CustomFillActive
          || Math.abs(cpuCompact.renderedPillFillOpacity - 0.4) > 0.001
          || Math.abs(cpuCompact.renderedPillFillColor.a - 0.4) > 0.001
          || Math.abs(cpuCompact.widgetInk.r - 17 / 255) > 0.001
          || Math.abs(cpuCompact.widgetInk.g - 17 / 255) > 0.001
          || Math.abs(cpuCompact.widgetInk.b - 17 / 255) > 0.001
          || cpuCompact.effectiveAppearanceSettings.colorMode !== "fill"
          || cpuCompact.implicitWidth
            <= fakeBar.visualTokens.pillPaddingX * 2
              + fakeBar.visualTokens.iconSize
              + fakeBar.visualTokens.compactGap
          || cpuCompact.implicitWidth >= cpu.implicitWidth
          || gpu.displayMode !== "icon"
          || !gpu.visible || gpu.implicitWidth <= 0
          || temperature.stateGroupId !== "G:hancore.shibumi.temperature"
          || temperature.iconSlotSize !== 14
          || temperature.iconGlyphHorizontalOffset !== 1
          || temperature.contentHorizontalOffset !== -1)
        return root.fail("widget settings were not retained"
          + " cpuCompact=" + cpuCompact.compact
          + " percentVisible=" + cpuCompact.percentageVisible
          + " fill=" + cpuCompact.v1CustomFillActive
          + " fillOpacity=" + cpuCompact.renderedPillFillOpacity
          + " fillAlpha=" + cpuCompact.renderedPillFillColor.a
          + " ink=" + cpuCompact.widgetInk
          + " mode=" + cpuCompact.effectiveAppearanceSettings.colorMode
          + " compactWidth=" + cpuCompact.implicitWidth
          + " fullWidth=" + cpu.implicitWidth)
      if (telemetryService.system.memoryConsumers !== 1
          || telemetryService.system.cpuConsumers !== 2)
        return root.fail("shared telemetry leases are not balanced per widget")
      if (cpuService.gpu.consumers !== 1)
        return root.fail("GPU widget did not own exactly one telemetry lease")
      if (telemetryService.thermal.consumers !== 1
          || !temperature.setTemperatureSource("memory")
          || fakeState.lastGroup !== "G:hancore.shibumi.temperature"
          || fakeState.lastKey !== "source" || fakeState.lastValue !== "memory")
        return root.fail("dynamic V1 temperature source persistence")
      if (!memory.openSystemMonitor()
          || fakeBar.lastCommand !== "omarchy-launch-or-focus-tui btop"
          || !cpu.openSystemMonitor()
          || fakeBar.lastCommand !== "omarchy-launch-or-focus-tui btop"
          || fakeBar.runCount !== 2)
        return root.fail("system monitor action did not use the Quattro TUI launcher")

      gpu.toggle()
      root.phase = 1
    }
  }

  Timer {
    id: releaseCheck
    interval: 0
    onTriggered: {
      if (telemetryService.system.memoryConsumers !== 0
          || telemetryService.system.cpuConsumers !== 0
          || cpuService.gpu.consumers !== 0
          || telemetryService.thermal.consumers !== 0)
        return root.fail("widget destruction leaked telemetry leases")
      console.log("telemetry plugins smoke passed")
      Qt.quit()
    }
  }
}
