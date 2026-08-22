function text(value) {
  return String(value || "").trim()
}

function nodeProperties(node) {
  return node && node.ready !== false && node.properties
    ? node.properties : ({})
}

function stableNodeId(node, kind) {
  if (!node || node.id === undefined || node.id === null) return ""
  var id = String(node.id).trim()
  if (!/^[0-9]+$/.test(id)) return ""
  return String(kind || "node") + ":" + id
}

function nodeLabel(node) {
  if (!node) return "Audio device"
  var properties = nodeProperties(node)
  return text(node.description)
    || text(properties["node.description"])
    || text(properties["device.description"])
    || text(node.name)
    || "Audio device"
}

function isAudioSource(node) {
  if (!node || node.isSink || node.isStream) return false
  if (node.audio) return true
  var type = text(node.type)
  return type.indexOf("Audio/Source") !== -1
    || type.indexOf("AudioSource") !== -1
    || type.indexOf("Source") !== -1
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true
  var type = text(node.type)
  return type.indexOf("Stream/Output/Audio") !== -1
    || type.indexOf("AudioOutStream") !== -1
    || type.indexOf("Output") !== -1
}

function nodeText(node) {
  var properties = nodeProperties(node)
  return [
    node ? node.name : "",
    node ? node.description : "",
    node ? node.nickname : "",
    node ? node.nick : "",
    properties["node.name"],
    properties["node.description"],
    properties["device.name"],
    properties["device.description"],
    properties["api.bluez5.address"],
    properties["bluez5.address"],
    properties["media.name"]
  ].join(" ").toLowerCase()
}

function normalizedAddress(value) {
  return text(value).toLowerCase().replace(/[^0-9a-f]/g, "")
}

function bluetoothSinkMatchesRequest(node, request) {
  if (!node || !node.isSink || node.isStream || !request) return false
  var rawAddress = text(request.address)
  var address = normalizedAddress(rawAddress)
  var nodeTextValue = nodeText(node)
  // A supplied Bluetooth address is authoritative. Never route to a same-name
  // device when its address is absent, invalid, or different.
  if (rawAddress) {
    if (!/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(rawAddress))
      return false
    return normalizedAddress(nodeTextValue).indexOf(address) !== -1
  }
  var label = text(request.deviceName || request.name).toLowerCase()
  return !!label && nodeTextValue.indexOf(label) !== -1
}

function snapshot(node, kind, isDefault) {
  if (!node) return null
  var audio = node.audio
  return {
    id: stableNodeId(node, kind),
    kind: String(kind || "node"),
    name: text(node.name),
    label: nodeLabel(node),
    description: text(node.description),
    available: node.ready !== false,
    isDefault: isDefault === true,
    volume: audio && audio.volume !== undefined ? Number(audio.volume) : 0,
    muted: audio && audio.muted === true,
    isStream: node.isStream === true
  }
}

function actionResult(ok, code, message, entityId, generation) {
  return {
    ok: ok === true,
    code: String(code || (ok ? "ok" : "unavailable")),
    message: String(message || ""),
    entityId: String(entityId || ""),
    generation: Number(generation || 0)
  }
}
