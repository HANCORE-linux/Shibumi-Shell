import QtQuick
import QtQuick.Effects
import "../hancore.shibumi.state/lib/presentation" as Presentation

// The original pixel mark, rasterized at its native grid before nearest sampling.
Item {
  id: root
  required property color baseColor
  required property color fillColor
  required property real baseOpacity
  required property real usageFraction

  Presentation.BarInk { id: placement; target: root }
  Item {
    id: paint
    width: Math.round(root.width * placement.dpr) / placement.dpr
    height: Math.round(width * placement.dpr * 14 / 22) / placement.dpr
    x: placement.snapX((root.width - width) / 2)
    y: placement.rectangleY(height)

    Image {
      id: mark
      anchors.fill: parent
      visible: false
      source: Qt.resolvedUrl("assets/opencode-mark.svg")
      // Qt scales SVG requests by DPR before rasterizing them.
      sourceSize: Qt.size(Math.max(1, Math.round(22 / placement.dpr)),
        Math.max(1, Math.round(14 / placement.dpr)))
      fillMode: Image.Stretch
      smooth: false
      mipmap: false
    }
    MultiEffect {
      anchors.fill: parent
      source: mark
      colorization: 1
      colorizationColor: Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, 1)
      opacity: root.baseColor.a * root.baseOpacity
    }
    Item {
      anchors.bottom: parent.bottom
      width: parent.width
      height: Math.round(parent.height * root.usageFraction * placement.dpr) / placement.dpr
      clip: true
      Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
      MultiEffect {
        anchors.bottom: parent.bottom
        width: paint.width
        height: paint.height
        source: mark
        colorization: 1
        colorizationColor: Qt.rgba(root.fillColor.r, root.fillColor.g, root.fillColor.b, 1)
        opacity: root.fillColor.a
      }
    }
  }
}
