import QtQuick
import qs.Commons as Commons

// Active, panel-local presentation; vendored, never a State-library scheduler.
Canvas {
  id: root

  required property int percent
  required property color foreground
  required property color accent
  property bool water: true
  property bool panelOpen: false
  property bool waves: true
  property real waterOpacity: 0.35
  property bool bubbles: false
  property bool outlined: true
  property bool progressArc: true
  property real holeRatio: 0
  property real phaseOffset: 0
  readonly property bool animationActive: water && panelOpen && (waves || bubbles)
  readonly property bool animating: clock.running
  property int waveFrame: 0
  property real displayedPercent: percent

  width: Commons.Style.space(80)
  height: width

  function repaint() { if (!water || panelOpen) requestPaint() }
  Timer {
    id: clock
    interval: 50
    running: root.water && root.panelOpen && (root.waves || root.bubbles)
    repeat: true
    onTriggered: {
      root.waveFrame = (root.waveFrame + 1) % 72
      const delta = root.percent - root.displayedPercent
      root.displayedPercent = Math.abs(delta) < 0.1 ? root.percent : root.displayedPercent + delta * 0.25
      root.requestPaint()
    }
  }
  onPanelOpenChanged: {
    if (!panelOpen) return
    displayedPercent = percent
    repaint()
  }
  onPercentChanged: { if (!animationActive) displayedPercent = percent; repaint() }
  onForegroundChanged: repaint()
  onAccentChanged: repaint()
  onWaterOpacityChanged: repaint()
  onHoleRatioChanged: repaint()
  onWaterChanged: repaint()
  Component.onCompleted: repaint()

  onPaint: {
    if (water && !panelOpen) return
    const context = getContext("2d")
    context.clearRect(0, 0, width, height)
    const center = width / 2
    const radius = width / 2 - 1.5
    const inner = outlined ? radius - 3 : radius
    const hole = Math.max(0, Math.min(0.9, holeRatio)) * inner
    const ratio = Math.max(0, Math.min(1, (water ? displayedPercent : percent) / 100))
    const start = -Math.PI / 2

    if (water && ratio > 0) {
      const left = center - inner, right = center + inner, bottom = center + inner
      const level = bottom - 2 * inner * ratio
      const wave = waves ? Math.min(Commons.Style.space(3), 2 * inner * ratio, 2 * inner * (1 - ratio)) : 0
      context.save()
      context.beginPath()
      context.arc(center, center, inner, 0, Math.PI * 2)
      if (hole > 0) { context.moveTo(center + hole, center); context.arc(center, center, hole, 0, Math.PI * 2, true) }
      context.clip()
      context.beginPath()
      context.moveTo(left, bottom)
      for (let step = 0; step <= 40; step++) {
        const phase = step / 40 * Math.PI * 4 - waveFrame / 72 * Math.PI * 2 + phaseOffset
        context.lineTo(left + (right - left) * step / 40, level + wave * 0.3 * Math.sin(phase))
      }
      context.lineTo(right, bottom)
      context.lineTo(left, bottom)
      context.closePath()
      context.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, waterOpacity)
      context.fill()
      if (bubbles) {
        context.clip()
        const count = 2 + Math.floor(Math.pow(ratio, 3) * 12)
        for (let i = 0; i < count; i++) {
          const t = (waveFrame / 72 + i * 0.381966) % 1
          const x = center + Math.sin(i * 2.4) * inner * 0.7 + Math.sin(t * 6 + i) * 1.5
          const y = bottom - t * (bottom - level + 4)
          context.beginPath()
          context.arc(x, y, Commons.Style.space(1.2 + i % 3 * 0.6), 0, Math.PI * 2)
          context.strokeStyle = Qt.rgba(foreground.r, foreground.g, foreground.b, 0.5)
          context.lineWidth = 0.8
          context.stroke()
        }
      }
      context.restore()
    }

    context.lineWidth = 1.8
    context.lineCap = "round"
    context.beginPath()
    context.arc(center, center, radius, 0, Math.PI * 2)
    context.strokeStyle = Qt.rgba(foreground.r, foreground.g, foreground.b, 0.2)
    if (outlined) context.stroke()
    if (outlined && progressArc && ratio > 0) {
      context.beginPath()
      context.arc(center, center, radius, start, start + Math.PI * 2 * ratio)
      context.strokeStyle = accent
      context.stroke()
    }
  }
}
