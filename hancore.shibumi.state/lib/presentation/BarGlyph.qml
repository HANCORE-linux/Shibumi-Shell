import QtQuick
import qs.Commons as Commons

// A paint-only optical glyph. The hidden native Text reserves the original
// advance and line box, so the enclosing widget and its hit targets never grow.
Item {
  id: root

  property string text: ""
  property color color: "white"
  property font font
  font.family: "Material Symbols Rounded"
  font.pixelSize: 13
  property real fill: 0
  property bool optical: true
  property bool centerInkY: true
  property bool nativeLineBox: false
  property real inkCenterY: height / 2
  property bool compactInk: false
  property int referencePixelSize: font.pixelSize
  property int renderType: Text.QtRendering
  property int horizontalAlignment: Text.AlignHCenter
  property int paintPixelSize: optical && compactInk
    ? Math.max(1, Math.min(font.pixelSize, Math.floor(font.pixelSize
        * (Commons.Style.bar.iconFont - 1) / Math.max(1, seed.tightBoundingRect.height))))
    : font.pixelSize
  readonly property real inkLeft: glyph.x + ink.tightBoundingRect.x
  readonly property real inkRight: inkLeft + ink.tightBoundingRect.width

  implicitWidth: reference.implicitWidth
  implicitHeight: reference.implicitHeight

  function fontAt(size) {
    return Qt.font({ family: font.family, pixelSize: size, weight: font.weight,
      italic: font.italic, letterSpacing: font.letterSpacing,
      wordSpacing: font.wordSpacing, capitalization: font.capitalization,
      variableAxes: font.family === "Material Symbols Rounded" ? { FILL: fill } : ({}) })
  }

  Text {
    id: reference
    visible: false
    text: root.text
    font: root.fontAt(root.referencePixelSize)
    renderType: root.renderType
  }

  TextMetrics { id: seed; text: root.text; font: root.fontAt(root.font.pixelSize) }
  TextMetrics { id: ink; text: root.text; font: glyph.font }

  Text {
    id: glyph
    text: root.text
    color: root.color
    font: root.fontAt(root.optical ? root.paintPixelSize : root.referencePixelSize)
    renderType: root.optical ? Text.NativeRendering : root.renderType
    // Tight bounds correct only paint. No per-symbol offset or texture scale.
    x: !root.optical ? 0 : (root.horizontalAlignment === Text.AlignLeft ? 0
      : root.horizontalAlignment === Text.AlignRight ? root.width - ink.tightBoundingRect.width
      : (root.width - ink.tightBoundingRect.width) / 2)
      - ink.tightBoundingRect.x - root.anchors.horizontalCenterOffset
    // P8's native line-box centering for token-calibrated glyph sizes. Ligature
    // tight vertical bounds include blank baseline space and cannot center ink.
    y: !root.optical ? 0 : root.nativeLineBox
      ? Math.round(root.inkCenterY - implicitHeight / 2) : root.centerInkY
      ? root.inkCenterY - glyph.baselineOffset
        - ink.tightBoundingRect.y - ink.tightBoundingRect.height / 2
      : Math.floor((root.height - implicitHeight) / 2)
  }
}
