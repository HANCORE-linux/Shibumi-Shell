pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "network" as Network
import "network/NetworkModel.js" as NetworkModel
import "network/NetworkQrModel.js" as QrModel
import "network/NetworkQrEncoder.js" as QrEncoder
import "network/NetworkQrSecretModel.js" as QrSecretModel

ShellRoot {
  id: root

  property int activations: 0
  property string deviceId: NetworkModel.deviceId(
    "wifi", "AA:BB:CC:DD:EE:42", "wlan-qr")
  property var currentRow: networkRow("Guest", "open", 1)

  function fail(message) {
    console.error("network-qr-regression:", message)
    Qt.exit(1)
  }

  function networkRow(ssid, security, generation) {
    return {
      id: NetworkModel.networkId(root.deviceId, ssid, security),
      deviceId: root.deviceId,
      ssid: ssid,
      security: security,
      hidden: false,
      connected: true,
      state: "connected",
      stateChanging: false,
      ambiguous: false,
      generation: generation
    }
  }

  function independentEscape(value) {
    let result = ""
    for (let index = 0; index < value.length; index++) {
      const character = value.charAt(index)
      result += ["\\", ";", ",", ":", "\""].indexOf(character) >= 0
        ? "\\" + character : character
    }
    return result
  }

  function validMatrix(session) {
    if (!session.ready || session.qrSize < 29 || session.qrSize > 69
        || session.qrRows.length !== session.qrSize) return false
    const quiet = "0".repeat(session.qrSize)
    for (let index = 0; index < session.qrRows.length; index++) {
      const row = session.qrRows[index]
      if (typeof row !== "string" || row.length !== session.qrSize
          || !/^[01]+$/.test(row)) return false
      if ((index < 4 || index >= session.qrSize - 4) && row !== quiet)
        return false
    }
    return true
  }

  Network.NetworkQrSession { id: session }

  Item {
    width: 800
    height: 600

    Network.NetworkQrButton {
      id: qrButton
      network: root.currentRow
      onActivated: root.activations++
    }

    Network.NetworkQrDialog {
      id: qrDialog
      anchors.fill: parent
    }
  }

  Timer {
    interval: 50
    running: true
    onTriggered: {
      const diagnostic = QrModel.fixedMessage("authorization-denied")
      const workerFailure = QrSecretModel.parseFailure(
        '{"schemaVersion":1,"status":"failed","requestToken":"shibumi-qr-secret-v1:[1,1]","code":"authorization-denied"}')
      if (!workerFailure || workerFailure.code !== "authorization-denied"
          || diagnostic.indexOf("denied") < 0
          || QrSecretModel.parseFailure(
            '{"schemaVersion":1,"status":"failed","requestToken":"shibumi-qr-secret-v1:[1,1]","code":"forged"}'))
        return root.fail("secret-free worker diagnostics are not bounded")

      const open = root.networkRow("Guest", "open", 1)
      let result = session.openNetwork(open)
      if (!result.ok || result.code !== "ready" || session.needsPassphrase
          || session.ssid !== "Guest" || !root.validMatrix(session))
        return root.fail("open Wi-Fi did not produce a bounded QR matrix")
      session.close()
      if (session.opened || session.ready || session.qrSize !== 0
          || session.qrRows.length !== 0 || session.ssid !== "")
        return root.fail("closing QR session retained presentation state")

      const persisted = {
        uuid: "11111111-2222-4333-8444-555555555555",
        profileType: "wifi",
        ssid: "Private;Office",
        security: "wpa2-psk"
      }
      if (!NetworkModel.qrShareEligible(true, false, "wpa2-psk",
          "Private;Office", persisted.uuid, 1, persisted)
          || NetworkModel.qrShareEligible(true, false, "wpa2-psk",
            "Private;Office", persisted.uuid, 1, null)
          || NetworkModel.qrShareEligible(true, false, "wpa2-psk",
            "Private;Office", persisted.uuid, 0, persisted)
          || NetworkModel.qrShareEligible(true, false, "wpa2-psk",
            "Private;Office", persisted.uuid, 2, persisted)
          || NetworkModel.qrShareEligible(true, false, "wpa2-psk",
            "Other", persisted.uuid, 1, persisted))
        return root.fail("secured QR persisted-profile eligibility failed")

      const psk = root.networkRow("Private;Office", "wpa2-psk", 4)
      result = session.openNetwork(psk)
      if (!result.ok || result.code !== "passphrase-required"
          || !session.needsPassphrase || session.qrSize !== 0)
        return root.fail("PSK Wi-Fi did not require a transient passphrase")
      const invalidPassphrase = session.submitPassphrase(psk, "short")
      if (invalidPassphrase.ok
          || invalidPassphrase.code !== "invalid-passphrase"
          || session.qrSize !== 0)
        return root.fail("invalid PSK produced QR state")
      const changed = Object.assign({}, psk, { generation: 5 })
      const stale = session.submitPassphrase(changed, "correct;horse")
      if (stale.ok || stale.code !== "invalid-network"
          || session.needsPassphrase || session.qrSize !== 0)
        return root.fail("changed PSK identity accepted a stale passphrase")

      session.openNetwork(psk)
      const accepted = session.submitPassphrase(psk, "correct;horse")
      if (!accepted.ok || accepted.code !== "ready"
          || session.needsPassphrase || !root.validMatrix(session))
        return root.fail("valid transient PSK did not produce QR state")
      const publicState = JSON.stringify({
        opened: session.opened,
        ssid: session.ssid,
        errorCode: session.errorCode,
        size: session.qrSize,
        rows: session.qrRows
      })
      if (publicState.indexOf("correct;horse") >= 0)
        return root.fail("passphrase leaked into QR session state")
      session.close()

      const sae = root.networkRow("WPA3", "sae", 7)
      const saePrepared = QrModel.prepare(sae)
      const saeEncoded = QrModel.encode(saePrepared, "dragonfly")
      const expectedSae = QrEncoder.encode(
        "WIFI:T:SAE;S:WPA3;P:dragonfly;H:false;;")
      if (!saeEncoded.ok || !expectedSae.ok
          || saeEncoded.size !== expectedSae.size
          || saeEncoded.rows.join("\n") !== expectedSae.rows.join("\n"))
        return root.fail("SAE Wi-Fi was not encoded with SAE authentication")

      const hiddenOpen = Object.assign({}, open, { hidden: true })
      const hiddenOpenEncoded = QrModel.encode(
        QrModel.prepare(hiddenOpen), "")
      const expectedHiddenOpen = QrEncoder.encode(
        "WIFI:T:nopass;S:Guest;H:true;;")
      if (!hiddenOpenEncoded.ok || !expectedHiddenOpen.ok
          || hiddenOpenEncoded.rows.join("\n")
            !== expectedHiddenOpen.rows.join("\n"))
        return root.fail("hidden open Wi-Fi did not emit H:true")

      const specialUnit = "\\;,:\""
      const specialSsid = specialUnit.repeat(6) + "\\;"
      const specialPassphrase = specialUnit.repeat(12) + "\\;,"
      const specialNetwork = Object.assign({}, root.networkRow(
        specialSsid, "wpa2-psk", 9), { hidden: true })
      const specialEncoded = QrModel.encode(
        QrModel.prepare(specialNetwork), specialPassphrase)
      const expectedSpecial = QrEncoder.encode(
        "WIFI:T:WPA;S:" + root.independentEscape(specialSsid)
          + ";P:" + root.independentEscape(specialPassphrase)
          + ";H:true;;")
      if (!specialEncoded.ok || !expectedSpecial.ok
          || specialEncoded.rows.join("\n")
            !== expectedSpecial.rows.join("\n"))
        return root.fail("Wi-Fi fields were not escaped exactly")

      const enterprise = root.networkRow("Corp", "wpa2-eap", 1)
      const enterpriseResult = session.openNetwork(enterprise)
      if (enterpriseResult.ok || enterpriseResult.code !== "enterprise"
          || session.qrSize !== 0)
        return root.fail("enterprise Wi-Fi crossed the unsupported boundary")
      session.close()
      const unsupportedRows = [
        root.networkRow("Legacy", "static-wep", 1),
        root.networkRow("Enhanced", "owe", 1)
      ]
      for (let index = 0; index < unsupportedRows.length; index++) {
        const unsupported = QrModel.prepare(unsupportedRows[index])
        if (unsupported.ok || unsupported.code !== "unsupported")
          return root.fail("unsupported Wi-Fi security became shareable")
      }
      const unstableRows = [
        Object.assign({}, open, { connected: false, state: "disconnected" }),
        Object.assign({}, open, { stateChanging: true }),
        Object.assign({}, open, { ambiguous: true }),
        Object.assign({}, open, { id: open.id + "forged" })
      ]
      const unstableCodes = [
        "not-connected", "changing", "ambiguous", "invalid-network"
      ]
      for (let unstableIndex = 0;
          unstableIndex < unstableRows.length; unstableIndex++) {
        const rejected = QrModel.prepare(unstableRows[unstableIndex])
        if (rejected.ok || rejected.code !== unstableCodes[unstableIndex])
          return root.fail("unstable Wi-Fi row crossed QR preparation")
      }

      const getterReads = new Array(10).fill(0)
      const accessorRow = {}
      const fields = [
        "id", "deviceId", "ssid", "security", "hidden", "connected",
        "state", "stateChanging", "ambiguous", "generation"
      ]
      const values = [
        open.id, open.deviceId, open.ssid, open.security, open.hidden,
        open.connected, open.state, open.stateChanging, open.ambiguous,
        open.generation
      ]
      for (let fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
        const captured = values[fieldIndex]
        Object.defineProperty(accessorRow, fields[fieldIndex], {
          enumerable: true,
          get: function() {
            getterReads[fieldIndex]++
            if (getterReads[fieldIndex] > 1)
              throw new Error("QR row getter read twice")
            return captured
          }
        })
      }
      const accessorPrepared = QrModel.prepare(accessorRow)
      if (!accessorPrepared.ok
          || getterReads.some(function(reads) { return reads !== 1 }))
        return root.fail("QR row boundary repeatedly evaluated getters")

      root.currentRow = open
      if (!qrButton.shareable || !qrButton.activate()
          || root.activations !== 1)
        return root.fail("Shibumi QR button did not expose open Wi-Fi action")
      root.currentRow = enterprise
      if (qrButton.shareable || qrButton.activate()
          || root.activations !== 1)
        return root.fail("Shibumi QR button exposed enterprise Wi-Fi action")

      let dialogResult = qrDialog.openNetwork(open)
      if (!dialogResult.ok || !qrDialog.opened || !qrDialog.qrReady)
        return root.fail("Shibumi QR dialog did not present open Wi-Fi")
      const bravo = root.networkRow("Bravo", "open", 1)
      let updated = qrDialog.updateNetwork(bravo)
      if (updated.ok || qrDialog.qrReady)
        return root.fail("network switch left the previous QR visible")
      dialogResult = qrDialog.openNetwork(open)
      const disconnectedOpen = Object.assign({}, open, {
        connected: false, state: "disconnected"
      })
      updated = qrDialog.updateNetwork(disconnectedOpen)
      if (updated.ok || updated.code !== "not-connected" || qrDialog.qrReady)
        return root.fail("disconnect left the previous QR visible")
      dialogResult = qrDialog.openNetwork(open)
      updated = qrDialog.updateNetwork(Object.assign({}, open, {
        generation: open.generation + 1
      }))
      if (updated.ok || qrDialog.qrReady)
        return root.fail("generation change left the previous QR visible")
      qrDialog.close()
      if (qrDialog.opened || qrDialog.qrReady || qrDialog.network !== null)
        return root.fail("Shibumi QR dialog retained closed state")

      console.log("network QR regression passed")
      Qt.exit(0)
    }
  }
}
