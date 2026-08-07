import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  IpcHandler {
    target: `omarchy.audio`
    function ping(): string { return "conflict" }
  }
}
