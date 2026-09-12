import QtQuick
import Quickshell
import Quickshell.Io
import "network" as Network

ShellRoot {
  id: root

  QtObject {
    id: networkWidgetA
    property bool opened: false
    property string mode: "none"
    function openNetworkPresentation(requested) {
      opened = true
      mode = String(requested || "panel")
      return true
    }
    function open() { opened = true; mode = "panel" }
    function close() { opened = false; mode = "none" }
  }

  QtObject {
    id: networkWidgetB
    property bool opened: false
    property string mode: "none"
    function openNetworkPresentation(requested) {
      opened = true
      mode = String(requested || "panel")
      return true
    }
    function open() { opened = true; mode = "panel" }
    function close() { opened = false; mode = "none" }
  }

  QtObject {
    id: nativeService
    property int toggleCount: 0
    function toggleWifi() {
      toggleCount++
      return { accepted: true }
    }
  }

  QtObject {
    id: fakeBar
    property string focusedOutput: "A"
    function findPanelWidget(id) {
      if (id !== "hancore.shibumi.network" && id !== "omarchy.network")
        return null
      return focusedOutput === "B" ? networkWidgetB : networkWidgetA
    }
  }

  Network.NetworkPanelBridge {
    id: bridge
    bar: fakeBar
    networkService: nativeService
  }

  IpcHandler {
    target: "network-ipc-routing-test"
    function state(): string {
      return [
        networkWidgetA.opened ? "a-open" : "a-closed",
        networkWidgetA.mode,
        networkWidgetB.opened ? "b-open" : "b-closed",
        networkWidgetB.mode,
        nativeService.toggleCount
      ].join(":")
    }
    function focusA(): void { fakeBar.focusedOutput = "A" }
    function focusB(): void { fakeBar.focusedOutput = "B" }
    function closeA(): void { networkWidgetA.close() }
    function closeB(): void { networkWidgetB.close() }
  }
}
