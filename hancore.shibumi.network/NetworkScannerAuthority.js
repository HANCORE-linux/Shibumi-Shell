.pragma library

// One scanner mutation authority per QML engine. The short-lived guard is
// parented to its lease component; claim() discards a stale destroyed guard.
// Cross-engine overlap is separately guarded by the native gateway's
// foreign-scanner conflict protocol.
var currentClaim = 0
var currentGuard = null
var nextClaim = 1

function guardAlive() {
  try {
    return currentGuard !== null && currentGuard.authorityAlive === true
  } catch (error) {
    return false
  }
}

function claim(guard) {
  if (!guard) return 0
  if (currentClaim !== 0 && guardAlive()) return 0
  currentClaim = 0
  currentGuard = null

  var token = nextClaim++
  if (token <= 0 || !isFinite(token)) {
    nextClaim = 2
    token = 1
  }
  currentClaim = token
  currentGuard = guard
  return token
}

function block(token) {
  if (typeof token !== "number" || token !== currentClaim) return
  // A destroyed generation that could not disable its scanner must not hand
  // mutation authority to another owner. The QML engine teardown eventually
  // discards this library state; cross-engine owners still see the foreign
  // scannerEnabled conflict and remain closed.
  currentGuard = ({ authorityAlive: true, blocked: true })
}

function release(token) {
  if (typeof token !== "number" || token !== currentClaim) return
  currentClaim = 0
  currentGuard = null
}
