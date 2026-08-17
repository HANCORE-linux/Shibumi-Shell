pragma ComponentBehavior: Bound

import QtQuick

// Models Omarchy's scanner ownership contract since 5f74a996: only an opened
// stock panel may drive WifiDevice.scannerEnabled. Shibumi deliberately keeps
// this backend closed, so its process-wide service must own the scan lease.
Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property bool manageIpc: false
  property bool opened: false
  property bool scannerRequiresOpened: true
  property var scannerObserver: null
  property bool networkManagerAvailable: true
  property string kind: "wifi"
  property var connectedWifiNetwork: null
  property int signalStrength: 60
  property bool scanning: false
  property bool busy: false
  property var scannerDevice: null
  property var wifiDevice: primaryDevice
  property bool wifiStationAvailable: wifiDevice !== null
  property var info: ({ iface: "fixture-wifi" })
  property var wifiNetworks: []
  property string dnsProvider: "DHCP"
  property var dnsProviders: ["DHCP"]
  property string actionSsid: ""
  property string actionKind: ""
  property string failureSsid: ""
  property string failureReason: ""
  property int refreshCount: 0
  property bool lastScanRequest: false
  property int primaryActivationCount: 0
  property int secondaryActivationCount: 0

  readonly property bool primaryScannerEnabled: primaryDevice.scannerEnabled
  readonly property bool secondaryScannerEnabled: secondaryDevice.scannerEnabled

  function setScannerEnabled(enabled) {
    const nextDevice = opened || !scannerRequiresOpened ? wifiDevice : null
    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false
    scannerDevice = nextDevice
    if (scannerDevice) scannerDevice.scannerEnabled = enabled === true
  }

  function publishNetworks(deviceName) {
    if (!wifiDevice || wifiDevice.scannerEnabled !== true) return
    wifiNetworks = [{
      network: ({ fixture: true }),
      connected: false,
      known: false,
      ssid: "Synthetic " + deviceName,
      signal: 60,
      security: 0
    }]
    scanning = false
  }

  function syncWifiNetworks() {
    if (!wifiDevice || wifiDevice.scannerEnabled !== true)
      wifiNetworks = []
    scanning = false
  }

  function refresh(scanWifi) {
    refreshCount++
    lastScanRequest = scanWifi === true
    // scannerRequiresOpened models the compatibility boundary introduced by
    // Omarchy 5f74a996; false retains the accepted b99fd91 behavior.
    if ((opened || !scannerRequiresOpened) && wifiDevice) {
      if (scanWifi === true) {
        scanning = true
        setScannerEnabled(false)
        scanRestart.restart()
      } else {
        setScannerEnabled(true)
      }
    }
    syncWifiNetworks()
  }

  function replaceDevice() { wifiDevice = secondaryDevice }
  function detachDevice() { wifiDevice = null }
  function attachPrimaryDevice() { wifiDevice = primaryDevice }
  function open() { opened = true }
  function close() { opened = false }

  onWifiDeviceChanged: {
    setScannerEnabled(true)
    syncWifiNetworks()
  }

  QtObject {
    id: primaryDevice
    property bool scannerEnabled: false
    onScannerEnabledChanged: {
      if (root.scannerObserver
          && typeof root.scannerObserver.record === "function")
        root.scannerObserver.record("primary", scannerEnabled)
      if (scannerEnabled) {
        root.primaryActivationCount++
        root.publishNetworks("Primary")
      } else if (root.wifiDevice === primaryDevice) {
        root.syncWifiNetworks()
      }
    }
  }

  QtObject {
    id: secondaryDevice
    property bool scannerEnabled: false
    onScannerEnabledChanged: {
      if (root.scannerObserver
          && typeof root.scannerObserver.record === "function")
        root.scannerObserver.record("secondary", scannerEnabled)
      if (scannerEnabled) {
        root.secondaryActivationCount++
        root.publishNetworks("Secondary")
      } else if (root.wifiDevice === secondaryDevice) {
        root.syncWifiNetworks()
      }
    }
  }

  Timer {
    id: scanRestart
    interval: 100
    onTriggered: {
      if ((root.opened || !root.scannerRequiresOpened) && root.wifiDevice) {
        root.setScannerEnabled(true)
        scanDone.restart()
      }
    }
  }

  Timer {
    id: scanDone
    interval: 1500
    onTriggered: root.syncWifiNetworks()
  }

  Component.onCompleted: refresh()
  Component.onDestruction: {
    scanRestart.stop()
    scanDone.stop()
    if (scannerDevice) scannerDevice.scannerEnabled = false
  }
}
