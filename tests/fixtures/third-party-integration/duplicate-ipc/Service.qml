import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  property var shell: null
  property var manifest: null

  IpcHandler {
    target: "omarchy.audio"
    function ping(): string { return "conflict" }
  }
}
