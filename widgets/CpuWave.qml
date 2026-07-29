import QtQuick
import qs.Commons as Commons

Canvas {
  id: root

  required property var history
  required property color accent
  property int maxSamples: 30

  width: Commons.Style.space(36)
  height: Commons.Style.space(14)

  onHistoryChanged: requestPaint()
  onAccentChanged: requestPaint()
  Component.onCompleted: requestPaint()

  onPaint: {
    const context = getContext("2d")
    context.clearRect(0, 0, width, height)
    const values = root.history || []
    if (values.length < 2) return

    let maximum = 0.25
    for (let i = 0; i < values.length; i++) maximum = Math.max(maximum, values[i])
    maximum = Math.min(1, Math.max(0.25, maximum * 1.15))

    const points = []
    for (let j = 0; j < values.length; j++) {
      points.push({
        x: (j / Math.max(1, maxSamples - 1)) * width,
        y: height - (values[j] / maximum) * height
      })
    }

    context.beginPath()
    context.moveTo(points[0].x, height)
    context.lineTo(points[0].x, points[0].y)
    for (let k = 1; k < points.length; k++) {
      const controlX = (points[k - 1].x + points[k].x) / 2
      context.bezierCurveTo(controlX, points[k - 1].y, controlX, points[k].y,
        points[k].x, points[k].y)
    }
    context.lineTo(points[points.length - 1].x, height)
    context.closePath()
    context.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.12)
    context.fill()

    context.beginPath()
    context.moveTo(points[0].x, points[0].y)
    for (let n = 1; n < points.length; n++) {
      const controlX = (points[n - 1].x + points[n].x) / 2
      context.bezierCurveTo(controlX, points[n - 1].y, controlX, points[n].y,
        points[n].x, points[n].y)
    }
    context.strokeStyle = accent
    context.lineWidth = 1.5
    context.lineCap = "round"
    context.lineJoin = "round"
    context.stroke()
  }
}
