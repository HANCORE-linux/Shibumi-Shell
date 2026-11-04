pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Text {
  id: root

  required property bool stockOmarchyHost
  required property string shellStyle
  required property string barPosition
  required property color neutralColor
  required property string fontFamily

  // Inputs describe the rendered host, never the pending settings draft.
  readonly property string styleName: stockOmarchyHost ? "Omarchy"
    : ({shibumi: "Default", full: "Full", fit: "Fit", notch: "Notch",
        dock: "Dock"})[shellStyle] || "Default"
  readonly property string positionName:
    ({top: "Top", bottom: "Bottom", left: "Left", right: "Right"})[barPosition] || "Top"
  readonly property string statusText: styleName + " · " + positionName
  readonly property alias renderedLabelColor: root.color

  text: statusText
  color: neutralColor
  opacity: 0.74
  font.family: fontFamily
  font.pixelSize: Commons.Style.font.caption
  font.letterSpacing: 0.2
  Accessible.role: Accessible.StaticText
  Accessible.name: statusText
}
