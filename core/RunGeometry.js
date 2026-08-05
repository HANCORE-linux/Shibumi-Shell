.pragma library

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function validRange(value, allowEmpty) {
  if (!value || typeof value !== "object") return null
  var x = finiteNumber(value.x, NaN)
  var width = finiteNumber(value.width, NaN)
  if (!isFinite(x) || !isFinite(width) || width < 0
      || (!allowEmpty && width <= 0)) return null
  return { x: x, width: width }
}

function addCut(cuts, fromValue, toValue, width) {
  var from = Math.max(0, Math.min(width, finiteNumber(fromValue, 0)))
  var to = Math.max(0, Math.min(width, finiteNumber(toValue, 0)))
  if (to > from) cuts.push([from, to])
}

function sectionCuts(cuts, section, width, padding) {
  if (!section || typeof section !== "object") return
  var origin = finiteNumber(section.x, 0)
  var groups = Array.isArray(section.groups) ? section.groups : []
  var splits = Array.isArray(section.splits) ? section.splits : []
  for (var i = 0; i < groups.length - 1; i++) {
    var current = groups[i]
    var next = groups[i + 1]
    var index = current ? Number(current.index) : -1
    var nextIndex = next ? Number(next.index) : -1
    var boundaryIndex = nextIndex - 1
    // V1 splits belong to slot boundaries. Across hidden slots, the rendered
    // gap uses the last boundary before the next visible group; every other
    // hidden boundary remains dormant and positionally stable.
    if (!Number.isInteger(index) || index < 0
        || !Number.isInteger(nextIndex) || nextIndex <= index
        || splits[boundaryIndex] !== true)
      continue
    var currentRight = origin + finiteNumber(current.right, 0)
    var nextLeft = origin + finiteNumber(next.left, currentRight)
    addCut(cuts, currentRight + padding, nextLeft - padding, width)
  }
}

function boundaryCuts(cuts, spec, width, padding) {
  var boundaries = Array.isArray(spec.boundaries) ? spec.boundaries : []
  var left = validRange(spec.left, false)
  var center = validRange(spec.center, true)
  var right = validRange(spec.right, false)
  if (boundaries[0] === true && boundaries[1] === true
      && (!center || center.width <= 0) && left) {
    addCut(cuts, left.x + left.width + padding,
      right ? right.x - padding : width, width)
    return
  }
  if (boundaries[0] === true && left && center)
    addCut(cuts, left.x + left.width + padding, center.x - padding, width)
  if (boundaries[1] === true && center)
    addCut(cuts, center.x + center.width + padding,
      right ? right.x - padding : width, width)
}

function runsFromCuts(widthValue, cuts) {
  var width = Math.max(0, finiteNumber(widthValue, 0))
  if (width <= 0) return []
  cuts.sort(function(left, right) { return left[0] - right[0] })
  var runs = []
  var start = 0
  for (var i = 0; i < cuts.length; i++) {
    if (cuts[i][0] > start)
      runs.push({ x: start, width: cuts[i][0] - start })
    if (cuts[i][1] > start) start = cuts[i][1]
  }
  if (width > start) runs.push({ x: start, width: width - start })
  return runs
}

function compute(specValue) {
  var spec = specValue && typeof specValue === "object" ? specValue : {}
  var width = Math.max(0, finiteNumber(spec.width, 0))
  if (width <= 0) return []
  var padding = Math.max(0, finiteNumber(spec.padding, 4))
  var cuts = []
  var sections = Array.isArray(spec.sections) ? spec.sections : []
  for (var i = 0; i < sections.length; i++)
    sectionCuts(cuts, sections[i], width, padding)
  boundaryCuts(cuts, spec, width, padding)
  return runsFromCuts(width, cuts)
}
