pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

// In-panel Shibumi Wi-Fi QR dialog. It creates no window, process, helper, or
// backend owner. The final native Network panel supplies the current primitive
// connected row and updates `network` while this screen-local dialog is open.
FocusScope {
  id: root

  property var visualTokens: null
  property var network: null
  readonly property bool opened: session.opened
  readonly property bool needsPassphrase: session.needsPassphrase
  readonly property bool qrReady: session.ready
  property bool secretPending: false
  property string secretRequestToken: ""

  signal dismissed()
  signal secretCancelRequested(string requestToken)

  visible: root.opened
  z: 1000
  focus: visible

  function openNetwork(network) {
    root.network = network
    root.secretPending = false
    root.secretRequestToken = ""
    const result = session.openNetwork(network)
    Qt.callLater(function() {
      if (root.opened) closeButton.forceActiveFocus()
    })
    return result
  }

  function beginSecretRequest(requestToken) {
    if (!root.opened || !session.needsPassphrase
        || typeof requestToken !== "string" || requestToken === "")
      return false
    const result = session.awaitSavedSecret()
    if (!result.ok) return false
    root.secretRequestToken = requestToken
    root.secretPending = true
    return true
  }

  function boundedFailureCode(code) {
    const value = String(code || "")
    const allowed = [
      "timeout", "stale", "preflight-manager", "preflight-device",
      "preflight-active", "preflight-active-connection",
      "preflight-active-device", "preflight-active-profile",
      "preflight-access-point", "preflight-active-network",
      "preflight-profile", "preflight-profile-identity",
      "preflight-profile-security", "preflight-profile-version",
      "authorization-denied", "authorization-timeout",
      "authorization-failed", "secret-response", "connection-changed",
      "consumer-invalid", "dispatcher-inactive", "authority-unavailable",
      "dispatcher-busy", "worker-unavailable", "backend-unavailable",
      "worker-runtime", "worker-no-result", "start-failed", "protocol",
      "consumer-rejected", "restart-required", "descriptor-stale",
      "gesture-expired", "descriptor-invalid", "request-invalid"
    ]
    return allowed.indexOf(value) >= 0 ? value : "secret-unavailable"
  }

  function rejectSecretRequest(code) {
    if (!root.opened || !session.needsPassphrase) return false
    root.secretPending = false
    root.secretRequestToken = ""
    session.rejectSavedSecret(root.boundedFailureCode(code))
    closeButton.forceActiveFocus()
    return true
  }

  function stageSavedSecret(evidence, passphrase) {
    if (!root.opened || !root.secretPending || !evidence
        || evidence.requestToken !== root.secretRequestToken) return false
    const result = session.stagePassphrase(root.network, passphrase)
    if (!result.ok || result.code !== "staged") {
      root.secretPending = false
      root.secretRequestToken = ""
      closeButton.forceActiveFocus()
      return false
    }
    return !root.qrReady
  }

  function commitSavedSecret(requestToken) {
    if (!root.opened || !root.secretPending
        || requestToken !== root.secretRequestToken) return false
    const result = session.commitSavedSecret()
    if (!result.ok || result.code !== "ready") return false
    root.secretPending = false
    root.secretRequestToken = ""
    closeButton.forceActiveFocus()
    return true
  }

  function rejectSavedSecret(requestToken, code) {
    if (!root.opened || !root.secretPending
        || requestToken !== root.secretRequestToken) return false
    root.secretPending = false
    root.secretRequestToken = ""
    session.rejectSavedSecret(root.boundedFailureCode(code))
    closeButton.forceActiveFocus()
    return true
  }

  function updateNetwork(network) {
    root.network = network
    const result = session.updateNetwork(network)
    if (!result.ok && root.secretPending) {
      const token = root.secretRequestToken
      root.secretPending = false
      root.secretRequestToken = ""
      root.secretCancelRequested(token)
    }
    return result
  }

  function close() {
    const token = root.secretRequestToken
    root.secretPending = false
    root.secretRequestToken = ""
    if (token !== "") root.secretCancelRequested(token)
    root.network = null
    session.close()
    root.dismissed()
  }

  Keys.onEscapePressed: function(event) {
    event.accepted = true
    root.close()
  }

  NetworkQrSession { id: session }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.74)

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - Commons.Style.space(32),
      Commons.Style.space(360))
    implicitHeight: content.implicitHeight + Commons.Style.space(36)
    height: Math.min(parent.height - Commons.Style.space(32), implicitHeight)
    radius: root.visualTokens ? root.visualTokens.panelRadius
      : Commons.Style.space(12)
    color: root.visualTokens ? root.visualTokens.panelBackground
      : Commons.Color.background
    border.width: root.visualTokens
      ? root.visualTokens.panelBorderWidth : 1
    border.color: root.visualTokens ? root.visualTokens.panelBorder
      : Qt.rgba(1, 1, 1, 0.18)
    clip: true

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: content
      anchors.centerIn: parent
      width: parent.width - Commons.Style.space(36)
      spacing: Commons.Style.space(12)

      Text {
        width: parent.width
        text: session.ssid || "Wi-Fi sharing"
        color: root.visualTokens ? root.visualTokens.ink
          : Commons.Color.foreground
        font.family: root.visualTokens ? root.visualTokens.fontFamily
          : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.title
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: root.secretPending
        text: "Loading saved Wi-Fi QR code…"
        color: root.visualTokens ? root.visualTokens.mutedInk
          : Commons.Color.muted
        font.family: root.visualTokens ? root.visualTokens.fontFamily
          : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }

      Rectangle {
        id: qrCanvas
        objectName: "shibumiNetworkQrCanvas"
        readonly property int moduleSize: session.qrSize > 0
          ? Math.max(3, Math.floor(Commons.Style.space(270) / session.qrSize))
          : 0
        visible: session.ready
        width: session.qrSize * moduleSize
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        radius: 0

        Canvas {
          id: modules
          anchors.fill: parent
          renderStrategy: Canvas.Cooperative
          antialiasing: false
          onPaint: {
            const context = getContext("2d")
            context.reset()
            context.clearRect(0, 0, width, height)
            context.fillStyle = "#ffffff"
            context.fillRect(0, 0, width, height)
            context.fillStyle = "#000000"
            const rows = session.qrRows
            const size = session.qrSize
            const scale = qrCanvas.moduleSize
            for (let row = 0; row < size; row++) {
              const values = rows[row] || ""
              for (let column = 0; column < size; column++) {
                if (values.charAt(column) === "1")
                  context.fillRect(column * scale, row * scale, scale, scale)
              }
            }
          }

          Connections {
            target: session
            function onQrRowsChanged() { modules.requestPaint() }
            function onQrSizeChanged() { modules.requestPaint() }
          }
        }
      }

      Text {
        width: parent.width
        visible: session.ready
        text: "Scan to join this Wi-Fi network"
        color: root.visualTokens ? root.visualTokens.mutedInk
          : Commons.Color.muted
        font.family: root.visualTokens ? root.visualTokens.fontFamily
          : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        objectName: "shibumiNetworkQrErrorMessage"
        width: parent.width
        visible: session.errorMessage !== ""
        text: session.errorMessage
        color: root.visualTokens ? root.visualTokens.seal
          : Commons.Color.bar.active
        font.family: root.visualTokens ? root.visualTokens.fontFamily
          : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }

      ActionButton {
        id: closeButton
        objectName: "shibumiNetworkQrCloseButton"
        width: parent.width
        label: session.ready ? "Done" : "Close"
        primary: true
        onActivated: root.close()
      }
    }
  }

  component ActionButton: Rectangle {
    id: action
    required property string label
    property bool primary: false
    signal activated()

    height: Commons.Style.space(36)
    radius: root.visualTokens ? root.visualTokens.tileRadius
      : Commons.Style.space(7)
    readonly property bool hovered: actionMouse.containsMouse && action.enabled
    color: !action.enabled ? Qt.rgba(0, 0, 0, 0.08)
      : action.hovered
        ? (root.visualTokens ? root.visualTokens.fillPrimaryHover
          : Qt.rgba(1, 1, 1, 0.16))
        : action.primary
          ? (root.visualTokens ? root.visualTokens.seal
            : Commons.Color.accent)
          : (root.visualTokens ? root.visualTokens.fillIdle
            : Qt.rgba(0, 0, 0, 0.10))
    border.width: action.activeFocus ? 1 : action.primary ? 0
      : root.visualTokens ? root.visualTokens.panelBorderWidth : 1
    border.color: action.activeFocus
      ? (root.visualTokens ? root.visualTokens.paper : Commons.Color.background)
      : root.visualTokens ? root.visualTokens.panelBorder
        : Qt.rgba(1, 1, 1, 0.18)
    activeFocusOnTab: true

    function activate() {
      if (!action.enabled) return false
      action.activated()
      return true
    }

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: action.label
      color: action.primary
        ? (root.visualTokens ? root.visualTokens.paper
          : Commons.Color.background)
        : (root.visualTokens ? root.visualTokens.ink
          : Commons.Color.foreground)
      font.family: root.visualTokens ? root.visualTokens.fontFamily
        : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      font.bold: true
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: action.enabled
      onClicked: action.activate()
    }
    Keys.onSpacePressed: function(event) {
      if (!action.enabled) return
      event.accepted = true
      action.activate()
    }
    Keys.onReturnPressed: function(event) {
      if (!action.enabled) return
      event.accepted = true
      action.activate()
    }
    Keys.onEnterPressed: function(event) {
      if (!action.enabled) return
      event.accepted = true
      action.activate()
    }
    Accessible.role: Accessible.Button
    Accessible.name: action.label
  }

  Component.onDestruction: {
    secretPending = false
    secretRequestToken = ""
    session.close()
  }
}
