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
  property bool barText: false
  property string nativeText: Symbols.glyph(paintText)
  // Approved LAN, palette and profile enlargements affect paint only;
  // the hidden reference still owns the original layout and input geometry.
  readonly property bool lanSymbol: nativeText === "\u{F0317}"
  readonly property int nativePixelSize: Commons.Style.bar.iconFont + (lanSymbol ? 1 : 0) + (["\u{F03D8}", "\u{F032A}", "\u{F029A}", "\u{F04C5}"].indexOf(nativeText) >= 0 ? 1 : 0)
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
      root.inkAligned ? root.nativeLabelX + root.nativeBounds.x / placement.metricScale
        : nativeGlyph.paintedCenterX - nativeGlyph.tightWidth / 2,
      nativeGlyph.baselineY + (root.inkAligned
        ? root.nativeBounds.y / placement.metricScale : nativeInk.tightBoundingRect.y),
      root.inkAligned ? root.nativeBounds.width / placement.metricScale
        : nativeGlyph.tightWidth, root.inkAligned
        ? root.nativeBounds.height / placement.metricScale : nativeInk.tightBoundingRect.height))
  }
  // Row balancing consumes unsnapped bounds. Feeding the final pixel correction
  // back into the parent's translation would make its own position recursive.
  readonly property real inkLeft: symbol ? (root.inkAligned
    ? (root.width - root.nativeBounds.width / placement.metricScale) / 2 : symbolInk.x)
    : glyphX + ink.tightBoundingRect.x
  readonly property real inkRight: symbol ? inkLeft + (root.inkAligned
    ? root.nativeBounds.width / placement.metricScale : symbolInk.width) : inkLeft + ink.tightBoundingRect.width
  readonly property real inkTop: symbol ? symbolInk.y
    : glyph.y + glyph.baselineOffset + ink.tightBoundingRect.y
  // Keep the approved badge reservation independent of the new paint snap.
  readonly property real badgeLeft: Math.ceil(symbol && inkAligned
    ? width / 2 + nativeGlyph.tightWidth / 2
      + (lanSymbol ? 0 : nativeGlyph.paintedCenterX - nativeGlyph.width / 2)
    : inkRight) - Commons.Style.space(3)

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
    font.pixelSize: root.nativePixelSize
  }

  FontMetrics { id: nativeFont; font: nativeInk.font }
  BarInk { id: placement; target: root }
  TextMetrics {
    id: nativeOutline
    text: root.symbol ? root.nativeText
      : root.barText ? placement.caption() : glyph.text
    font: Qt.font({ family: root.symbol ? Commons.Style.font.family : glyph.font.family,
      pixelSize: (root.symbol ? root.nativePixelSize : glyph.font.pixelSize) * placement.metricScale,
      weight: root.symbol ? Font.Normal : glyph.font.weight,
      italic: !root.symbol && glyph.font.italic,
      hintingPreference: Font.PreferNoHinting })
  }
  // PathText contributes metrics only. Unlike tightBoundingRect's baseline
  // envelope, its height excludes blank space below a raised glyph (e.g. FA).
  PathText { id: nativePath; text: nativeOutline.text; font: nativeOutline.font }
  readonly property rect nativeBounds: {
    const bounds = nativeOutline.tightBoundingRect
    return bounds.y + bounds.height === 0
      ? Qt.rect(bounds.x, bounds.y, bounds.width, nativePath.height) : bounds
  }
  readonly property bool inkAligned: root.optical && placement.enabled
    && root.symbolRotation === 0
  readonly property real nativeLabelX: nativeGlyph.paintedCenterX
    - nativeInk.tightBoundingRect.x - nativeGlyph.tightWidth / 2
  readonly property real glyphX: !optical ? 0
    : (horizontalAlignment === Text.AlignLeft ? 0
      : horizontalAlignment === Text.AlignRight ? width - ink.tightBoundingRect.width
      : (width - ink.tightBoundingRect.width) / 2)
      - ink.tightBoundingRect.x - anchors.horizontalCenterOffset

  // Keep the host font and size. Center visible ink rather than its line box;
  // snap the pen position/baseline in output pixels, not the reserved box.
  Item {
    id: symbolCanvas
    visible: root.symbol
    x: root.inkAligned
      ? placement.snapX(root.width / 2
        - (root.nativeBounds.x + root.nativeBounds.width / 2) / placement.metricScale)
        - root.nativeLabelX
      : (root.width - width) / 2
        + (root.lanSymbol ? width / 2 - nativeGlyph.paintedCenterX : 0)
    y: root.inkAligned && root.centerInkY
      ? placement.textTop(placement.baselineFor(root.nativeBounds), nativeFont.ascent)
        - nativeGlyph.baselineY + nativeFont.ascent
      : (root.height - height) / 2
        + (root.lanSymbol ? height / 2 - nativeGlyph.baselineY
          - nativeInk.tightBoundingRect.y - nativeInk.tightBoundingRect.height / 2 : 0)
    width: Commons.Style.bar.iconCanvas
    height: Commons.Style.bar.iconCanvas
    rotation: root.symbolRotation

    Ui.OpticalGlyph {
      id: nativeGlyph
      anchors.fill: parent
      text: root.nativeText
      fontFamily: Commons.Style.font.family
      fontSize: root.nativePixelSize
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
    x: root.optical && placement.enabled
      ? placement.snapX(root.glyphX) : root.glyphX
    // P8's native line-box centering for token-calibrated glyph sizes. Ligature
    // tight vertical bounds include blank baseline space and cannot center ink.
    y: !root.optical ? 0 : root.nativeLineBox
      ? Math.round(root.inkCenterY - implicitHeight / 2) : root.centerInkY
      ? placement.enabled
        ? placement.textTop(placement.baselineFor(root.nativeBounds), glyph.baselineOffset)
        : root.inkCenterY - glyph.baselineOffset
          - ink.tightBoundingRect.y - ink.tightBoundingRect.height / 2
      : Math.floor((root.height - implicitHeight) / 2)
  }
}
