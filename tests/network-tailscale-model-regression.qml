import QtQuick
import Quickshell
import "network/NetworkTailscaleModel.js" as Model

ShellRoot {
  id: root

  function fail(message) {
    console.error("network-tailscale-model-regression:", message)
    Qt.exit(1)
  }

  function peer(id, host, ip, online, exitOption, exitNode) {
    return {
      ID: id, HostName: host, DNSName: host + ".example.ts.net.",
      TailscaleIPs: [ip, "fd7a:115c:a1e0::" + id], OS: "linux",
      Online: online, ExitNodeOption: exitOption, ExitNode: exitNode
    }
  }

  function status(backendState, peers) {
    const map = {}
    for (let index = 0; index < peers.length; index++)
      map["nodekey:" + index] = peers[index]
    return JSON.stringify({
      BackendState: backendState,
      CurrentTailnet: { Name: "example.org" },
      Self: {
        HostName: "laptop", DNSName: "laptop.example.ts.net.",
        TailscaleIPs: ["100.64.0.1", "fd7a:115c:a1e0::1"]
      },
      Peer: map
    })
  }

  Timer {
    interval: 0
    running: true
    onTriggered: root.run()
  }

  function run() {
    const running = Model.parseStatus(status("Running", [
      peer("1", "zeta", "100.64.0.9", false, false, false),
      peer("2", "alpha", "100.64.0.2", true, false, false),
      peer("3", "exit", "100.64.0.3", true, true, true),
      peer("4", "relay", "100.64.0.4", true, true, false)
    ]))
    if (!running.available || !running.running || running.needsLogin)
      fail("running status was not admitted")
    if (running.tailnet !== "example.org" || running.selfName !== "laptop"
        || running.selfIp !== "100.64.0.1"
        || running.selfDnsName !== "laptop.example.ts.net")
      fail("self identity was not parsed")
    if (running.peers.length !== 4 || running.onlineCount !== 3)
      fail("peer counts are wrong")
    if (running.peers[0].name !== "exit" || running.peers[3].name !== "zeta")
      fail("peers are not ordered exit node, online, offline")
    if (running.exitNodeIp !== "100.64.0.3" || running.exitNodeName !== "exit")
      fail("active exit node was not detected")

    if (Model.exitNodeTarget(running, "100.64.0.4") !== "100.64.0.4")
      fail("advertised exit node was rejected")
    if (Model.exitNodeTarget(running, "") !== "")
      fail("clearing the exit node was rejected")
    if (Model.exitNodeTarget(running, "100.64.0.2") !== null)
      fail("peer without exit-node offer was accepted")
    if (Model.exitNodeTarget(running, "--accept-routes") !== null)
      fail("flag-shaped exit node was accepted")

    const stopped = Model.parseStatus(status("Stopped", []))
    if (!stopped.available || stopped.running
        || Model.stateLabel(stopped) !== "Disconnected")
      fail("stopped status is wrong")
    if (Model.exitNodeTarget(stopped, "") !== null)
      fail("exit node change accepted while stopped")

    const login = Model.parseStatus(status("NeedsLogin", []))
    if (!login.needsLogin || Model.stateLabel(login) !== "Needs login")
      fail("login state is wrong")

    if (Model.parseStatus("not json").available
        || Model.parseStatus("").available
        || Model.parseStatus("[]").available)
      fail("malformed status was admitted")

    const hostile = Model.parseStatus(status("Running", [
      peer("5", "<img src=x>\u0007" + "a".repeat(400), "999.1.1.1",
        true, true, false)
    ]))
    const row = hostile.peers[0]
    if (row.name.indexOf("\u0007") >= 0 || row.name.length > 63)
      fail("peer name is not bounded and sanitized")
    if (row.ip !== "" || row.exitNodeOption)
      fail("invalid IPv4 address was admitted")

    if (Model.copyableText("100.64.0.2") !== "100.64.0.2"
        || Model.copyableText("$(reboot)") !== ""
        || Model.copyableText("a b") !== "")
      fail("copy text validation is wrong")

    if (Model.actionError("Error: Access denied: prefs write access denied")
        .indexOf("--operator") < 0)
      fail("operator guidance missing from permission error")
    if (Model.probeFailure("failed to connect to local tailscaled") !== "daemon")
      fail("daemon failure not classified")
    if (Model.stateLabel(Model.emptySnapshot("missing")) !== "Not installed")
      fail("missing CLI label is wrong")

    console.log("network tailscale model regression passed")
    Qt.exit(0)
  }
}
