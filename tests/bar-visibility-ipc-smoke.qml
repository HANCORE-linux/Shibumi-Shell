import QtQuick
import Quickshell
import Quickshell.Io
import "hancore.shibumi.bar" as BarPlugin

ShellRoot {
  id: root

  property bool hiddenObserved: false
  property int waits: 0

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
      version: "0.1.1-beta.14",
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
      if (!bar.barToggleStateLoaded) return "unloaded"
      return (bar.barHiddenProbeBusy ? "busy-" : "idle-")
        + (bar.barToggledOff ? "hidden" : "visible")
    }

    function finish(): string {
      if (bar.barHiddenProbeBusy || bar.barToggledOff) return "not-ready"
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
