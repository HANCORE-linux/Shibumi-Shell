.pragma library

var MaxStatusLength = 2097152
var MaxPeers = 256
var MaxTextLength = 253
var MaxErrorLength = 180
var BackendStates = [
  "NoState", "NeedsLogin", "NeedsMachineAuth", "Stopped", "Starting", "Running"
]

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function boundedText(value, limit) {
  const max = limit > 0 ? limit : MaxTextLength
  const result = String(value === null || value === undefined ? "" : value)
    .replace(/[\u0000-\u001f\u007f]/g, "").trim()
  return result.length > max ? result.slice(0, max - 1) + "…" : result
}

function validIpv4(value) {
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(
    String(value || ""))
  if (!match) return false
  for (let index = 1; index <= 4; index++)
    if (Number(match[index]) > 255) return false
  return true
}

function validIpv6(value) {
  const text = String(value || "")
  return text.length >= 2 && text.length <= 45
    && text.indexOf(":") >= 0 && /^[0-9a-fA-F:.]+$/.test(text)
}

function firstAddress(values, ipv6) {
  const rows = Array.isArray(values) ? values : []
  for (let index = 0; index < rows.length; index++) {
    const value = String(rows[index] || "")
    if (ipv6 ? validIpv6(value) : validIpv4(value)) return value
  }
  return ""
}

function dnsName(value) {
  return boundedText(String(value || "").replace(/\.$/, ""), MaxTextLength)
}

function nodeName(node) {
  const host = boundedText(node.HostName, 63)
  if (host !== "" && host !== "localhost") return host
  const dns = dnsName(node.DNSName)
  return dns !== "" ? dns.split(".")[0] : host
}

function emptySnapshot(reason) {
  return {
    available: false,
    reason: String(reason || "unavailable"),
    backendState: "",
    running: false,
    needsLogin: false,
    tailnet: "",
    selfName: "",
    selfDnsName: "",
    selfIp: "",
    selfIp6: "",
    exitNodeIp: "",
    exitNodeName: "",
    peers: [],
    onlineCount: 0
  }
}

function peerFrom(node) {
  const ip = firstAddress(node.TailscaleIPs, false)
  return {
    key: boundedText(node.ID || node.PublicKey || ip, 128),
    name: nodeName(node),
    dnsName: dnsName(node.DNSName),
    ip: ip,
    ip6: firstAddress(node.TailscaleIPs, true),
    os: boundedText(node.OS, 32),
    online: node.Online === true,
    exitNodeOption: node.ExitNodeOption === true && ip !== "",
    exitNode: node.ExitNode === true
  }
}

function comparePeers(left, right) {
  if (left.exitNode !== right.exitNode) return left.exitNode ? -1 : 1
  if (left.online !== right.online) return left.online ? -1 : 1
  return left.name.localeCompare(right.name)
}

function parseStatus(raw) {
  const text = String(raw || "")
  if (text.length === 0 || text.length > MaxStatusLength)
    return emptySnapshot("invalid")
  let payload = null
  try { payload = JSON.parse(text) } catch (error) { payload = null }
  if (!isObject(payload)) return emptySnapshot("invalid")

  const reported = String(payload.BackendState || "")
  const backendState = BackendStates.indexOf(reported) >= 0
    ? reported : "Unknown"
  const self = isObject(payload.Self) ? payload.Self : {}
  const tailnet = isObject(payload.CurrentTailnet)
    ? boundedText(payload.CurrentTailnet.Name, 128) : ""
  const source = isObject(payload.Peer) ? payload.Peer : {}
  const peers = []
  for (const id in source) {
    if (peers.length >= MaxPeers) break
    if (isObject(source[id])) peers.push(peerFrom(source[id]))
  }
  peers.sort(comparePeers)

  let onlineCount = 0
  let exitNode = null
  for (let index = 0; index < peers.length; index++) {
    if (peers[index].online) onlineCount++
    if (peers[index].exitNode && exitNode === null) exitNode = peers[index]
  }

  const result = emptySnapshot("")
  result.available = true
  result.backendState = backendState
  result.running = backendState === "Running"
  result.needsLogin = backendState === "NeedsLogin"
    || backendState === "NeedsMachineAuth"
  result.tailnet = tailnet
  result.selfName = nodeName(self)
  result.selfDnsName = dnsName(self.DNSName)
  result.selfIp = firstAddress(self.TailscaleIPs, false)
  result.selfIp6 = firstAddress(self.TailscaleIPs, true)
  result.exitNodeIp = exitNode ? exitNode.ip : ""
  result.exitNodeName = exitNode ? exitNode.name : ""
  result.peers = peers
  result.onlineCount = onlineCount
  return result
}

// Returns the argument for `tailscale set --exit-node=`, or null when the
// requested node is not an advertised exit node in the current snapshot.
function exitNodeTarget(snapshot, ip) {
  if (!snapshot || snapshot.running !== true) return null
  const target = String(ip || "")
  if (target === "") return ""
  const peers = Array.isArray(snapshot.peers) ? snapshot.peers : []
  for (let index = 0; index < peers.length; index++) {
    if (peers[index].ip === target && peers[index].exitNodeOption === true)
      return target
  }
  return null
}

function copyableText(value) {
  const text = String(value || "")
  return text !== "" && text.length <= MaxTextLength
    && /^[A-Za-z0-9.:_-]+$/.test(text) ? text : ""
}

function stateLabel(snapshot) {
  if (!snapshot || snapshot.available !== true) {
    const reason = snapshot ? String(snapshot.reason || "") : ""
    if (reason === "loading") return "Checking…"
    if (reason === "missing") return "Not installed"
    if (reason === "daemon") return "tailscaled not running"
    return "Unavailable"
  }
  if (snapshot.running) return "Connected"
  if (snapshot.needsLogin) return "Needs login"
  if (snapshot.backendState === "Starting") return "Starting…"
  return "Disconnected"
}

function probeFailure(stderr) {
  const text = String(stderr || "").toLowerCase()
  if (text.indexOf("tailscaled") >= 0 || text.indexOf("connect") >= 0)
    return "daemon"
  return "unavailable"
}

function actionError(stderr) {
  const text = String(stderr || "")
  const lower = text.toLowerCase()
  if (lower.indexOf("access denied") >= 0
      || lower.indexOf("prefs write access denied") >= 0
      || lower.indexOf("--operator") >= 0)
    return "Permission denied. Run 'sudo tailscale set --operator=$USER' once."
  if (lower.indexOf("non-default flags") >= 0
      || lower.indexOf("requires mentioning all") >= 0)
    return "Run 'tailscale up' with your usual flags in a terminal."
  const lines = text.trim().split("\n")
  const message = boundedText(lines.length > 0 ? lines[0] : "", MaxErrorLength)
  return message !== "" ? message : "Tailscale command failed"
}
