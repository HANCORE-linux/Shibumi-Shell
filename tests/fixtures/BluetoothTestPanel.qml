pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui as Ui

Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property bool manageIpc: true
  property bool opened: false
  property bool adapterPresent: true
  property var adapter: adapterPresent ? fakeAdapter : null
  property var pendingActions: ({})
  property int toggleCount: 0
  property int connectCount: 0
  property int disconnectCount: 0
  property int forgetCount: 0
  property int viewLoadCount: 0
  property var connectedDevices: [
    {
      address: "00:11:22:33:44:55",
      name: "Headphones",
      connected: true,
      paired: true,
      batteryAvailable: true,
      battery: 0.72,
      state: 0
    }
  ]
  property var knownDevices: [
    {
      address: "66:77:88:99:AA:BB",
      name: "Keyboard",
      connected: false,
      paired: true,
      state: 0
    }
  ]
  property var discoveredDevices: [
    {
      address: "CC:DD:EE:FF:00:11",
      name: "Phone",
      connected: false,
      paired: false,
      state: 0
    }
  ]
  readonly property var internalButton: button

  implicitWidth: 27
  implicitHeight: 35

  QtObject {
    id: fakeAdapter
    property bool enabled: true
    property bool discovering: false
  }

  function open() {
    opened = true
    if (fakeAdapter.enabled) fakeAdapter.discovering = true
    if (bar) bar.requestPopout(root)
  }
  function close() {
    opened = false
    if (bar) bar.releasePopout(root)
  }
  function toggleBluetooth() {
    toggleCount++
    fakeAdapter.enabled = !fakeAdapter.enabled
    if (!fakeAdapter.enabled) fakeAdapter.discovering = false
    else Qt.callLater(function() {
      if (fakeAdapter.enabled) fakeAdapter.discovering = true
    })
  }
  function deviceLabel(device) {
    return device ? String(device.name || "") : ""
  }
  function pendingAction(address) {
    return pendingActions[String(address || "")] || ""
  }
  function setPending(address, action) {
    const next = ({})
    for (const key in pendingActions) next[key] = pendingActions[key]
    next[address] = action
    pendingActions = next
  }
  function connectDevice(device) {
    connectCount++
    setPending(device.address, "connecting")
  }
  function disconnectDevice(device) {
    disconnectCount++
    setPending(device.address, "disconnecting")
  }
  function forgetDevice(device) {
    forgetCount++
    setPending(device.address, "forgetting")
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "bluetooth"
    onPressed: function(_button) { root.opened ? root.close() : root.open() }
  }
}
