import QtQuick

// Only use for passive contents whose input surface lives outside the Row.
// Row geometry remains unchanged; balance its painted endpoints inside it.
Row {
  id: root

  property bool optical: true
  property bool boundLastAdvance: false
  property real opticalBias: anchors.horizontalCenterOffset
  readonly property var contents: Array.from(children).filter(item => item.visible)
  readonly property var first: contents.length ? contents[0] : null
  readonly property var last: contents.length ? contents[contents.length - 1] : null
  readonly property real inkLeft: first ? first.x + (first.inkLeft !== undefined
    ? first.inkLeft : first.font !== undefined ? firstInk.tightBoundingRect.x : 0) : 0
  readonly property real inkRight: last ? last.x + (last.inkRight !== undefined
    ? last.inkRight : last.font !== undefined
      ? boundLastAdvance ? Math.floor(Math.min(last.width,
          lastInk.tightBoundingRect.x + lastInk.tightBoundingRect.width))
        : lastInk.tightBoundingRect.x + lastInk.tightBoundingRect.width
      : last.width) : width

  TextMetrics {
    id: firstInk
    text: root.first && root.first.text !== undefined ? root.first.text : ""
    font: root.first && root.first.font !== undefined ? root.first.font : Qt.font({pixelSize: 1})
  }
  TextMetrics {
    id: lastInk
    text: root.last && root.last.text !== undefined ? root.last.text : ""
    font: root.last && root.last.font !== undefined ? root.last.font : Qt.font({pixelSize: 1})
  }
  transform: Translate {
    x: root.optical ? (root.width - root.inkLeft - root.inkRight) / 2 - root.opticalBias : 0
  }
}
