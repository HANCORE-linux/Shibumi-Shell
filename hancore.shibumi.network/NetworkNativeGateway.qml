pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Networking

// Native Quickshell 0.3.0 access stays behind NetworkBackendAdapter's Loader.
// The gateway is never created by fake-backed or inactive adapters and is not
// a public service surface; raw NetworkManager wrappers do not leave it.
Item {
  id: root

  // Quickshell 0.3.0 initializes this backend once and cannot observe later
  // NetworkManager loss. The outer adapter therefore combines this immutable
  // initialization fact with a separate reactive service-liveness gate.
  readonly property bool backendInitialized:
    Networking.backend === NetworkBackendType.NetworkManager
  readonly property bool wifiEnabled: root.backendInitialized
    && Networking.wifiEnabled === true
  readonly property bool wifiHardwareEnabled: root.backendInitialized
    && Networking.wifiHardwareEnabled === true
  readonly property string connectivity:
    connectivityToken(Networking.connectivity)
  readonly property var deviceObjects: root.backendInitialized
    && Networking.devices ? Networking.devices.values : []

  signal connectionFailure(var deviceObject, var networkObject, string reason)

  visible: false
  width: 0
  height: 0

  function deviceTypeToken(value) {
    if (value === DeviceType.Wifi) return "wifi"
    if (value === DeviceType.Wired) return "wired"
    return "none"
  }

  function connectionStateToken(value) {
    if (value === ConnectionState.Connecting) return "connecting"
    if (value === ConnectionState.Connected) return "connected"
    if (value === ConnectionState.Disconnecting) return "disconnecting"
    if (value === ConnectionState.Disconnected) return "disconnected"
    return "unknown"
  }

  function connectivityToken(value) {
    if (value === NetworkConnectivity.None) return "none"
    if (value === NetworkConnectivity.Portal) return "portal"
    if (value === NetworkConnectivity.Limited) return "limited"
    if (value === NetworkConnectivity.Full) return "full"
    return "unknown"
  }

  function securityToken(value) {
    if (value === WifiSecurityType.Wpa3SuiteB192)
      return "wpa3-suite-b-192"
    if (value === WifiSecurityType.Sae) return "sae"
    if (value === WifiSecurityType.Wpa2Eap) return "wpa2-eap"
    if (value === WifiSecurityType.Wpa2Psk) return "wpa2-psk"
    if (value === WifiSecurityType.WpaEap) return "wpa-eap"
    if (value === WifiSecurityType.WpaPsk) return "wpa-psk"
    if (value === WifiSecurityType.StaticWep) return "static-wep"
    if (value === WifiSecurityType.DynamicWep) return "dynamic-wep"
    if (value === WifiSecurityType.Leap) return "leap"
    if (value === WifiSecurityType.Owe) return "owe"
    if (value === WifiSecurityType.Open) return "open"
    return "unknown"
  }

  function networkObjects(device) {
    return device && device.networks ? device.networks.values : []
  }

  function profileObjects(network) {
    return network && network.nmSettings ? network.nmSettings : []
  }

  function profileUuid(profile) {
    return profile && typeof profile.uuid === "string" ? profile.uuid : ""
  }

  function profileName(profile) {
    return profile && typeof profile.id === "string" ? profile.id : ""
  }

  function supportsNetworkAction(action, target) {
    if (!target) return false
    if (action === "connect") return typeof target.connect === "function"
    if (action === "connectWithPsk")
      return typeof target.connectWithPsk === "function"
    if (action === "disconnect")
      return typeof target.disconnect === "function"
    return false
  }

  function supportsProfileAction(action, network, profile) {
    if (!network || !profile) return false
    if (action === "connect")
      return network.connected !== true && network.stateChanging !== true
        && typeof network.connectWithSettings === "function"
    if (action === "forget") return typeof profile.forget === "function"
    return false
  }

  function setWifiEnabled(enabled) {
    if (!root.backendInitialized) return false
    Networking.wifiEnabled = enabled === true
    return true
  }

  function connectNetwork(target) {
    if (!supportsNetworkAction("connect", target)) return false
    target.connect()
    return true
  }

  function connectNetworkWithPsk(target, passphrase) {
    if (!supportsNetworkAction("connectWithPsk", target)) return false
    target.connectWithPsk(passphrase)
    return true
  }

  function disconnectNetwork(target) {
    if (!supportsNetworkAction("disconnect", target)) return false
    target.disconnect()
    return true
  }

  function connectProfile(network, profile) {
    if (!supportsProfileAction("connect", network, profile)) return false
    network.connectWithSettings(profile)
    return {
      ok: true,
      code: "accepted",
      message: "Saved-profile connection dispatch accepted."
    }
  }

  function forgetProfile(profile) {
    if (!profile || typeof profile.forget !== "function") return false
    profile.forget()
    return {
      ok: true,
      code: "accepted",
      message: "Saved-profile removal dispatch accepted."
    }
  }

  Instantiator {
    model: root.deviceObjects

    delegate: QtObject {
      id: deviceObserver
      required property var modelData
      readonly property var observedDevice: modelData

      property Instantiator networkObservers: Instantiator {
        model: root.networkObjects(deviceObserver.observedDevice)

        delegate: NetworkFailureObserver {
          required property var modelData
          deviceObject: deviceObserver.observedDevice
          networkObject: modelData
          onObserved: function(deviceObject, networkObject, reason) {
            root.connectionFailure(deviceObject, networkObject, reason)
          }
        }
      }
    }
  }
}
