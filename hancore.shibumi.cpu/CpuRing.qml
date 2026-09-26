// Plugin-local copy of Shibumi's MemoryRing; no cross-plugin presentation import.
import QtQuick
import qs.Commons as Commons

Canvas {
  id: root

  required property int percent
  required property color foreground
  required property color accent
  property bool water: false

  width: Commons.Style.space(16)
  height: width

  onPercentChanged: requestPaint()
  onWaterChanged: requestPaint()
  onForegroundChanged: requestPaint()
  onAccentChanged: requestPaint()
  Component.onCompleted: requestPaint()

  onPaint: {
    const context = getContext("2d")
    context.clearRect(0, 0, width, height)
    const center = width / 2
    const radius = width / 2 - 1.5
    const ratio = Math.max(0, Math.min(1, percent / 100))
    const start = -Math.PI / 2

    // Static waterline: height follows the clamped value; no clock or animation.
    if (water && ratio > 0) {
      const inner = radius - 3
      const left = center - inner, right = center + inner, bottom = center + inner
      const level = bottom - 2 * inner * ratio
      const wave = Math.min(Commons.Style.space(3), 2 * inner * ratio, 2 * inner * (1 - ratio))
      context.save()
      context.beginPath()
      context.arc(center, center, inner, 0, Math.PI * 2)
      context.clip()
      context.beginPath()
      context.moveTo(left, level)
      context.bezierCurveTo(center - inner / 3, level - wave, center + inner / 3, level + wave, right, level)
      context.lineTo(right, bottom)
      context.lineTo(left, bottom)
      context.closePath()
      context.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.35)
      context.fill()
      context.restore()
    }

    context.lineWidth = 1.8
    context.lineCap = "round"
    context.beginPath()
    context.arc(center, center, radius, 0, Math.PI * 2)
    context.strokeStyle = Qt.rgba(foreground.r, foreground.g, foreground.b, 0.2)
    context.stroke()

    if (ratio > 0) {
      context.beginPath()
      context.arc(center, center, radius, start, start + Math.PI * 2 * ratio)
      context.strokeStyle = accent
      context.stroke()
    }
  }
}
