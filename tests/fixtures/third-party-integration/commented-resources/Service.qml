import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  property var shell: null
  property var manifest: null

  // IpcHandler { target: 'omarchy.audio' }
  /*
    WlrLayershell.namespace: "shibumi-bar"
    IpcHandler {
      target: "shibumi-suite-runtime"
    }
  */
  IpcHandler {
    target: 'example.commented-resources.ipc'
    function ping(): string { return 'ok' }
  }
}
