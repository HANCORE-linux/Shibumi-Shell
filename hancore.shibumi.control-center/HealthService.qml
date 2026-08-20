pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string healthCommand: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/hancore.shibumi.control-center"
    + "/manager/shibumi-health"
  property var report: ({
    schemaVersion: 1,
    generatedEpoch: 0,
    overall: "loading",
    summary: "Not checked yet",
    fetchRequested: false,
    installOrigin: "unknown",
    suiteVersion: "unknown",
    packageName: "",
    packageVersion: "",
    checks: []
  })
  property string failure: ""
  property bool fetching: false
  readonly property bool running: healthProbe.running
  readonly property int generatedEpoch: Number(report.generatedEpoch || 0)

  width: 0
  height: 0
  visible: false

  function runChecks(fetchUpdates) {
    if (healthProbe.running || healthCommand === "") return false
    fetching = fetchUpdates === true
    failure = ""
    healthProbe.command = [
      "timeout", "--signal=TERM", "--kill-after=1s", "16s",
      healthCommand
    ].concat(fetching ? ["--fetch"] : [])
    healthProbe.running = true
    return true
  }

  function ensureFresh(maxAgeSeconds) {
    const ageLimit = Math.max(0, Number(maxAgeSeconds || 0))
    const now = Math.floor(Date.now() / 1000)
    if (generatedEpoch > 0 && now - generatedEpoch <= ageLimit)
      return false
    return runChecks(false)
  }

  function sanitizeDiagnosticText(value, limit) {
    let text = String(value || "")
      .replace(/\u0000/g, "")
    const containsSensitive = /authorization|cookie|credential|password|secret|ssid|token/i
      .test(text)
    text = text
      .replace(/\r/g, "")
      .replace(/\/home\/[^\/\s]+/g, "~")
      .replace(/\b(?:https?|ftp):\/\/[^\s]+/gi, "[URL redacted]")
      .replace(/\b(?:bearer|basic)\s+[^\s]+/gi,
        "[authorization redacted]")
      .replace(/\b(?:password|passwd|passphrase|token|secret|cookie|credential|ssid|authorization)\b\s*["']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,}]+)/gi,
        "[sensitive value redacted]")
    if (containsSensitive
        || /authorization|cookie|credential|password|secret|ssid|token/i.test(text))
      return "[sensitive diagnostic redacted]"
    const max = Math.max(1, Number(limit || 320))
    return text.length <= max ? text : text.slice(0, max - 1) + "…"
  }

  function acceptReport(raw) {
    try {
      const parsed = JSON.parse(String(raw || "{}"))
      const owners = ["shibumi", "omarchy", "third-party", "unknown"]
      const statuses = ["ok", "warning", "error", "info"]
      if (Number(parsed.schemaVersion || 0) !== 1
          || !Array.isArray(parsed.checks)
          || typeof parsed.summary !== "string")
        throw new Error("unsupported report")
      parsed.checks = parsed.checks.map(function(check) {
        if (!check || typeof check !== "object"
            || typeof check.id !== "string"
            || typeof check.status !== "string"
            || statuses.indexOf(check.status) < 0)
          throw new Error("invalid check")
        if (check.owner !== undefined
            && (typeof check.owner !== "string"
              || owners.indexOf(check.owner) < 0))
          throw new Error("invalid check owner")
        const normalized = Object.assign({}, check)
        normalized.owner = check.owner === undefined ? "unknown" : check.owner
        const rawDiagnostic = String(check.value || "") + " "
          + String(check.detail || "") + " "
          + String(check.component || "") + " "
          + String(check.sourcePath || "") + " "
          + String(check.action || "")
        const sensitive = /authorization|cookie|credential|password|secret|ssid|token/i
          .test(rawDiagnostic)
        normalized.label = root.sanitizeDiagnosticText(check.label, 160)
        normalized.value = root.sanitizeDiagnosticText(check.value, 160)
        normalized.detail = root.sanitizeDiagnosticText(check.detail, 900)
        normalized.component = root.sanitizeDiagnosticText(check.component, 240)
        normalized.action = root.sanitizeDiagnosticText(check.action, 240)
        normalized.sourcePath = root.sanitizeDiagnosticText(
          check.sourcePath, 240)
        normalized.pluginId = root.sanitizeDiagnosticText(check.pluginId, 240)
        normalized.upstream = root.sanitizeDiagnosticText(check.upstream, 240)
        normalized.issueEligible = normalized.owner === "shibumi"
          && check.issueEligible === true && !sensitive
        return normalized
      })
      report = parsed
      failure = ""
      return true
    } catch (_error) {
      failure = "Health returned an invalid report."
      return false
    }
  }

  Process {
    id: healthProbe
    running: false
    stdout: StdioCollector {
      id: healthStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: healthStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0)
        root.acceptReport(healthStdout.text)
      else
        root.failure = exitCode === 124
          ? "Health check timed out."
          : "Health check failed (exit " + exitCode + ")."
      root.fetching = false
    }
  }
}
