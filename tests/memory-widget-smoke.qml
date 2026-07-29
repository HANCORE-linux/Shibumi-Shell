import QtQuick
import Quickshell
import "../services" as Services
import "../widgets" as Widgets

ShellRoot {
  id: root

  property bool failed: false

  function fail(message) {
    failed = true
    console.error("memory-widget-smoke:", message)
    Qt.quit()
  }

  Services.SystemTelemetry {
    id: telemetry
  }

  QtObject {
    id: actions
    function openSystemMonitor() { return true }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 26
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#e8e8e8"
    property color barForeground: foreground
    property color background: "#181818"
    property color urgent: "#88bbee"
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
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var systemTelemetry: telemetry
    property var gpuTelemetry: null
    property var systemActions: actions

    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(owner, direction) { return false }
  }

  Loader {
    id: memoryLoader
    active: true
    sourceComponent: Component {
      Widgets.MemoryWidget {
        bar: fakeBar
        settings: ({ compact: false })
      }
    }
  }

  Loader {
    id: cpuLoader
    active: true
    sourceComponent: Component {
      Widgets.CpuWidget {
        bar: fakeBar
        settings: ({ compact: false })
      }
    }
  }

  Timer {
    interval: 800
    running: true
    onTriggered: {
      if (!memoryLoader.item) {
        root.fail("widget did not instantiate")
        return
      }
      if (telemetry.memoryConsumers !== 1) {
        root.fail("widget did not acquire exactly one telemetry consumer")
        return
      }
      if (telemetry.cpuConsumers !== 1 || telemetry.previousCpuTotal <= 0) {
        root.fail("CPU widget did not acquire or prime shared telemetry")
        return
      }
      if (telemetry.memTotalMiB <= 0 || telemetry.memAvailableMiB <= 0) {
        root.fail("procfs memory data did not load")
        return
      }
      memoryLoader.active = false
      cpuLoader.active = false
      releaseCheck.restart()
    }
  }

  Timer {
    id: releaseCheck
    interval: 0
    onTriggered: {
      if (telemetry.memoryConsumers !== 0) {
        root.fail("widget did not release telemetry on destruction")
        return
      }
      if (telemetry.cpuConsumers !== 0) {
        root.fail("CPU widget did not release telemetry on destruction")
        return
      }
      console.log("telemetry widget smoke passed")
      Qt.quit()
    }
  }
}
