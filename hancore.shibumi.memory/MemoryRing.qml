import QtQuick
import qs.Commons as Commons

Canvas {
  id: root

  required property int percent
  required property color foreground
  required property color accent

  width: Commons.Style.space(16)
  height: width

  onPercentChanged: requestPaint()
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
