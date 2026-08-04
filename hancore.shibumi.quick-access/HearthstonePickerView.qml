pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Commons as Commons
import "PickerModel.js" as PickerModel

Item {
  id: root
  required property var bar
  required property var controller

  readonly property real cardWidth: Commons.Style.space(232)
  readonly property real cardHeight: Commons.Style.space(330)
  readonly property real stepX: Commons.Style.space(128)
  readonly property real focusLift: Commons.Style.space(54)
  readonly property real focusScale: 1.24
  readonly property real spreadDegrees: 6
  readonly property int maxVisible: 5
  readonly property color frameColor: "#16161c"
  readonly property color textColor: "#ececee"
  readonly property color dimTextColor: Qt.rgba(0.92, 0.92, 0.94, 0.55)
  property real dealProgress: 0
  property bool dealStarted: false
  readonly property bool dealSettled: dealProgress >= 0.999
  readonly property int activeImageSourceCount: {
    let count = 0
    for (let i = 0; i < hearthstoneRepeater.count; i++) {
      const item = hearthstoneRepeater.itemAt(i)
      if (item && String(item.loadedThumbnailSource || "") !== "") count++
    }
    return count
  }

  function startDeal() {
    if (dealStarted || controller.filteredEntries.length === 0) return
    dealStarted = true
    dealProgress = 0
    Qt.callLater(function() { root.dealProgress = 1 })
  }

  Component.onCompleted: startDeal()

  Connections {
    target: root.controller
    function onFilteredEntriesChanged() { root.startDeal() }
  }

  Behavior on dealProgress {
    NumberAnimation {
      duration: root.controller.mode === "theme" ? 260 : 180
      easing.type: Easing.OutCubic
    }
  }

  Text {
    visible: root.controller.filteredEntries.length > 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Commons.Style.space(40)
    text: root.controller.mode.toUpperCase() + "      "
      + (root.controller.selectedIndex + 1) + " / "
      + root.controller.filteredEntries.length
    color: root.dimTextColor
    font.family: root.bar.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.letterSpacing: 2
    renderType: Text.NativeRendering
  }

  Item {
    id: hand
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -Commons.Style.space(16)
    width: parent.width
    height: root.cardHeight + root.focusLift + Commons.Style.space(40)

    Repeater {
      id: hearthstoneRepeater
      model: root.controller.filteredEntries

      delegate: Item {
        id: card
        required property int index
        required property var modelData
        readonly property int relative: index - root.controller.selectedIndex
        readonly property bool focused: relative === 0
        readonly property bool nearby: Math.abs(relative) <= root.maxVisible
        readonly property bool imageSourceActive:
          typeof root.controller.shouldLoadImage === "function"
            ? root.controller.shouldLoadImage(modelData, index) : nearby
        readonly property string loadedThumbnailSource: String(
          thumbnailImage.source || "")
        readonly property real shade: focused ? 0
          : Math.min(0.62, 0.30 + Math.abs(relative) * 0.05)
        readonly property bool current: root.controller.mode === "theme"
          ? String(modelData.label || "") === String(root.controller.currentSelection || "")
          : String(modelData.sourcePath || "") === String(root.controller.currentSelection || "")

        visible: nearby
        width: root.cardWidth
        height: root.cardHeight
        transformOrigin: Item.Bottom
        x: (hand.width - width) / 2
          + relative * root.stepX * root.dealProgress
        y: hand.height - height
          - (focused ? root.focusLift * root.dealProgress : 0)
        z: focused ? 1000 : 500 - Math.min(Math.abs(relative), 40)
        rotation: relative * root.spreadDegrees * root.dealProgress
        scale: focused
          ? 1 + (root.focusScale - 1) * root.dealProgress : 1
        opacity: root.dealProgress

        Behavior on x {
          enabled: root.dealSettled
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on y {
          enabled: root.dealSettled
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on rotation {
          enabled: root.dealSettled
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
          enabled: root.dealSettled
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Item {
          anchors.fill: parent
          anchors.margins: Commons.Style.space(6)
          clip: true

          Image {
            id: thumbnailImage
            anchors.fill: parent
            source: card.imageSourceActive
              ? root.controller.thumbnailUrl(card.modelData) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            retainWhileLoading: true
            sourceSize.width: Math.round(root.cardWidth * 2)
            sourceSize.height: Math.round(root.cardHeight * 2)
          }

          IconText {
            anchors.centerIn: parent
            visible: !root.controller.isThumbnailReady(card.modelData)
            text: root.controller.videoMode ? "movie" : "image"
            color: Qt.rgba(root.textColor.r, root.textColor.g,
              root.textColor.b, 0.34)
            font.pixelSize: Commons.Style.font.displayLarge
            fill: 0
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Commons.Style.space(70)
            gradient: Gradient {
              GradientStop { position: 0; color: "transparent" }
              GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.72) }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Commons.Style.space(12)
            text: !card.modelData ? ""
              : root.controller.mediaMode
                ? PickerModel.mediaLabel(card.modelData.sourcePath)
                : String(card.modelData.label || "")
            color: root.textColor
            font.family: root.bar.fontFamily
            font.pixelSize: Commons.Style.space(13)
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            renderType: Text.NativeRendering
          }

          Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: card.shade
            Behavior on opacity { NumberAnimation { duration: 180 } }
          }
        }

        Shape {
          id: frame
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          readonly property real outerRadius: Commons.Style.space(18)
          readonly property real matWidth: Commons.Style.space(8)
          readonly property real innerRadius: Commons.Style.space(10)

          ShapePath {
            fillRule: ShapePath.OddEvenFill
            fillColor: root.frameColor
            strokeColor: "transparent"
            strokeWidth: 0
            startX: frame.outerRadius
            startY: 0
            PathLine { x: frame.width - frame.outerRadius; y: 0 }
            PathArc { x: frame.width; y: frame.outerRadius; radiusX: frame.outerRadius; radiusY: frame.outerRadius }
            PathLine { x: frame.width; y: frame.height - frame.outerRadius }
            PathArc { x: frame.width - frame.outerRadius; y: frame.height; radiusX: frame.outerRadius; radiusY: frame.outerRadius }
            PathLine { x: frame.outerRadius; y: frame.height }
            PathArc { x: 0; y: frame.height - frame.outerRadius; radiusX: frame.outerRadius; radiusY: frame.outerRadius }
            PathLine { x: 0; y: frame.outerRadius }
            PathArc { x: frame.outerRadius; y: 0; radiusX: frame.outerRadius; radiusY: frame.outerRadius }
            PathMove { x: frame.matWidth + frame.innerRadius; y: frame.matWidth }
            PathLine { x: frame.width - frame.matWidth - frame.innerRadius; y: frame.matWidth }
            PathArc { x: frame.width - frame.matWidth; y: frame.matWidth + frame.innerRadius; radiusX: frame.innerRadius; radiusY: frame.innerRadius }
            PathLine { x: frame.width - frame.matWidth; y: frame.height - frame.matWidth - frame.innerRadius }
            PathArc { x: frame.width - frame.matWidth - frame.innerRadius; y: frame.height - frame.matWidth; radiusX: frame.innerRadius; radiusY: frame.innerRadius }
            PathLine { x: frame.matWidth + frame.innerRadius; y: frame.height - frame.matWidth }
            PathArc { x: frame.matWidth; y: frame.height - frame.matWidth - frame.innerRadius; radiusX: frame.innerRadius; radiusY: frame.innerRadius }
            PathLine { x: frame.matWidth; y: frame.matWidth + frame.innerRadius }
            PathArc { x: frame.matWidth + frame.innerRadius; y: frame.matWidth; radiusX: frame.innerRadius; radiusY: frame.innerRadius }
          }

          ShapePath {
            fillColor: "transparent"
            strokeColor: card.focused ? root.bar.urgent : "transparent"
            strokeWidth: card.focused ? Commons.Style.space(2) : 0
            startX: frame.outerRadius
            startY: 0
            PathLine { x: frame.width - frame.outerRadius; y: 0 }
            PathArc { x: frame.width; y: frame.outerRadius; radiusX: frame.outerRadius; radiusY: frame.outerRadius }
            PathLine { x: frame.width; y: frame.height - frame.outerRadius }
            PathArc { x: frame.width - frame.outerRadius; y: frame.height; radiusX: frame.outerRadius; radiusY: frame.outerRadius }
            PathLine { x: frame.outerRadius; y: frame.height }
            PathArc { x: 0; y: frame.height - frame.outerRadius; radiusX: frame.outerRadius; radiusY: frame.outerRadius }
            PathLine { x: 0; y: frame.outerRadius }
            PathArc { x: frame.outerRadius; y: 0; radiusX: frame.outerRadius; radiusY: frame.outerRadius }
          }
        }

        Rectangle {
          visible: card.current
          width: Commons.Style.space(9)
          height: width
          radius: width / 2
          x: Commons.Style.space(14)
          y: Commons.Style.space(14)
          z: 5
          color: root.bar.urgent
          border.color: Qt.rgba(0, 0, 0, 0.35)
          border.width: 1
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: card.focused
            ? root.controller.activateSelected()
            : root.controller.selectIndex(card.index)
        }
      }
    }
  }
}
