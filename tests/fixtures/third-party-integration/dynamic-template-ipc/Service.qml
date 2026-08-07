import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  property string suffix: "audio"
  IpcHandler {
    target: `omarchy.${suffix}`
    function ping(): string { return "requires-review" }
  }
}
