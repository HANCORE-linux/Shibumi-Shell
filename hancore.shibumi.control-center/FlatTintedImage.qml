pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  property url source
  property color tint: "white"

  Image {
    anchors.fill: parent
    source: root.source
    fillMode: Image.PreserveAspectFit
    cache: false
    smooth: true
    mipmap: true
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.max(1, Math.round(width * 3)),
      Math.max(1, Math.round(height * 3)))
    layer.effect: ShaderEffect {
      property color tintColor: root.tint
      fragmentShader: Qt.resolvedUrl("assets/logo-tint.frag.qsb")
    }
  }
}
