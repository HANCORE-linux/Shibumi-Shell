pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
  id: root

  property url source
  property var candidates: source ? [source] : []
  property string fallbackText: ""
  property int candidateIndex: 0
  readonly property string candidatesKey: candidates.join("\n")
  onCandidatesKeyChanged: candidateIndex = 0
  readonly property url resolvedSource: sourceImage.status === Image.Ready ? sourceImage.source : ""
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
    source: root.candidateIndex < root.candidates.length ? root.candidates[root.candidateIndex] : ""
    onStatusChanged: if (status === Image.Error) Qt.callLater(function() {
      if (sourceImage.status === Image.Error) root.candidateIndex++
    })
    sourceSize: root.sourceSize
    fillMode: Image.PreserveAspectFit
    cache: true
    smooth: root.smooth
    mipmap: root.mipmap
  }

  Text {
    anchors.centerIn: parent
    visible: sourceImage.status !== Image.Ready
    text: root.fallbackText
    color: root.tint
    font.family: "Material Symbols Rounded"
    font.pixelSize: Math.min(root.width, root.height)
  }

  MultiEffect {
    visible: sourceImage.status === Image.Ready
    anchors.fill: parent
    source: sourceImage
    // MultiEffect uses colorizationColor.a as color-mix strength, not output
    // opacity. Keep the tint fully colorized and apply alpha to the item.
    opacity: root.tint.a
    colorization: 1
    colorizationColor: root.opaqueTint
  }
}
