import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property bool focused
  required property bool occupied
  property bool hovered: false
  property real eatProgress: 0
  property int eatDirection: 1
  property color activeColor: "white"
  property color occupiedColor: "white"
  property color emptyColor: "white"
  property color hoverColor: "white"

  readonly property int glyphSize: Commons.Style.space(14)
  readonly property int pelletSize: Commons.Style.space(5)
  readonly property real eatOffset: Commons.Style.spaceReal(3)
  readonly property real boundedEatProgress:
    Math.max(0, Math.min(1, eatProgress))
  readonly property real hoverFactor:
    hovered && boundedEatProgress === 0 ? 1.08 : 1

  implicitWidth: Commons.Style.space(22)
  implicitHeight: Commons.Style.space(18)
  opacity: 1 - boundedEatProgress
  scale: (1 - 0.45 * boundedEatProgress) * hoverFactor
  transformOrigin: Item.Center
  transform: Translate {
    x: -root.eatDirection * root.eatOffset
      * root.boundedEatProgress
  }

  Behavior on scale {
    enabled: root.boundedEatProgress === 0
    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
  }

  Text {
    anchors.centerIn: parent
    visible: root.focused || root.occupied
    text: root.focused ? "󰮯" : "󰊠"
    color: root.hovered ? root.hoverColor
      : root.focused ? root.activeColor
      : root.occupiedColor
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: root.glyphSize
    font.weight: Font.Bold
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering

    Behavior on color {
      ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  Rectangle {
    id: emptyPellet

    visible: !root.focused && !root.occupied
    anchors.centerIn: parent
    width: root.pelletSize
    height: width
    radius: width / 2
    color: root.hovered ? root.hoverColor : root.emptyColor
    opacity: root.hovered ? 0.90 : 0.55
    antialiasing: true

    Behavior on color {
      ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }
}
