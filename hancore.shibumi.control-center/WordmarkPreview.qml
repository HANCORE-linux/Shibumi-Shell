pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  property string value: "shibumi"
  property color foreground: "white"
  property string fontFamily: "monospace"

  readonly property bool shibumiWordmark: value === "shibumi"
  readonly property bool archWordmark: value === "arch"
  readonly property url imageSource: value === "hyprland"
    ? Qt.resolvedUrl("assets/bob3.png")
    : value === "omacom"
      ? Qt.resolvedUrl("assets/omacom-text.png")
      : Qt.resolvedUrl("assets/bob2.png")
  readonly property real imageAspect: value === "hyprland" ? 948 / 154
    : value === "omacom" ? 550 / 112 : 656 / 192

  implicitWidth: 110
  implicitHeight: 24
  clip: true

  Text {
    visible: root.shibumiWordmark
    anchors.centerIn: parent
    text: "SHIBUMI"
    color: root.foreground
    renderType: Text.NativeRendering
    font.family: root.fontFamily
    font.pixelSize: 10
    font.weight: Font.Medium
    font.letterSpacing: 1.2
  }

  Item {
    visible: root.archWordmark
    anchors.centerIn: parent
    width: Math.min(parent.width, 100)
    height: 19

    Row {
      anchors.centerIn: parent
      height: 15
      spacing: 3

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: root.foreground
        renderType: Text.QtRendering
        font.family: root.fontFamily
        font.pixelSize: 13
      }

      FlatTintedImage {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(height * 605 / 231)
        height: 11
        source: Qt.resolvedUrl("assets/arch-header-arch.png")
        tint: root.foreground
      }

      FlatTintedImage {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(height * 549 / 230)
        height: 11
        source: Qt.resolvedUrl("assets/arch-header-linux.png")
        tint: root.foreground
      }
    }
  }

  FlatTintedImage {
    visible: !root.shibumiWordmark && !root.archWordmark
    anchors.centerIn: parent
    height: root.value === "hyprland" ? 12
      : root.value === "omacom" ? 14 : 18
    width: Math.min(parent.width, Math.round(height * root.imageAspect))
    source: root.imageSource
    tint: root.foreground
  }
}
