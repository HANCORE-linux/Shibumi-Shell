pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons as Commons
import qs.Ui as Ui

// Quattro Dropdown behavior with radius supplied by Shibumi tokens.
Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []
  property color foreground: Commons.Color.popups.text
  property color background: Commons.Color.popups.background
  property color popupBorder: Commons.Color.popups.border
  property color accent: Commons.Color.accent
  property string fontFamily: Commons.Style.font.family
  property int rowHeight: Commons.Style.spacing.controlHeight
  property int popupRowHeight: Commons.Style.spacing.popupRowHeight
  property bool showLabel: true
  property bool hasCursor: false
  property real controlRadius: Commons.Style.cornerRadius
  readonly property var popupBorderSpec: Commons.Border.localOrSurfaceSpec(
    "popups", "border", popupBorder, Commons.Color.popups.border,
    Commons.Style.normalBorderWidth)
  readonly property bool popupOpen: popup.opened

  signal changed(string value)
  signal hovered(bool isHovered)

  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }
  function optionValue(option) {
    return option && typeof option === "object"
      ? String(option.value) : String(option)
  }
  function optionLabel(option) {
    return option && typeof option === "object"
      ? String(option.label) : String(option)
  }
  function currentLabel() {
    for (let i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    return value
  }

  implicitWidth: Commons.Style.spacing.dropdownWidth
  implicitHeight: showLabel && label !== ""
    ? rowHeight + Commons.Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Commons.Style.spacing.labelGap

    Text {
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.bold: true
    }

    Ui.BorderSurface {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: root.controlRadius
      readonly property bool focused: activeFocus
      readonly property bool hot: triggerHover.hovered || root.hasCursor
      readonly property var stateBorderSpec: Commons.Border.controlSpec(
        focused ? "focus" : (hot ? "hover-cursor" : "normal"),
        root.foreground, root.accent)
      color: Commons.Style.controlFill(focused, hot,
        root.foreground, root.accent)
      borderSpec: stateBorderSpec
      activeFocusOnTab: true

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close()
          event.accepted = true
        }
      }

      Text {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft
          + Commons.Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Commons.Style.spacing.md
        text: root.currentLabel()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight
          + Commons.Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      Popup {
        id: popup
        x: 0
        y: trigger.height + Commons.Style.spacing.xxs
        width: trigger.width
        implicitHeight: Math.min(
          root.options.length * root.popupRowHeight
            + Math.max(0, root.options.length - 1)
              * Commons.Style.spacing.labelGap
            + Commons.Style.spacing.xxs,
          root.popupRowHeight * 8 + 7 * Commons.Style.spacing.labelGap
            + Commons.Style.spacing.xxs)
        padding: Commons.Style.spacing.hairline
        leftPadding: Commons.Border.left(root.popupBorderSpec)
          + Commons.Style.spacing.hairline
        rightPadding: Commons.Border.right(root.popupBorderSpec)
          + Commons.Style.spacing.hairline
        topPadding: Commons.Border.top(root.popupBorderSpec)
          + Commons.Style.spacing.hairline
        bottomPadding: Commons.Border.bottom(root.popupBorderSpec)
          + Commons.Style.spacing.hairline
        focus: true

        background: Ui.BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: root.controlRadius
        }

        onOpened: {
          optionList.currentIndex = Math.max(0,
            optionList.indexOfValue(root.value))
          optionList.forceActiveFocus()
        }

        contentItem: ListView {
          id: optionList
          spacing: Commons.Style.spacing.labelGap
          implicitHeight: contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.options
          currentIndex: -1

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              popup.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.text === "j") {
              optionList.currentIndex = Math.min(root.options.length - 1,
                optionList.currentIndex + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              optionList.currentIndex = Math.max(0,
                optionList.currentIndex - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter) {
              optionList.selectCurrent()
              event.accepted = true
            }
          }

          function indexOfValue(value) {
            for (let i = 0; i < root.options.length; i++)
              if (root.optionValue(root.options[i]) === value) return i
            return -1
          }

          function selectCurrent() {
            if (currentIndex < 0 || currentIndex >= root.options.length) return
            const nextValue = root.optionValue(root.options[currentIndex])
            root.value = nextValue
            root.changed(nextValue)
            popup.close()
          }

          delegate: Rectangle {
            required property var modelData
            required property int index
            width: optionList.width
            height: root.popupRowHeight
            radius: root.controlRadius
            color: index === optionList.currentIndex
              ? Commons.Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Commons.Style.spacing.controlPaddingX
              anchors.rightMargin: Commons.Style.spacing.controlPaddingX
              text: root.optionLabel(parent.modelData)
              color: parent.index === optionList.currentIndex
                ? Commons.Style.hoverStateColor(root.foreground, root.accent)
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.body
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: optionList.currentIndex = parent.index
              onClicked: optionList.selectCurrent()
            }
          }
        }
      }
    }
  }
}
