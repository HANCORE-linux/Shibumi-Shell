import QtQuick
import Quickshell
import "media" as Media

ShellRoot {
  id: root

  readonly property string mode: Quickshell.env("SHIBUMI_CAVA_TEST_MODE")
  property int phase: 0
  property int waits: 0
  property int failedStartCount: -1

  function fail(message) {
    console.error("media-spectrum-service-smoke:", mode + ": " + message)
    Qt.exit(1)
  }

  QtObject {
    id: player
    property bool isPlaying: true
  }

  QtObject {
    id: mediaState
    property var activePlayer: player
    readonly property bool hasMedia: activePlayer !== null
  }

  QtObject {
    id: fakeShell
    function firstPartyServiceFor(id) {
      return String(id || "") === "omarchy.media" ? mediaState : null
    }
  }

  QtObject { id: clientA }
  QtObject { id: clientB }

  Media.Service {
    id: spectrum
    shell: fakeShell
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.waits++
      if (root.waits > 180)
        return root.fail("timed out in phase " + root.phase)

      if (root.mode === "unavailable") {
        if (root.phase === 0) {
          if (spectrum.workerRunning || spectrum.clientCount !== 0
              || spectrum.workerStartCount !== 0)
            return root.fail("non-lazy initial state")
          spectrum.beginSpectrum(clientA)
          root.phase++
        } else if (spectrum.state === "unavailable") {
          if (spectrum.workerRunning || spectrum.workerStartCount !== 0
              || spectrum.clientCount !== 1)
            return root.fail("unavailable degraded state")
          spectrum.endSpectrum(clientA)
          stop()
          console.log("media spectrum unavailable smoke passed")
          Qt.quit()
        }
        return
      }

      if (root.mode === "failure") {
        if (root.phase === 0) {
          spectrum.beginSpectrum(clientA)
          root.phase++
        } else if (root.phase === 1
            && spectrum.failureCount === spectrum.maximumRetries
            && !spectrum.workerRunning && spectrum.state === "failed") {
          root.failedStartCount = spectrum.workerStartCount
          root.waits = 0
          root.phase++
        } else if (root.phase === 2 && root.waits >= 30) {
          if (root.failedStartCount !== spectrum.maximumRetries
              || spectrum.workerStartCount !== root.failedStartCount)
            return root.fail("bounded retry/backoff")
          spectrum.endSpectrum(clientA)
          stop()
          console.log("media spectrum failure smoke passed")
          Qt.quit()
        }
        return
      }

      if (root.phase === 0) {
        if (spectrum.workerRunning || spectrum.clientCount !== 0
            || spectrum.workerStartCount !== 0
            || spectrum.levels.length !== 24)
          return root.fail("non-lazy initial state")
        player.isPlaying = false
        spectrum.beginSpectrum(clientA)
        root.phase++
      } else if (root.phase === 1) {
        if (spectrum.clientCount !== 1 || spectrum.workerRunning)
          return root.fail("paused lease must remain worker-free")
        player.isPlaying = true
        root.phase++
      } else if (root.phase === 2) {
        if (!spectrum.workerRunning || spectrum.state !== "running"
            || spectrum.workerStartCount !== 1
            || Number(spectrum.levels[0]) < 0.24) return
        spectrum.beginSpectrum(clientB)
        root.phase++
      } else if (root.phase === 3) {
        if (!spectrum.workerRunning || spectrum.clientCount !== 2
            || spectrum.workerStartCount !== 1)
          return root.fail("multi-client single-worker lease")
        spectrum.endSpectrum(clientA)
        root.phase++
      } else if (root.phase === 4) {
        if (!spectrum.workerRunning || spectrum.clientCount !== 1
            || spectrum.workerStartCount !== 1)
          return root.fail("first lease release stopped shared worker")
        player.isPlaying = false
        root.phase++
      } else if (root.phase === 5) {
        if (spectrum.workerRunning) return
        if (spectrum.state !== "inactive" || spectrum.clientCount !== 1)
          return root.fail("pause cleanup")
        player.isPlaying = true
        root.phase++
      } else if (root.phase === 6) {
        if (!spectrum.workerRunning || spectrum.state !== "running"
            || spectrum.workerStartCount !== 2) return
        spectrum.endSpectrum(clientB)
        root.phase++
      } else if (root.phase === 7) {
        if (spectrum.workerRunning) return
        if (spectrum.clientCount !== 0 || spectrum.state !== "inactive")
          return root.fail("final lease cleanup")
        stop()
        console.log("media spectrum service smoke passed")
        Qt.quit()
      }
    }
  }
}
