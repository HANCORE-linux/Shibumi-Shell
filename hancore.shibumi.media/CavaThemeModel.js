.pragma library

var ColorPattern = /^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/
var MaxInputLength = 65536
var MaxLines = 1024
var MaxGradientColors = 8

function parse(raw) {
  var gradientEnabled = false
  var gradientCount = 0
  var foreground = ""
  var indexedColors = {}
  var lines = String(raw || "").slice(0, MaxInputLength).split("\n")

  for (var i = 0; i < lines.length && i < MaxLines; i++) {
    var assignment = lines[i].match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/)
    if (!assignment) continue
    var key = String(assignment[1]).toLowerCase()
    var value = String(assignment[2]).replace(/^\s*["']?|["']?\s*$/g, "")

    if (key === "gradient") {
      gradientEnabled = value === "1" || value.toLowerCase() === "true"
    } else if (key === "gradient_count") {
      var count = parseInt(value)
      gradientCount = isNaN(count) ? 0
        : Math.max(0, Math.min(MaxGradientColors, count))
    } else if (key === "foreground" && ColorPattern.test(value)) {
      foreground = value
    } else {
      var colorMatch = key.match(/^gradient_color_([1-8])$/)
      if (colorMatch && ColorPattern.test(value))
        indexedColors[parseInt(colorMatch[1])] = value
    }
  }

  if (!gradientEnabled) return foreground ? [foreground] : []

  var count = gradientCount
  if (count === 0) {
    while (count < MaxGradientColors && indexedColors[count + 1]) count++
  }
  if (count < 2) return foreground ? [foreground] : []

  var colors = []
  for (var index = 1; index <= count; index++) {
    if (!indexedColors[index]) return foreground ? [foreground] : []
    colors.push(indexedColors[index])
  }
  return colors
}
