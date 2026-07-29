pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// One process-wide adapter over Quattro-owned status backends. Bar views never
// instantiate their own pollers, so multiple monitors consume the same state.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var actionRunner: null
  property bool runtimeProbesEnabled: true

  readonly property var idleService: shell
    && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property var notificationService: shell
    && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool stayAwake: idleService
    ? idleService.stayAwake === true : false
  readonly property bool notificationsSilenced: notificationService
    ? notificationService.doNotDisturb === true : false

  property string recordingPid: ""
  property int recordingElapsed: 0
  property int recordingBaseElapsed: 0
  property double recordingBaseMs: 0
  property bool recordingRefreshPending: false
  readonly property bool recording: recordingPid !== ""

  property string voxtypeState: "idle"
  property string voxtypeHint: ""
  property bool voxtypeAvailable: false
  readonly property bool voxtypeActive: voxtypeState === "recording"
    || voxtypeState === "transcribing"

  function toggleStayAwake() {
    if (!idleService || typeof idleService.setIdleEnabled !== "function") return false
    idleService.setIdleEnabled(stayAwake)
    return true
  }

  function toggleNotifications() {
    if (!notificationService
        || typeof notificationService.setDoNotDisturb !== "function") return false
    notificationService.setDoNotDisturb(!notificationsSilenced)
    return true
  }

  function stopRecording() {
    if (!recording) return false
    launch(["omarchy-capture-screenrecording", "--stop-recording"])
    if (runtimeProbesEnabled) recordingRetry.restart()
    return true
  }

  function openVoxtypeModel() {
    launch(["omarchy-voxtype-model"])
    return true
  }

  function openVoxtypeConfig() {
    launch(["omarchy-voxtype-config"])
    return true
  }

  function launch(command) {
    if (actionRunner && typeof actionRunner.run === "function")
      return actionRunner.run(command) !== false
    actionLauncher.command = command
    actionLauncher.startDetached()
    return true
  }

  function refreshRecording() {
    if (!runtimeProbesEnabled) return
    if (recordingProbe.running) {
      recordingRefreshPending = true
      return
    }
    recordingProbe.running = true
  }

  function setRecordingPid(value) {
    const next = String(value || "").trim()
    if (next === recordingPid) return
    recordingPid = next
    recordingElapsed = 0
    recordingBaseElapsed = 0
    recordingBaseMs = next ? Date.now() : 0
    if (!next) return
    recordingElapsedProbe.command = ["ps", "-o", "etimes=", "-p", next]
    recordingElapsedProbe.running = true
  }

  function updateRecordingElapsed() {
    if (!recording || recordingBaseMs <= 0) return
    recordingElapsed = recordingBaseElapsed
      + Math.floor((Date.now() - recordingBaseMs) / 1000)
  }

  function updateVoxtype(raw) {
    try {
      const data = JSON.parse(String(raw || "{}"))
      const next = String(data.alt || data.class || "idle")
      voxtypeState = next === "recording" || next === "transcribing"
        ? next : "idle"
      voxtypeHint = String(data.tooltip || "").split("\n")[0]
      voxtypeAvailable = true
    } catch (error) {
      voxtypeState = "idle"
      voxtypeHint = ""
    }
  }

  FileView {
    id: recordingState
    path: "/tmp/omarchy-screenrecord-filename"
    watchChanges: root.runtimeProbesEnabled
    printErrors: false
    onFileChanged: {
      reload()
      root.refreshRecording()
    }
    onLoaded: root.refreshRecording()
    onLoadFailed: root.refreshRecording()
  }

  Process {
    id: recordingProbe
    command: ["pgrep", "-o", "-f", "^gpu-screen-recorder"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.setRecordingPid(text)
    }
    onExited: {
      if (!root.recordingRefreshPending) return
      root.recordingRefreshPending = false
      Qt.callLater(root.refreshRecording)
    }
  }

  Process {
    id: recordingElapsedProbe
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const seconds = Math.max(0, parseInt(String(text || "").trim()) || 0)
        root.recordingBaseElapsed = seconds
        root.recordingElapsed = seconds
        root.recordingBaseMs = Date.now()
      }
    }
  }

  Timer {
    interval: 45000
    running: root.runtimeProbesEnabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshRecording()
  }

  Timer {
    id: recordingRetry
    interval: 900
    onTriggered: root.refreshRecording()
  }

  Timer {
    interval: 1000
    running: root.runtimeProbesEnabled && root.recording
    repeat: true
    triggeredOnStart: true
    onTriggered: root.updateRecordingElapsed()
  }

  Process {
    id: voxtypeStatus
    command: ["bash", "-lc", "exec omarchy-voxtype-status"]
    running: root.runtimeProbesEnabled
    stdout: SplitParser {
      onRead: function(data) { root.updateVoxtype(data) }
    }
    onExited: {
      root.voxtypeAvailable = false
      root.voxtypeState = "idle"
      root.voxtypeHint = ""
    }
  }

  Timer {
    interval: 60000
    running: root.runtimeProbesEnabled && !voxtypeStatus.running
    repeat: true
    onTriggered: voxtypeStatus.running = true
  }

  Process { id: actionLauncher }
}
