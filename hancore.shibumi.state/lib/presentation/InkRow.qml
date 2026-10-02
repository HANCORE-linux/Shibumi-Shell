import QtQuick

// Only use for passive contents whose input surface lives outside the Row.
// Row geometry remains unchanged; balance its painted endpoints inside it.
Row {
  id: root

  property bool optical: true
  property bool boundLastAdvance: false
  property real opticalBias: anchors.horizontalCenterOffset
  readonly property var contents: Array.from(children).filter(item => item.visible)
  readonly property int metricScale: 64
  function metricFont(item) {
    if (!item || item.font === undefined) return Qt.font({pixelSize: 1})
    const font = item.font
    return Qt.font({family: font.family, pixelSize: font.pixelSize * metricScale,
      weight: font.weight, italic: font.italic, capitalization: font.capitalization,
      letterSpacing: font.letterSpacing * metricScale,
      wordSpacing: font.wordSpacing * metricScale,
      hintingPreference: Font.PreferNoHinting})
  }
  readonly property var first: contents.length ? contents[0] : null
  readonly property var last: contents.length ? contents[contents.length - 1] : null
  readonly property real inkLeft: first ? first.x + (first.inkLeft !== undefined
    ? first.inkLeft : first.font !== undefined ? firstInk.tightBoundingRect.x / metricScale : 0) : 0
  readonly property real inkRight: last ? last.x + (last.inkRight !== undefined
    ? last.inkRight : last.font !== undefined
      ? boundLastAdvance ? Math.floor(Math.min(last.width,
          (lastInk.tightBoundingRect.x + lastInk.tightBoundingRect.width) / metricScale))
        : (lastInk.tightBoundingRect.x + lastInk.tightBoundingRect.width) / metricScale
      : last.width) : width
  readonly property real inkOffsetX: optical
    ? (width - inkLeft - inkRight) / 2 - opticalBias : 0

  TextMetrics {
    id: firstInk
    text: root.first && root.first.text !== undefined ? root.first.text : ""
    font: root.metricFont(root.first)
  }
  TextMetrics {
    id: lastInk
    text: root.last && root.last.text !== undefined ? root.last.text : ""
    font: root.metricFont(root.last)
  }
  transform: Translate {
    x: root.inkOffsetX
  }
}
