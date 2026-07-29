pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property var bar
  required property int mode
  required property var runs
  readonly property bool active: mode >= 1 && mode <= 6 && runs.length > 1

  visible: active

  function requestFrame() {
    if (active && width > 0 && height > 0) canvas.requestPaint()
  }

  onModeChanged: requestFrame()
  onRunsChanged: requestFrame()
  onWidthChanged: requestFrame()
  onHeightChanged: requestFrame()

  Timer {
    interval: root.mode === 5 || root.mode === 6 ? 16 : 33
    repeat: true
    running: root.active
    onTriggered: root.requestFrame()
  }

  Canvas {
    id: canvas

    anchors.fill: parent
    renderStrategy: Canvas.Threaded

    onPaint: {
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!root.active) return

      const now = Date.now()
      const cy = height / 2
      const seal = root.bar.urgent
      const sr = Math.round(seal.r * 255)
      const sg = Math.round(seal.g * 255)
      const sb = Math.round(seal.b * 255)
      const rgba = function(alpha) {
        return "rgba(" + sr + "," + sg + "," + sb + "," + alpha + ")"
      }
      const hash = function(value) {
        const result = Math.sin(value * 127.1) * 43758.5453
        return result - Math.floor(result)
      }

      for (let gapIndex = 0; gapIndex + 1 < root.runs.length; gapIndex++) {
        const leftRun = root.runs[gapIndex]
        const rightRun = root.runs[gapIndex + 1]
        const x1 = Number(leftRun.x || 0) + Number(leftRun.width || 0)
        const x2 = Number(rightRun.x || 0)
        const gapWidth = x2 - x1
        if (gapWidth < 10 || !isFinite(x1) || !isFinite(x2)) continue

        ctx.save()
        ctx.beginPath()
        ctx.rect(x1, 0, gapWidth, height)
        ctx.clip()

        if (root.mode === 1) {
          const glowHeight = 8
          const glow = ctx.createLinearGradient(0, cy - glowHeight, 0, cy + glowHeight)
          glow.addColorStop(0.00, rgba(0.00))
          glow.addColorStop(0.25, rgba(0.06))
          glow.addColorStop(0.45, rgba(0.11))
          glow.addColorStop(0.50, rgba(0.14))
          glow.addColorStop(0.55, rgba(0.11))
          glow.addColorStop(0.75, rgba(0.06))
          glow.addColorStop(1.00, rgba(0.00))
          ctx.globalAlpha = 1
          ctx.fillStyle = glow
          ctx.fillRect(x1, cy - glowHeight, gapWidth, glowHeight * 2)

          ctx.globalAlpha = 0.55
          ctx.strokeStyle = rgba(1)
          ctx.lineWidth = 1.5
          ctx.beginPath()
          ctx.moveTo(x1, cy)
          ctx.lineTo(x2, cy)
          ctx.stroke()
          ctx.globalAlpha = 0.28
          ctx.strokeStyle = "#ffffff"
          ctx.lineWidth = 0.75
          ctx.beginPath()
          ctx.moveTo(x1, cy)
          ctx.lineTo(x2, cy)
          ctx.stroke()

          const fastSpacing = 65
          const slowSpacing = 110
          const fastOffset = (now / 1000 * 70) % fastSpacing
          const slowOffset = (now / 1000 * 38) % slowSpacing
          const fastStart = Math.ceil((x1 - fastOffset) / fastSpacing)
          for (let dot = 0; dot < 60; dot++) {
            const dotId = fastStart + dot + 100000
            const dotX = fastOffset + (fastStart + dot) * fastSpacing
            if (dotX >= x2) break
            const pulse = dotId % 5 === 0
              ? 0.5 + 0.5 * Math.sin(now / 700 + dotId * 2.4) : 0
            ctx.globalAlpha = pulse > 0 ? 0.28 + pulse * 0.18 : 0.30
            ctx.fillStyle = seal
            ctx.beginPath()
            ctx.arc(dotX, cy, pulse > 0 ? 4 + pulse * 1.5 : 4.5, 0, Math.PI * 2)
            ctx.fill()
            ctx.globalAlpha = pulse > 0 ? 0.95 : 0.90
            ctx.fillStyle = "#ffffff"
            ctx.beginPath()
            ctx.arc(dotX, cy, pulse > 0 ? 1.6 + pulse * 0.4 : 1.6, 0, Math.PI * 2)
            ctx.fill()
          }

          const slowStart = Math.ceil((x1 - slowOffset) / slowSpacing)
          for (let dot = 0; dot < 40; dot++) {
            const dotX = slowOffset + (slowStart + dot) * slowSpacing
            if (dotX >= x2) break
            ctx.globalAlpha = 0.11
            ctx.fillStyle = seal
            ctx.beginPath()
            ctx.arc(dotX, cy, 8.5, 0, Math.PI * 2)
            ctx.fill()
            ctx.globalAlpha = 0.50
            ctx.fillStyle = "#ffffff"
            ctx.beginPath()
            ctx.arc(dotX, cy, 2.3, 0, Math.PI * 2)
            ctx.fill()
          }
        } else if (root.mode === 2) {
          const cycle = 3900
          const phase = (((now % cycle) / cycle) + gapIndex * 0.20) % 1
          const envelope = Math.min(1, phase / 0.12)
          const mid = (x1 + x2) / 2
          const reach = gapWidth / 2
          const leftX = x1 + phase * reach
          const rightX = x2 - phase * reach

          ctx.globalAlpha = 0.16
          ctx.strokeStyle = seal
          ctx.lineWidth = 1
          ctx.beginPath()
          ctx.moveTo(x1, cy)
          ctx.lineTo(x2, cy)
          ctx.stroke()

          const leftTrace = ctx.createLinearGradient(x1, 0, leftX, 0)
          leftTrace.addColorStop(0, rgba(0))
          leftTrace.addColorStop(1, rgba(0.5 * envelope))
          ctx.globalAlpha = 1
          ctx.strokeStyle = leftTrace
          ctx.lineWidth = 1.6
          ctx.beginPath()
          ctx.moveTo(x1, cy)
          ctx.lineTo(leftX, cy)
          ctx.stroke()
          const rightTrace = ctx.createLinearGradient(x2, 0, rightX, 0)
          rightTrace.addColorStop(0, rgba(0))
          rightTrace.addColorStop(1, rgba(0.5 * envelope))
          ctx.strokeStyle = rightTrace
          ctx.beginPath()
          ctx.moveTo(x2, cy)
          ctx.lineTo(rightX, cy)
          ctx.stroke()

          ctx.globalAlpha = 0.45 * envelope
          ctx.fillStyle = seal
          ctx.beginPath()
          ctx.arc(leftX, cy, 4, 0, Math.PI * 2)
          ctx.fill()
          ctx.beginPath()
          ctx.arc(rightX, cy, 4, 0, Math.PI * 2)
          ctx.fill()
          ctx.globalAlpha = 0.95 * envelope
          ctx.fillStyle = "#ffffff"
          ctx.beginPath()
          ctx.arc(leftX, cy, 1.7, 0, Math.PI * 2)
          ctx.fill()
          ctx.beginPath()
          ctx.arc(rightX, cy, 1.7, 0, Math.PI * 2)
          ctx.fill()

          if (phase > 0.78) {
            const flash = (phase - 0.78) / 0.22
            ctx.globalAlpha = 0.50 * (1 - flash)
            ctx.fillStyle = "#ffffff"
            ctx.beginPath()
            ctx.arc(mid, cy, 2 + flash * 6, 0, Math.PI * 2)
            ctx.fill()
            ctx.globalAlpha = 0.30 * (1 - flash)
            ctx.fillStyle = seal
            ctx.beginPath()
            ctx.arc(mid, cy, 4 + flash * 10, 0, Math.PI * 2)
            ctx.fill()
          }
        } else if (root.mode === 3) {
          const cycle = 3800
          const local = now / cycle + gapIndex * 0.37
          const phase = local - Math.floor(local)
          const seed = Math.floor(local) * 131.7 + gapIndex * 53.3
          const charging = phase < 0.82
          const charge = Math.pow(Math.min(1, phase / 0.82), 1.6)
          const discharge = charging ? 0 : (phase - 0.82) / 0.18
          const intensity = charging ? charge : 1 - discharge
          const baseAmplitude = Math.min(height * 0.30, 6)
          const amplitude = (0.22 + 0.78 * intensity) * baseAmplitude
          const step = Math.max(2, Math.round(gapWidth / 120))
          const waveTime = now / 1300
          const waves = [[0.055, -3, 0, 1], [0.072, 3.6, 2.4, 0.78]]
          for (let waveIndex = 0; waveIndex < waves.length; waveIndex++) {
            const wave = waves[waveIndex]
            ctx.beginPath()
            let first = true
            for (let waveX = x1; waveX <= x2; waveX += step) {
              const waveY = cy + amplitude * wave[3]
                * Math.sin(waveX * wave[0] + waveTime * wave[1] + wave[2])
              if (first) {
                ctx.moveTo(waveX, waveY)
                first = false
              } else {
                ctx.lineTo(waveX, waveY)
              }
            }
            ctx.globalAlpha = (0.05 + intensity * 0.16) * wave[3]
            ctx.strokeStyle = seal
            ctx.lineWidth = 2.6
            ctx.stroke()
            ctx.globalAlpha = (0.22 + intensity * 0.55) * wave[3]
            ctx.lineWidth = 1
            ctx.stroke()
          }

          if (!charging) {
            const segments = Math.max(4, Math.min(14, Math.round(gapWidth / 26)))
            const boltAmplitude = Math.min(height * 0.26, 4.6)
            const strikeEnvelope = function(value, start, end, power) {
              if (value < start || value > end) return 0
              return power * Math.pow(1 - (value - start) / (end - start), 2.35)
            }
            const trailEnvelope = function(value, start, end, power) {
              if (value < start || value > end) return 0
              return power * Math.pow(1 - (value - start) / (end - start), 1.55)
            }
            const firstStart = 0.015 + hash(seed + 211) * 0.085
            const firstEnd = firstStart + 0.24 + hash(seed + 212) * 0.10
            const secondStart = firstStart + 0.21 + hash(seed + 213) * 0.18
            const secondEnd = Math.min(0.98,
              secondStart + 0.24 + hash(seed + 214) * 0.12)
            const firstStrike = strikeEnvelope(discharge, firstStart, firstEnd,
              0.86 + hash(seed + 215) * 0.20)
            const secondStrike = strikeEnvelope(discharge, secondStart, secondEnd,
              0.72 + hash(seed + 216) * 0.26)
            const firstTrail = trailEnvelope(discharge, firstStart + 0.02,
              Math.min(0.96, firstEnd + 0.38 + hash(seed + 217) * 0.16),
              0.54 + hash(seed + 218) * 0.18)
            const secondTrail = trailEnvelope(discharge, secondStart + 0.02,
              Math.min(0.99, secondEnd + 0.28 + hash(seed + 219) * 0.14),
              0.42 + hash(seed + 220) * 0.16)
            const hot = Math.max(firstStrike, secondStrike)
            const flash = Math.pow(hot, 1.15)
              + 0.10 * Math.max(firstTrail, secondTrail)
            if (flash > 0) {
              const flashHeight = 9
              const flashGlow = ctx.createLinearGradient(0, cy - flashHeight,
                0, cy + flashHeight)
              flashGlow.addColorStop(0, rgba(0))
              flashGlow.addColorStop(0.5, rgba(0.24 * flash))
              flashGlow.addColorStop(1, rgba(0))
              ctx.globalAlpha = 1
              ctx.fillStyle = flashGlow
              ctx.fillRect(x1, cy - flashHeight, gapWidth, flashHeight * 2)
            }
            const drawStrike = function(laneSeed, strike, trail) {
              if (strike <= 0.01 && trail <= 0.01) return
              const lean = (hash(laneSeed + 700) - 0.5) * 2
                * boltAmplitude * 0.55
              ctx.lineJoin = "round"
              ctx.beginPath()
              ctx.moveTo(x1, cy)
              for (let segment = 1; segment <= segments; segment++) {
                const progress = segment / segments
                const boltX = x1 + progress * gapWidth
                const boltY = segment === segments ? cy
                  : cy + (hash(laneSeed + segment) - 0.5) * 2 * boltAmplitude
                    + Math.sin(progress * Math.PI) * lean
                ctx.lineTo(boltX, boltY)
              }
              ctx.globalAlpha = 0.18 * trail
              ctx.strokeStyle = seal
              ctx.lineWidth = 4.8
              ctx.stroke()
              ctx.globalAlpha = 0.08 * trail
              ctx.strokeStyle = "#ffffff"
              ctx.lineWidth = 1.8
              ctx.stroke()
              ctx.globalAlpha = 0.40 * strike
              ctx.strokeStyle = seal
              ctx.lineWidth = 3.2
              ctx.stroke()
              ctx.globalAlpha = 0.92 * strike
              ctx.strokeStyle = "#ffffff"
              ctx.lineWidth = 1.15
              ctx.stroke()
            }
            drawStrike(seed + 17 + hash(seed + 221) * 23, firstStrike, firstTrail)
            drawStrike(seed + 91 + hash(seed + 222) * 29, secondStrike, secondTrail)
          }
        } else if (root.mode === 4) {
          const sparkAmplitude = Math.min(height * 0.30, 5.5)
          const slot = Math.floor(now / 300)
          const slotProgress = (now % 300) / 300
          for (let spark = 0; spark < 2; spark++) {
            const sparkSeed = slot * 77.7 + gapIndex * 13.3 + spark * 311.1
            if (hash(sparkSeed) > 0.32) continue
            const life = 1 - slotProgress
            const fromLeft = hash(sparkSeed + 1) < 0.5
            const originX = fromLeft ? x1 : x2
            const direction = fromLeft ? 1 : -1
            const originY = cy + (hash(sparkSeed + 2) - 0.5) * height * 0.45
            const length = 4 + hash(sparkSeed + 3) * 6
            ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(originX, originY)
            for (let segment = 1; segment <= 3; segment++) {
              ctx.lineTo(originX + direction * length * (segment / 3),
                originY + (hash(sparkSeed + 4 + segment) - 0.5) * 4)
            }
            const flicker = 0.6 + 0.4 * Math.sin(now / 23 + sparkSeed)
            ctx.globalAlpha = 0.30 * life * flicker
            ctx.strokeStyle = seal
            ctx.lineWidth = 1.6
            ctx.stroke()
            ctx.globalAlpha = 0.75 * life * flicker
            ctx.strokeStyle = "#ffffff"
            ctx.lineWidth = 0.7
            ctx.stroke()
            ctx.globalAlpha = 0.55 * life
            ctx.fillStyle = "#ffffff"
            ctx.beginPath()
            ctx.arc(originX, originY, 0.9, 0, Math.PI * 2)
            ctx.fill()
          }

          const cycle = 4000
          const local = now / cycle + gapIndex * 0.37
          const phase = local - Math.floor(local)
          const seed = Math.floor(local) * 131.7 + gapIndex * 53.3
          const strikeStart = 0.10 + hash(seed + 99) * 0.75
          const elapsed = (phase - strikeStart) * cycle
          if (elapsed >= 0 && elapsed < 340) {
            let brightness = 0
            if (elapsed < 90) brightness = 1
            else if (elapsed < 150) brightness = 0.25
            else if (elapsed < 230) brightness = 0.7
            else brightness = 0.7 * (1 - (elapsed - 230) / 110)
            brightness *= 0.82 + 0.18 * Math.sin(now / 21)
            const segments = Math.max(4, Math.min(16, Math.round(gapWidth / 22)))
            ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(x1, cy)
            for (let segment = 1; segment <= segments; segment++) {
              ctx.lineTo(x1 + segment / segments * gapWidth,
                segment === segments ? cy
                  : cy + (hash(seed + segment) - 0.5) * 2 * sparkAmplitude)
            }
            ctx.globalAlpha = 0.42 * brightness
            ctx.strokeStyle = seal
            ctx.lineWidth = 3.4
            ctx.stroke()
            ctx.globalAlpha = 0.95 * brightness
            ctx.strokeStyle = "#ffffff"
            ctx.lineWidth = 1.2
            ctx.stroke()
            const bloomRadius = 6 + brightness * 3
            for (const electrodeX of [x1, x2]) {
              const bloom = ctx.createRadialGradient(electrodeX, cy, 0,
                electrodeX, cy, bloomRadius)
              bloom.addColorStop(0, rgba(0.50 * brightness))
              bloom.addColorStop(1, rgba(0))
              ctx.globalAlpha = 1
              ctx.fillStyle = bloom
              ctx.beginPath()
              ctx.arc(electrodeX, cy, bloomRadius, 0, Math.PI * 2)
              ctx.fill()
            }
          }
        } else if (root.mode === 5) {
          const cycle = 3200
          const local = now / cycle + gapIndex * 0.41
          const phase = local - Math.floor(local)
          const seed = Math.floor(local) * 131.7 + gapIndex * 53.3
          const start = hash(seed + 9) * 0.22
          const progress = (phase - start) / 0.74
          if (progress >= 0 && progress <= 1) {
            const coreRadius = 2.4
            let dropletX = -1
            let scale = 1
            if (progress < 0.40) {
              dropletX = x1
              scale = progress / 0.40
            } else if (progress < 0.85) {
              let move = (progress - 0.40) / 0.45
              move = move * move * (3 - 2 * move)
              dropletX = x1 + move * gapWidth
            }

            if (dropletX >= 0) {
              if (progress >= 0.40 && dropletX > x1 + 4) {
                const trail = ctx.createLinearGradient(dropletX - 14, 0, dropletX, 0)
                trail.addColorStop(0, rgba(0))
                trail.addColorStop(1, rgba(0.35))
                ctx.globalAlpha = 1
                ctx.strokeStyle = trail
                ctx.lineWidth = 1.4
                ctx.beginPath()
                ctx.moveTo(Math.max(x1, dropletX - 14), cy)
                ctx.lineTo(dropletX, cy)
                ctx.stroke()
              }
              const breath = 0.92 + 0.08 * Math.sin(now / 130)
              const glowRadius = coreRadius * 2.6 * scale * breath
              const glow = ctx.createRadialGradient(dropletX, cy, 0,
                dropletX, cy, glowRadius)
              glow.addColorStop(0, rgba(0.55 * scale))
              glow.addColorStop(1, rgba(0))
              ctx.globalAlpha = 1
              ctx.fillStyle = glow
              ctx.beginPath()
              ctx.arc(dropletX, cy, glowRadius, 0, Math.PI * 2)
              ctx.fill()
              ctx.globalAlpha = 0.92 * scale
              ctx.fillStyle = "#ffffff"
              ctx.beginPath()
              ctx.arc(dropletX, cy, coreRadius * 0.7 * scale, 0, Math.PI * 2)
              ctx.fill()
            } else {
              const flash = 1 - (progress - 0.85) / 0.15
              const glow = ctx.createRadialGradient(x2, cy, 0, x2, cy, 8)
              glow.addColorStop(0, rgba(0.60 * flash))
              glow.addColorStop(1, rgba(0))
              ctx.globalAlpha = 1
              ctx.fillStyle = glow
              ctx.beginPath()
              ctx.arc(x2, cy, 8, 0, Math.PI * 2)
              ctx.fill()
              ctx.globalAlpha = 0.9 * flash
              ctx.fillStyle = "#ffffff"
              ctx.beginPath()
              ctx.arc(x2, cy, 1.2 * flash, 0, Math.PI * 2)
              ctx.fill()
            }
          }
        } else if (root.mode === 6) {
          const cycle = 3800
          const local = now / cycle + gapIndex * 0.31
          const phase = local - Math.floor(local)
          const seed = Math.floor(local) * 131.7 + gapIndex * 53.3
          const start = hash(seed + 9) * 0.5
          const elapsed = (phase - start) * cycle
          if (elapsed >= 0 && elapsed < 1180) {
            const mid = (x1 + x2) / 2
            const flightTime = 580
            if (elapsed < flightTime) {
              let progress = elapsed / flightTime
              progress *= progress
              const heads = [
                x1 + progress * (mid - x1),
                x2 - progress * (x2 - mid)
              ]
              for (let headIndex = 0; headIndex < heads.length; headIndex++) {
                const headX = heads[headIndex]
                const trailLength = (headIndex === 0 ? -1 : 1)
                  * (8 + progress * 14)
                const trail = ctx.createLinearGradient(headX + trailLength, 0,
                  headX, 0)
                trail.addColorStop(0, rgba(0))
                trail.addColorStop(1, rgba(0.45))
                ctx.globalAlpha = 1
                ctx.strokeStyle = trail
                ctx.lineWidth = 1.6
                ctx.beginPath()
                ctx.moveTo(headX + trailLength, cy)
                ctx.lineTo(headX, cy)
                ctx.stroke()
                const glow = ctx.createRadialGradient(headX, cy, 0, headX, cy, 4.5)
                glow.addColorStop(0, rgba(0.50))
                glow.addColorStop(1, rgba(0))
                ctx.fillStyle = glow
                ctx.beginPath()
                ctx.arc(headX, cy, 4.5, 0, Math.PI * 2)
                ctx.fill()
                ctx.globalAlpha = 0.95
                ctx.fillStyle = "#ffffff"
                ctx.beginPath()
                ctx.arc(headX, cy, 1.5, 0, Math.PI * 2)
                ctx.fill()
              }
            } else {
              const progress = (elapsed - flightTime) / 600
              const fade = Math.pow(1 - progress, 1.6)
              const flashRadius = 5 + progress * 9
              const impact = ctx.createRadialGradient(mid, cy, 0,
                mid, cy, flashRadius)
              impact.addColorStop(0, rgba(0.60 * fade))
              impact.addColorStop(1, rgba(0))
              ctx.globalAlpha = 1
              ctx.fillStyle = impact
              ctx.beginPath()
              ctx.arc(mid, cy, flashRadius, 0, Math.PI * 2)
              ctx.fill()
              if (progress < 0.25) {
                ctx.globalAlpha = 0.95 * (1 - progress / 0.25)
                ctx.fillStyle = "#ffffff"
                ctx.beginPath()
                ctx.arc(mid, cy, 1.8, 0, Math.PI * 2)
                ctx.fill()
              }
              const travel = 1 - Math.pow(1 - progress, 2)
              ctx.lineJoin = "round"
              for (let shard = 0; shard < 5; shard++) {
                const angle = (hash(seed + 30 + shard) - 0.5) * 2.4
                  + (shard % 2 === 0 ? 0 : Math.PI)
                const distance = (8 + hash(seed + 40 + shard) * 14) * travel
                const shardX = mid + Math.cos(angle) * distance
                const shardY = cy + Math.sin(angle) * distance * 0.55
                ctx.globalAlpha = 0.75 * fade
                ctx.strokeStyle = "#ffffff"
                ctx.lineWidth = 0.8
                ctx.beginPath()
                ctx.moveTo(shardX, shardY)
                ctx.lineTo(shardX + Math.cos(angle) * 3.5,
                  shardY + Math.sin(angle) * 3.5 * 0.55)
                ctx.stroke()
              }
            }
          }
        }

        ctx.restore()
      }
      ctx.globalAlpha = 1
    }
  }
}
