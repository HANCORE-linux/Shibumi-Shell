pragma ComponentBehavior: Bound

import QtQuick
import "NetworkQrModel.js" as Model

// Screen-local, ephemeral QR presentation state. It retains only validated
// primitive network identity and the rendered module matrix. Passphrases and
// Wi-Fi payload strings are never properties and are discarded in the submit
// call before control returns to the event loop.
Item {
  id: root

  property bool opened: false
  readonly property bool needsPassphrase: implementation.needsPassphrase
  readonly property bool ready: root.opened && implementation.size > 0
    && implementation.errorCode === ""
  readonly property string ssid: implementation.ssid
  readonly property string errorCode: implementation.errorCode
  readonly property string errorMessage: implementation.errorCode === ""
    ? "" : Model.fixedMessage(implementation.errorCode)
  readonly property int qrSize: implementation.size
  readonly property var qrRows: implementation.rows.slice()

  visible: false
  width: 0
  height: 0

  function openNetwork(network) { return implementation.openNetwork(network) }
  function updateNetwork(network) { return implementation.updateNetwork(network) }
  function submitPassphrase(network, passphrase) {
    return implementation.submitPassphrase(network, passphrase)
  }
  function close() { implementation.close() }

  QtObject {
    id: implementation

    property var prepared: null
    property string ssid: ""
    property bool needsPassphrase: false
    property string errorCode: ""
    property int size: 0
    property var rows: []

    function publicResult(ok, code) {
      return { ok: ok === true, code: String(code || "invalid-network") }
    }

    function clearMatrix() {
      size = 0
      rows = []
    }

    function acceptMatrix(result) {
      if (!result || result.ok !== true || result.code !== "ready"
          || typeof result.size !== "number" || result.size < 29
          || result.size > 69 || !Array.isArray(result.rows)
          || result.rows.length !== result.size) return false
      const nextRows = []
      for (let index = 0; index < result.rows.length; index++) {
        const row = result.rows[index]
        if (typeof row !== "string" || row.length !== result.size
            || !/^[01]+$/.test(row)) return false
        nextRows.push(row)
      }
      size = result.size
      rows = nextRows
      return true
    }

    function sameIdentity(left, right) {
      return left && right && left.network && right.network
        && left.mode === right.mode
        && left.network.id === right.network.id
        && left.network.deviceId === right.network.deviceId
        && left.network.ssid === right.network.ssid
        && left.network.security === right.network.security
        && left.network.hidden === right.network.hidden
        && left.network.generation === right.network.generation
    }

    function openNetwork(network) {
      close()
      root.opened = true
      const candidate = Model.prepare(network)
      if (!candidate.ok) {
        errorCode = candidate.code
        return publicResult(false, candidate.code)
      }
      prepared = candidate
      ssid = candidate.network.ssid
      needsPassphrase = candidate.mode === "passphrase"
      if (needsPassphrase) {
        errorCode = "passphrase-required"
        return publicResult(true, "passphrase-required")
      }
      const encoded = Model.encode(candidate, "")
      if (!acceptMatrix(encoded)) {
        errorCode = encoded && encoded.code ? encoded.code : "encode"
        return publicResult(false, errorCode)
      }
      errorCode = ""
      return publicResult(true, "ready")
    }

    function updateNetwork(network) {
      if (!root.opened || !prepared)
        return publicResult(false, "invalid-network")
      const current = Model.prepare(network)
      if (!current.ok || !sameIdentity(prepared, current)) {
        clearMatrix()
        prepared = null
        needsPassphrase = false
        errorCode = current.ok ? "invalid-network" : current.code
        return publicResult(false, errorCode)
      }
      prepared = current
      return publicResult(true, root.ready ? "ready"
        : needsPassphrase ? "passphrase-required" : "invalid-network")
    }

    function submitPassphrase(network, passphrase) {
      if (!root.opened || !needsPassphrase || !prepared)
        return publicResult(false, "invalid-network")
      const current = Model.prepare(network)
      if (!current.ok || !sameIdentity(prepared, current)) {
        clearMatrix()
        prepared = null
        needsPassphrase = false
        errorCode = current.ok ? "invalid-network" : current.code
        return publicResult(false, errorCode)
      }
      const encoded = Model.encode(current, passphrase)
      if (!acceptMatrix(encoded)) {
        clearMatrix()
        errorCode = encoded && encoded.code ? encoded.code : "encode"
        return publicResult(false, errorCode)
      }
      prepared = current
      needsPassphrase = false
      errorCode = ""
      return publicResult(true, "ready")
    }

    function close() {
      root.opened = false
      prepared = null
      ssid = ""
      needsPassphrase = false
      errorCode = ""
      clearMatrix()
    }
  }

  Component.onDestruction: implementation.close()
}
