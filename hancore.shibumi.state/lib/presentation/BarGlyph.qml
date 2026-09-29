import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "BarSymbols.js" as Symbols

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
  property string paintText: text
  property bool symbol: true
  property string nativeText: Symbols.glyph(paintText)
  property real symbolRotation: 0
  property int paintWeight: font.family === "Material Symbols Rounded"
    ? Font.Medium : font.weight
  property real paintFill: 0
  property bool optical: true
  property bool centerInkY: true
  property bool nativeLineBox: font.family === "Material Symbols Rounded"
  property real inkCenterY: height / 2
  property bool compactInk: false
  property int referencePixelSize: font.pixelSize
  property int renderType: Text.QtRendering
  property int horizontalAlignment: Text.AlignHCenter
  property int paintPixelSize: font.pixelSize
  readonly property rect symbolInk: {
    void(symbolCanvas.x)
    void(symbolCanvas.y)
    void(symbolCanvas.rotation)
    return symbolCanvas.mapToItem(root, Qt.rect(
      nativeGlyph.paintedCenterX - nativeGlyph.tightWidth / 2,
      nativeGlyph.baselineY + nativeInk.tightBoundingRect.y,
      nativeGlyph.tightWidth, nativeInk.tightBoundingRect.height))
  }
  readonly property real inkLeft: symbol ? symbolInk.x
    : glyph.x + ink.tightBoundingRect.x
  readonly property real inkRight: symbol ? symbolInk.x + symbolInk.width
    : inkLeft + ink.tightBoundingRect.width
  readonly property real inkTop: symbol ? symbolInk.y
    : glyph.y + glyph.baselineOffset + ink.tightBoundingRect.y
  // Status badges share one height while retaining the ink-relative x overlap.
  readonly property real badgeLeft: Math.ceil(inkRight) - Commons.Style.space(3)

  function badgeY(owner, badge) {
    for (let item = badge.parent; item && item !== owner; item = item.parent) {
      void(item.y)
      void(item.height)
    }
    return owner.mapToItem(badge.parent, 0, Math.round(owner.height / 2)
      - Commons.Style.space(7) - Math.round(badge.height / 2)).y
  }

  implicitWidth: reference.implicitWidth
  implicitHeight: reference.implicitHeight

  function connectionIcon(kind, strength) {
    return Symbols.connectionIcon(kind, strength)
  }

  function batteryIcon(percent, charging, full) {
    return Symbols.batteryIcon(percent, charging, full)
  }

  function verticalBatteryIcon(percent, charging, full) {
    return Symbols.verticalBatteryIcon(percent, charging, full)
  }

  function outputIcon(volume, muted, ready) {
    return Symbols.outputIcon(volume, muted, ready)
  }

  function fontAt(size, paint) {
    return Qt.font({ family: font.family, pixelSize: size,
      weight: paint ? paintWeight : font.weight,
      italic: font.italic, letterSpacing: font.letterSpacing,
      wordSpacing: font.wordSpacing, capitalization: font.capitalization,
      variableAxes: font.family === "Material Symbols Rounded"
        ? { FILL: paint ? paintFill : fill } : ({}) })
  }

  Text {
    id: reference
    visible: false
    text: root.text
    font: root.fontAt(root.referencePixelSize)
    renderType: root.renderType
  }

  TextMetrics { id: ink; text: glyph.text; font: glyph.font }
  TextMetrics {
    id: nativeInk
    text: root.nativeText
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.bar.iconFont
  }

  // The host renderer owns font, size, baseline and horizontal ink correction.
  // The old Text above reserves layout only; panels do not use this component.
  Item {
    id: symbolCanvas
    visible: root.symbol
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    width: Commons.Style.bar.iconCanvas
    height: Commons.Style.bar.iconCanvas
    rotation: root.symbolRotation

    Ui.OpticalGlyph {
      id: nativeGlyph
      anchors.fill: parent
      text: root.nativeText
      fontFamily: Commons.Style.font.family
      fontSize: Commons.Style.bar.iconFont
      color: root.color
    }
  }

  Text {
    id: glyph
    visible: !root.symbol
    text: root.optical ? root.paintText : root.text
    color: root.color
    font: root.fontAt(root.optical ? root.paintPixelSize : root.referencePixelSize,
      root.optical)
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
