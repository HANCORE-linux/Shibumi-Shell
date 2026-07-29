pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property var bar
  required property var service
  required property var runs
  required property string screenName

  readonly property bool active: service !== null && runs.length > 1
  readonly property int ambientParticleCount: 36
  readonly property int fastTick: 16
  readonly property int ambientTick: 250
  readonly property int dormantTick: 500
  property var pulses: []
  property bool animating: true

  visible: active

  function pulseLife(pulse) {
    if (!pulse) return 0
    if (pulse.kind === "text") return pulse.life || 10500
    if (pulse.kind === "monsweep") return pulse.life || 3400
    if (pulse.kind === "win") return 1600
    return 5000
  }

  function accepts(event) {
    return event && (!event.screen || event.screen === screenName)
  }

  function acceptEvent(event) {
    if (!active || !accepts(event)) return
    const now = Date.now()
    let next = []
    for (let index = 0; index < pulses.length; index++) {
      const pulse = pulses[index]
      if (now - pulse.timestamp < pulseLife(pulse)) next.push(pulse)
    }

    const pulse = {
      timestamp: now,
      serial: Number(event.serial) || now,
      kind: String(event.kind || "text"),
      direction: Number(event.direction) < 0 ? -1 : 1,
      left: String(event.left || ""),
      right: String(event.right || ""),
      warning: event.profile === "warn",
      quote: event.profile === "quote",
      count: Math.max(1, Math.min(36, Number(event.count) || 1)),
      gain: Math.max(0.1, Math.min(1, Number(event.gain) || 1)),
      choices: Array.isArray(event.choices) ? event.choices.slice(0, 64) : [],
      grid: null
    }
    if (pulse.kind === "text") {
      const shortProfile = event.profile === "short"
      const quoteProfile = pulse.quote
      if (!pulse.warning) {
        for (let index = 0; index < next.length; index++) {
          if (next[index].kind === "text" && next[index].warning) return
        }
      }
      next = next.filter(function(item) { return item.kind !== "text" })
      const textLife = Math.min(9500, 4500 + pulse.left.length * 55)
      pulse.life = quoteProfile ? 12600
        : pulse.warning ? 10000 : shortProfile ? 4200 : textLife
      pulse.snapStart = quoteProfile ? 2000 : shortProfile ? 900 : 1500
      pulse.snapEnd = quoteProfile ? 2800 : shortProfile ? 1500 : 2300
      pulse.releaseStart = pulse.warning ? 8600
        : quoteProfile ? 9800 : shortProfile ? 3000 : textLife - 1500
      pulse.releaseEnd = pulse.warning ? 9400
        : quoteProfile ? 10600 : shortProfile ? 3600 : textLife - 700
      pulse.fade = quoteProfile ? 400
        : pulse.warning ? 1100 : shortProfile ? 750 : 900
    } else if (pulse.kind === "monsweep") {
      pulse.life = 5200
    }
    next.push(pulse)
    pulses = next.slice(-8)
    animating = true
    canvas.tick = fastTick
    requestFrame()
  }

  function clear() {
    pulses = []
    canvas.recruited = 0
    animating = true
    canvas.tick = ambientTick
    requestFrame()
  }

  function requestFrame() {
    if (active && width > 0 && height > 0) canvas.requestPaint()
  }

  onRunsChanged: requestFrame()
  onWidthChanged: requestFrame()
  onHeightChanged: requestFrame()

  Connections {
    target: root.service
    function onEventRaised(event) { root.acceptEvent(event) }
    function onCleared() { root.clear() }
  }

  Timer {
    interval: canvas.tick
    repeat: true
    running: root.active && root.animating
    onTriggered: root.requestFrame()
  }

  Canvas {
    id: canvas

    anchors.fill: parent
    renderStrategy: Canvas.Threaded
    property int tick: root.ambientTick
    property var glyphs: null
    property real fieldFade: 1
    property int recruited: 0
    property real fieldTime: 0
    property real lastPaintTime: 0

    onPaint: {
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!root.active) return

      if (!glyphs) {
        glyphs = {
          A: [[1,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
          B: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[1,4]],
          C: [[0,0],[1,0],[2,0],[0,1],[0,2],[0,3],[0,4],[1,4],[2,4]],
          D: [[0,0],[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4]],
          E: [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[0,3],[0,4],[1,4],[2,4]],
          F: [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[0,3],[0,4]],
          G: [[0,0],[1,0],[2,0],[0,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
          H: [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
          I: [[0,0],[1,0],[2,0],[1,1],[1,2],[1,3],[0,4],[1,4],[2,4]],
          J: [[2,0],[2,1],[2,2],[0,3],[2,3],[1,4]],
          K: [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[2,4]],
          L: [[0,0],[0,1],[0,2],[0,3],[0,4],[1,4],[2,4]],
          M: [[0,0],[2,0],[0,1],[1,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
          N: [[0,0],[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
          O: [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
          P: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[0,4]],
          Q: [[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[1,4],[2,4]],
          R: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[2,4]],
          S: [[1,0],[2,0],[0,1],[1,2],[2,3],[0,4],[1,4]],
          T: [[0,0],[1,0],[2,0],[1,1],[1,2],[1,3],[1,4]],
          U: [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
          V: [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[1,4]],
          W: [[0,0],[2,0],[0,1],[1,1],[2,1],[0,2],[2,2],[0,3],[1,3],[2,3],[0,4],[2,4]],
          X: [[0,0],[2,0],[0,1],[2,1],[1,2],[0,3],[2,3],[0,4],[2,4]],
          Y: [[0,0],[2,0],[0,1],[2,1],[1,2],[1,3],[1,4]],
          Z: [[0,0],[1,0],[2,0],[2,1],[1,2],[0,3],[0,4],[1,4],[2,4]],
          "0": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
          "1": [[1,0],[0,1],[1,1],[1,2],[1,3],[0,4],[1,4],[2,4]],
          "2": [[0,0],[1,0],[2,0],[2,1],[0,2],[1,2],[2,2],[0,3],[0,4],[1,4],[2,4]],
          "3": [[0,0],[1,0],[2,0],[2,1],[1,2],[2,2],[2,3],[0,4],[1,4],[2,4]],
          "4": [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[2,3],[2,4]],
          "5": [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[2,3],[0,4],[1,4]],
          "6": [[1,0],[2,0],[0,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
          "7": [[0,0],[1,0],[2,0],[2,1],[1,2],[1,3],[1,4]],
          "8": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
          "9": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[2,3],[0,4],[1,4]],
          ".": [[1,4]], ",": [[1,3],[0,4]], "'": [[1,0],[1,1]],
          "!": [[1,0],[1,1],[1,2],[1,4]], "-": [[0,2],[1,2],[2,2]],
          "+": [[1,1],[0,2],[1,2],[2,2],[1,3]],
          "/": [[2,0],[2,1],[1,2],[0,3],[0,4]],
          ";": [[1,1],[1,3],[0,4]], "<": [[2,0],[1,1],[0,2],[1,3],[2,4]]
        }
      }

      const now = Date.now()
      const centerY = height / 2
      const seal = root.bar.urgent
      const red = Math.round(seal.r * 255)
      const green = Math.round(seal.g * 255)
      const blue = Math.round(seal.b * 255)
      const rgba = function(alpha) {
        return "rgba(" + red + "," + green + "," + blue + "," + alpha + ")"
      }
      const hash = function(value) {
        const result = Math.sin(value * 127.1) * 43758.5453
        return result - Math.floor(result)
      }
      const gaps = []
      for (let index = 0; index + 1 < root.runs.length; index++) {
        const leftRun = root.runs[index]
        const rightRun = root.runs[index + 1]
        const x1 = Number(leftRun.x || 0) + Number(leftRun.width || 0)
        const x2 = Number(rightRun.x || 0)
        if (x2 - x1 >= 10 && isFinite(x1) && isFinite(x2))
          gaps.push({ x1: x1, x2: x2 })
      }
      if (gaps.length === 0) {
        root.animating = false
        tick = root.dormantTick
        return
      }

      const firstX = gaps[0].x1
      const lastX = gaps[gaps.length - 1].x2
      let widestIndex = 0
      for (let index = 1; index < gaps.length; index++) {
        if (gaps[index].x2 - gaps[index].x1
            > gaps[widestIndex].x2 - gaps[widestIndex].x1) widestIndex = index
      }

      const visibility = function(x) {
        for (let index = 0; index < gaps.length; index++) {
          const gap = gaps[index]
          if (x >= gap.x1 - 2 && x <= gap.x2 + 2)
            return Math.max(0, Math.min(1,
              Math.min((x - gap.x1 + 2) / 6, (gap.x2 + 2 - x) / 6)))
        }
        return 0
      }
      const dot = function(x, y, glowRadius, coreRadius, alpha) {
        if (alpha <= 0.01) return
        const visible = visibility(x)
        if (visible <= 0.01) return
        ctx.globalAlpha = 0.30 * alpha * visible
        ctx.fillStyle = seal
        ctx.fillRect(x - glowRadius, y - glowRadius,
          glowRadius * 2, glowRadius * 2)
        ctx.globalAlpha = 0.92 * alpha * visible
        ctx.fillStyle = "#ffffff"
        ctx.fillRect(x - coreRadius, y - coreRadius,
          coreRadius * 2, coreRadius * 2)
      }
      const clockGapPair = function() {
        const middle = width / 2
        let left = -1
        let right = -1
        for (let index = 0; index < gaps.length; index++) {
          if (gaps[index].x2 <= middle
              && (left < 0 || gaps[index].x2 > gaps[left].x2)) left = index
          if (gaps[index].x1 >= middle
              && (right < 0 || gaps[index].x1 < gaps[right].x1)) right = index
        }
        if (left < 0 && right < 0) return [widestIndex, widestIndex]
        if (left < 0) left = right
        if (right < 0) right = left
        return [left, right]
      }
      const sweep = function(pulse, age, life, direction, gain, count) {
        const seed = pulse.serial % 86400000
        const fade = age > life - 600 ? (life - age) / 600 : 1
        const span = lastX - firstX + 120
        const amplitude = height / 2 - 8
        const breath = 1 + 0.35 * Math.sin(now / 1100 + seed)
        const sharedY = amplitude * 0.55 * Math.sin(now / 1400 + seed * 1.7)
        for (let index = 0; index < count; index++) {
          const delay = hash(seed + index * 7 + 1) * 900
          const localAge = age - delay
          if (localAge < 0) continue
          let progress = localAge / life
          if (progress > 1) continue
          progress += 0.025 * Math.sin(now / 480
            + 6.283 * hash(seed + index * 7 + 2))
          const bodyX = direction > 0 ? firstX - 60 + progress * span
            : lastX + 60 - progress * span
          const x = bodyX + (hash(seed + index * 7 + 3) - 0.5) * 110 * breath
            + 10 * Math.sin(now / (900 + 500 * hash(seed + index * 7 + 4))
              + 6.283 * hash(seed + index * 7 + 5))
          const y = centerY + sharedY * (0.6 + 0.4 * hash(seed + index * 7 + 2))
            + (hash(seed + index * 7 + 6) - 0.5) * amplitude * breath * 0.5
            + 3 * Math.sin(now / (600 + 300 * hash(seed + index * 7 + 4)) + index)
          const size = 1.6 + hash(seed + index * 7 + 5) * 1.2
          const twinkle = 0.8 + 0.2 * Math.sin(now / 350 + index * 1.9)
          dot(x, y, size, size * 0.45,
            gain * fade * twinkle * Math.min(1, localAge / 350))
        }
      }

      const elapsed = now - lastPaintTime
      lastPaintTime = now
      fieldTime += elapsed > 0 && elapsed < 60 ? elapsed : elapsed >= 60 ? 16 : 0
      const driftPosition = function(index) {
        const r1 = hash(index * 3 + 1)
        const r2 = hash(index * 3 + 2)
        const r3 = hash(index * 3 + 3)
        const baseFraction = hash(index * 5 + 7)
        const gapIndex = Math.min(gaps.length - 1,
          Math.floor(hash(index * 5 + 11) * gaps.length))
        const gap = gaps[Math.max(0, gapIndex)]
        const span = Math.max(1, gap.x2 - gap.x1 - 12)
        return {
          x: gap.x1 + 6 + baseFraction * span
            + 20 * Math.sin(fieldTime / (1250 + 650 * r1) + 6.283 * r2)
            + 7 * Math.sin(fieldTime / (460 + 220 * r3) + r1 * 5),
          y: centerY + (height / 2 - 5) * 0.82
            * Math.sin(fieldTime / (980 + 520 * r3) + 6.283 * r1)
            + 3 * Math.sin(fieldTime / (380 + 180 * r2) + r3 * 4)
        }
      }
      const paintAmbient = function(fromIndex, alpha) {
        if (alpha <= 0.01) return
        const blinkSlot = Math.floor(fieldTime / 900)
        const blinkPhase = (fieldTime % 900) / 900
        for (let index = fromIndex; index < root.ambientParticleCount; index++) {
          const position = driftPosition(index)
          const blink = hash(index * 19 + blinkSlot * 23) > 0.94
            ? Math.sin(blinkPhase * Math.PI) * 0.75 : 0
          const twinkle = 0.48 + 0.26 * Math.sin(fieldTime / 640 + index * 1.3)
            + blink
          const size = 1.18 + 0.24 * Math.sin(fieldTime / 820 + index * 2.1)
            + blink * 0.55
          dot(position.x, position.y, size, size * 0.4, alpha * twinkle)
        }
      }

      const sourcePulses = root.pulses
      let hasText = false
      for (let index = 0; index < sourcePulses.length; index++) {
        if (sourcePulses[index].kind === "text"
            && now - sourcePulses[index].timestamp < root.pulseLife(sourcePulses[index])) {
          hasText = true
          break
        }
      }
      if (!hasText) recruited = 0
      fieldFade += ((hasText ? 0.34 : 1) - fieldFade)
        * (hasText ? 0.025 : 0.04)
      paintAmbient(recruited, 0.72 * fieldFade)

      let alive = false
      let needsFastTick = false
      const livePulses = []
      for (let pulseIndex = 0; pulseIndex < sourcePulses.length; pulseIndex++) {
        const pulse = sourcePulses[pulseIndex]
        const age = now - pulse.timestamp
        if (age < root.pulseLife(pulse)) livePulses.push(pulse)
        const seed = pulse.serial % 86400000
        if (pulse.kind === "monsweep") {
          const life = pulse.life || 3400
          if (age >= life) continue
          alive = true
          needsFastTick = true
          sweep(pulse, age, life, pulse.direction, pulse.gain || 0.55,
            pulse.count || 30)
        } else if (pulse.kind === "win") {
          if (age >= 1600) continue
          alive = true
          needsFastTick = true
          const time = age / 1600
          const eased = time * time * (3 - 2 * time)
          const alpha = Math.sin(Math.min(1, time) * Math.PI)
          const pair = clockGapPair()
          for (let side = 0; side < 2; side++) {
            const gap = gaps[pair[side]]
            if (!gap) continue
            const direction = side === 0 ? -1 : 1
            const near = direction < 0 ? gap.x2 - 8 : gap.x1 + 8
            const travel = Math.min(34, Math.max(8, (gap.x2 - gap.x1) * 0.45))
            const far = direction < 0 ? Math.max(gap.x1 + 8, near - travel)
              : Math.min(gap.x2 - 8, near + travel)
            const progress = pulse.direction > 0 ? eased : 1 - eased
            for (let dotIndex = 0; dotIndex < 14; dotIndex++) {
              const lag = hash(seed + side * 100 + dotIndex * 9 + 1) * 0.28
              const local = Math.max(0, Math.min(1, progress - lag + 0.12))
              const x = near + (far - near) * local
                + (hash(seed + side * 100 + dotIndex * 9 + 2) - 0.5) * 7
              const y = centerY
                + (hash(seed + side * 100 + dotIndex * 9 + 3) - 0.5)
                  * (height - 10) * 0.68
                + 2 * Math.sin(now / 360 + dotIndex)
              const strength = alpha
                * (0.45 + 0.45 * hash(seed + side * 100 + dotIndex * 9 + 4))
              dot(x, y, 1.8, 0.8, strength)
            }
          }
        } else if (pulse.kind === "text") {
          if (age >= pulse.life) continue
          alive = true
          if (!pulse.grid) {
            const points = []
            const addPoints = function(text, columnOffset, rowOffset, slot) {
              for (let characterIndex = 0; characterIndex < text.length; characterIndex++) {
                const character = glyphs[text.charAt(characterIndex)]
                if (!character) continue
                for (let pointIndex = 0; pointIndex < character.length; pointIndex++)
                  points.push([columnOffset + characterIndex * 4 + character[pointIndex][0],
                    rowOffset + character[pointIndex][1], slot])
              }
            }
            let firstGap = 0
            let secondGap = -1
            for (let index = 1; index < gaps.length; index++) {
              if (gaps[index].x2 - gaps[index].x1 > gaps[firstGap].x2 - gaps[firstGap].x1) {
                secondGap = firstGap
                firstGap = index
              } else if (secondGap < 0
                  || gaps[index].x2 - gaps[index].x1
                    > gaps[secondGap].x2 - gaps[secondGap].x1) secondGap = index
            }
            if (!pulse.right) secondGap = -1
            else if (secondGap >= 0 && gaps[secondGap].x1 < gaps[firstGap].x1) {
              const swap = firstGap
              firstGap = secondGap
              secondGap = swap
            }
            const firstWidth = gaps[firstGap].x2 - gaps[firstGap].x1
            const fitCell = function(columns, rows) {
              const maxCell = pulse.quote ? 3.2
                : columns <= 11 ? 5.4 : 4.4
              const cell = Math.min(maxCell,
                (firstWidth - 24) / Math.max(1, columns - 1),
                (height - 6) / Math.max(1, rows - 1))
              return cell > 0 && isFinite(cell) ? cell : 0
            }
            let firstLine = ""
            let secondLine = ""
            let secondLineOffset = 7
            let firstRows = 5
            let selectedAuthor = pulse.right
            let selectedQuoteText = ""
            if (pulse.quote && pulse.choices.length > 0) {
              for (let choiceIndex = 0; choiceIndex < pulse.choices.length; choiceIndex++) {
                const choice = pulse.choices[choiceIndex]
                const quoteText = String(choice.quote || "")
                if (!quoteText) continue
                const oneLineCell = fitCell(quoteText.length * 4 - 1, 5)
                if (quoteText.length <= 44 && oneLineCell >= 2.65) {
                  firstLine = quoteText
                  selectedQuoteText = quoteText
                  selectedAuthor = choice.author ? "-" + choice.author : ""
                  break
                }
                const words = quoteText.split(" ")
                let bestCut = -1
                let bestLength = 1000000
                for (let wordIndex = 1; wordIndex < words.length; wordIndex++) {
                  const leftText = words.slice(0, wordIndex).join(" ")
                  const rightText = words.slice(wordIndex).join(" ")
                  const length = Math.max(leftText.length, rightText.length)
                  if (length < bestLength) {
                    bestLength = length
                    bestCut = wordIndex
                  }
                }
                if (bestCut > 0 && fitCell(bestLength * 4 - 1, 11) >= 2.35) {
                  firstLine = words.slice(0, bestCut).join(" ")
                  secondLine = words.slice(bestCut).join(" ")
                  selectedQuoteText = quoteText
                  secondLineOffset = 6
                  firstRows = 11
                  selectedAuthor = choice.author ? "-" + choice.author : ""
                  break
                }
              }
            }

            if (!pulse.quote) {
              const capacity = Math.max(3,
                Math.floor((firstWidth - 24) / 1.9 / 4))
              const fullText = pulse.left.substring(0, capacity * 2)
              const middle = Math.ceil(fullText.length / 2)
              let cut = fullText.lastIndexOf(" ",
                Math.min(fullText.length - 1, middle + 4))
              if (cut < 3) cut = fullText.indexOf(" ", middle)
              if (cut < 3) cut = middle
              const candidateFirst = fullText.substring(0, cut).trim()
                .substring(0, capacity)
              const candidateSecond = fullText.substring(cut).trim()
                .substring(0, capacity)
              const oneLineCell = fitCell(fullText.length * 4 - 1, 5)
              const twoLineCell = candidateSecond
                ? fitCell(Math.max(candidateFirst.length,
                  candidateSecond.length) * 4 - 1, 12) : 0
              firstLine = fullText.substring(0, capacity)
              selectedQuoteText = fullText
              if (candidateSecond && twoLineCell >= 1.8
                  && (fullText.length > capacity
                    || twoLineCell > oneLineCell + 0.2)) {
                firstLine = candidateFirst
                secondLine = candidateSecond
                firstRows = 12
              }
            }

            let maxLength = Math.max(firstLine.length, secondLine.length)
            if (firstLine) {
              addPoints(firstLine,
                Math.round((maxLength - firstLine.length) * 2), 0, 0)
              if (secondLine)
                addPoints(secondLine,
                  Math.round((maxLength - secondLine.length) * 2),
                  secondLineOffset, 0)
            } else if (pulse.quote) {
              const alienColumns = Math.max(3, Math.min(23,
                Math.floor((firstWidth - 24) / 3.2)))
              for (let row = 0; row < 5; row++) {
                for (let column = 0; column < alienColumns; column++) {
                  if (hash(pulse.serial + row * 37.3 + column * 5.1) < 0.42)
                    points.push([column, row, 0])
                }
              }
              maxLength = Math.max(1, Math.ceil(alienColumns / 4))
              firstRows = 5
              selectedAuthor = ""
            }
            let rightColumns = 1
            if (secondGap >= 0 && selectedAuthor) {
              const rightWidth = gaps[secondGap].x2 - gaps[secondGap].x1
              const fullRightColumns = Math.max(1, selectedAuthor.length * 4 - 1)
              const rightCell = Math.min(pulse.quote ? 3.2 : 4.4,
                (rightWidth - 24) / Math.max(1, fullRightColumns - 1),
                (height - 6) / 4)
              if (!pulse.quote || rightCell >= 2.35) {
                const rightCapacity = pulse.quote ? selectedAuthor.length
                  : Math.max(3, Math.floor((rightWidth - 24) / 1.9 / 4))
                const rightText = selectedAuthor.substring(0, rightCapacity)
                rightColumns = Math.max(1, rightText.length * 4 - 1)
                addPoints(rightText, 0, 0, 1)
              }
            }
            pulse.grid = {
              points: points,
              firstGap: firstGap,
              secondGap: secondGap,
              firstColumns: Math.max(1, maxLength * 4 - 1),
              firstRows: firstRows,
              rightColumns: rightColumns,
              selectedQuote: selectedQuoteText,
              selectedAuthor: selectedAuthor
            }
          }

          const grid = pulse.grid
          const geometry = [null, null]
          const fitGeometry = function(slot, gap, columns, rows) {
            if (!gap) return
            const maxCell = pulse.quote ? 3.2
              : columns <= 11 ? 5.4 : 4.4
            const cell = Math.min(maxCell,
              (gap.x2 - gap.x1 - 24) / Math.max(1, columns - 1),
              (height - 6) / Math.max(1, rows - 1))
            if (cell < 1.8) return
            geometry[slot] = {
              x: (gap.x1 + gap.x2) / 2 - (columns - 1) * cell / 2,
              y: centerY - (rows - 1) * cell / 2,
              cell: cell
            }
          }
          fitGeometry(0, gaps[grid.firstGap], grid.firstColumns, grid.firstRows)
          fitGeometry(1, grid.secondGap >= 0 ? gaps[grid.secondGap] : null,
            grid.rightColumns, 5)
          let formation = 0
          if (age >= pulse.snapEnd) formation = 1
          else if (age > pulse.snapStart) {
            let progress = (age - pulse.snapStart) / (pulse.snapEnd - pulse.snapStart)
            formation = progress * progress * (3 - 2 * progress)
          }
          if (age > pulse.releaseStart) {
            let release = Math.min(1,
              (age - pulse.releaseStart) / (pulse.releaseEnd - pulse.releaseStart))
            release = release * release * (3 - 2 * release)
            formation *= 1 - release
          }
          const alpha = Math.min(1, age / 450)
            * Math.min(1, (pulse.life - age) / pulse.fade)
          let warningAlpha = 1
          let warningScale = 1
          if (pulse.warning && formation > 0.9) {
            warningAlpha = 0.78 + 0.28 * Math.sin(now / 280)
            warningScale = 1 + 0.15 * Math.sin(now / 280)
          }
          if (age < pulse.snapEnd || age > pulse.releaseStart || pulse.warning)
            needsFastTick = true
          const enter = Math.pow(Math.max(0, 1 - age / pulse.snapStart), 2)
          const leave = age > pulse.releaseEnd
            ? Math.pow((age - pulse.releaseEnd) / (pulse.life - pulse.releaseEnd), 2) : 0
          const shift = pulse.direction * (lastX - firstX) * 0.45 * (leave - enter)
          for (let pointIndex = 0; pointIndex < grid.points.length; pointIndex++) {
            const point = grid.points[pointIndex]
            const target = geometry[point[2]]
            const drift = driftPosition(pointIndex)
            let x = drift.x
            let y = drift.y
            let glowRadius = 1.3
            let coreRadius = 0.5
            if (!target) x += shift
            if (target && formation > 0) {
              x += (target.x + point[0] * target.cell - x) * formation
              y += (target.y + point[1] * target.cell - y) * formation
              if (formation > 0.98) {
                x += 0.4 * Math.sin(now / 240 + pointIndex)
                y += 0.4 * Math.cos(now / 300 + pointIndex * 1.7)
              }
              glowRadius += (target.cell * 0.62 - glowRadius) * formation
              coreRadius += (target.cell * 0.30 - coreRadius) * formation
            }
            dot(x, y, glowRadius * warningScale, coreRadius * warningScale,
              alpha * warningAlpha)
          }
          recruited = Math.min(grid.points.length, root.ambientParticleCount)
        }
      }

      if (livePulses.length !== sourcePulses.length) root.pulses = livePulses
      root.animating = true
      tick = alive && needsFastTick ? root.fastTick : root.ambientTick
      ctx.globalAlpha = 1
    }
  }
}
