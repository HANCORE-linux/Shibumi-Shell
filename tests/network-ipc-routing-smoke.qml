import QtQuick
import Quickshell
import Quickshell.Io
import "network" as Network
import "fixtures" as Fixtures

ShellRoot {
  id: root

  function externalQrOpen() {
    const host = fakeBar.shell
    if (!host) return false
    if (typeof host.isPluginOpen === "function")
      return host.isPluginOpen("omarchy.wifiqr") === true
    return host.openPanelIds
      && host.openPanelIds["omarchy.wifiqr"] === true
  }

  QtObject {
    id: speedPanel
    property bool speedDetailsVisible: false
  }

  QtObject {
    id: inlineSpeedService
    property var owners: []
    property bool speedTestRunning: false
    property int runCount: 0

    function beginSession(owner) {
      if (owners.indexOf(owner) >= 0) return
      owners = owners.concat([owner])
    }
    function endSession(owner) {
      owners = owners.filter(candidate => candidate !== owner)
      if (owners.length === 0) speedTestRunning = false
    }
    function runSpeedTest() {
      runCount++
      speedTestRunning = true
      return true
    }
  }

  QtObject {
    id: networkWidgetA
    property bool opened: false
    readonly property bool panelLoaded: true
    readonly property var panelItem: speedPanel
    function open() {
      if (!opened) inlineSpeedService.beginSession(networkWidgetA)
      opened = true
    }
    function close() {
      if (opened) inlineSpeedService.endSession(networkWidgetA)
      opened = false
    }
  }

  QtObject {
    id: networkWidgetB
    property bool opened: false
    readonly property bool panelLoaded: true
    readonly property var panelItem: speedPanel
    function open() {
      if (!opened) inlineSpeedService.beginSession(networkWidgetB)
      opened = true
    }
    function close() {
      if (opened) inlineSpeedService.endSession(networkWidgetB)
      opened = false
    }
  }

  QtObject {
    id: fakeShell
    property var openPanelIds: ({})
    readonly property string qrProviderId:
      Quickshell.env("SHIBUMI_TEST_NETWORK_IPC_STYLE") === "current-clone"
      ? "example.wifiqr-clone" : "omarchy.wifiqr"

    function resolvedId(id) {
      return String(id || "") === "omarchy.wifiqr"
        ? qrProviderId : String(id || "")
    }
    function summon(id, _payloadJson) {
      const next = ({})
      for (const key in openPanelIds) next[key] = openPanelIds[key]
      next[resolvedId(id)] = true
      openPanelIds = next
      return true
    }
    function hide(id) {
      const target = resolvedId(id)
      const next = ({})
      for (const key in openPanelIds)
        if (key !== target) next[key] = openPanelIds[key]
      openPanelIds = next
      return true
    }
    function isPluginOpen(id) {
      return openPanelIds[resolvedId(id)] === true
    }
  }

  QtObject {
    id: fallbackShell
    property var openPanelIds: ({})

    function summon(id, _payloadJson) {
      const next = ({})
      for (const key in openPanelIds) next[key] = openPanelIds[key]
      next[String(id || "")] = true
      openPanelIds = next
      return true
    }
    function hide(id) {
      const target = String(id || "")
      const next = ({})
      for (const key in openPanelIds)
        if (key !== target) next[key] = openPanelIds[key]
      openPanelIds = next
      return true
    }
  }

  QtObject {
    id: fakeBar
    property string focusedOutput: "A"
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    property var shell:
      Quickshell.env("SHIBUMI_TEST_NETWORK_IPC_STYLE") === "current-fallback"
      ? fallbackShell : fakeShell

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

  Component {
    id: replacementPanel
    Fixtures.NetworkIpcTestPanel {}
  }

  Network.NetworkPanelBridge {
    id: bridge
    bar: fakeBar
    ownerWidget: ownerWidget
    panelComponent: authoritativePanel
    networkService: inlineSpeedService
  }

  IpcHandler {
    target: "network-ipc-routing-test"

    function state(): string {
      if (!bridge.panel) return "loading"
      return [
        bridge.panel.opened ? "backend-open" : "backend-closed",
        networkWidgetA.opened ? "a-open" : "a-closed",
        networkWidgetB.opened ? "b-open" : "b-closed",
        (bridge.panel.qrVisible || root.externalQrOpen())
          ? "qr-open" : "qr-closed",
        inlineSpeedService.speedTestRunning ? "speed-running" : "speed-idle",
        inlineSpeedService.runCount,
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
        (bridge.panel.qrWindowVisible || root.externalQrOpen())
          ? "qr-visible" : "qr-hidden",
        bridge.panel.speedWindowVisible ? "speed-visible" : "speed-hidden"
      ].join(":")
    }
    function probeSpeedWindow(): void {
      if (bridge.panel) bridge.panel.speedWindowProbe = true
    }
    function clearSpeedWindowProbe(): void {
      if (bridge.panel) bridge.panel.speedWindowProbe = false
    }
    function backendOpenCount(): string {
      return bridge.panel ? String(bridge.panel.backendOpenCount) : "loading"
    }
    function officialSpeedRuns(): string {
      return bridge.panel ? String(bridge.panel.officialSpeedRunCount) : "loading"
    }
    function reloadBackend(): void {
      bridge.panelComponent = replacementPanel
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
