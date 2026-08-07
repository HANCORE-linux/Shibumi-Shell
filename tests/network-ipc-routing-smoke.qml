import QtQuick
import Quickshell
import Quickshell.Io
import "network" as Network
import "fixtures" as Fixtures

ShellRoot {
  id: root

  QtObject {
    id: speedPanel
    property bool speedDetailsVisible: false
  }

  QtObject {
    id: networkWidgetA
    property bool opened: false
    readonly property bool panelLoaded: true
    readonly property var panelItem: speedPanel
    function open() { opened = true }
    function close() { opened = false }
  }

  QtObject {
    id: networkWidgetB
    property bool opened: false
    readonly property bool panelLoaded: true
    readonly property var panelItem: speedPanel
    function open() { opened = true }
    function close() { opened = false }
  }

  QtObject {
    id: fakeBar
    property string focusedOutput: "A"
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    property var shell: null

    function findPanelWidget(id, screenName) {
      if (id !== "omarchy.network") return null
      const requested = String(screenName || "") || focusedOutput
      return requested === "B" ? networkWidgetB : networkWidgetA
    }
    function summonBarWidget(id, screenName) {
      const owner = findPanelWidget(id, screenName)
      if (!owner) return false
      owner.open()
      return true
    }
    function hideBarWidget(id) {
      if (id !== "omarchy.network") return false
      networkWidgetA.close()
      networkWidgetB.close()
      return true
    }
  }

  Item { id: ownerWidget }

  Component {
    id: authoritativePanel
    Fixtures.NetworkIpcTestPanel {}
  }

  Network.NetworkPanelBridge {
    id: bridge
    bar: fakeBar
    ownerWidget: ownerWidget
    panelComponent: authoritativePanel
  }

  IpcHandler {
    target: "network-ipc-routing-test"

    function state(): string {
      if (!bridge.panel) return "loading"
      return [
        bridge.panel.opened ? "backend-open" : "backend-closed",
        networkWidgetA.opened ? "a-open" : "a-closed",
        networkWidgetB.opened ? "b-open" : "b-closed",
        bridge.panel.qrVisible ? "qr-open" : "qr-closed",
        bridge.panel.speedTestModalOpen ? "speed-modal-open" : "speed-modal-closed",
        bridge.panel.speedTestRunning ? "speed-running" : "speed-idle",
        speedPanel.speedDetailsVisible ? "details-open" : "details-closed"
      ].join(":")
    }
    function backendWindowState(): string {
      if (!bridge.panel) return "loading"
      return [
        bridge.panel.backendKeyboardPanelOpen ? "open" : "closed",
        bridge.panel.backendKeyboardPanelVisible ? "visible" : "hidden"
      ].join(":")
    }
    function overlayWindowState(): string {
      if (!bridge.panel) return "loading"
      return [
        bridge.panel.qrWindowVisible ? "qr-visible" : "qr-hidden",
        bridge.panel.speedWindowVisible ? "speed-visible" : "speed-hidden"
      ].join(":")
    }
    function probeSpeedWindow(): void {
      if (bridge.panel) bridge.panel.speedWindowProbe = true
    }
    function clearSpeedWindowProbe(): void {
      if (bridge.panel) bridge.panel.speedWindowProbe = false
    }
    function focusA(): void { fakeBar.focusedOutput = "A" }
    function focusB(): void { fakeBar.focusedOutput = "B" }
    function openA(): void { networkWidgetA.open() }
    function openB(): void { networkWidgetB.open() }
    function closeA(): void { networkWidgetA.close() }
    function closeB(): void { networkWidgetB.close() }
    function closeQr(): void {
      if (bridge.panel) bridge.panel.hideWifiQr()
    }
  }
}
