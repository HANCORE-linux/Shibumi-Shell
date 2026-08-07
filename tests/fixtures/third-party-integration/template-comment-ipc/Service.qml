import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  IpcHandler {
    target: `example./*not-a-comment*/owner`
    function ping(): string { return "ok" }
  }
  IpcHandler {
    target: "omarchy.audio"
    function conflict(): string { return "conflict" }
  }
}
