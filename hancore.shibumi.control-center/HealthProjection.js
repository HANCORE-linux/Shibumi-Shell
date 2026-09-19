.pragma library

const ExternalRuntimeIds = [
  "runtime-errors", "runtime-errors-omarchy",
  "runtime-errors-third-party", "runtime-errors-unknown",
  "runtime-warnings", "runtime-warnings-omarchy",
  "runtime-warnings-third-party", "runtime-warnings-unknown"
]

function reportChecks(report) {
  return report && Array.isArray(report.checks) ? report.checks : []
}

function isOtherRuntimeFinding(check) {
  const status = String(check.status || "")
  return (status === "error" || status === "warning")
    && ExternalRuntimeIds.indexOf(String(check.id || "")) >= 0
    && String(check.owner || "unknown") !== "shibumi"
    && !(String(check.id || "") === "runtime-errors"
      && status === "warning" && check.value === "Log unavailable")
}

function primaryChecks(report) {
  return reportChecks(report).filter(function(check) {
    return !isOtherRuntimeFinding(check)
  })
}

function otherRuntimeChecks(report) {
  return reportChecks(report).filter(isOtherRuntimeFinding)
}
