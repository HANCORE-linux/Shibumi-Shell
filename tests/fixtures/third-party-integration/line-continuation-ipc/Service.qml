import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  IpcHandler {
    target: "omarchy.au\
dio"
    function ping(): string { return "conflict" }
  }
}
