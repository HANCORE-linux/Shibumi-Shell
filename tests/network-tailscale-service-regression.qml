import QtQuick
import Quickshell
import Quickshell.Io
import "network" as Network

ShellRoot {
  id: root

  readonly property string logPath: Quickshell.env("SHIBUMI_TAILSCALE_LOG")
  property int step: 0

  function fail(message) {
    console.error("network-tailscale-service-regression:", message)
    Qt.exit(1)
  }

  Network.NetworkTailscale { id: tailscale }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (++root.step > 80) root.fail("timed out at phase " + phase.state)
      phase.advance()
    }
  }

  QtObject {
    id: phase
    property string state: "initial"

    function advance() {
      const snapshot = tailscale.snapshot
      if (state === "initial") {
        if (!snapshot.available || tailscale.busy) return
        if (snapshot.running || snapshot.backendState !== "Stopped")
          root.fail("stopped fixture was not parsed")
        if (tailscale.setExitNode("100.64.0.3"))
          root.fail("exit node accepted while stopped")
        if (!tailscale.setEnabled(true)) root.fail("up was rejected")
        state = "up"
      } else if (state === "up") {
        if (tailscale.busy || !snapshot.running) return
        if (snapshot.peers.length !== 2 || snapshot.onlineCount !== 1)
          root.fail("running peers were not parsed")
        if (tailscale.setExitNode("100.64.0.4"))
          root.fail("non exit node accepted")
        if (!tailscale.setExitNode("100.64.0.3"))
          root.fail("advertised exit node rejected")
        state = "exit"
      } else if (state === "exit") {
        if (tailscale.busy) return
        if (tailscale.errorText !== "")
          root.fail("exit node action failed: " + tailscale.errorText)
        if (!tailscale.setEnabled(false)) root.fail("down was rejected")
        state = "down"
      } else if (state === "down") {
        if (tailscale.busy || snapshot.running) return
        state = "done"
        logReader.reload()
      }
    }
  }

  FileView {
    id: logReader
    path: root.logPath
    blockLoading: true
    onLoaded: {
      if (phase.state !== "done") return
      const lines = text().trim().split("\n")
      for (const expected of ["up", "set --exit-node=100.64.0.3", "down"])
        if (lines.indexOf(expected) < 0)
          root.fail("missing CLI call: " + expected)
      for (const line of lines)
        if (line !== "status --json" && line !== "up" && line !== "down"
            && line !== "set --exit-node=100.64.0.3")
          root.fail("unexpected CLI call: " + line)
      console.log("network tailscale service regression passed")
      Qt.exit(0)
    }
  }
}
