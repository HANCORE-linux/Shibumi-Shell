pragma ComponentBehavior: Bound

import QtQuick

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
  property var info: ({ iface: "wlan0", ssid: "Details Fallback" })
  property var wifiNetworks: [
    { ssid: "Fixture Network", connected: true }
  ]
  property int enterpriseConnectCount: 0
  property string enterpriseSsid: ""
  property string enterpriseIdentity: ""
  property string enterprisePassphrase: ""

  function open() { opened = true }
  function close() { opened = false }
  function refresh(_scanWifi) { return true }
  function connectEnterprise(ssid, identity, passphrase) {
    enterpriseConnectCount++
    enterpriseSsid = ssid
    enterpriseIdentity = identity
    enterprisePassphrase = passphrase
  }
}
