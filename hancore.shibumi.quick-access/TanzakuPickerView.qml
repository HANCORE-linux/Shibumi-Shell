pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root
  required property var bar
  required property var controller

  readonly property real centerX: width / 2
  readonly property real centerY: height / 2 - Commons.Style.space(10)
  readonly property real focusedWidth: Math.min(Commons.Style.space(460), width * 0.48)
  readonly property real focusedHeight: focusedWidth * 9 / 16
  readonly property real peekWidth: Commons.Style.space(104)
  readonly property real stripWidth: Commons.Style.space(24)
  readonly property real gap: Commons.Style.space(8)
  readonly property int maxVisible: 5
  property bool navigationAnimationsEnabled: false
  property int layoutGeneration: 0
  readonly property int activeImageSourceCount: {
    let count = 0
    for (let i = 0; i < tanzakuRepeater.count; i++) {
      const item = tanzakuRepeater.itemAt(i)
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
    if (controller.mode === "theme")
      return String(entry.label || "") === String(controller.currentSelection || "")
    return String(entry.sourcePath || "") === String(controller.currentSelection || "")
  }

  function itemWidth(relative) {
    const distance = Math.abs(relative)
    return distance === 0 ? focusedWidth
      : distance === 1 ? peekWidth : stripWidth
  }

  function itemX(relative) {
    const targetWidth = itemWidth(relative)
    if (relative === 0) return centerX - targetWidth / 2
    if (relative === -1) return centerX - focusedWidth / 2 - gap - targetWidth
    if (relative === 1) return centerX + focusedWidth / 2 + gap
    const offset = peekWidth + gap + (Math.abs(relative) - 2) * (stripWidth + gap)
    return relative < 0
      ? centerX - focusedWidth / 2 - gap - offset - targetWidth
      : centerX + focusedWidth / 2 + gap + offset
  }

  Repeater {
    id: tanzakuRepeater
    model: root.controller.filteredEntries

    delegate: Item {
      id: slice
      required property int index
      required property var modelData
      readonly property int relative: index - root.controller.selectedIndex
      readonly property bool focused: relative === 0
      readonly property bool neighbor: Math.abs(relative) === 1
      readonly property bool imageSourceActive:
        typeof root.controller.shouldLoadImage === "function"
          ? root.controller.shouldLoadImage(modelData, index)
          : Math.abs(relative) <= root.maxVisible
      readonly property string loadedThumbnailSource: pickerImage.loadedSource

      visible: Math.abs(relative) <= root.maxVisible
      width: root.itemWidth(relative)
      height: root.focusedHeight
      x: root.itemX(relative)
      y: root.centerY - height / 2
      z: focused ? 20 : 10 - Math.abs(relative)
      opacity: 1

      Behavior on x {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
      }
      Behavior on width {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 200 }
      }

      PickerImage {
        id: pickerImage
        anchors.fill: parent
        bar: root.bar
        controller: root.controller
        entry: slice.modelData
        selected: slice.focused
        current: root.isCurrent(slice.modelData)
        imageRadius: Commons.Style.space(8)
        imageInset: Commons.Style.space(3)
        washOpacity: slice.focused ? 0 : slice.neighbor ? 0.28 : 0.5
        decodeWidth: root.focusedWidth
        decodeHeight: root.focusedHeight
        sourceActive: slice.imageSourceActive
        onActivated: slice.focused
          ? root.controller.activateSelected() : root.controller.selectIndex(slice.index)
      }
    }
  }

  Connections {
    target: root.controller
    function onRequestSerialChanged() { root.settleInitialLayout() }
    function onOpenedChanged() { root.settleInitialLayout() }
    function onFilteredEntriesChanged() { root.settleInitialLayout() }
  }

  Component.onCompleted: settleInitialLayout()

  Text {
    visible: root.controller.selectedEntry !== null
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.centerY - root.focusedHeight / 2 - Commons.Style.space(22) - height
    text: root.controller.mode === "theme" ? "THEME"
      : root.controller.mode === "wallpaper" ? "WALLPAPER"
      : String(root.controller.title || "").toUpperCase()
    color: root.bar.urgent
    font.family: root.bar.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.letterSpacing: Commons.Style.space(3)
    font.weight: Font.Medium
    renderType: Text.NativeRendering
  }

  Text {
    visible: root.controller.selectedEntry !== null
    x: root.centerX + root.focusedWidth / 2 - width
    y: root.centerY - root.focusedHeight / 2 - Commons.Style.space(23) - height
    text: (root.controller.selectedIndex + 1) + " / "
      + root.controller.filteredEntries.length
    color: root.bar && "visualTokens" in root.bar && root.bar.visualTokens
      ? root.bar.visualTokens.mutedInk
      : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
        root.bar.foreground.b, 0.45)
    font.family: root.bar.fontFamily
    font.pixelSize: Commons.Style.font.caption
    renderType: Text.NativeRendering
  }

  Text {
    visible: root.controller.selectedEntry === null
    anchors.centerIn: parent
    text: root.controller.emptyText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Commons.Style.font.body
    font.letterSpacing: Commons.Style.space(1)
    renderType: Text.NativeRendering
  }
}
