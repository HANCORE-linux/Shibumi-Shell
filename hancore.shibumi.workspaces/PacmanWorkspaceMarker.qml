import QtQuick

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

  implicitWidth: 22
  implicitHeight: 18
  opacity: 1 - Math.max(0, Math.min(1, eatProgress))
  scale: 1 - 0.45 * Math.max(0, Math.min(1, eatProgress))
  transformOrigin: Item.Center
  transform: Translate {
    x: -root.eatDirection * 3 * Math.max(0, Math.min(1, root.eatProgress))
  }

  Text {
    anchors.centerIn: parent
    visible: root.focused || root.occupied
    text: root.focused ? "󰮯" : "󰊠"
    color: root.hovered ? root.hoverColor
      : root.focused ? root.activeColor
      : root.occupiedColor
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: 14
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
    width: 5
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
