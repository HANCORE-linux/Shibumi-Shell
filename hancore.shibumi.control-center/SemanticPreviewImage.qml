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
