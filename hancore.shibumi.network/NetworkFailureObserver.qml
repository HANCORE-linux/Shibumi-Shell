pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Networking

// Private observer for one raw Quickshell Network wrapper. The owning native
// gateway converts its signal into primitive identity before publication.
QtObject {
  id: root

  required property var deviceObject
  required property var networkObject

  signal observed(var deviceObject, var networkObject, string reason)

  function reasonToken(value) {
    if (value === ConnectionFailReason.NoSecrets) return "no-secrets"
    if (value === ConnectionFailReason.WifiClientDisconnected)
      return "client-disconnected"
    if (value === ConnectionFailReason.WifiClientFailed)
      return "client-failed"
    if (value === ConnectionFailReason.WifiAuthTimeout)
      return "authentication-timeout"
    if (value === ConnectionFailReason.WifiNetworkLost)
      return "network-lost"
    return "unknown"
  }

  property Connections observer: Connections {
    target: root.networkObject
    enabled: root.networkObject !== null
    ignoreUnknownSignals: false

    function onConnectionFailed(reason) {
      root.observed(root.deviceObject, root.networkObject,
        root.reasonToken(reason))
    }
  }
}
