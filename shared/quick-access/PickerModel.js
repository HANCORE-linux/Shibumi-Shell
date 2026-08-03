.pragma library

function parseRows(text) {
  var rows = String(text || "").split("\n")
  var result = []
  var seen = {}
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i]) continue
    var columns = rows[i].split("\t")
    var source = columns[0] || ""
    if (!source || seen[source]) continue
    seen[source] = true
    result.push({
      sourcePath: source,
      thumbnailPath: columns[1] || "",
      label: columns[2] || source.split("/").pop(),
      directory: columns[3] || "",
      thumbnailReady: columns[4] === "1"
    })
  }
  return result
}

function mediaLabel(path) {
  var name = String(path || "").split("/").pop().replace(/\.[^.]+$/, "")
  var match = name.match(
    /(\d{4})-(\d{2})-(\d{2})[_-](\d{2})-(\d{2})-(\d{2})/)
  return match
    ? match[1] + "-" + match[2] + "-" + match[3]
      + "  " + match[4] + ":" + match[5]
    : name
}

function filtered(entries, text) {
  var needle = String(text || "").trim().toLowerCase()
  if (!needle) return Array.isArray(entries) ? entries.slice() : []
  var source = Array.isArray(entries) ? entries : []
  return source.filter(function(entry) {
    return String(entry.label || "").toLowerCase().indexOf(needle) >= 0
      || String(entry.sourcePath || "").toLowerCase().indexOf(needle) >= 0
  })
}

function indexForSource(entries, sourcePath) {
  var source = Array.isArray(entries) ? entries : []
  var wanted = String(sourcePath || "")
  if (!wanted) return 0
  for (var i = 0; i < source.length; i++) {
    if (String(source[i].sourcePath || "") === wanted) return i
  }
  return 0
}

function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, Number(index) || 0))
}

function entriesEqual(left, right) {
  var first = Array.isArray(left) ? left : []
  var second = Array.isArray(right) ? right : []
  if (first.length !== second.length) return false
  for (var i = 0; i < first.length; i++) {
    if (String(first[i].sourcePath || "") !== String(second[i].sourcePath || "")
        || String(first[i].thumbnailPath || "")
          !== String(second[i].thumbnailPath || "")
        || String(first[i].label || "") !== String(second[i].label || "")
        || String(first[i].directory || "") !== String(second[i].directory || "")
        || (first[i].thumbnailReady === true)
          !== (second[i].thumbnailReady === true)) return false
  }
  return true
}

function replaceThumbnailReady(entries, thumbnailPath) {
  var source = Array.isArray(entries) ? entries : []
  var result = source
  var wanted = String(thumbnailPath || "")
  if (!wanted) return result
  for (var i = 0; i < source.length; i++) {
    if (String(source[i].thumbnailPath || "") !== wanted
        || source[i].thumbnailReady === true) continue
    if (result === source) result = source.slice()
    var old = source[i]
    result[i] = {
      sourcePath: old.sourcePath,
      thumbnailPath: old.thumbnailPath,
      label: old.label,
      directory: old.directory,
      thumbnailReady: true
    }
  }
  return result
}
