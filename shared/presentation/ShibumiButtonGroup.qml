pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

// Quattro ButtonGroup behavior with radius supplied by Shibumi tokens.
Row {
  id: root

  property var options: []
  property string value: ""
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color accent: Commons.Color.accent
  property string fontFamily: Commons.Style.font.family
  property real fontSize: Commons.Style.font.body
  property bool focusable: true
  property real controlRadius: Commons.Style.cornerRadius
  property int cursorIndex: -1
  property int _focusedIndex: -1

  signal changed(string value)
  signal hovered(int index, bool isHovered)

  spacing: Commons.Style.spacing.md
  activeFocusOnTab: focusable

  function optionValue(option) {
    return option && typeof option === "object"
      ? String(option.value) : String(option)
  }

  function optionLabel(option) {
    return option && typeof option === "object"
        && option.label !== undefined
      ? String(option.label) : String(option)
  }

  function optionIcon(option) {
    return option && typeof option === "object" && option.icon
      ? String(option.icon) : ""
  }

  function optionTooltip(option) {
    return option && typeof option === "object" && option.tooltip
      ? String(option.tooltip) : ""
  }

  function selectedOptionIndex() {
    for (let i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return i
    return -1
  }

  function activateFocused() {
    if (_focusedIndex < 0 || _focusedIndex >= options.length) return
    root.changed(optionValue(options[_focusedIndex]))
  }

  onActiveFocusChanged: {
    if (activeFocus) {
      const index = selectedOptionIndex()
      _focusedIndex = index < 0 ? 0 : index
    } else {
      _focusedIndex = -1
    }
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H
        || event.text === "h") {
      _focusedIndex = Math.max(0,
        (_focusedIndex < 0 ? 0 : _focusedIndex) - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L
        || event.text === "l") {
      _focusedIndex = Math.min(options.length - 1,
        (_focusedIndex < 0 ? 0 : _focusedIndex) + 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space) {
      activateFocused()
      event.accepted = true
    }
  }

  Repeater {
    model: root.options

    delegate: Ui.Button {
      required property var modelData
      required property int index
      text: root.optionLabel(modelData)
      iconText: root.optionIcon(modelData)
      tooltipText: root.optionTooltip(modelData)
      selected: root.optionValue(modelData) === root.value
      hasCursor: root.cursorIndex === index
        || (root.activeFocus && root._focusedIndex === index)
      bordered: true
      foreground: root.foreground
      background: root.background
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      radius: root.controlRadius
      onClicked: root.changed(root.optionValue(modelData))
      onHovered: function(hovered) { root.hovered(index, hovered) }
    }
  }
}
