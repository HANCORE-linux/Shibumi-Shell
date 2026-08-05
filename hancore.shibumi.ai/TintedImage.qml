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
  readonly property color opaqueTint: Qt.rgba(
    tint.r, tint.g, tint.b, 1)

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
    // MultiEffect uses colorizationColor.a as color-mix strength, not output
    // opacity. Keep the tint fully colorized and apply alpha to the item.
    opacity: root.tint.a
    colorization: 1
    colorizationColor: root.opaqueTint
  }
}
