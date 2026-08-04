pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Widgets
import qs.Commons as Commons

Item {
  id: root

  required property var bar
  required property var controller
  required property var entry
  property real skewOffset: Commons.Style.space(20)
  property real washOpacity: 0
  property real decodeWidth: 0
  property real decodeHeight: 0
  property bool selected: false
  property bool current: false
  property bool interactive: true
  property bool sourceActive: true
  readonly property real effectiveSkew: Math.min(
    Math.abs(skewOffset), width / 3)
  readonly property real topLeft: skewOffset >= 0 ? effectiveSkew : 0
  readonly property real topRight: skewOffset >= 0
    ? width : width - effectiveSkew
  readonly property real bottomRight: skewOffset >= 0
    ? width - effectiveSkew : width
  readonly property real bottomLeft: skewOffset >= 0 ? 0 : effectiveSkew
  readonly property string loadedSource: String(thumbnailImage.source || "")
  signal activated()

  Item {
    id: maskShape
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: "white"
        strokeColor: "transparent"
        startX: root.topLeft
        startY: 0
        PathLine { x: root.topRight; y: 0 }
        PathLine { x: root.bottomRight; y: root.height }
        PathLine { x: root.bottomLeft; y: root.height }
        PathLine { x: root.topLeft; y: 0 }
      }
    }
  }

  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: maskShape
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, 0.055)
    }

    Image {
      id: thumbnailImage
      anchors.fill: parent
      source: root.sourceActive ? root.controller.thumbnailUrl(root.entry) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      retainWhileLoading: true
      sourceSize.width: Math.max(1, Math.round(root.decodeWidth > 0
        ? root.decodeWidth : width * 1.25))
      sourceSize.height: Math.max(1, Math.round(root.decodeHeight > 0
        ? root.decodeHeight : height * 1.25))
    }

    Rectangle {
      anchors.fill: parent
      color: root.bar && "visualTokens" in root.bar && root.bar.visualTokens
        ? root.bar.visualTokens.paper : root.bar.background
      opacity: root.washOpacity
    }

    IconText {
      anchors.centerIn: parent
      visible: !root.controller.isThumbnailReady(root.entry)
      text: root.controller.videoMode ? "movie" : "image"
      color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, 0.34)
      font.pixelSize: Commons.Style.font.displayLarge
      fill: 0
    }
  }

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.selected ? root.bar.urgent
        : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.2)
      strokeWidth: root.selected ? Commons.Style.space(2) : 1
      joinStyle: ShapePath.MiterJoin
      startX: root.topLeft
      startY: 0
      PathLine { x: root.topRight; y: 0 }
      PathLine { x: root.bottomRight; y: root.height }
      PathLine { x: root.bottomLeft; y: root.height }
      PathLine { x: root.topLeft; y: 0 }
    }
  }

  Rectangle {
    visible: root.current
    width: Commons.Style.space(8)
    height: width
    radius: width / 2
    x: root.topLeft + Commons.Style.space(9)
    y: Commons.Style.space(9)
    color: root.bar.urgent
    border.color: Qt.rgba(0, 0, 0, 0.35)
    border.width: 1
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
