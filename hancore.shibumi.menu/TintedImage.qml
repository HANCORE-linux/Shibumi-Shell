pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
  id: root

  property url source
  property color tint: "white"

  Image {
    id: sourceImage
    anchors.fill: parent
    visible: false
    source: root.source
    fillMode: Image.PreserveAspectFit
    cache: true
    smooth: true
    mipmap: true
  }

  MultiEffect {
    anchors.fill: parent
    source: sourceImage
    colorization: 1
    colorizationColor: root.tint
  }
}
