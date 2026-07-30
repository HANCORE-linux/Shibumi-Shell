.pragma library

function groupVisibleAtStage(groupId, stage) {
  var id = String(groupId || "")
  var value = Math.max(0, Math.min(3, Number(stage) || 0))
  if (id === "G8" || value === 0) return true
  if (value === 1) return ["G7", "G9", "G10"].indexOf(id) < 0
  if (value === 2)
    return ["G4", "G5", "G7", "G9", "G10"].indexOf(id) < 0
  return ["G1", "G2", "G6", "G8", "G11", "G14"].indexOf(id) >= 0
}

function nextNarrowStage(currentStage, availableWidth, stageWidths) {
  var stage = Math.max(0, Math.min(3, Number(currentStage) || 0))
  var width = Math.max(0, Number(availableWidth) || 0)
  var candidates = Array.isArray(stageWidths) ? stageWidths : []
  function need(index) {
    return Math.max(0, Number(candidates[index]) || 0)
  }

  if (width <= 0) return stage
  // The complete composition is allowed to use the complete measured width.
  // A provider swap can leave an exactly fitting layout inside the old
  // 24/48px hysteresis band and permanently hide G9/G10. Only enter compact
  // mode when the full budget genuinely exceeds the surface, and leave it as
  // soon as that complete budget fits again.
  if (stage === 0 && need(0) > width) stage = 1
  if (stage === 1 && need(1) + 24 > width) stage = 2
  if (stage === 2 && need(2) + 24 > width) stage = 3
  if (stage === 3 && need(2) + 48 <= width) stage = 2
  if (stage === 2 && need(1) + 48 <= width) stage = 1
  if (stage === 1 && need(0) <= width) stage = 0
  return stage
}

function centerAvailableWidth(compactShell, surfaceWidth, frameInset,
                              contentInset, leftWidth, rightWidth,
                              centerGap, measuredSpan) {
  if (!compactShell)
    return Math.max(0, Number(measuredSpan) || 0)

  // Fit, Dock and Notch are content-driven surfaces. Measuring their center
  // budget from the current shell width makes the responsive center feed back
  // into its own input: the compact stage shrinks the shell, which then keeps
  // weather hidden. Use the monitor-local surface capacity, as V2 does.
  return Math.max(0,
    (Number(surfaceWidth) || 0)
    - 2 * Math.max(0, Number(frameInset) || 0)
    - 2 * Math.max(0, Number(contentInset) || 0)
    - Math.max(0, Number(leftWidth) || 0)
    - Math.max(0, Number(rightWidth) || 0)
    - 2 * Math.max(0, Number(centerGap) || 0))
}
