.pragma library

function nextStage(currentStage, availableWidth, needNormal, needCompact,
                   centered) {
  if (!centered || Number(availableWidth) <= 0) return 0

  var stage = Math.max(0, Math.min(2, Number(currentStage) || 0))
  var available = Math.max(0, Number(availableWidth) || 0)
  var normal = Math.max(0, Number(needNormal) || 0)
  var compact = Math.max(0, Number(needCompact) || 0)

  if (stage === 0 && normal + 24 > available) stage = 1
  if (stage === 1 && compact + 24 > available) stage = 2
  if (stage === 2 && compact + 48 <= available) stage = 1
  if (stage === 1 && normal + 48 <= available) stage = 0
  return stage
}
