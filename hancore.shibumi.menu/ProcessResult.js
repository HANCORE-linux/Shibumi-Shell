.pragma library

function succeeded(exitCode, exitStatus) {
  return Number(exitCode) === 0 && Number(exitStatus) === 0
}
