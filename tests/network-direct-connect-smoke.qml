pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking
import "network" as Network

ShellRoot {
  id: root

  property int ticks: 0

  function fail(message) {
    console.error("network-direct-connect-smoke:", message)
    Qt.exit(1)
  }

  Item {
    id: fakeBar
    visible: false
    property bool vertical: false
    property int barSize: 35
    property int sizeHorizontal: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color background: "#111111"
    property color urgent: "#88bbee"
    property var shell: null

    function registeredWidgetSource(_id) { return "" }
    function registeredWidgetComponent(_id) { return null }
    function widgetSettings(_group, _module) { return ({}) }
    function findPanelWidget(_id) { return null }
  }

  Component {
    id: directPanelComponent

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
      property var info: ({ iface: "wlan0", ssid: "" })
      property var wifiNetworks: [
        {
          ssid: "Forward Connect Fixture",
          connected: false,
          known: true,
          signal: 67,
          security: WifiSecurityType.Open
        }
      ]
      property string dnsProvider: "DHCP"
      property var dnsProviders: ["DHCP"]
      property string actionSsid: ""
      property string actionKind: ""
      property string failureSsid: ""
      property string failureReason: ""
      property int directConnectCount: 0
      property string directConnectSsid: ""

      function open() { opened = true }
      function close() { opened = false }
      function refresh(_scanWifi) { return true }
      function syncWifiNetworks() {}
      function connectDirectly(ssid) {
        directConnectCount++
        directConnectSsid = ssid
      }
      function connectWithPassphrase(_ssid, _passphrase) {}
      function connectEnterprise(_ssid, _identity, _passphrase) {}
      function disconnectRow(_ssid) {}
      function forget(_entry) {}
      function setDns(_provider) {}
      function formatRate(_value) { return "0 B/s" }
      function formatPingLatency(_value) { return "--" }
    }
  }

  Network.Service {
    id: service
    bar: fakeBar
    panelComponent: directPanelComponent
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (!service.ready || root.ticks < 2) {
        if (root.ticks > 200) root.fail("service did not become ready")
        return
      }

      const entry = service.networks[0]
      if (!entry) return root.fail("forward-connect fixture row is missing")
      if (!service.connect(entry))
        return root.fail("Service.connect rejected connectDirectly backend")
      if (service.backend.directConnectCount !== 1
          || service.backend.directConnectSsid !== "Forward Connect Fixture")
        return root.fail("Service.connect did not call connectDirectly")

      console.log("network direct connect smoke passed")
      Qt.exit(0)
    }
  }
}
