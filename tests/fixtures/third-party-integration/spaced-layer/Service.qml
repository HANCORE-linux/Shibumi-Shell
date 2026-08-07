import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  visible: false
  WlrLayershell . namespace: "shibumi-bar"
  WlrLayershell.layer: WlrLayer.Top
}
