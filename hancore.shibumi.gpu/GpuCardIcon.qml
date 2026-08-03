import QtQuick

Item {
  id: root

  property color color: "white"

  implicitWidth: 20
  implicitHeight: 14
  readonly property real artworkScale: width > 0 && height > 0
    ? Math.min(width / implicitWidth, height / implicitHeight) : 0

  // Preserve the approved 20x14 pixel drawing at the default theme scale, but
  // transform the complete artwork as one unit when the host spacing scale
  // changes. Scaling individual coordinates independently would distort the
  // card aspect ratio and separate its one-pixel contour segments.
  Item {
    id: artwork

    objectName: "gpuCardArtwork"
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    width: root.implicitWidth
    height: root.implicitHeight
    scale: root.artworkScale

    Rectangle {
      x: 3
      y: 2
      width: 15
      height: 10
      radius: 1.5
      color: "transparent"
      border.width: 1
      border.color: root.color
      antialiasing: true
    }

    Rectangle {
      x: 1
      y: 3
      width: 2
      height: 8
      radius: 0.75
      color: "transparent"
      border.width: 1
      border.color: root.color
      antialiasing: true
    }

    Rectangle {
      x: 12
      y: 11
      width: 4
      height: 2
      radius: 0.75
      color: "transparent"
      border.width: 1
      border.color: root.color
      antialiasing: true
    }

    Rectangle {
      x: 6
      y: 4.5
      width: 5
      height: 5
      radius: 2.5
      color: "transparent"
      border.width: 1
      border.color: root.color
      antialiasing: true
    }

    Rectangle {
      x: 8
      y: 6.5
      width: 1
      height: 1
      radius: 0.5
      color: root.color
      antialiasing: true
    }

    Rectangle {
      x: 13
      y: 5
      width: 3
      height: 1
      radius: 0.5
      color: root.color
      antialiasing: true
    }

    Rectangle {
      x: 13
      y: 8
      width: 3
      height: 1
      radius: 0.5
      color: root.color
      antialiasing: true
    }
  }
}
