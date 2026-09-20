import QtQuick
import Quickshell
import Quickshell.Io
import "hancore.shibumi.bar" as BarPlugin
import "hancore.shibumi.state/runtime" as SuiteRuntime

ShellRoot {
  id: root

  property bool hiddenObserved: false
  property int waits: 0
  property bool hostVisibilityHandlerActive: true
  property bool stockTakeoverStarted: false

  // Keep the isolated handoff gap observable even on a slow test host. This
  // fixture-only binding is installed before the Bar can become admitted.
  Binding {
    target: SuiteRuntime.Runtime
    property: "visibilityIpcHandoffDelayMs"
    value: 2000
  }

  // Omarchy can retain its outgoing/default handler while the plugin Bar is
  // admitted. The suite endpoint must wait for that real host handoff instead
  // of attempting a duplicate registration.
  IpcHandler {
    enabled: root.hostVisibilityHandlerActive
    target: "omarchy.bar"
    function syncHidden(): void {}
  }

  Timer {
    interval: 250
    running: true
    onTriggered: root.hostVisibilityHandlerActive = false
  }

  QtObject {
    id: fakeShell
    property var bar: bar
    property var shellConfig: ({ bar: ({}) })
    function serviceFor(_id) { return null }
    function firstPartyServiceFor(_id) { return null }
  }

  QtObject {
    id: fakePluginRegistry
    signal pluginsChanged()
    property var installedPlugins: ({})
  }

  QtObject {
    id: fakeBarWidgetRegistry
    property var widgets: ({})
  }

  BarPlugin.Bar {
    id: bar
    omarchyPath: "/fixture/omarchy"
    shell: fakeShell
    manifest: ({
      id: "hancore.shibumi.bar",
      version: "0.1.1-beta.15",
      kinds: ["bar"]
    })
    pluginRegistry: fakePluginRegistry
    barWidgetRegistry: fakeBarWidgetRegistry
    barConfig: ({
      id: "hancore.shibumi.bar",
      position: "top",
      style: "shibumi",
      centerAnchor: "omarchy.clock",
      layout: ({ left: [], center: [], right: [] })
    })
    // The initial process and directory watch may establish the visible
    // baseline. Each marker transition below is observed through syncHidden.
    outputWindowsEnabled: false
    nativeRegistryPrimeEnabled: false
  }

  IpcHandler {
    target: "bar-visibility-test"

    function state(): string {
      if (root.stockTakeoverStarted) {
        if (SuiteRuntime.Runtime.visibilityIpcArmed)
          return "takeover-runtime-armed"
        return root.hostVisibilityHandlerActive
          ? "stock-owner" : "takeover-gap"
      }
      if (root.hostVisibilityHandlerActive) return "host-handoff"
      if (!SuiteRuntime.Runtime.visibilityIpcArmed) return "handoff-gap"
      if (!bar.barToggleStateLoaded) return "unloaded"
      return (bar.barHiddenProbeBusy ? "busy-" : "idle-")
        + (bar.barToggledOff ? "hidden" : "visible")
    }

    function beginStockTakeover(): string {
      if (bar.barHiddenProbeBusy || bar.barToggledOff) return "not-ready"
      const next = JSON.parse(JSON.stringify(bar.barConfig))
      next.id = "omarchy.bar"
      bar.barConfig = next
      root.stockTakeoverStarted = true
      Qt.callLater(function() { root.hostVisibilityHandlerActive = true })
      return "ok"
    }

    function finish(): string {
      if (bar.barHiddenProbeBusy || bar.barToggledOff
          || !root.stockTakeoverStarted
          || !root.hostVisibilityHandlerActive
          || SuiteRuntime.Runtime.visibilityIpcArmed) return "not-ready"
      console.log("bar visibility IPC smoke passed")
      Qt.callLater(function() { Qt.exit(0) })
      return "ok"
    }
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (!root.hiddenObserved && bar.barToggledOff) {
        root.hiddenObserved = true
        console.log("bar visibility IPC observed hidden marker")
      }
      if (++root.waits > 500) {
        console.error("bar visibility IPC smoke timed out",
          "hiddenObserved=" + root.hiddenObserved,
          "hidden=" + bar.barToggledOff)
        Qt.exit(1)
      }
    }
  }
}
