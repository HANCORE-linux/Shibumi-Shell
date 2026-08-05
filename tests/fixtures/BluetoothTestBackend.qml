pragma ComponentBehavior: Bound

import QtQuick

QtObject {
  id: root

  property bool adapterPresent: true
  property var selectedAdapter: fakeAdapter
  property var adapter: adapterPresent ? selectedAdapter : null
  property var pendingActions: ({})
  property int toggleCount: 0
  property int connectCount: 0
  property int disconnectCount: 0
  property int forgetCount: 0
  property int viewLoadCount: 0
  property int discoveryStartAttempts: 0
  property int rejectedDiscoveryStarts: 0
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

  property QtObject fakeAdapter: QtObject {
    property bool enabled: true
    property bool discovering: false
    function requestDiscovery() {
      root.discoveryStartAttempts++
      if (root.rejectedDiscoveryStarts > 0) {
        root.rejectedDiscoveryStarts--
        return
      }
      Qt.callLater(function() { root.fakeAdapter.discovering = true })
    }
  }
  property QtObject alternateAdapter: QtObject {
    property bool enabled: true
    property bool discovering: false
    function requestDiscovery() {
      root.discoveryStartAttempts++
      Qt.callLater(function() { root.alternateAdapter.discovering = true })
    }
  }

  function requestDiscovery(target) {
    target.requestDiscovery()
  }

  function toggleBluetooth() {
    toggleCount++
    fakeAdapter.enabled = !fakeAdapter.enabled
    if (!fakeAdapter.enabled) fakeAdapter.discovering = false
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
}
