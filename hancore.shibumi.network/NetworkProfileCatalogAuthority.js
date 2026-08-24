.pragma library

var nextClaim = 1
var currentClaim = 0
var currentGuard = null

function claim(guard) {
  if (!guard || guard.authorityAlive !== true) return 0
  if (currentClaim !== 0) {
    if (currentGuard && currentGuard.authorityAlive === true) return 0
    currentClaim = 0
    currentGuard = null
  }
  const token = nextClaim++
  if (nextClaim > 9007199254740991) nextClaim = 1
  currentClaim = token
  currentGuard = guard
  return token
}

function release(token) {
  if (typeof token !== "number" || token !== currentClaim) return
  currentClaim = 0
  currentGuard = null
}
