pragma ComponentBehavior: Bound

import QtQuick

// Current Omarchy network panel contract after speed tests moved into the
// standalone omarchy.speedtest panel plugin.
Item {
  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property bool manageIpc: true
  property bool opened: false
  property bool networkManagerAvailable: true
  property string kind: "wifi"
  property var connectedWifiNetwork: ({ name: "" })
  property int signalStrength: 67
  property bool scanning: false
  property bool busy: false
  property var wifiDevice: null
  property var info: ({ iface: "wlan0", ssid: "Current Fixture" })
  property var wifiNetworks: [
    { ssid: "Current Fixture", connected: true }
  ]

  function open() { opened = true }
  function close() { opened = false }
  function refresh(_scanWifi) { return true }
}
