.pragma library

var MaxRows = 512

function keyForId(id) {
  return "$" + String(id || "")
}
function shellQuote(value) {
  return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
}

function cleanText(value, maxLength) {
  var result = String(value || "").replace(/[\x00-\x1f\x7f]/g, " ").trim()
  return result.length <= maxLength ? result : result.slice(0, maxLength).trim()
}

function slugify(value) {
  return String(value || "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "item"
}

function spec(providerKey) {
  if (providerKey === "fonts") {
    return {
      command: ["timeout", "--kill-after=1s", "5s", "bash", "-lc",
        "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while IFS= read -r value; do [[ -n $value ]] && printf '%s\\t%s\\t%s\\n' \"$value\" \"$value\" \"$current\"; done"],
      actionPrefix: "omarchy-font-set",
      keywordSuffix: "typeface"
    }
  }
  if (providerKey === "power-profiles") {
    return {
      command: ["timeout", "--kill-after=1s", "5s", "bash", "-lc",
        "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while IFS= read -r value; do [[ -n $value ]] && printf '%s\\t%s\\t%s\\n' \"$value\" \"$value\" \"$current\"; done"],
      actionPrefix: "powerprofilesctl set",
      keywordSuffix: "power profile"
    }
  }
  return null
}

function commandFor(providerKey) {
  var provider = spec(providerKey)
  return provider ? provider.command.slice() : []
}

function rows(providerKey, parentId, raw) {
  var provider = spec(providerKey)
  var parent = String(parentId || "")
  if (!provider || !/^[a-z0-9][a-z0-9._-]{0,254}$/.test(parent)) return []

  var result = []
  var seenIds = ({})
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length && result.length < MaxRows; i++) {
    if (!lines[i].trim()) continue
    var parts = lines[i].split("\t")
    var label = cleanText(parts[0], 256)
    var value = cleanText(parts.length > 1 ? parts[1] : parts[0], 512)
    var current = cleanText(parts.length > 2 ? parts[2] : "", 512)
    if (!label || !value) continue

    var maxSlug = Math.max(1, 254 - parent.length - 1)
    var baseSlug = slugify(value).slice(0, maxSlug).replace(/-+$/g, "") || "item"
    var candidate = parent + "." + baseSlug
    var suffix = 2
    while (seenIds[keyForId(candidate)]) {
      var suffixText = "-" + suffix
      candidate = parent + "." + baseSlug.slice(0, Math.max(1, maxSlug - suffixText.length)) + suffixText
      suffix++
    }
    seenIds[keyForId(candidate)] = true
    result.push({
      id: candidate,
      raw: {
        parent: parent,
        label: label,
        icon: value === current ? "✓" : "",
        keywords: value + " " + provider.keywordSuffix,
        action: provider.actionPrefix + " " + shellQuote(value)
      }
    })
  }
  return result
}
