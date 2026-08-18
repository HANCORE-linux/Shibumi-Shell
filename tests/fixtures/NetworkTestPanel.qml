pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Networking

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
  property bool wifiStationAvailable: true
  property var info: ({ iface: "wlan0", ssid: "Details Fallback" })
  property var wifiNetworks: [
    {
      ssid: "Fixture Network",
      connected: true,
      known: true,
      signal: 67,
      security: WifiSecurityType.Open
    },
    {
      ssid: "Fixture Enterprise",
      connected: false,
      known: false,
      signal: 61,
      security: WifiSecurityType.Wpa2Eap
    }
  ]
  property string dnsProvider: "DHCP"
  property var dnsProviders: ["DHCP"]
  property string actionSsid: ""
  property string actionKind: ""
  property string failureSsid: ""
  property string failureReason: ""
  property int knownConnectCount: 0
  property string knownConnectSsid: ""
  property int pskConnectCount: 0
  property string pskSsid: ""
  property string pskPassphrase: ""
  property int enterpriseConnectCount: 0
  property int disconnectRowCount: 0
  property string disconnectSsid: ""
  property int forgetCount: 0
  property string forgetSsid: ""
  // Deliberate legacy trap: Shibumi must not delegate its inline speed test
  // back to these formerly host-owned fields or function.
  property bool speedTestRunning: false
  property string speedTestPhase: ""
  property string speedTestDownloadMbps: ""
  property string speedTestUploadMbps: ""
  property string speedTestError: ""
  property int speedTestRunCount: 0
  property string enterpriseSsid: ""
  property string enterpriseIdentity: ""
  property string enterprisePassphrase: ""

  function open() { opened = true }
  function close() { opened = false }
  function refresh(_scanWifi) { return true }
  function syncWifiNetworks() {}
  function connectKnown(ssid) {
    knownConnectCount++
    knownConnectSsid = ssid
  }
  function connectWithPassphrase(ssid, passphrase) {
    pskConnectCount++
    pskSsid = ssid
    pskPassphrase = passphrase
  }
  function connectEnterprise(ssid, identity, passphrase) {
    enterpriseConnectCount++
    enterpriseSsid = ssid
    enterpriseIdentity = identity
    enterprisePassphrase = passphrase
  }
  function disconnectRow(ssid) {
    disconnectRowCount++
    disconnectSsid = ssid
  }
  function forget(entry) {
    forgetCount++
    forgetSsid = entry ? String(entry.ssid || "") : ""
  }
  function setDns(_provider) {}
  function formatRate(_value) { return "0 B/s" }
  function formatPingLatency(_value) { return "--" }
  function runSpeedTest() {
    speedTestRunCount++
    speedTestRunning = true
    speedTestPhase = "down"
  }
}
