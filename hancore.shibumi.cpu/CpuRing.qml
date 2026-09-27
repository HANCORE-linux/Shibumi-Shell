// Plugin-local copy of Shibumi's MemoryRing; no cross-plugin presentation import.
import QtQuick
import qs.Commons as Commons

Canvas {
  id: root

  required property int percent
  required property color foreground
  required property color accent
  property bool water: false
  property bool panelOpen: false
  readonly property bool animationActive: water && panelOpen
  readonly property bool animating: waveClock.running
  property int waveFrame: 0
  property real displayedPercent: percent

  NumberAnimation on waveFrame {
    id: waveClock
    from: 0; to: 72; duration: 3600; loops: Animation.Infinite
    running: root.animationActive
  }
  onAnimationActiveChanged: if (animationActive) displayedPercent = percent
  // One ~20 Hz clock advances both the wave and the gently settling level.
  onWaveFrameChanged: {
    if (!animationActive) return
    const delta = percent - displayedPercent
    displayedPercent = Math.abs(delta) < 0.1 ? percent : displayedPercent + delta * 0.25
    requestPaint()
  }

  width: Commons.Style.space(16)
  height: width

  onPercentChanged: if (!water) requestPaint()
  onWaterChanged: if (!water) requestPaint()
  onForegroundChanged: if (!water) requestPaint()
  onAccentChanged: if (!water) requestPaint()
  Component.onCompleted: if (!water) requestPaint()

  onPaint: {
    if (water && !panelOpen) return
    const context = getContext("2d")
    context.clearRect(0, 0, width, height)
    const center = width / 2
    const radius = width / 2 - 1.5
    const ratio = Math.max(0, Math.min(1, (water ? displayedPercent : percent) / 100))
    const start = -Math.PI / 2

    // Two slow crests, with the subtle amplitude of the former cubic waterline.
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
      context.moveTo(left, bottom)
      for (let step = 0; step <= 40; step++) {
        const phase = step / 40 * Math.PI * 4 - waveFrame / 72 * Math.PI * 2
        context.lineTo(left + (right - left) * step / 40, level + wave * 0.3 * Math.sin(phase))
      }
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
