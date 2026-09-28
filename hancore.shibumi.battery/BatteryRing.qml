import QtQuick
import QtQuick.Window
import qs.Commons as Commons

// Battery-local effects over the shared, panel-gated water renderer.
Item {
  id: root
  required property int percent
  required property color foreground
  required property color accent
  property bool panelOpen: false
  property bool waves: true
  property bool plasma: false
  readonly property bool water: true
  readonly property bool animating: liquid.animating || arcClock.running
  readonly property bool plasmaAnimating: arcClock.running
  readonly property int waveFrame: liquid.waveFrame
  readonly property real physicalPixel: 1 / Math.max(1, Screen.devicePixelRatio)
  readonly property color lightAccent: Qt.tint(accent, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55))
  readonly property color brightInk: Qt.lighter(foreground, 1.12)
  property var arcs: []
  property int arcFrame: 0
  width: Commons.Style.space(80)
  height: width

  WaterRing {
    id: liquid
    anchors.fill: parent
    percent: root.percent; foreground: root.foreground; accent: root.accent
    panelOpen: root.panelOpen; waves: root.waves
    onWaveFrameChanged: root.repaint()
  }

  function repaint() { if (panelOpen && plasma && bolts) bolts.requestPaint() }
  onForegroundChanged: repaint()
  onAccentChanged: repaint()

  function jag(start, end) {
    let points = [start, end]
    for (let depth = 0; depth < 6; depth++) {
      const next = [points[0]]
      for (let i = 1; i < points.length; i++) {
        const a = points[i - 1], b = points[i], dx = b[0] - a[0], dy = b[1] - a[1]
        const length = Math.sqrt(dx * dx + dy * dy) || 1
        const offset = (Math.random() - 0.5) * length * 0.28
        next.push([(a[0] + b[0]) / 2 - dy / length * offset,
          (a[1] + b[1]) / 2 + dx / length * offset], b)
      }
      points = next
    }
    return points
  }

  Timer {
    id: arcClock
    interval: 160; repeat: true
    running: root.panelOpen && root.plasma
    onTriggered: {
      const next = []
      for (let i = 0; i < 5; i++) {
        const angle = -Math.PI / 2 + (Math.random() - 0.5) * 2.2
        const x = Math.cos(angle) * 1.2
        next.push({ points: root.jag([0, 0.45], [x, bolts.surface(x)]), flicker: 0.7 + Math.random() * 0.3 })
      }
      root.arcs = next
      root.arcFrame = (root.arcFrame + 1) % 45
      bolts.requestPaint()
    }
  }
  onPanelOpenChanged: { if (!panelOpen) arcs = []; repaint() }
  onPlasmaChanged: { if (!plasma) arcs = []; repaint() }

  Canvas {
    id: bolts
    anchors.fill: parent
    visible: root.panelOpen && root.plasma
    readonly property real radius: width / 2 - 4.5
    readonly property real ratio: Math.max(0, Math.min(1, liquid.displayedPercent / 100))

    // Match the shared WaterRing surface so every effect stays underwater.
    function surface(x) {
      const amplitude = root.waves ? Math.min(Commons.Style.space(3), 2 * radius * ratio, 2 * radius * (1 - ratio)) * 0.3 / radius : 0
      return 1 - 2 * ratio + amplitude * Math.sin((x + 1) * Math.PI * 2 - liquid.waveFrame / 72 * Math.PI * 2)
    }
    onVisibleChanged: if (visible) requestPaint()
    onPaint: {
      if (!root.panelOpen || !root.plasma) return
      const ctx = getContext("2d"), center = width / 2, r = radius
      ctx.clearRect(0, 0, width, height)
      if (ratio <= 0) return
      ctx.save()
      ctx.beginPath(); ctx.arc(center, center, r, 0, Math.PI * 2); ctx.clip()
      ctx.beginPath(); ctx.moveTo(center - r, center + r)
      for (let i = 0; i <= 40; i++) {
        const x = -1 + i / 20
        ctx.lineTo(center + x * r, center + surface(x) * r)
      }
      ctx.lineTo(center + r, center + r); ctx.closePath(); ctx.clip()
      ctx.lineJoin = "round"; ctx.lineCap = "round"
      const glow = root.lightAccent, ink = root.brightInk
      for (const arc of root.arcs) {
        ctx.beginPath()
        arc.points.forEach((p, index) => {
          const x = center + p[0] * r, y = center + p[1] * r
          if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
        })
        ctx.shadowBlur = r * 0.05
        ctx.shadowColor = Qt.rgba(glow.r, glow.g, glow.b, 0.16 * arc.flicker)
        ctx.strokeStyle = ctx.shadowColor
        ctx.lineWidth = Math.min(root.physicalPixel * 0.6, r * 0.018); ctx.stroke()
        ctx.shadowBlur = 0; ctx.shadowColor = "transparent"
        ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.42 * arc.flicker)
        ctx.lineWidth = root.physicalPixel; ctx.stroke()
      }
      const coreY = center + r * 0.45
      const halo = r * (0.155 + 0.005 * Math.sin(root.arcFrame * 160 / 3600 * Math.PI * 4))
      ctx.beginPath(); ctx.arc(center, coreY, halo, 0, Math.PI * 2)
      ctx.shadowBlur = r * 0.033
      ctx.shadowColor = Qt.rgba(glow.r, glow.g, glow.b, 0.35)
      ctx.fillStyle = ctx.shadowColor; ctx.fill()
      ctx.shadowBlur = 0; ctx.shadowColor = "transparent"
      ctx.beginPath(); ctx.arc(center, coreY, r * 0.054, 0, Math.PI * 2)
      ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.85); ctx.fill()
      ctx.restore()
    }
  }
}
