pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var bar
  required property var controller

  readonly property real previewWidth: Math.min(
    Commons.Style.space(560), width * 0.54)
  readonly property real previewHeight: previewWidth * 9 / 16
  readonly property real sliceWidth: previewWidth * 0.14
  readonly property real sliceHeight: previewHeight * 0.90
  readonly property real sliceGap: -sliceWidth * 0.28
  readonly property real skewOffset: Commons.Style.space(20)
  readonly property real centerY: height / 2 - Commons.Style.space(24)
  readonly property int maxVisible: 5
  property bool navigationAnimationsEnabled: false
  property int layoutGeneration: 0
  readonly property int activeImageSourceCount: {
    let count = 0
    for (let i = 0; i < carouselRepeater.count; i++) {
      const item = carouselRepeater.itemAt(i)
      if (item && String(item.loadedThumbnailSource || "") !== "") count++
    }
    return count
  }

  function settleInitialLayout() {
    navigationAnimationsEnabled = false
    const generation = ++layoutGeneration
    if (!controller.opened || controller.filteredEntries.length === 0) return
    Qt.callLater(function() {
      if (generation !== root.layoutGeneration || !root.controller.opened
          || root.controller.filteredEntries.length === 0) return
      root.navigationAnimationsEnabled = true
    })
  }

  function isCurrent(entry) {
    if (!entry) return false
    return controller.mode === "theme"
      ? String(entry.label || "") === String(controller.currentSelection || "")
      : String(entry.sourcePath || "") === String(controller.currentSelection || "")
  }

  function itemWidth(relative) {
    return relative === 0 ? previewWidth : sliceWidth
  }

  function itemHeight(relative) {
    return relative === 0 ? previewHeight : sliceHeight
  }

  function itemX(relative) {
    const previewX = (width - previewWidth) / 2
    const step = sliceWidth + sliceGap
    if (relative === 0) return previewX
    if (relative < 0) return previewX + relative * step
    return previewX + previewWidth + sliceGap + (relative - 1) * step
  }

  Repeater {
    id: carouselRepeater
    model: root.controller.filteredEntries

    delegate: Item {
      id: card
      required property int index
      required property var modelData
      readonly property int relative: index - root.controller.selectedIndex
      readonly property bool focused: relative === 0
      readonly property bool imageSourceActive:
        typeof root.controller.shouldLoadImage === "function"
          ? root.controller.shouldLoadImage(modelData, index)
          : Math.abs(relative) <= root.maxVisible
      readonly property string loadedThumbnailSource: pickerImage.loadedSource

      visible: Math.abs(relative) <= root.maxVisible
      x: root.itemX(relative)
      y: root.centerY - height / 2
      width: root.itemWidth(relative)
      height: root.itemHeight(relative)
      z: focused ? 20 : 10 - Math.abs(relative)

      Behavior on x {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }
      Behavior on width {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }
      Behavior on height {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }
      Behavior on y {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }
      CarouselPickerImage {
        id: pickerImage
        anchors.fill: parent
        bar: root.bar
        controller: root.controller
        entry: card.modelData
        selected: card.focused
        current: root.isCurrent(card.modelData)
        skewOffset: root.skewOffset
        washOpacity: card.focused ? 0 : 0.42
        decodeWidth: root.previewWidth
        decodeHeight: root.previewHeight
        sourceActive: card.imageSourceActive
        onActivated: card.focused
          ? root.controller.activateSelected()
          : root.controller.selectIndex(card.index)
      }

    }
  }

  Text {
    visible: root.controller.selectedEntry !== null
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.centerY - root.previewHeight / 2
      - Commons.Style.space(34) - height
    text: root.controller.mode.toUpperCase() + "     "
      + (root.controller.selectedIndex + 1) + " / "
      + root.controller.filteredEntries.length
    color: root.bar.urgent
    font.family: root.bar.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.letterSpacing: Commons.Style.space(2)
    font.weight: Font.Medium
    renderType: Text.NativeRendering
  }

  Text {
    visible: root.controller.selectedEntry === null
    anchors.centerIn: parent
    text: root.controller.emptyText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Commons.Style.font.body
    renderType: Text.NativeRendering
  }

  Connections {
    target: root.controller
    function onRequestSerialChanged() { root.settleInitialLayout() }
    function onOpenedChanged() { root.settleInitialLayout() }
    function onFilteredEntriesChanged() { root.settleInitialLayout() }
  }

  Component.onCompleted: settleInitialLayout()
}
