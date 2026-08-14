pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "cpu" as Cpu
import "gpu" as Gpu
import "state" as State

ShellRoot {
  id: root

  property int stage: 0
  property int attempts: 0
  property bool fixtureParsed: false

  State.Service {
    id: stateService
    shell: fakeShell
  }

  Cpu.Service {
    id: cpuService
    Component.onCompleted: gpu.helperPath = "/usr/bin/false"
  }

  QtObject {
    id: fakeShell

    property var shellConfig: ({
      version: 1,
      bar: { shibumi: { version: 1 } }
    })
    property int writes: 0

    function serviceFor(pluginId) {
      if (pluginId === "hancore.shibumi.cpu") return cpuService
      if (pluginId === "hancore.shibumi.state") return stateService
      return null
    }

    function mutateShellConfig(mutator) {
      const next = JSON.parse(JSON.stringify(shellConfig))
      mutator(next)
      shellConfig = next
      writes++
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
    property color urgent: "#88bbee"
    property var activePopout: null
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
      widgetHasFill: function(_settings) { return false },
      widgetFillColor: function(_settings) { return "transparent" },
      widgetSurfaceOpacity: function(_settings) { return 1 },
      widgetContentColor: function(_settings, fallback) { return fallback }
    })

    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function switchPanelFrom(_owner, _direction) { return false }
  }

  Gpu.BarWidget {
    id: gpuWidget
    bar: fakeBar
    hostGroupId: "G17"
    settings: stateService.groupSettings("G17")
  }

  function fail(message) {
    console.error("gpu-selection-state-smoke:", message)
    Qt.exit(1)
  }

  Timer {
    interval: 20
    running: true
    repeat: true
    onTriggered: {
      root.attempts++
      if (root.attempts > 100)
        return root.fail("state-backed selection timed out at stage " + root.stage)
      if (!stateService.ready || !gpuWidget.gpu) return

      if (!root.fixtureParsed) {
        cpuService.gpu.parse([
          "device|pci:0000:03:00.0|sysfs|17|49|0|0|"
            + "AMD Ryzen 9 7950X Integrated Graphics|amdgpu|6.14.2|card0",
          "device|pci:0000:04:00.0|sysfs|73|61|4096|16384|"
            + "AMD Radeon RX 7900 XTX|amdgpu|6.14.2|card1",
          "status|ok"
        ].join("\n"))
        root.fixtureParsed = true
        return
      }

      if (root.stage === 0) {
        if (gpuWidget.configuredDeviceId !== "auto"
            || gpuWidget.selectedDeviceId !== "pci:0000:03:00.0"
            || !gpuWidget.setGpuDevice("pci:0000:04:00.0"))
          return root.fail("initial automatic selection or state mutation"
            + " configured=" + gpuWidget.configuredDeviceId
            + " selected=" + gpuWidget.selectedDeviceId
            + " devices=" + gpuWidget.availableGpus.length
            + " state=" + stateService.groupSetting("G17", "device", "unset"))
        root.stage = 1
        return
      }

      if (root.stage === 1) {
        if (gpuWidget.configuredDeviceId !== "pci:0000:04:00.0"
            || gpuWidget.selectedDeviceId !== "pci:0000:04:00.0"
            || gpuWidget.selectedGpu.utilization !== 73
            || stateService.groupSetting("G17", "device", "")
              !== "pci:0000:04:00.0"
            || fakeShell.shellConfig.bar.shibumi.widgets.G17.device
              !== "pci:0000:04:00.0"
            || fakeShell.writes !== 1)
          return root.fail("state service did not update the live GPU widget")
        const persisted = JSON.parse(JSON.stringify(
          fakeShell.shellConfig.bar.shibumi))
        fakeShell.shellConfig = ({ version: 1, bar: { shibumi: persisted } })
        root.stage = 2
        return
      }

      if (root.stage === 2) {
        if (stateService.groupSetting("G17", "device", "")
              !== "pci:0000:04:00.0"
            || gpuWidget.configuredDeviceId !== "pci:0000:04:00.0"
            || gpuWidget.selectedDeviceId !== "pci:0000:04:00.0")
          return root.fail("normalized reload lost the persisted GPU")
        if (!gpuWidget.setGpuDevice("auto"))
          return root.fail("automatic source reset")
        root.stage = 3
        return
      }

      if (gpuWidget.configuredDeviceId !== "auto"
          || gpuWidget.selectedDeviceId !== "pci:0000:03:00.0"
          || stateService.groupSetting("G17", "device", "") !== "auto"
          || fakeShell.writes !== 2)
        return root.fail("automatic source did not persist after reload")
      console.log("GPU selection state smoke passed")
      Qt.quit()
    }
  }
}
