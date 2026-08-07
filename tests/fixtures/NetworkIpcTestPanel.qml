import QtQuick
import Quickshell.Io

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "omarchy.network"
  property var settings: ({})
  property bool manageIpc: false
  property bool opened: false
  property bool qrVisible: false
  property bool speedTestModalOpen: false
  property bool speedTestRunning: false
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
    function show() { root.opened = true }
    function hide() { root.opened = false }
  }

  readonly property bool overlayVisible: qrVisible || speedTestModalOpen
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
    property bool open: root.speedTestModalOpen
    property bool visible: root.speedTestModalOpen || root.speedWindowProbe
  }

  function open() {
    if (overlayVisible) {
      hideWifiQr()
      hideSpeedTest()
      return
    }
    controller.show()
  }
  function close() {
    controller.hide()
    hideWifiQr()
    hideSpeedTest()
  }
  function refresh(_scan) {}
  function showWifiQr(_force) {
    opened = false
    qrVisible = true
  }
  function hideWifiQr() { qrVisible = false }
  function showSpeedTest() {
    opened = false
    speedTestModalOpen = true
    speedTestRunning = true
  }
  function hideSpeedTest() {
    speedTestModalOpen = false
    speedTestRunning = false
  }

  IpcHandler {
    target: "omarchy.network"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.opened ? root.close() : root.open() }
    function showQr(): void { root.showWifiQr(true) }
    function speedTest(): void { root.showSpeedTest() }
  }
}
