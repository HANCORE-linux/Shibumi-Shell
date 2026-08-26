.pragma library

.import "NetworkModel.js" as NetworkModel
.import "NetworkActionModel.js" as ActionModel
.import "NetworkQrEncoder.js" as Encoder

var SchemaVersion = 1
var OpenSecurity = ["open"]
var PskSecurity = ["wpa-psk", "wpa2-psk", "sae"]
var EnterpriseSecurity = ["wpa-eap", "wpa2-eap", "wpa3-suite-b-192"]

function ownData(value, key) {
  var descriptor = Object.getOwnPropertyDescriptor(value, key)
  if (!descriptor) throw new Error("missing field")
  return "value" in descriptor
    ? descriptor.value : descriptor.get.call(value)
}

function networkData(value) {
  try {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null
    var data = {
      id: ownData(value, "id"),
      deviceId: ownData(value, "deviceId"),
      ssid: ownData(value, "ssid"),
      security: ownData(value, "security"),
      hidden: ownData(value, "hidden"),
      connected: ownData(value, "connected"),
      state: ownData(value, "state"),
      stateChanging: ownData(value, "stateChanging"),
      ambiguous: ownData(value, "ambiguous"),
      generation: ownData(value, "generation")
    }
    if (!ActionModel.validEntityId(data.id, false)
        || !ActionModel.validEntityId(data.deviceId, false)
        || !ActionModel.validGeneration(data.generation)
        || !NetworkModel.validSsid(data.ssid)
        || NetworkModel.SecurityTokens.indexOf(data.security) < 0
        || data.id !== NetworkModel.networkId(
          data.deviceId, data.ssid, data.security)
        || typeof data.hidden !== "boolean"
        || typeof data.connected !== "boolean"
        || ["unknown", "connecting", "connected", "disconnecting",
          "disconnected"].indexOf(data.state) < 0
        || typeof data.stateChanging !== "boolean"
        || typeof data.ambiguous !== "boolean") return null
    return data
  } catch (error) {
    return null
  }
}

function modeForSecurity(security) {
  if (OpenSecurity.indexOf(security) >= 0) return "open"
  if (PskSecurity.indexOf(security) >= 0) return "passphrase"
  if (EnterpriseSecurity.indexOf(security) >= 0) return "enterprise"
  return "unsupported"
}

function prepare(network) {
  var data = networkData(network)
  if (!data)
    return { ok: false, code: "invalid-network", mode: "", network: null }
  if (data.ambiguous)
    return { ok: false, code: "ambiguous", mode: "", network: null }
  if (data.stateChanging)
    return { ok: false, code: "changing", mode: "", network: null }
  if (!data.connected || data.state !== "connected")
    return { ok: false, code: "not-connected", mode: "", network: null }
  var mode = modeForSecurity(data.security)
  if (mode === "enterprise")
    return { ok: false, code: "enterprise", mode: "", network: null }
  if (mode === "unsupported")
    return { ok: false, code: "unsupported", mode: "", network: null }
  return { ok: true, code: "ready", mode: mode, network: data }
}

function preparedData(prepared) {
  try {
    if (!prepared || typeof prepared !== "object" || Array.isArray(prepared))
      return null
    var ok = ownData(prepared, "ok")
    var code = ownData(prepared, "code")
    var mode = ownData(prepared, "mode")
    var data = networkData(ownData(prepared, "network"))
    if (ok !== true || code !== "ready"
        || (mode !== "open" && mode !== "passphrase")
        || data === null || !data.connected || data.state !== "connected"
        || data.stateChanging || data.ambiguous
        || modeForSecurity(data.security) !== mode) return null
    return { mode: mode, network: data }
  } catch (error) {
    return null
  }
}

function escapeField(value) {
  return String(value).replace(/[\\;,:\"]/g, "\\$&")
}

function encode(prepared, passphrase) {
  var safe = preparedData(prepared)
  if (!safe) return Encoder.failure("invalid-network")
  var network = safe.network
  var payload = ""
  if (safe.mode === "open") {
    payload = "WIFI:T:nopass;S:" + escapeField(network.ssid)
      + ";H:" + (network.hidden ? "true" : "false") + ";;"
  } else {
    if (typeof passphrase !== "string" || passphrase === "")
      return Encoder.failure("passphrase-required")
    if (!NetworkModel.validPsk(passphrase, network.security))
      return Encoder.failure("invalid-passphrase")
    var authentication = network.security === "sae" ? "SAE" : "WPA"
    payload = "WIFI:T:" + authentication + ";S:"
      + escapeField(network.ssid) + ";P:" + escapeField(passphrase)
      + ";H:" + (network.hidden ? "true" : "false") + ";;"
  }
  var result = Encoder.encode(payload)
  return result.ok ? result : Encoder.failure("encode")
}

function canShare(network) {
  return prepare(network).ok
}

function fixedMessage(code) {
  switch (code) {
  case "not-connected": return "Connect to this Wi-Fi network before sharing it."
  case "changing": return "Wait for the Wi-Fi connection to settle."
  case "ambiguous": return "This Wi-Fi identity is ambiguous."
  case "enterprise": return "Enterprise Wi-Fi sharing is not available yet."
  case "unsupported": return "This Wi-Fi security type cannot be shared yet."
  case "passphrase-required": return "Loading the saved Wi-Fi QR code."
  case "secret-unavailable": return "The saved Wi-Fi password is unavailable."
  case "preflight-manager": return "NetworkManager could not be verified."
  case "preflight-device": return "The active Wi-Fi device did not match."
  case "preflight-active": return "The active Wi-Fi connection could not be verified."
  case "preflight-active-connection": return "The active Wi-Fi connection identity did not match."
  case "preflight-active-device": return "The active Wi-Fi connection used a different device."
  case "preflight-active-profile": return "The active saved Wi-Fi profile did not match."
  case "preflight-access-point": return "The active Wi-Fi access point did not match."
  case "preflight-active-network": return "The active Wi-Fi network identity did not match."
  case "preflight-profile": return "The saved Wi-Fi profile could not be read."
  case "preflight-profile-identity": return "The saved Wi-Fi profile identity did not match."
  case "preflight-profile-security": return "The saved Wi-Fi security settings did not match."
  case "preflight-profile-version": return "The saved Wi-Fi profile version could not be verified."
  case "authorization-request": return "The saved Wi-Fi authorization request could not be created."
  case "authorization-call": return "The saved Wi-Fi authorization request could not be sent."
  case "authorization-runtime": return "The saved Wi-Fi authorization request failed unexpectedly."
  case "authorization-denied": return "Authorization to read the saved Wi-Fi password was denied."
  case "authorization-timeout": return "Authorization to read the saved Wi-Fi password timed out."
  case "authorization-failed": return "Authorization to read the saved Wi-Fi password failed."
  case "secret-response": return "NetworkManager returned an invalid saved Wi-Fi password response."
  case "secret-response-type": return "NetworkManager returned an invalid saved Wi-Fi password response type."
  case "secret-response-empty": return "NetworkManager returned no saved Wi-Fi password groups."
  case "secret-response-groups": return "NetworkManager returned unexpected saved Wi-Fi password groups."
  case "secret-extra-groups": return "NetworkManager returned data in an additional Wi-Fi password group."
  case "secret-fields-empty": return "NetworkManager returned an empty Wi-Fi password group."
  case "secret-psk-missing": return "NetworkManager returned no PSK in the saved Wi-Fi password group."
  case "secret-extra-fields": return "NetworkManager returned additional saved Wi-Fi password fields."
  case "secret-value-invalid": return "NetworkManager returned an invalid saved Wi-Fi PSK value."
  case "connection-changed": return "The Wi-Fi connection changed during the password request."
  case "consumer-invalid": return "The QR dialog could not receive the saved Wi-Fi password."
  case "dispatcher-inactive": return "The saved Wi-Fi password reader is inactive."
  case "authority-unavailable": return "The saved Wi-Fi password reader is not ready."
  case "dispatcher-busy": return "Another saved Wi-Fi password request is still running."
  case "worker-unavailable": return "The saved Wi-Fi password reader could not be started."
  case "backend-unavailable": return "NetworkManager is not ready for a saved password request."
  case "worker-runtime": return "The saved Wi-Fi password reader failed unexpectedly."
  case "worker-no-result": return "The saved Wi-Fi password reader returned no result."
  case "start-failed": return "The saved Wi-Fi password reader failed to start."
  case "protocol": return "The saved Wi-Fi password reader returned invalid output."
  case "consumer-rejected": return "The QR dialog rejected the saved Wi-Fi password result."
  case "restart-required": return "Restart the shell before requesting the saved Wi-Fi password."
  case "descriptor-stale": return "The connected Wi-Fi details changed before the password request."
  case "gesture-expired": return "The QR Code click expired before the password request."
  case "descriptor-invalid": return "The saved Wi-Fi password request identity was invalid."
  case "request-invalid": return "The saved Wi-Fi password request could not be encoded."
  case "stale": return "The Wi-Fi connection changed. Open QR Code again."
  case "timeout": return "The saved Wi-Fi password request timed out."
  case "invalid-passphrase": return "The saved Wi-Fi password is invalid."
  case "encode": return "Could not create the Wi-Fi QR code."
  default: return "The Wi-Fi network changed. Select it again."
  }
}
