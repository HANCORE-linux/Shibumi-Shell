import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
  property var shell: null
  property var manifest: null

  IpcHandler {
    target: "shibumi-suite"
    function ping(): string { return "conflict" }
  }

  // A literal representative of the real hancore.shibumi.bar BarPanel layer.
  // The integration gate must reject it before this surface can be created.
  PanelWindow {
    visible: false
    WlrLayershell.namespace: "shibumi-bar"
    WlrLayershell.layer: WlrLayer.Top
  }
}
