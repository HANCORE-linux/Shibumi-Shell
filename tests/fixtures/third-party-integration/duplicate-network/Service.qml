import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  property var shell: null
  property var manifest: null

  IpcHandler {
    target: "omarchy.network"
    function ping(): string { return "conflict" }
  }
}
