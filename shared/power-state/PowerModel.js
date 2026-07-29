.pragma library

function clampPercent(value) {
  var number = Number(value)
  if (!isFinite(number)) return 0
  if (number >= 0 && number <= 1) number *= 100
  return Math.max(0, Math.min(100, Math.round(number)))
}

function parseKeyValue(raw) {
  var result = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var tab = lines[i].indexOf("\t")
    if (tab <= 0) continue
    var key = lines[i].substring(0, tab).trim()
    if (!/^[a-z][a-z0-9-]*$/.test(key)) continue
    result[key] = lines[i].substring(tab + 1).trim()
  }
  return result
}

function parseProfiles(raw) {
  var profiles = []
  var activeProfile = ""
  var seen = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split("\t")
    var profile = String(parts[0] || "").trim()
    if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(profile) || seen[profile]) continue
    seen[profile] = true
    profiles.push(profile)
    if (parts.length > 1 && parts[1].trim() === "1") activeProfile = profile
  }
  return { profiles: profiles, activeProfile: activeProfile }
}

function profileLabel(profile) {
  var value = String(profile || "")
  if (value === "power-saver") return "Power Saver"
  if (value === "balanced") return "Balanced"
  if (value === "performance") return "Performance"
  return value.split("-").map(function(part) {
    return part ? part.charAt(0).toUpperCase() + part.slice(1) : ""
  }).join(" ")
}

function profileShortName(profile) {
  if (profile === "power-saver") return "SAV"
  if (profile === "performance") return "PRF"
  if (profile === "balanced") return "BAL"
  return String(profile || "---").substring(0, 3).toUpperCase()
}

function duration(seconds) {
  var total = Math.max(0, Math.round(Number(seconds) || 0))
  if (total <= 0) return ""
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m"
}
