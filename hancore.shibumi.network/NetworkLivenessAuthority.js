.pragma library

var nextClaim = 1
var currentClaim = 0
var currentGuard = null
// Deliberately persists across same-engine component replacement. The QML
// PersistentProperties latch additionally spans soft engine reloads; only a
// complete Quickshell process restart can establish backend continuity again.
var continuityBlocked = false

function claim(guard) {
  if (!guard || guard.authorityAlive !== true)
    return { token: 0, continuityBlocked: true }
  if (currentClaim !== 0) {
    if (currentGuard && currentGuard.authorityAlive === true)
      return { token: 0, continuityBlocked: continuityBlocked }
    currentClaim = 0
    currentGuard = null
    continuityBlocked = true
  }
  const token = nextClaim++
  if (nextClaim > 9007199254740991) nextClaim = 1
  currentClaim = token
  currentGuard = guard
  return { token: token, continuityBlocked: continuityBlocked }
}

function retire(token, taintContinuity) {
  if (typeof token !== "number" || token !== currentClaim) return
  if (taintContinuity === true) continuityBlocked = true
  currentClaim = 0
  currentGuard = null
}
