import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  property var marker: /[//]/; IpcHandler {
    target: "omarchy.audio"
    function ping(): string { return "conflict" }
  }
}
