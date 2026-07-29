pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
  id: root

  property url source
  property color tint: "white"
  property size sourceSize: Qt.size(0, 0)
  property bool smooth: true
  property bool mipmap: true

  Image {
    id: sourceImage
    anchors.fill: parent
    visible: false
    source: root.source
    sourceSize: root.sourceSize
    fillMode: Image.PreserveAspectFit
    cache: true
    smooth: root.smooth
    mipmap: root.mipmap
  }

  MultiEffect {
    anchors.fill: parent
    source: sourceImage
    colorization: 1
    colorizationColor: root.tint
  }
}
