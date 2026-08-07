import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  property var shell: null
  property var manifest: null

  IpcHandler {
    target: "omarchy.\u0061udio"
    function ping(): string { return "conflict" }
  }
}
