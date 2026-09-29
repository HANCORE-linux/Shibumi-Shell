// Bar-only presentation mappings. No backend, state, or panel authority.
// Network thresholds match Omarchy v4.0.4. Battery uses the selected FA ladder.
function wifiIconFor(strength) {
  var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
  var index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))
  return icons[index]
}

function connectionIcon(kind, signalStrength) {
  if (kind === "wifi") return wifiIconFor(signalStrength)
  if (kind === "ethernet") return "󰈀"
  return "󰤮"
}

function batteryIcon(percent, charging, full) {
  // Five equal 20-percent bands; 100% clamps to the full glyph. Charging is
  // painted separately, with a same-font bolt rather than a rotated symbol.
  var icons = ["\uF244", "\uF243", "\uF242", "\uF241", "\uF240"]
  var index = full ? 4 : Math.max(0, Math.min(4, Math.floor(percent / 20)))
  return icons[index]
}

function verticalBatteryIcon(percent, charging, full) {
  // Omarchy's ten-level glyph tables. The existing facade has no complete
  // charge-threshold state, so that state is deliberately not synthesized.
  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(percent / 100 * 10)))
  if (full) return "󰂅"
  return charging ? chargingIcons[index] : defaultIcons[index]
}

function outputIcon(volume, muted, ready) {
  if (!ready || muted || volume <= 0) return ""
  if (volume >= 0.67) return ""
  if (volume >= 0.34) return ""
  return ""
}

function glyph(text) {
  var symbols = {
    "planner_review": "󰚗", "󰢮": "", "graphic_eq": "", "schedule": "",
    "music_note": "", "skip_previous": "", "pause": "",
    "play_arrow": "", "skip_next": "", "collections": "",
    "palette": "󰏘", "\uE7F4": "", "\uE7F6": "󰂛",
    "\uE029": "󰍬", "\uE65F": "󰔟",
    "\uE5D3": "󰇘", "\uF569": "󰏗", "\uF466": "󰏗",
    "\uE627": "󰏗", "\uE1A9": "󰂲", "\uE1A8": "󰂱",
    "\uE1A7": "󰂯",
    "\uE900": "", "⻯": "󰊠"
  }
  return symbols[text] || text
}
