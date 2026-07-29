pragma ComponentBehavior: Bound

import QtQuick

Canvas {
  id: root

  property var levels: []
  property color tint: "white"
  property var themeColors: []

  onLevelsChanged: requestPaint()
  onTintChanged: requestPaint()
  onThemeColorsChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  Component.onCompleted: requestPaint()

  onPaint: {
    const ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    const values = levels || []
    if (values.length === 0) return

    const barWidth = 4
    const gap = Math.max(1, (width - values.length * barWidth) / (values.length + 1))
    const maxHeight = Math.max(barWidth, height - 2)
    const palette = themeColors || []
    if (palette.length > 1) {
      const gradient = ctx.createLinearGradient(0, height, 0, 0)
      for (let index = 0; index < palette.length; index++)
        gradient.addColorStop(index / (palette.length - 1), palette[index])
      ctx.fillStyle = gradient
    } else {
      ctx.fillStyle = palette.length === 1 ? palette[0] : tint
    }

    for (let i = 0; i < values.length; i++) {
      const barHeight = Math.max(barWidth,
        Math.min(1, Number(values[i]) || 0) * maxHeight)
      const x = gap + i * (barWidth + gap)
      const y = height - barHeight
      const radius = barWidth / 2

      ctx.beginPath()
      ctx.moveTo(x + radius, y)
      ctx.lineTo(x + barWidth - radius, y)
      ctx.arcTo(x + barWidth, y, x + barWidth, y + radius, radius)
      ctx.lineTo(x + barWidth, y + barHeight)
      ctx.lineTo(x, y + barHeight)
      ctx.lineTo(x, y + radius)
      ctx.arcTo(x, y, x + radius, y, radius)
      ctx.closePath()
      ctx.fill()
    }
  }
}
