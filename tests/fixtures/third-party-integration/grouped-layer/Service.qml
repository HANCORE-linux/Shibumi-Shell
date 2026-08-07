import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  visible: false
  WlrLayershell {
    namespace: "shibumi-bar"
    layer: WlrLayer.Top
  }
}
