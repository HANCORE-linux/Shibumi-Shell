pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var monitorService

  property string cursorSection: ""
  property int cursorIndex: 0
  property bool cursorActive: false
  readonly property var visibleSections: {
    const result = []
    if (monitorService.brightnessAvailable) result.push("brightness")
    if (monitorService.textSizeAvailable) result.push("textsize")
    result.push("scale")
    if (monitorService.displays.length > 1) result.push("displays")
    return result
  }

  owner: ownerWidget
  open: ownerWidget.opened && monitorService && monitorService.ready
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(380))
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    Commons.Style.space(620))

  function resetCursor() {
    cursorSection = monitorService.brightnessAvailable ? "brightness" : "scale"
    cursorIndex = cursorSection === "brightness" ? -1 : 0
    cursorActive = false
  }

  function refreshDisplayState() {
    return monitorService && typeof monitorService.refresh === "function"
      ? monitorService.refresh() : false
  }

  function sectionIndex() { return visibleSections.indexOf(cursorSection) }

  function moveVertical(delta) {
    const sections = visibleSections
    if (sections.length === 0) return
    let current = sectionIndex()
    if (current < 0) {
      resetCursor()
      return
    }

    if (cursorSection === "displays") {
      const count = monitorService.displays.length
      const next = cursorIndex + delta
      if (next >= 0 && next < count) {
        cursorIndex = next
        return
      }
    }

    current = Math.max(0, Math.min(sections.length - 1, current + delta))
    cursorSection = sections[current]
    cursorIndex = cursorSection === "brightness"
      || cursorSection === "textsize" ? -1 : 0
  }

  function moveHorizontal(delta) {
    if (cursorSection === "brightness") {
      monitorService.setBrightness(monitorService.brightnessPercent + delta * 5)
      return
    }
    if (cursorSection === "textsize") {
      monitorService.adjustTextSize(delta)
      return
    }
    if (cursorSection !== "scale") return
    cursorIndex = Math.max(0, Math.min(monitorService.scaleValues.length - 1,
      cursorIndex + delta))
  }

  function activateCursor() {
    if (cursorSection === "scale" && cursorIndex >= 0
        && cursorIndex < monitorService.scaleValues.length) {
      monitorService.setScale(monitorService.scaleValues[cursorIndex])
      return
    }
    if (cursorSection !== "displays" || cursorIndex < 0
        || cursorIndex >= monitorService.displays.length) return
    const display = monitorService.displays[cursorIndex]
    if (!display || (display.enabled && monitorService.enabledDisplayCount <= 1)) return
    monitorService.toggleDisplay(display.name, display.enabled)
  }

  function ensureVisible(item) {
    if (!item || !scroller) return
    const point = item.mapToItem(contentColumn, 0, 0)
    const top = point.y
    const bottom = top + item.height
    if (top < scroller.contentY) scroller.contentY = Math.max(0, top - 6)
    else if (bottom > scroller.contentY + scroller.height)
      scroller.contentY = Math.max(0, bottom - scroller.height + 6)
  }

  onOpenChanged: {
    if (!open) return
    resetCursor()
  }

  onVisibleSectionsChanged: {
    if (visibleSections.indexOf(cursorSection) < 0) resetCursor()
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }
    onMoveRequested: function(dx, dy) {
      if (!panel.cursorActive) {
        panel.cursorActive = true
        return
      }
      if (dy !== 0) panel.moveVertical(dy)
      else if (dx !== 0) panel.moveHorizontal(dx)
    }
    onActivateRequested: if (panel.cursorActive) panel.activateCursor()

    Flickable {
      id: scroller
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: scroller.width
        spacing: Commons.Style.space(10)

        Row {
          width: parent.width
          spacing: Commons.Style.space(4)

          Text {
            width: parent.width - headerActions.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: "Display"
            color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.font.heading
            font.letterSpacing: 2
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          Row {
            id: headerActions
            spacing: Commons.Style.space(2)

            IconAction {
              icon: "refresh"
              tooltip: "Refresh display state"
              onClicked: panel.refreshDisplayState()
            }

            IconAction {
              icon: "close"
              tooltip: "Close"
              onClicked: panel.ownerWidget.close()
            }
          }
        }

        Ui.PanelSeparator { width: parent.width }

        Row {
          width: parent.width
          spacing: Commons.Style.space(10)

          IconText {
            anchors.verticalCenter: parent.verticalCenter
            text: panel.monitorService.displays.length > 1
              ? "desktop_windows" : "monitor"
            color: panel.bar ? panel.bar.urgent : Commons.Color.accent
            font.pixelSize: Commons.Style.font.display
            fill: 1
          }

          Column {
            width: parent.width - x
            anchors.verticalCenter: parent.verticalCenter
            spacing: Commons.Style.space(2)

            Text {
              width: parent.width
              text: panel.monitorService.focusedMonitor || "Display controls"
              color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.body
              font.weight: Font.Medium
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              width: parent.width
              text: panel.monitorService.brightnessAvailable
                ? panel.monitorService.brightnessName(
                  panel.monitorService.brightnessPercent).toUpperCase()
                  + " · " + panel.monitorService.brightnessPercent + "%"
                : "NO CONTROLLABLE BACKLIGHT"
              color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
                panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
                : Commons.Color.foreground
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.caption
              font.letterSpacing: 1
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }
          }
        }

        Ui.PanelSeparator {
          width: parent.width
          visible: panel.monitorService.brightnessAvailable
        }

        Column {
          width: parent.width
          visible: panel.monitorService.brightnessAvailable
          spacing: Commons.Style.space(5)

          SectionLabel { text: "BRIGHTNESS" }

          Item {
            id: brightnessRow
            width: parent.width
            height: Commons.Style.space(30)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              text: panel.monitorService.brightnessPercent + "%"
              color: panel.bar ? panel.bar.urgent : Commons.Color.accent
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.body
              font.weight: Font.Medium
              renderType: Text.NativeRendering
            }

            Ui.PanelSlider {
              id: brightnessSlider
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Commons.Style.space(6)
              anchors.rightMargin: Commons.Style.space(6)
              bar: panel.bar
              minimum: 1
              maximum: 100
              step: 1
              integer: true
              trackColor: panel.controlActiveFillColor
              fillColor: panel.controlAccent
              knobColor: panel.controlAccent
              value: panel.monitorService.brightnessPercent
              onMoved: function(value) {
                panel.monitorService.previewBrightness(value)
              }
              onReleased: function(value) {
                panel.monitorService.setBrightness(value)
              }
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                panel.cursorActive = true
                panel.cursorSection = "brightness"
                panel.cursorIndex = -1
                panel.ensureVisible(brightnessRow)
              }
            }
          }

          Row {
            width: parent.width
            spacing: Commons.Style.space(6)

            PanelButton {
              width: (parent.width - parent.spacing) / 2
              label: "− 5%"
              onClicked: panel.monitorService.setBrightness(
                panel.monitorService.brightnessPercent - 5)
            }
            PanelButton {
              width: (parent.width - parent.spacing) / 2
              label: "+ 5%"
              onClicked: panel.monitorService.setBrightness(
                panel.monitorService.brightnessPercent + 5)
            }
          }
        }

        Ui.PanelSeparator {
          width: parent.width
          visible: panel.monitorService.textSizeAvailable
        }

        Column {
          width: parent.width
          visible: panel.monitorService.textSizeAvailable
          spacing: Commons.Style.space(5)

          Item {
            width: parent.width
            implicitHeight: Math.max(textSizeLabel.implicitHeight,
              textSizeValue.implicitHeight)

            SectionLabel {
              id: textSizeLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "TEXT SIZE"
            }

            Text {
              id: textSizeValue
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: (textSizeSlider.dragging
                ? panel.monitorService.textSizeStops[
                  Math.round(textSizeSlider.liveValue)]
                : panel.monitorService.textSizePx) + "px"
              color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
                panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
                : Commons.Color.foreground
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.caption
              font.weight: Font.Medium
              renderType: Text.NativeRendering
            }
          }

          Ui.CursorSurface {
            id: textSizeRow
            width: parent.width
            height: textSizeSlider.implicitHeight
              + Commons.Style.spacing.controlGap
            hasCursor: panel.cursorActive
              && panel.cursorSection === "textsize" && panel.cursorIndex === -1
            foreground: panel.controlForeground
            accent: panel.controlAccent
            outline: true
            onHasCursorChanged: if (hasCursor) panel.ensureVisible(textSizeRow)

            Row {
              id: v2TextSizeSegments
              visible: panel.shellStyle !== "shibumi"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Commons.Style.space(6)
              anchors.rightMargin: Commons.Style.space(6)
              anchors.verticalCenter: textSizeSlider.verticalCenter
              height: textSizeSlider.trackHeight
              spacing: Commons.Style.space(2)
              readonly property int segmentCount: Math.max(0,
                panel.monitorService.textSizeStops.length - 1)

              Repeater {
                model: Math.max(0,
                  panel.monitorService.textSizeStops.length - 1)

                Rectangle {
                  required property int index
                  width: (v2TextSizeSegments.width
                    - v2TextSizeSegments.spacing
                      * Math.max(0, v2TextSizeSegments.segmentCount - 1))
                    / Math.max(1, v2TextSizeSegments.segmentCount)
                  height: v2TextSizeSegments.height
                  radius: height / 2
                  color: panel.controlActiveFillColor

                  Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1,
                      textSizeSlider.progress
                        * v2TextSizeSegments.segmentCount - parent.index))
                    radius: parent.radius
                    color: panel.controlAccent
                  }
                }
              }
            }

            Ui.PanelSlider {
              id: textSizeSlider
              anchors.fill: parent
              anchors.leftMargin: Commons.Style.space(6)
              anchors.rightMargin: Commons.Style.space(6)
              bar: panel.bar
              minimum: 0
              maximum: Math.max(0,
                panel.monitorService.textSizeStops.length - 1)
              step: 1
              integer: true
              tickCount: panel.shellStyle === "shibumi"
                ? panel.monitorService.textSizeStops.length : 0
              trackColor: panel.shellStyle === "shibumi"
                ? panel.controlActiveFillColor : "transparent"
              fillColor: panel.shellStyle === "shibumi"
                ? panel.controlAccent : "transparent"
              knobColor: panel.controlAccent
              tickColor: panel.renderedSurfaceColor
              value: panel.monitorService.textSizeIndex
              onReleased: function(value) {
                const index = Math.max(0, Math.min(
                  panel.monitorService.textSizeStops.length - 1,
                  Math.round(value)))
                panel.monitorService.setTextSize(
                  panel.monitorService.textSizeStops[index])
              }
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                panel.cursorActive = true
                panel.cursorSection = "textsize"
                panel.cursorIndex = -1
              }
            }
          }
        }

        Ui.PanelSeparator { width: parent.width }

        Column {
          width: parent.width
          spacing: Commons.Style.space(6)

          SectionLabel { text: "SCALE" }

          Grid {
            id: scaleGrid
            width: parent.width
            columns: panel.monitorService.scaleValues.length
            spacing: Commons.Style.space(3)
            readonly property real cellWidth: columns > 0
              ? (width - spacing * (columns - 1)) / columns : 0

            Repeater {
              model: panel.monitorService.scaleValues
              delegate: ScaleButton {
                required property string modelData
                required property int index
                width: scaleGrid.cellWidth
                scaleValue: modelData
                scaleIndex: index
              }
            }
          }
        }

        Ui.PanelSeparator {
          width: parent.width
          visible: panel.monitorService.displays.length > 1
        }

        Column {
          width: parent.width
          spacing: Commons.Style.space(5)
          visible: panel.monitorService.displays.length > 1

          SectionLabel { text: "DISPLAYS" }

          Repeater {
            model: panel.monitorService.displays
            delegate: DisplayRow {
              required property var modelData
              required property int index
              width: contentColumn.width
              display: modelData
              rowIndex: index
            }
          }
        }
      }
    }
  }

  component SectionLabel: Text {
    color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
      panel.bar.foreground.g, panel.bar.foreground.b, 0.58)
      : Commons.Color.foreground
    font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    font.letterSpacing: 1.2
    font.weight: Font.Medium
    renderType: Text.NativeRendering
  }

  component PanelButton: Rectangle {
    id: button
    property string label: ""
    signal clicked()
    readonly property bool hovered: buttonMouse.containsMouse
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    color: hovered ? panel.controlHoverFillColor : panel.controlFillColor
    border.width: panel.controlBorderWidth
    border.color: hovered ? panel.controlHoverBorderColor
      : panel.controlBorderColor

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: button.label
      color: button.hovered ? panel.controlAccent : panel.controlForeground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

    IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }

  component ScaleButton: Rectangle {
    id: scaleButton
    required property string scaleValue
    required property int scaleIndex
    readonly property bool activeScale: panel.monitorService.normalizeScale(
      panel.monitorService.monitorScale) === panel.monitorService.normalizeScale(scaleValue)
    readonly property bool keyboardFocused: panel.cursorActive
      && panel.cursorSection === "scale" && panel.cursorIndex === scaleIndex
    readonly property bool hovered: scaleMouse.containsMouse
    readonly property bool highlighted: keyboardFocused || hovered
    implicitHeight: Commons.Style.space(30)
    radius: panel.controlRadius
    color: activeScale ? panel.controlActiveFillColor
      : highlighted ? panel.controlHoverFillColor : panel.controlFillColor
    border.width: panel.controlBorderWidth
    border.color: activeScale || highlighted ? panel.controlAccent
      : panel.controlBorderColor

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: scaleButton.scaleValue + "x"
      color: scaleButton.activeScale || scaleButton.highlighted
        ? panel.controlAccent : panel.controlForeground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      font.weight: scaleButton.activeScale ? Font.DemiBold : Font.Normal
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: scaleMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        panel.cursorActive = true
        panel.cursorSection = "scale"
        panel.cursorIndex = scaleButton.scaleIndex
      }
      onClicked: panel.monitorService.setScale(scaleButton.scaleValue)
    }
  }

  component DisplayRow: Rectangle {
    id: displayRow
    required property var display
    required property int rowIndex
    readonly property bool enabledDisplay: display && display.enabled === true
    readonly property bool focusedDisplay: display && display.focused === true
    readonly property bool canToggle: display
      && (!enabledDisplay || panel.monitorService.enabledDisplayCount > 1)
    readonly property bool keyboardFocused: panel.cursorActive
      && panel.cursorSection === "displays" && panel.cursorIndex === rowIndex
    readonly property bool hovered: displayMouse.containsMouse && canToggle
    readonly property bool highlighted: keyboardFocused || hovered
    implicitHeight: Commons.Style.space(36)
    radius: panel.controlRadius
    color: focusedDisplay ? panel.controlActiveFillColor
      : highlighted ? panel.controlHoverFillColor : panel.controlFillColor
    border.width: panel.controlBorderWidth
    border.color: focusedDisplay || highlighted ? panel.controlAccent
      : panel.controlBorderColor
    opacity: canToggle ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }
    onKeyboardFocusedChanged: if (keyboardFocused) panel.ensureVisible(displayRow)

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Commons.Style.space(8)
      anchors.rightMargin: Commons.Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Commons.Style.space(7)

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: "monitor"
        color: displayRow.focusedDisplay || displayRow.highlighted
          ? panel.controlAccent : panel.controlForeground
        font.pixelSize: Commons.Style.font.body
        fill: 1
      }

      Column {
        width: parent.width - x - stateIcon.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          width: parent.width
          text: String(displayRow.display.name || "Display")
          color: displayRow.focusedDisplay || displayRow.highlighted
            ? panel.controlAccent : panel.controlForeground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.body
          font.weight: displayRow.focusedDisplay ? Font.DemiBold : Font.Normal
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          text: displayRow.focusedDisplay ? "Focused"
            : displayRow.enabledDisplay ? "Enabled" : "Disabled"
          color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
            panel.bar.foreground.g, panel.bar.foreground.b, 0.55)
            : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption
          renderType: Text.NativeRendering
        }
      }

      IconText {
        id: stateIcon
        anchors.verticalCenter: parent.verticalCenter
        text: displayRow.enabledDisplay ? "check_circle" : "radio_button_unchecked"
        color: displayRow.enabledDisplay
          ? panel.controlAccent : panel.controlForeground
        font.pixelSize: Commons.Style.font.body
        fill: displayRow.enabledDisplay ? 1 : 0
      }
    }

    MouseArea {
      id: displayMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: displayRow.canToggle
      cursorShape: displayRow.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) {
        panel.cursorActive = true
        panel.cursorSection = "displays"
        panel.cursorIndex = displayRow.rowIndex
      }
      onClicked: panel.monitorService.toggleDisplay(
        displayRow.display.name, displayRow.enabledDisplay)
    }
  }
}
