.pragma library

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(value, maximum))
}

function cardX(position, surfaceWidth, cardWidth, gap, barSize, topOffset) {
  var maximum = Math.max(gap, surfaceWidth - cardWidth - gap)
  var requested = position === "left" ? gap + barSize
    : (position === "right"
      ? surfaceWidth - cardWidth - gap - barSize
      : topOffset)
  return clamp(requested, gap, maximum)
}

function cardY(position, surfaceHeight, cardHeight, gap, barSize) {
  var maximum = Math.max(gap, surfaceHeight - cardHeight - gap)
  var requested = position === "top" ? gap + barSize
    : (position === "bottom"
      ? surfaceHeight - cardHeight - gap - barSize
      : gap)
  return clamp(requested, gap, maximum)
}
