pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Row {
  id: root

  required property bool stockOmarchyHost
  required property bool v2LayoutActive
  required property var stateService
  required property color neutralColor
  required property string fontFamily

  readonly property color statusColor: stateService
    && typeof stateService.paletteColor === "function"
    ? stateService.paletteColor("color03") : Commons.Color.accent
  readonly property string statusText: stockOmarchyHost
    ? "OMARCHY BAR ACTIVE"
    : v2LayoutActive ? "SHIBUMI V2 ACTIVE" : "SHIBUMI V1 ACTIVE"
  readonly property alias renderedDotColor: statusDot.color
  readonly property alias renderedLabelColor: statusLabel.color

  spacing: Commons.Style.space(5)
  Accessible.role: Accessible.StaticText
  Accessible.name: statusText

  Text {
    id: statusDot
    anchors.verticalCenter: parent.verticalCenter
    text: "●"
    color: root.statusColor
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
  }

  Text {
    id: statusLabel
    anchors.verticalCenter: parent.verticalCenter
    text: root.statusText
    color: root.neutralColor
    opacity: 0.74
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.letterSpacing: 1.1
  }
}
