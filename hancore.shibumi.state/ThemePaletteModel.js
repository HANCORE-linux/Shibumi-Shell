.pragma library

var ColorPattern = /^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/
var MaxInputLength = 65536
var MaxLines = 1024

function parse(raw) {
  var values = {}
  var lines = String(raw || "").slice(0, MaxInputLength).split("\n")
  for (var i = 0; i < lines.length && i < MaxLines; i++) {
    var match = lines[i].match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*["']?(#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?)/)
    if (!match || !ColorPattern.test(match[2])) continue
    values[String(match[1]).toLowerCase()] = match[2]
  }
  return {
    color01: values.color1 || values.red || "",
    color02: values.color2 || values.green || "",
    color03: values.color3 || values.yellow || "",
    color04: values.color4 || values.blue || "",
    color05: values.color5 || values.magenta || "",
    color06: values.color6 || values.cyan || "",
    color07: values.color7 || values.bright_fg || values.light_fg || "",
    color08: values.color8 || values.bright_black || ""
  }
}

function selection(value) {
  var candidate = String(value || "").toLowerCase()
  if (candidate === "red" || candidate === "accent"
      || candidate === "0" || candidate === "1"
      || candidate === "color1") return "color01"
  if (candidate === "green" || candidate === "color2") return "color02"
  if (candidate === "yellow" || candidate === "color3") return "color03"
  return [
    "color01", "color02", "color03", "color04",
    "color05", "color06", "color07", "color08", "foreground"
  ].indexOf(candidate) >= 0 ? candidate : "color01"
}
