import QtQuick

Text {
  id: root

  property real fill: 0
  // Opt-in for bar labels only. Panel glyphs keep their original paint path.
  property bool barText: false
  property bool wholeInk: false
  property bool hintedInk: false
  // A smaller inline label can follow its larger sibling without changing
  // its own font, advance or input reservation.
  property font baselineFont: root.font
  property alias inkAxisItem: placement.axisItem
  renderType: Text.QtRendering
  font.family: "Material Symbols Rounded"
  font.variableAxes: root.barText ? ({}) : ({ "FILL": root.fill })

  BarInk { id: placement; target: root }
  TextMetrics {
    id: capitals
    text: root.barText ? (root.wholeInk ? root.text : placement.caption(root.text)) : ""
    font: root.font
  }
  // Raised pictograms and unhinted distance-field text need outline metrics,
  // not the small-size integer envelope that can include empty baseline space.
  readonly property bool outlineInk: barText || wholeInk || renderType === Text.QtRendering
  TextMetrics {
    id: outline
    text: root.barText && root.outlineInk ? capitals.text : ""
    font: Qt.font({ family: root.baselineFont.family,
      pixelSize: root.baselineFont.pixelSize * placement.metricScale,
      weight: root.baselineFont.weight, italic: root.baselineFont.italic,
      hintingPreference: Font.PreferNoHinting })
  }
  PathText { id: outlinePath; text: outline.text; font: outline.font }
  readonly property bool rasterInk: wholeInk && hintedInk && renderType === Text.NativeRendering
    && outline.tightBoundingRect.y + outline.tightBoundingRect.height !== 0
  TextMetrics {
    id: raster
    text: root.barText && root.rasterInk ? capitals.text : ""
    font: Qt.font({ family: root.font.family,
      pixelSize: Math.max(1, Math.round(root.font.pixelSize * placement.dpr)),
      weight: root.font.weight, italic: root.font.italic,
      hintingPreference: root.font.hintingPreference })
    renderType: Text.NativeRendering
  }
  readonly property rect inkBounds: {
    if (rasterInk) return raster.tightBoundingRect
    if (!outlineInk) return capitals.tightBoundingRect
    const bounds = outline.tightBoundingRect
    return bounds.y + bounds.height === 0
      ? Qt.rect(bounds.x, bounds.y, bounds.width, outlinePath.height) : bounds
  }
  readonly property real inkBaseline: placement.baselineFor(inkBounds,
    rasterInk ? placement.dpr : outlineInk ? placement.metricScale : 1)
  transform: Translate {
    x: root.barText && placement.enabled ? placement.snapX(0) : 0
    y: root.barText && placement.enabled
      ? root.renderType === Text.NativeRendering
        ? placement.textTop(root.inkBaseline, root.baselineOffset)
        : root.inkBaseline - root.baselineOffset
      : 0
  }
}
