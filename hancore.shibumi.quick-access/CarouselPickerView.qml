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
  readonly property real sliceWidth: Commons.Style.space(58)
  readonly property real sliceGap: Commons.Style.space(10)
  readonly property real centerY: height / 2 - Commons.Style.space(24)
  readonly property int maxVisible: 5
  property bool navigationAnimationsEnabled: false
  property int layoutGeneration: 0

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

  function itemX(relative) {
    const previewX = (width - previewWidth) / 2
    if (relative === 0) return previewX
    if (relative < 0)
      return previewX + relative * (sliceWidth + sliceGap)
    return previewX + previewWidth + sliceGap
      + (relative - 1) * (sliceWidth + sliceGap)
  }

  Repeater {
    model: root.controller.filteredEntries

    delegate: Item {
      id: card
      required property int index
      required property var modelData
      readonly property int relative: index - root.controller.selectedIndex
      readonly property bool focused: relative === 0

      visible: Math.abs(relative) <= root.maxVisible
      x: root.itemX(relative)
      y: root.centerY - height / 2
      width: root.itemWidth(relative)
      height: root.previewHeight
      z: focused ? 20 : 10 - Math.abs(relative)

      Behavior on x {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }
      Behavior on width {
        enabled: root.navigationAnimationsEnabled
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
      }

      PickerImage {
        anchors.fill: parent
        bar: root.bar
        controller: root.controller
        entry: card.modelData
        selected: card.focused
        current: root.isCurrent(card.modelData)
        imageRadius: Commons.Style.space(10)
        imageInset: Commons.Style.space(3)
        washOpacity: card.focused ? 0 : 0.38
        decodeWidth: root.previewWidth
        decodeHeight: root.previewHeight
        onActivated: card.focused
          ? root.controller.activateSelected()
          : root.controller.selectIndex(card.index)
      }

      Rectangle {
        anchors.fill: parent
        visible: !card.focused
        radius: Commons.Style.space(10)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(root.bar.foreground.r,
          root.bar.foreground.g, root.bar.foreground.b, 0.18)
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
