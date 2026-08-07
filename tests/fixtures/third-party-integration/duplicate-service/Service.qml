import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  property var shell: null
  property var manifest: null

  // This is the actual process-global target owned by
  // hancore.shibumi.state/Service.qml.
  IpcHandler {
    target: "shibumi-suite-runtime"
    function ping(): string { return "conflict" }
  }
}
