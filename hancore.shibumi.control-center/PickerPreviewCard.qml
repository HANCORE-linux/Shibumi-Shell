pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string styleValue
  required property string label
  property string selectedValue: ""
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property real uiScale: 1
  readonly property bool selected: selectedValue === styleValue
  signal chosen(string styleValue)

  height: Commons.Style.space(82)
  radius: controller.controlRadius
  color: selected || pointer.containsMouse
    ? controller.controlHoverFillColor : controller.controlFillColor
  border.width: selected ? Math.max(1, controller.controlBorderWidth) : 1
  border.color: selected ? accent : controller.controlBorderColor

  Canvas {
    id: preview
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      margins: Commons.Style.space(7)
    }
    height: Commons.Style.space(47)
    antialiasing: true

    function roundedRect(context, x, y, width, height, radius) {
      const r = Math.min(radius, width / 2, height / 2)
      context.beginPath()
      context.moveTo(x + r, y)
      context.lineTo(x + width - r, y)
      context.quadraticCurveTo(x + width, y, x + width, y + r)
      context.lineTo(x + width, y + height - r)
      context.quadraticCurveTo(x + width, y + height,
        x + width - r, y + height)
      context.lineTo(x + r, y + height)
      context.quadraticCurveTo(x, y + height, x, y + height - r)
      context.lineTo(x, y + r)
      context.quadraticCurveTo(x, y, x + r, y)
      context.closePath()
    }

    function card(context, x, y, width, height, radius, emphasized) {
      roundedRect(context, x, y, width, height, radius)
      context.fillStyle = emphasized
        ? Commons.Util.alpha(root.accent, 0.24)
        : Commons.Util.alpha(root.foreground, 0.09)
      context.fill()
      context.strokeStyle = emphasized
        ? Commons.Util.alpha(root.accent, 0.86)
        : Commons.Util.alpha(root.foreground, 0.34)
      context.lineWidth = emphasized ? 1.25 : 1
      context.stroke()
    }

    function skewedCard(context, x, y, width, height, skew, emphasized) {
      context.beginPath()
      context.moveTo(x + skew, y)
      context.lineTo(x + width, y)
      context.lineTo(x + width - skew, y + height)
      context.lineTo(x, y + height)
      context.closePath()
      context.fillStyle = emphasized
        ? Commons.Util.alpha(root.accent, 0.24)
        : Commons.Util.alpha(root.foreground, 0.09)
      context.fill()
      context.strokeStyle = emphasized
        ? Commons.Util.alpha(root.accent, 0.86)
        : Commons.Util.alpha(root.foreground, 0.34)
      context.lineWidth = emphasized ? 1.25 : 1
      context.stroke()
    }

    function drawOmarchy(context, w, h) {
      drawCarousel(context, w, h)
    }

    function drawCarousel(context, w, h) {
      // Match CarouselPickerView and its source design: skewed, overlapping
      // slices with one expanded trapezoid-like focus card.
      const focusX = w * 0.24
      const focusY = h * 0.06
      const focusWidth = w * 0.52
      const focusHeight = h * 0.76
      const sliceWidth = w * 0.09
      const sliceHeight = h * 0.69
      const sliceY = h * 0.095
      const step = w * 0.065
      const skew = w * 0.025
      skewedCard(context, focusX - step * 2, sliceY,
        sliceWidth, sliceHeight, skew, false)
      skewedCard(context, focusX - step, sliceY,
        sliceWidth, sliceHeight, skew, false)
      skewedCard(context, focusX + focusWidth - w * 0.025, sliceY,
        sliceWidth, sliceHeight, skew, false)
      skewedCard(context, focusX + focusWidth - w * 0.025 + step, sliceY,
        sliceWidth, sliceHeight, skew, false)
      skewedCard(context, focusX, focusY,
        focusWidth, focusHeight, skew, true)
    }

    function drawTanzaku(context, w, h) {
      // This exact focus-and-slice schematic was previously assigned to
      // Carousel. It describes the real Tanzaku layout instead.
      const focusX = w * 0.24
      const focusY = h * 0.06
      const focusWidth = w * 0.52
      const focusHeight = h * 0.76
      const sliceWidth = w * 0.055
      const gap = w * 0.025
      card(context, focusX - gap * 2 - sliceWidth * 2, focusY,
        sliceWidth, focusHeight, 3, false)
      card(context, focusX - gap - sliceWidth, focusY,
        sliceWidth, focusHeight, 3, false)
      card(context, focusX, focusY, focusWidth, focusHeight, 5, true)
      card(context, focusX + focusWidth + gap, focusY,
        sliceWidth, focusHeight, 3, false)
      card(context, focusX + focusWidth + gap * 2 + sliceWidth, focusY,
        sliceWidth, focusHeight, 3, false)
    }

    function hearthCard(context, centerX, bottomY, width, height,
        angle, emphasized) {
      context.save()
      context.translate(centerX, bottomY)
      context.rotate(angle)
      const x = -width / 2
      const y = -height
      card(context, x, y, width, height, 4, emphasized)

      roundedRect(context, x + 3, y + 3, width - 6, height - 6, 2)
      context.fillStyle = emphasized
        ? Commons.Util.alpha(root.accent, 0.18)
        : Commons.Util.alpha(root.foreground, 0.07)
      context.fill()
      context.fillStyle = Commons.Util.alpha(root.foreground,
        emphasized ? 0.30 : 0.14)
      context.fillRect(x + 4, y + height * 0.67, width - 8, height * 0.20)
      context.fillStyle = emphasized
        ? Commons.Util.alpha(root.accent, 0.92)
        : Commons.Util.alpha(root.foreground, 0.38)
      context.fillRect(x + width * 0.22, y + height * 0.75,
        width * 0.56, 1)
      context.restore()
    }

    function drawHearthstone(context, w, h) {
      hearthCard(context, w * 0.25, h * 0.93,
        w * 0.23, h * 0.66, -0.16, false)
      hearthCard(context, w * 0.75, h * 0.93,
        w * 0.23, h * 0.66, 0.16, false)
      hearthCard(context, w * 0.50, h * 0.86,
        w * 0.29, h * 0.80, 0, true)
      context.fillStyle = Commons.Util.alpha(root.accent, 0.94)
      context.beginPath()
      context.arc(w * 0.50, h * 0.18, 2.2, 0, Math.PI * 2)
      context.fill()
    }

    onPaint: {
      const context = getContext("2d")
      context.reset()
      const w = width
      const h = height

      if (root.styleValue === "omarchy") drawOmarchy(context, w, h)
      else if (root.styleValue === "carousel") drawCarousel(context, w, h)
      else if (root.styleValue === "tanzaku") drawTanzaku(context, w, h)
      else drawHearthstone(context, w, h)
    }

    Connections {
      target: root
      function onStyleValueChanged() { preview.requestPaint() }
      function onSelectedChanged() { preview.requestPaint() }
      function onForegroundChanged() { preview.requestPaint() }
      function onAccentChanged() { preview.requestPaint() }
    }
  }

  Text {
    anchors {
      horizontalCenter: parent.horizontalCenter
      bottom: parent.bottom
      bottomMargin: Commons.Style.space(6)
    }
    text: root.label
    color: root.selected ? root.accent : root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.DemiBold
  }

  Text {
    visible: root.selected
    anchors {
      right: parent.right
      top: parent.top
      margins: Commons.Style.space(5)
    }
    text: "✓"
    color: root.accent
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Bold
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.chosen(root.styleValue)
  }

}
