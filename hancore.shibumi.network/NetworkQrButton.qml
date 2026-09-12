pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "NetworkQrModel.js" as Model

// Shibumi-owned Wi-Fi share action beside the connected primitive network row.
Rectangle {
  id: root

  required property var network
  property var visualTokens: null
  property string label: "Share QR"
  readonly property bool shareable: Model.canShare(root.network)
  signal activated()

  implicitWidth: labelRow.implicitWidth + Commons.Style.space(20)
  implicitHeight: Commons.Style.space(34)
  radius: root.visualTokens ? root.visualTokens.tileRadius
    : Commons.Style.space(7)
  color: !root.enabled ? Qt.rgba(0, 0, 0, 0.08)
    : hover.hovered
      ? (root.visualTokens ? root.visualTokens.fillHover
        : Qt.rgba(1, 1, 1, 0.12))
      : (root.visualTokens ? root.visualTokens.fillIdle
        : Qt.rgba(0, 0, 0, 0.12))
  border.width: root.visualTokens ? root.visualTokens.panelBorderWidth : 1
  border.color: root.visualTokens ? root.visualTokens.panelBorder
    : Qt.rgba(1, 1, 1, 0.16)
  enabled: root.shareable
  activeFocusOnTab: true

  function activate() {
    if (!root.enabled) return false
    root.activated()
    return true
  }

  Row {
    id: labelRow
    anchors.centerIn: parent
    spacing: Commons.Style.space(6)

    Text {
      text: "\uE00A"
      color: root.visualTokens ? root.visualTokens.ink
        : Commons.Color.foreground
      font.family: "Material Symbols Rounded"
      font.pixelSize: Commons.Style.space(17)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: root.label
      color: root.visualTokens ? root.visualTokens.ink
        : Commons.Color.foreground
      font.family: root.visualTokens ? root.visualTokens.fontFamily
        : Commons.Style.font.family
      font.pixelSize: root.visualTokens ? root.visualTokens.captionSize
        : Commons.Style.font.caption
      font.bold: true
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  HoverHandler { id: hover; enabled: root.enabled }
  TapHandler { enabled: root.enabled; onTapped: root.activate() }
  Keys.onSpacePressed: function(event) {
    event.accepted = root.activate()
  }
  Keys.onReturnPressed: function(event) {
    event.accepted = root.activate()
  }
  Keys.onEnterPressed: function(event) {
    event.accepted = root.activate()
  }

  Accessible.role: Accessible.Button
  Accessible.name: root.label
  Accessible.description: root.shareable
    ? "Share the connected Wi-Fi network as a QR code"
    : "Wi-Fi QR sharing is unavailable for this network"
}
