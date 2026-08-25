.pragma library

var nextClaim = 1
var currentClaim = 0
var currentGuard = null
var permanentlyBlocked = false

function claim(guard) {
  if (permanentlyBlocked || !guard || guard.alive !== true) return 0
  if (currentClaim !== 0) {
    if (currentGuard && currentGuard.alive === true) return 0
    currentClaim = 0
    currentGuard = null
  }
  const token = nextClaim++
  if (nextClaim > 2147483646) nextClaim = 1
  currentClaim = token
  currentGuard = guard
  return token
}

function release(token) {
  if (token !== currentClaim) return false
  currentClaim = 0
  currentGuard = null
  return true
}

function block(token) {
  if (token !== currentClaim) return false
  permanentlyBlocked = true
  currentClaim = 0
  currentGuard = null
  return true
}
