pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property var passwordControl: null
  property var closeControl: null
  property string deviceId: NetworkModel.deviceId(
    "wifi", "AA:BB:CC:DD:EE:54", "wlan-qr-render")
  readonly property string outputPath:
    Quickshell.env("SHIBUMI_QR_RENDER_PATH")
  readonly property string securedOutputPath: root.outputPath + ".secured.png"

  function fail(message) {
    console.error("network-qr-render-regression:", message)
    Qt.exit(1)
  }

  function row(ssid) {
    return {
      id: NetworkModel.networkId(root.deviceId, ssid, "open"),
      deviceId: root.deviceId,
      ssid: ssid,
      security: "open",
      hidden: false,
      connected: true,
      state: "connected",
      stateChanging: false,
      ambiguous: false,
      generation: 1
    }
  }

  function pskRow(generation, connected) {
    const ssid = "Private"
    return {
      id: NetworkModel.networkId(root.deviceId, ssid, "wpa2-psk"),
      deviceId: root.deviceId,
      ssid: ssid,
      security: "wpa2-psk",
      hidden: false,
      connected: connected,
      state: connected ? "connected" : "disconnected",
      stateChanging: false,
      ambiguous: false,
      generation: generation
    }
  }

  function findNamed(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    const children = item.children || []
    for (let index = 0; index < children.length; index++) {
      const found = root.findNamed(children[index], name)
      if (found) return found
    }
    return null
  }

  function controlsCleared(label) {
    if (!root.passwordControl || !root.closeControl
        || root.passwordControl.text !== ""
        || dialog.needsPassphrase
        || !root.closeControl.visible
        || !root.closeControl.activeFocus)
      return root.fail(label + " did not restore visible close focus")
    return true
  }

  Window {
    id: surface
    width: 800
    height: 600
    visible: true

    Network.NetworkQrDialog {
      id: dialog
      anchors.fill: parent
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 80)
        return root.fail("render regression timed out in phase " + root.phase)
      if (root.phase === 0) {
        if (!root.outputPath) return root.fail("missing render output path")
        const first = dialog.openNetwork(root.row("Alpha"))
        if (!first.ok || !dialog.qrReady)
          return root.fail("first QR did not render")
        root.phase = 1
        root.ticks = 0
        return
      }
      if (root.phase === 1) {
        if (root.ticks < 4) return
        const second = dialog.openNetwork(root.row("Bravo"))
        if (!second.ok || !dialog.qrReady)
          return root.fail("replacement QR did not render")
        root.phase = 2
        root.ticks = 0
        return
      }
      if (root.phase === 2) {
        if (root.ticks < 6) return
        const canvas = root.findNamed(
          surface.contentItem, "shibumiNetworkQrCanvas")
        if (!canvas || !canvas.visible || canvas.width <= 0)
          return root.fail("rendered QR canvas was not found")
        root.phase = 99
        canvas.grabToImage(function(result) {
          if (!result.saveToFile(root.outputPath))
            return root.fail("could not save rendered QR canvas")
          const opened = dialog.openNetwork(root.pskRow(1, true))
          root.passwordControl = root.findNamed(
            surface.contentItem, "shibumiNetworkQrPasswordField")
          root.closeControl = root.findNamed(
            surface.contentItem, "shibumiNetworkQrCloseButton")
          if (!opened.ok || !root.passwordControl || !root.closeControl)
            return root.fail("secured focus controls were not found")
          root.passwordControl.text = "correct horse"
          root.passwordControl.forceActiveFocus()
          dialog.updateNetwork(root.row("Other"))
          root.phase = 3
          root.ticks = 0
        }, Qt.size(canvas.width, canvas.height))
        return
      }
      if (root.phase === 3) {
        if (root.ticks < 2) return
        if (!root.controlsCleared("identity change")) return
        dialog.openNetwork(root.pskRow(1, true))
        root.passwordControl.text = "correct horse"
        root.passwordControl.forceActiveFocus()
        dialog.updateNetwork(root.pskRow(1, false))
        root.phase = 4
        root.ticks = 0
        return
      }
      if (root.phase === 4) {
        if (root.ticks < 2) return
        if (!root.controlsCleared("disconnect")) return
        dialog.openNetwork(root.pskRow(1, true))
        root.passwordControl.text = "correct horse"
        root.passwordControl.forceActiveFocus()
        dialog.updateNetwork(root.pskRow(2, true))
        root.phase = 5
        root.ticks = 0
        return
      }
      if (root.phase === 5) {
        if (root.ticks < 2) return
        if (!root.controlsCleared("generation change")) return
        dialog.openNetwork(root.pskRow(1, true))
        root.passwordControl.text = "correct horse"
        root.passwordControl.forceActiveFocus()
        dialog.network = root.pskRow(2, true)
        const submitted = dialog.submitPassphrase()
        if (submitted.ok || dialog.needsPassphrase)
          return root.fail("stale secured submit did not fail closed")
        root.phase = 6
        root.ticks = 0
        return
      }
      if (root.phase === 6) {
        if (root.ticks < 2) return
        if (!root.controlsCleared("stale submit")) return
        dialog.openNetwork(root.pskRow(1, true))
        root.passwordControl.text = "correct horse"
        root.passwordControl.forceActiveFocus()
        const submitted = dialog.submitPassphrase()
        if (!submitted.ok || submitted.code !== "ready"
            || dialog.needsPassphrase || !dialog.qrReady
            || root.passwordControl.text !== "")
          return root.fail("valid secured submit did not settle QR state")
        root.phase = 7
        root.ticks = 0
        return
      }
      if (root.phase === 7) {
        if (root.ticks < 2) return
        if (!root.closeControl.activeFocus)
          return root.fail("valid secured submit did not restore close focus")
        const canvas = root.findNamed(
          surface.contentItem, "shibumiNetworkQrCanvas")
        if (!canvas || !canvas.visible)
          return root.fail("secured QR canvas was not visible")
        root.phase = 98
        canvas.grabToImage(function(result) {
          if (!result.saveToFile(root.securedOutputPath))
            return root.fail("could not save secured QR canvas")
          console.log("network QR render regression passed")
          Qt.exit(0)
        }, Qt.size(canvas.width, canvas.height))
      }
    }
  }
}
