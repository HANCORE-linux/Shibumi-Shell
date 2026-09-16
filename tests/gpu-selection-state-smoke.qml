pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "cpu" as Cpu
import "gpu" as Gpu
import "hancore.shibumi.state" as State

ShellRoot {
  id: root

  property int stage: 0
  property int attempts: 0
  property bool fixtureParsed: false
  property var document: null
  FileView {
    id: writer
    path: Quickshell.env("XDG_CONFIG_HOME") + "/omarchy/shell.json"
    atomicWrites: true
    onLoaded: root.document = JSON.parse(text())
  }

  State.Service {
    id: stateService
    shell: fakeShell
    omarchyPath: Quickshell.env("OMARCHY_PATH")
    manifest: ({id: "hancore.shibumi.state", version: "0.1.1-beta.14.1", kinds: ["service"]})
  }

  Cpu.Service {
    id: cpuService
    shell: fakeShell
    manifest: ({id: "hancore.shibumi.cpu", version: "0.1.1-beta.14.1", kinds: ["service"]})
    gpuProbeEnabled: false
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

    function mutateShellConfig(mutator) { root.fail("legacy Bar writer was used") }
    function updateEntryInline(id, entry) {
      if (id !== "hancore.shibumi.state" || !entry || entry.id !== id || !root.document)
        return root.fail("foreign or unavailable State entry write")
      const next = JSON.parse(JSON.stringify(root.document))
      if (next.plugins[0].id !== id) return root.fail("ambiguous State entry")
      next.plugins[0] = entry
      root.document = next
      writer.setText(JSON.stringify(next))
      writes++
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
    throw new Error(message)
  }

  Timer {
    interval: 20
    running: true
    repeat: true
    onTriggered: {
      root.attempts++
      if (root.attempts > 100)
        return root.fail("state-backed selection timed out at stage " + root.stage)
      if (root.stage === 2) {
        if (stateService.ready) return root.fail("revoked State stayed ready")
        stateService.shell = fakeShell
        root.stage = 3
        return
      }
      if (!stateService.ready || stateService.writePending || !root.document || !gpuWidget.gpu) return

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
            || root.document.plugins[0].shibumi.widgets.G17.device
              !== "pci:0000:04:00.0"
            || fakeShell.writes !== 1)
          return root.fail("state service did not update the live GPU widget")
        stateService.shell = null
        root.stage = 2
        return
      }

      if (root.stage === 3) {
        if (stateService.groupSetting("G17", "device", "")
              !== "pci:0000:04:00.0"
            || gpuWidget.configuredDeviceId !== "pci:0000:04:00.0"
            || gpuWidget.selectedDeviceId !== "pci:0000:04:00.0")
          return root.fail("normalized reload lost the persisted GPU")
        if (!gpuWidget.setGpuDevice("auto"))
          return root.fail("automatic source reset")
        root.stage = 4
        return
      }

      if (gpuWidget.configuredDeviceId !== "auto"
          || gpuWidget.selectedDeviceId !== "pci:0000:03:00.0"
          || stateService.groupSetting("G17", "device", "") !== "auto"
          || root.document.plugins[0].shibumi.widgets.G17.device !== "auto"
          || root.document.plugins[0].foreign.keep !== 42
          || fakeShell.shellConfig.bar.shibumi.widgets !== undefined
          || fakeShell.writes !== 2)
        return root.fail("automatic source did not persist after reload")
      console.log("GPU selection state smoke passed")
      Qt.quit()
    }
  }
}
