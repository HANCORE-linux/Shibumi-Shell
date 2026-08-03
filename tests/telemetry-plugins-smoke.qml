pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "telemetry" as Telemetry
import "memory" as Memory
import "cpu" as Cpu
import "gpu" as Gpu

ShellRoot {
  id: root

  property int attempts: 0

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
      return null
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
      iconSize: 15
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
    id: gpuLoader
    active: true
    sourceComponent: Component {
      Gpu.BarWidget {
        bar: fakeBar
        settings: ({ displayMode: "icon" })
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
      const gpu = gpuLoader.item
      if (!memory || !cpu || !gpu || root.attempts < 4) return
      if (root.attempts > 100) return root.fail("widgets did not become ready")

      if (memory.telemetry !== telemetryService.system
          || cpu.telemetry !== telemetryService.system
          || cpu.gpuTelemetry !== cpuService.gpu
          || gpu.gpu !== cpuService.gpu)
        return root.fail("service resolution crossed plugin ownership")
      if (!memory.compact || cpu.compact || gpu.displayMode !== "icon"
          || !gpu.visible || gpu.implicitWidth <= 0)
        return root.fail("widget settings were not retained")
      if (telemetryService.system.memoryConsumers !== 1
          || telemetryService.system.cpuConsumers !== 1)
        return root.fail("shared telemetry leases are not balanced per widget")
      if (cpuService.gpu.consumers !== 1)
        return root.fail("GPU widget did not own exactly one telemetry lease")
      if (!memory.openSystemMonitor()
          || fakeBar.lastCommand !== "omarchy-launch-or-focus-tui btop"
          || !cpu.openSystemMonitor()
          || fakeBar.lastCommand !== "omarchy-launch-or-focus-tui btop"
          || fakeBar.runCount !== 2)
        return root.fail("system monitor action did not use the Quattro TUI launcher")

      memoryLoader.active = false
      cpuLoader.active = false
      gpuLoader.active = false
      releaseCheck.restart()
      stop()
    }
  }

  Timer {
    id: releaseCheck
    interval: 0
    onTriggered: {
      if (telemetryService.system.memoryConsumers !== 0
          || telemetryService.system.cpuConsumers !== 0
          || cpuService.gpu.consumers !== 0)
        return root.fail("widget destruction leaked telemetry leases")
      console.log("telemetry plugins smoke passed")
      Qt.quit()
    }
  }
}
