import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "omarchy.network"
  property var settings: ({})
  property bool manageIpc: false
  property bool opened: false
  property bool legacyHostStyle:
    Quickshell.env("SHIBUMI_TEST_NETWORK_IPC_STYLE") === "legacy"
  property int backendOpenCount: 0
  property int officialSpeedRunCount: 0
  property bool qrVisible: false
  property bool speedWindowProbe: false
  property bool networkManagerAvailable: true
  property string kind: "wifi"
  property string label: "Fixture"
  property int signalStrength: 75
  property bool scanning: false
  property bool busy: false
  property var wifiDevice: null
  property var wifiNetworks: []
  property var connectedWifiNetwork: null
  property var info: ({})

  readonly property QtObject controller: QtObject {
    function show() {
      root.backendOpenCount++
      root.opened = true
    }
    function hide() { root.opened = false }
  }

  readonly property bool overlayVisible: qrVisible
  readonly property bool backendKeyboardPanelOpen:
    backendKeyboardPanel.open
  readonly property bool backendKeyboardPanelVisible:
    backendKeyboardPanel.visible
  readonly property bool qrWindowVisible: qrWindow.visible
  readonly property bool speedWindowVisible: speedWindow.visible

  QtObject {
    id: backendKeyboardPanel
    property Item anchorItem: root
    property var owner: root
    property bool open: root.opened
    property bool visible: root.opened
    function beginFocusPrime() {}
  }

  QtObject {
    id: qrWindow
    property Item anchorItem: root
    property bool open: root.qrVisible
    property bool visible: root.qrVisible
  }

  QtObject {
    id: speedWindow
    property Item anchorItem: root
    property bool open: false
    property bool visible: root.speedWindowProbe
  }

  function open() {
    if (overlayVisible) {
      hideWifiQr()
      return
    }
    controller.show()
  }
  function close() {
    controller.hide()
    hideWifiQr()
  }
  function refresh(_scan) {}
  function showWifiQr(_force) {
    opened = false
    qrVisible = true
  }
  function hideWifiQr() { qrVisible = false }
  function summonWifiQr(_forceDetect) {
    controller.hide()
    if (bar && bar.shell && typeof bar.shell.summon === "function")
      bar.shell.summon("omarchy.wifiqr", "{}")
  }
  function summonSpeedTest() {
    controller.hide()
    if (bar && bar.shell && typeof bar.shell.summon === "function")
      bar.shell.summon("omarchy.speedtest", "{}")
  }
  function showLegacySpeedTest() {
    officialSpeedRunCount++
  }

  // Ui.Panel retains this disabled generic handler when a specialized panel
  // sets manageIpc=false and publishes its own compatibility target below.
  IpcHandler {
    target: "omarchy.network"
    enabled: root.manageIpc
  }

  IpcHandler {
    target: "omarchy.network"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.opened ? root.close() : root.open() }
    function showQr(): void {
      if (root.legacyHostStyle) root.showWifiQr(true)
      else root.summonWifiQr(true)
    }
    function speedTest(): void {
      if (root.legacyHostStyle) root.showLegacySpeedTest()
      else root.summonSpeedTest()
    }
  }
}
