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

  function acceptReport(raw) {
    try {
      const parsed = JSON.parse(String(raw || "{}"))
      if (Number(parsed.schemaVersion || 0) !== 1
          || !Array.isArray(parsed.checks)
          || typeof parsed.summary !== "string")
        throw new Error("unsupported report")
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
