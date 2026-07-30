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

    onPaint: {
      const context = getContext("2d")
      context.reset()
      const w = width
      const h = height

      if (root.styleValue === "omarchy"
          || root.styleValue === "carousel") {
        card(context, w * 0.06, h * 0.18, w * 0.25, h * 0.64, 4, false)
        card(context, w * 0.69, h * 0.18, w * 0.25, h * 0.64, 4, false)
        card(context, w * 0.24, h * 0.06, w * 0.52, h * 0.76, 5, true)
        context.fillStyle = Commons.Util.alpha(root.foreground, 0.72)
        for (let index = 0; index < 3; index++) {
          context.beginPath()
          context.arc(w * 0.46 + index * w * 0.04, h * 0.92,
            index === 1 ? 2 : 1.4, 0, Math.PI * 2)
          context.fill()
        }
      } else if (root.styleValue === "tanzaku") {
        const widths = [0.17, 0.20, 0.17, 0.20]
        const tops = [0.15, 0.04, 0.20, 0.09]
        for (let index = 0; index < 4; index++) {
          const x = w * (0.09 + index * 0.22)
          const y = h * tops[index]
          card(context, x, y, w * widths[index],
            h * (0.78 - tops[index]), 3, index === 1)
          context.fillStyle = index === 1
            ? Commons.Util.alpha(root.accent, 0.72)
            : Commons.Util.alpha(root.foreground, 0.34)
          context.fillRect(x + w * 0.025, y + h * 0.12,
            w * (widths[index] - 0.05), 1)
        }
      } else {
        // Match the real Hearthstone hand: dim fanned side cards and one
        // larger, lifted focus card with a framed image and title strip.
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
