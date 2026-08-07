import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  property var shell: null
  property var manifest: null

  IpcHandler {
    target: "example.conforming.ipc"
    function ping(): string { return "ok" }
  }
  IpcHandler {
    target: "example.conforming.service-owner"
    function ping(): string { return "ok" }
  }
  IpcHandler {
    target: "example.conforming.layer-owner"
    function ping(): string { return "ok" }
  }
}
