.pragma library

// Sample the original pulse sequences, including their first-cycle start and
// last-to-first transitions. No animation driver or clock belongs to a primitive.
var pulseDurations = [[220, 300, 260, 280], [310, 280, 340, 290], [380, 320, 350, 400]]
var pulseTargets = [[0.85, 0.18, 0.70, 0.10], [0.45, 0.92, 0.28, 0.65], [0.60, 0.12, 0.95, 0.32]]

function pulse(milliseconds, band, firstLevel) {
  const durations = pulseDurations[band], targets = pulseTargets[band]
  const period = durations.reduce(function(sum, value) { return sum + value }, 0)
  let time = milliseconds % period
  let from = milliseconds < period
    ? (firstLevel === undefined ? 0.08 : firstLevel) : targets[3]
  for (let index = 0; index < durations.length; index++) {
    if (time <= durations[index]) {
      const eased = (1 - Math.cos(Math.PI * time / durations[index])) / 2
      return from + (targets[index] - from) * eased
    }
    time -= durations[index]
    from = targets[index]
  }
  return targets[3]
}

function pulseRest(milliseconds, band, from) {
  const duration = [380, 430, 480][band]
  const remaining = 1 - Math.min(1, Math.max(0, milliseconds) / duration)
  return 0.08 + (from - 0.08) * remaining * remaining * remaining
}

function sameLevels(left, right) {
  if (!left || !right || left.length !== right.length) return false
  for (let index = 0; index < left.length; index++)
    if (left[index] !== right[index]) return false
  return true
}
