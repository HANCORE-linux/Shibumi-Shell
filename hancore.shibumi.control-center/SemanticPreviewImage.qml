pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  required property var controller
  property string routeId: "bars"
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  readonly property string semanticRoute: {
    const route = String(routeId || "").split(":")[0]
    if (route === "quick" || route === "layout") return "bars"
    if (route === "plugins") return "widgets"
    if (route === "functions") return "appearance"
    if (route === "preferences") return "health"
    return route
  }

  Canvas {
    id: preview
    anchors.fill: parent
    visible: root.semanticRoute !== "logo"
    antialiasing: true
    renderStrategy: Canvas.Threaded

    function rounded(context, x, y, w, h, r) {
      const radius = Math.min(r, w / 2, h / 2)
      context.beginPath()
      context.moveTo(x + radius, y)
      context.lineTo(x + w - radius, y)
      context.quadraticCurveTo(x + w, y, x + w, y + radius)
      context.lineTo(x + w, y + h - radius)
      context.quadraticCurveTo(x + w, y + h, x + w - radius, y + h)
      context.lineTo(x + radius, y + h)
      context.quadraticCurveTo(x, y + h, x, y + h - radius)
      context.lineTo(x, y + radius)
      context.quadraticCurveTo(x, y, x + radius, y)
      context.closePath()
    }

    function strokeBox(context, x, y, w, h, r, alpha) {
      rounded(context, x, y, w, h, r)
      context.fillStyle = Commons.Util.alpha(root.foreground, alpha * 0.32)
      context.fill()
      context.strokeStyle = Commons.Util.alpha(root.foreground, alpha)
      context.lineWidth = 1
      context.stroke()
    }

    function moduleBlock(context, x, y, w, h, accented) {
      rounded(context, x, y, w, h, Math.min(2.5, h / 2))
      context.fillStyle = accented
        ? root.accent : Commons.Util.alpha(root.foreground, 0.52)
      context.fill()
    }

    function moduleDot(context, x, y, radius, accented) {
      context.beginPath()
      context.arc(x, y, radius, 0, Math.PI * 2)
      context.fillStyle = accented
        ? root.accent : Commons.Util.alpha(root.foreground, 0.48)
      context.fill()
    }

    function edgeLine(context, y, x1, x2) {
      context.strokeStyle = Commons.Util.alpha(root.foreground, 0.14)
      context.lineWidth = 1
      context.beginPath()
      context.moveTo(x1, y)
      context.lineTo(x2, y)
      context.stroke()
    }

    function notchSurface(context, x, y, w, h, alpha) {
      const wing = Math.min(24, w * 0.08)
      const inset = wing + 12
      context.beginPath()
      context.moveTo(x, y)
      context.lineTo(x + w, y)
      context.bezierCurveTo(
        x + w - wing, y, x + w - wing, y + h, x + w - inset, y + h)
      context.lineTo(x + inset, y + h)
      context.bezierCurveTo(x + wing, y + h, x + wing, y, x, y)
      context.closePath()
      context.fillStyle = Commons.Util.alpha(root.foreground, alpha * 0.32)
      context.fill()
      context.strokeStyle = Commons.Util.alpha(root.foreground, alpha)
      context.lineWidth = 1
      context.stroke()
    }

    onPaint: {
      const context = getContext("2d")
      context.reset()
      context.clearRect(0, 0, width, height)
      const w = width
      const h = height
      const mid = h / 2
      const route = root.semanticRoute
      context.lineCap = "round"

      if (route === "bars") {
        const barW = w * 0.78
        for (let index = 0; index < 3; index++) {
          const y = mid - 25 + index * 20
          const inset = index * 9
          strokeBox(context, (w - barW) / 2 + inset, y,
            barW - inset * 2, 11, index === 0 ? 5.5 : 3, 0.34)
        }
      } else if (route === "bar-v1") {
        const y = mid - 12
        const shellHeight = 24
        const segments = [
          { x: w * 0.08, width: w * 0.30 },
          { x: w * 0.43, width: w * 0.14 },
          { x: w * 0.62, width: w * 0.30 }
        ]
        edgeLine(context, y - 7, w * 0.04, w * 0.96)
        for (let index = 0; index < segments.length; index++) {
          const segment = segments[index]
          strokeBox(context, segment.x, y, segment.width, shellHeight, 12,
            index === 0 ? 0.68 : 0.38)
        }
        moduleBlock(context, w * 0.105, mid - 4, w * 0.055, 8, false)
        moduleBlock(context, w * 0.177, mid - 4, w * 0.035, 8, false)
        moduleBlock(context, w * 0.228, mid - 4, w * 0.07, 8, true)
        moduleDot(context, w * 0.50, mid, 3.2, true)
        moduleBlock(context, w * 0.655, mid - 4, w * 0.045, 8, false)
        moduleBlock(context, w * 0.716, mid - 4, w * 0.075, 8, false)
        moduleDot(context, w * 0.825, mid, 3, false)
        moduleBlock(context, w * 0.85, mid - 4, w * 0.035, 8, false)
      } else if (route === "bar-v2"
          || route.indexOf("bar-v2-") === 0) {
        const v2Style = route.indexOf("bar-v2-") === 0
          ? route.slice("bar-v2-".length) : "full"
        const y = mid - 13
        const inset = v2Style === "fit" ? w * 0.08
          : v2Style === "dock" || v2Style === "notch" ? w * 0.13
            : w * 0.05
        const shellWidth = w - inset * 2
        edgeLine(context, y - 7, w * 0.04, w * 0.96)
        if (v2Style === "notch")
          notchSurface(context, inset, y, shellWidth, 26, 0.58)
        else
          strokeBox(context, inset, y, shellWidth, 26,
            v2Style === "full" ? 2 : v2Style === "fit" ? 6 : 10, 0.58)
        const contentInset = v2Style === "notch" ? inset + w * 0.09 : inset
        const contentWidth = v2Style === "notch"
          ? shellWidth - w * 0.18 : shellWidth
        moduleBlock(context, contentInset + contentWidth * 0.03,
          mid - 4, contentWidth * 0.08, 8, false)
        moduleBlock(context, contentInset + contentWidth * 0.13,
          mid - 4, contentWidth * 0.055, 8, false)
        moduleBlock(context, contentInset + contentWidth * 0.205,
          mid - 4, contentWidth * 0.09, 8, true)
        for (let index = 0; index < 5; index++)
          moduleDot(context, w * 0.45 + index * w * 0.025, mid,
            index === 2 ? 3.2 : 2.1, index === 2)
        moduleBlock(context, contentInset + contentWidth * 0.69,
          mid - 4, contentWidth * 0.07, 8, false)
        moduleBlock(context, contentInset + contentWidth * 0.78,
          mid - 4, contentWidth * 0.10, 8, false)
        moduleDot(context, contentInset + contentWidth * 0.915,
          mid, 3, false)
      } else if (route === "bar-omarchy") {
        const y = mid - 13
        edgeLine(context, y - 7, w * 0.04, w * 0.96)
        strokeBox(context, w * 0.05, y, w * 0.90, 26, 2, 0.42)
        moduleBlock(context, w * 0.08, mid - 4, w * 0.12, 8, false)
        moduleDot(context, w * 0.232, mid, 3.2, true)
        for (let index = 0; index < 4; index++)
          moduleDot(context, w * 0.45 + index * w * 0.033, mid,
            index === 0 ? 3.2 : 2.1, index === 0)
        moduleBlock(context, w * 0.69, mid - 4, w * 0.055, 8, false)
        moduleDot(context, w * 0.78, mid, 2.8, false)
        moduleBlock(context, w * 0.81, mid - 4, w * 0.055, 8, false)
        moduleDot(context, w * 0.895, mid, 2.8, false)
      } else if (route === "widgets") {
        for (let row = 0; row < 2; row++) {
          for (let column = 0; column < 3; column++) {
            const cellW = (w - 32) / 3
            strokeBox(context, 10 + column * (cellW + 6),
              mid - 29 + row * 34, cellW, 27, 5,
              row === 0 && column === 1 ? 0.76 : 0.26)
          }
        }
      } else if (route === "workspaces") {
        const widths = [9, 29, 8, 8]
        let x = (w - 72) / 2
        for (let index = 0; index < widths.length; index++) {
          rounded(context, x, mid - 4, widths[index], 8, 4)
          context.fillStyle = index === 1
            ? root.accent : Commons.Util.alpha(root.foreground, 0.28)
          context.fill()
          x += widths[index] + 6
        }
      } else if (route === "pickers") {
        for (let index = 0; index < 3; index++) {
          const cardW = w * 0.38
          strokeBox(context, w / 2 - cardW / 2 + (index - 1) * 19,
            mid - 30 + Math.abs(index - 1) * 7,
            cardW, 58, 5, index === 1 ? 0.72 : 0.22)
        }
      } else if (route === "appearance") {
        const colors = ["color01", "color02", "color03", "color04",
          "color05", "color06"]
        for (let index = 0; index < colors.length; index++) {
          context.fillStyle = root.controller.accentColor(colors[index])
          context.beginPath()
          context.arc(w / 2 - 45 + index * 18, mid - 13,
            index === 3 ? 6 : 4, 0, Math.PI * 2)
          context.fill()
        }
        strokeBox(context, w * 0.25, mid + 7, w * 0.5, 19, 9.5, 0.42)
      } else {
        for (let index = 0; index < 4; index++) {
          context.strokeStyle = index === 1
            ? root.accent : Commons.Util.alpha(root.foreground, 0.25)
          context.lineWidth = index === 1 ? 2 : 1
          context.beginPath()
          context.moveTo(w * 0.24, mid - 25 + index * 17)
          context.lineTo(w * (0.60 + index * 0.035),
            mid - 25 + index * 17)
          context.stroke()
          context.fillStyle = index === 1
            ? root.accent : Commons.Util.alpha(root.foreground, 0.32)
          context.beginPath()
          context.arc(w * 0.72, mid - 25 + index * 17,
            index === 1 ? 4 : 3, 0, Math.PI * 2)
          context.fill()
        }
      }
    }

    Connections {
      target: root
      function onSemanticRouteChanged() { preview.requestPaint() }
      function onForegroundChanged() { preview.requestPaint() }
      function onAccentChanged() { preview.requestPaint() }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()
  }

  WordmarkPreview {
    visible: root.semanticRoute === "logo"
    anchors.centerIn: parent
    width: Math.min(parent.width - 20, 130)
    height: 36
    value: "shibumi"
    foreground: root.foreground
    fontFamily: root.controller.marketFont
  }
}
