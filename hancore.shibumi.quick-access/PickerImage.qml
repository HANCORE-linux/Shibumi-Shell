pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Commons as Commons

Item {
  id: root

  required property var bar
  required property var controller
  required property var entry
  property real imageRadius: Commons.Style.cornerRadius
  property real imageInset: 0
  property real washOpacity: 0
  property real decodeWidth: 0
  property real decodeHeight: 0
  property bool selected: false
  property bool current: false
  property bool interactive: true
  property bool sourceActive: true
  readonly property string loadedSource: String(thumbnailImage.source || "")
  signal activated()

  Rectangle {
    anchors.fill: parent
    radius: root.imageRadius
    color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
      root.bar.foreground.b, 0.055)
    border.color: root.selected ? root.bar.urgent
      : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, 0.2)
    border.width: root.selected ? Commons.Style.space(2) : 1
    ClippingRectangle {
      id: imageClip
      anchors.fill: parent
      anchors.margins: Math.max(parent.border.width, root.imageInset)
      radius: Math.max(0, root.imageRadius - anchors.margins)
      color: "transparent"

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
        color: root.bar && "visualTokens" in root.bar
          && root.bar.visualTokens
          ? root.bar.visualTokens.paper : root.bar.background
        opacity: root.washOpacity
      }
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

    Rectangle {
      visible: root.current
      width: Commons.Style.space(8)
      height: width
      radius: width / 2
      x: Commons.Style.space(9)
      y: Commons.Style.space(9)
      color: root.bar.urgent
      border.color: Qt.rgba(0, 0, 0, 0.35)
      border.width: 1
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
