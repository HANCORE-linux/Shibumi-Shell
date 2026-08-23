function text(value) {
  return String(value || "").trim()
}

function nodeProperties(node) {
  return node && node.ready !== false && node.properties
    ? node.properties : ({})
}

function parseSinkAvailability(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index].trim()
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length >= 2) next[parts[0]] = parts[1] !== "0"
  }
  return next
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
  var profile = usableDeviceLabel(properties["device.profile.description"])
  var label = usableDeviceLabel(node.description)
    || usableDeviceLabel(properties["node.description"])
    || usableDeviceLabel(properties["device.description"])
    || usableDeviceLabel(node.nickname)
    || usableDeviceLabel(node.nick)
    || usableDeviceLabel(properties["node.nick"])
    || usableDeviceLabel(node.name)
  if (label && profile
      && label.toLowerCase().indexOf(profile.toLowerCase()) === -1)
    return label + " " + profile
  return label || profile || "Audio device"
}

function usableDeviceLabel(value) {
  var label = text(value)
  return !label || label === "(null)" ? "" : label
}

function nodeDeviceKey(node) {
  var properties = nodeProperties(node)
  var deviceId = usableDeviceLabel(properties["device.id"])
  if (deviceId) return "id:" + deviceId

  var deviceName = usableDeviceLabel(properties["device.name"])
  if (deviceName) return "device:" + deviceName.toLowerCase()

  var nodeName = usableDeviceLabel(node && node.name)
  var profileSeparator = nodeName.lastIndexOf(".")
  return "node:" + (profileSeparator > 0
    ? nodeName.slice(0, profileSeparator) : nodeName).toLowerCase()
}

function nodeProfileKey(node) {
  var properties = nodeProperties(node)
  return usableDeviceLabel(
    properties["device.profile.description"]).toLowerCase()
}

function groupedDeviceNodes(values) {
  var groups = []
  if (!values) return []

  for (var i = 0; i < values.length; i++) {
    var node = values[i]
    if (!node) continue
    var key = nodeDeviceKey(node) || "index:" + i
    var group = null
    for (var j = 0; j < groups.length; j++) {
      if (groups[j].key === key) {
        group = groups[j]
        break
      }
    }
    if (!group) {
      group = { key: key, nodes: [] }
      groups.push(group)
    }
    group.nodes.push(node)
  }

  var result = []
  for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
    groups[groupIndex].nodes.sort(function(left, right) {
      var leftProfile = nodeProfileKey(left)
      var rightProfile = nodeProfileKey(right)
      return leftProfile < rightProfile ? -1
        : leftProfile > rightProfile ? 1 : 0
    })
    for (var nodeIndex = 0; nodeIndex < groups[groupIndex].nodes.length; nodeIndex++)
      result.push(groups[groupIndex].nodes[nodeIndex])
  }
  return result
}

function isAudioSource(node) {
  if (!node || node.isSink || node.isStream) return false
  if (node.audio) return true
  var type = text(node.type)
  return type.indexOf("Audio/Source") !== -1
    || type.indexOf("AudioSource") !== -1
    || type.indexOf("Source") !== -1
}

function friendlyStreamLabel(label) {
  var value = text(label)
  if (!value) return ""
  return value.toLowerCase() === "spotify" ? "Spotify" : value
}

function rawStreamLabel(node) {
  if (!node) return ""
  var properties = nodeProperties(node)
  return usableDeviceLabel(properties["application.name"])
    || usableDeviceLabel(node.description)
    || usableDeviceLabel(properties["media.name"])
    || usableDeviceLabel(properties["node.name"])
    || usableDeviceLabel(node.name)
}

function mprisPlayerLabel(player) {
  return player
    ? friendlyStreamLabel(player.identity || player.desktopEntry || "") : ""
}

function mprisPlayerIsProxy(player) {
  var dbusName = text(player && player.dbusName).toLowerCase()
  var desktopEntry = text(player && player.desktopEntry).toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function streamRepresentsMprisPlayer(streamLabelValue, playerLabel) {
  var streamKey = friendlyStreamLabel(streamLabelValue).toLowerCase()
  var playerKey = text(playerLabel).toLowerCase()
  return !!streamKey && !!playerKey
    && (streamKey === playerKey
      || streamKey.indexOf(playerKey) !== -1
      || playerKey.indexOf(streamKey) !== -1)
}

function mprisLabelsFor(players, predicate) {
  var values = Array.isArray(players) ? players : []
  var playing = []
  var candidates = []
  var playingProxies = []
  var proxies = []
  for (var index = 0; index < values.length; index++) {
    var player = values[index]
    if (!player || (!player.isPlaying && !player.canPlay)) continue
    var label = mprisPlayerLabel(player)
    if (!label || !predicate(label)) continue
    if (mprisPlayerIsProxy(player)) {
      if (player.isPlaying) playingProxies.push(label)
      proxies.push(label)
    } else {
      if (player.isPlaying) playing.push(label)
      candidates.push(label)
    }
  }
  if (playing.length === 1) return playing[0]
  if (playing.length === 0 && playingProxies.length === 1) return playingProxies[0]
  if (candidates.length === 1) return candidates[0]
  if (candidates.length === 0 && proxies.length === 1) return proxies[0]
  return ""
}

function streamLabelIsGeneric(label) {
  return text(label).toLowerCase() === "audio-src"
}

function streamLabel(node, players, streams) {
  if (!node) return "Stream"
  var label = rawStreamLabel(node)
  var resolved = ""
  if (!streamLabelIsGeneric(label)) {
    resolved = mprisLabelsFor(players, function(playerLabel) {
      return streamRepresentsMprisPlayer(label, playerLabel)
    })
  } else {
    resolved = mprisLabelsFor(players, function(playerLabel) {
      var values = Array.isArray(streams) ? streams : []
      for (var index = 0; index < values.length; index++) {
        var other = rawStreamLabel(values[index])
        if (!streamLabelIsGeneric(other)
            && streamRepresentsMprisPlayer(other, playerLabel)) return false
      }
      return true
    })
  }
  return friendlyStreamLabel(resolved || label) || "Application"
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
  var properties = nodeProperties(node)
  var nodeAddress = normalizedAddress(
    properties["api.bluez5.address"] || properties["bluez5.address"])
  var nodeTextValue = nodeText(node)
  // A supplied Bluetooth address is authoritative. Never route to a same-name
  // device when its address is absent, invalid, or different.
  if (rawAddress) {
    if (!/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(rawAddress))
      return false
    if (node.ready === false) {
      var nodeName = String(node.name || "").toLowerCase()
      return nodeName.indexOf("bluez_output.") === 0
        && normalizedAddress(nodeName).indexOf(address) !== -1
    }
    return nodeAddress !== "" && nodeAddress === address
  }
  var label = text(request.deviceName || request.name).toLowerCase()
  return !!label && nodeTextValue.indexOf(label) !== -1
}

function resolveNode(id, values, kind) {
  var key = String(id || "")
  if (!key || !values) return null
  for (var index = 0; index < values.length; index++) {
    if (stableNodeId(values[index], kind) === key) return values[index]
  }
  return null
}

function snapshotList(values, kind, selected, labeler) {
  var result = []
  if (!values) return result
  for (var index = 0; index < values.length; index++) {
    var value = snapshot(values[index], kind, values[index] === selected)
    if (value && value.id) {
      var resolvedLabel = labeler ? text(labeler(values[index])) : ""
      if (resolvedLabel) value.label = resolvedLabel
      result.push(value)
    }
  }
  return result
}

function snapshot(node, kind, isDefault) {
  if (!node) return null
  var audio = node.ready !== false ? node.audio : null
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
