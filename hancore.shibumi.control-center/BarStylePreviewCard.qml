pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  required property var controller
  required property string styleValue
  required property string label
  required property string detail
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  readonly property bool selected:
    String(controller.barPresentation.shellStyle || "shibumi") === styleValue

  signal chosen(string styleValue)

  height: Commons.Style.space(92)
  radius: controller.controlRadius
  color: selected || pointer.containsMouse
    ? controller.controlHoverFillColor : controller.controlFillColor
  border.width: selected ? Math.max(1, controller.controlBorderWidth) : 1
  border.color: selected ? accent : controller.controlBorderColor

  Item {
    id: preview
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Commons.Style.space(9)
    anchors.rightMargin: Commons.Style.space(9)
    anchors.topMargin: Commons.Style.space(6)
    height: Commons.Style.space(44)
    clip: true

    Canvas {
      id: previewCanvas
      anchors.fill: parent
      antialiasing: true
      renderStrategy: Canvas.Threaded

      function roundedPath(context, x, y, width, height, radius) {
        const r = Math.max(0, Math.min(radius, width / 2, height / 2))
        context.beginPath()
        context.moveTo(x + r, y)
        context.lineTo(x + width - r, y)
        context.quadraticCurveTo(x + width, y, x + width, y + r)
        context.lineTo(x + width, y + height - r)
        context.quadraticCurveTo(
          x + width, y + height, x + width - r, y + height)
        context.lineTo(x + r, y + height)
        context.quadraticCurveTo(x, y + height, x, y + height - r)
        context.lineTo(x, y + r)
        context.quadraticCurveTo(x, y, x + r, y)
        context.closePath()
      }

      function drawSurface(context, x, y, width, height, radius) {
        roundedPath(context, x, y, width, height, radius)
        context.fillStyle = Commons.Util.alpha(
          root.selected ? root.accent : root.foreground,
          root.selected ? 0.22 : 0.10)
        context.fill()
        context.strokeStyle = root.selected
          ? root.accent : root.controller.controlBorderColor
        context.lineWidth = root.selected ? 1.3 : 1
        context.stroke()
      }

      function drawModules(context, x, y, width, height) {
        const moduleY = y + Math.max(3, (height - 8) / 2)
        const usable = Math.max(18, width - 16)
        const unit = Math.max(3, Math.min(8, usable / 16))
        const gap = Math.max(2, unit * 0.45)
        const clusters = [
          { x: x + 7, count: 3 },
          { x: x + width / 2 - unit * 1.5 - gap, count: 3 },
          { x: x + width - 7 - unit * 4 - gap * 3, count: 4 }
        ]
        context.fillStyle = root.selected
          ? root.accent : Commons.Util.alpha(root.foreground, 0.62)
        for (let clusterIndex = 0;
            clusterIndex < clusters.length; clusterIndex++) {
          const cluster = clusters[clusterIndex]
          for (let index = 0; index < cluster.count; index++) {
            roundedPath(context,
              cluster.x + index * (unit + gap), moduleY,
              unit, 8, Math.min(2, unit / 2))
            context.fill()
          }
        }
      }

      onPaint: {
        const context = getContext("2d")
        context.reset()
        context.clearRect(0, 0, width, height)
        const atTop = root.controller.barPosition !== "bottom"
        const shellHeight = Math.max(20, Math.min(28, height - 14))
        const edgeY = atTop ? 5 : height - 5
        const shellY = atTop ? 5 : height - 5 - shellHeight

        context.strokeStyle = Commons.Util.alpha(root.foreground, 0.16)
        context.lineWidth = 1
        context.beginPath()
        context.moveTo(0, edgeY)
        context.lineTo(width, edgeY)
        context.stroke()

        if (root.styleValue === "shibumi") {
          const gap = 5
          const segmentWidth = (width - gap * 2) / 3
          for (let index = 0; index < 3; index++)
            drawSurface(context, index * (segmentWidth + gap),
              shellY, segmentWidth, shellHeight, shellHeight / 2)
          drawModules(context, 0, shellY, width, shellHeight)
          return
        }

        if (root.styleValue === "full") {
          context.fillStyle = Commons.Util.alpha(
            root.selected ? root.accent : root.foreground,
            root.selected ? 0.22 : 0.10)
          context.fillRect(0, shellY, width, shellHeight)
          context.strokeStyle = root.selected
            ? root.accent : root.controller.controlBorderColor
          context.lineWidth = root.selected ? 1.3 : 1
          context.beginPath()
          context.moveTo(0, atTop ? shellY + shellHeight : shellY)
          context.lineTo(width, atTop ? shellY + shellHeight : shellY)
          context.stroke()
          drawModules(context, 0, shellY, width, shellHeight)
          return
        }

        const compactX = root.styleValue === "fit" ? 9 : 19
        const compactWidth = width - compactX * 2
        if (root.styleValue === "fit") {
          drawSurface(context, compactX, shellY,
            compactWidth, shellHeight, 6)
          drawModules(context, compactX, shellY, compactWidth, shellHeight)
          return
        }

        if (root.styleValue === "dock") {
          const radius = 8
          context.beginPath()
          if (atTop) {
            context.moveTo(compactX, shellY)
            context.lineTo(compactX + compactWidth, shellY)
            context.lineTo(compactX + compactWidth,
              shellY + shellHeight - radius)
            context.quadraticCurveTo(compactX + compactWidth,
              shellY + shellHeight, compactX + compactWidth - radius,
              shellY + shellHeight)
            context.lineTo(compactX + radius, shellY + shellHeight)
            context.quadraticCurveTo(compactX, shellY + shellHeight,
              compactX, shellY + shellHeight - radius)
          } else {
            context.moveTo(compactX + radius, shellY)
            context.lineTo(compactX + compactWidth - radius, shellY)
            context.quadraticCurveTo(compactX + compactWidth, shellY,
              compactX + compactWidth, shellY + radius)
            context.lineTo(compactX + compactWidth, shellY + shellHeight)
            context.lineTo(compactX, shellY + shellHeight)
            context.lineTo(compactX, shellY + radius)
            context.quadraticCurveTo(
              compactX, shellY, compactX + radius, shellY)
          }
          context.closePath()
          context.fillStyle = Commons.Util.alpha(
            root.selected ? root.accent : root.foreground,
            root.selected ? 0.22 : 0.10)
          context.fill()
          context.strokeStyle = root.selected
            ? root.accent : root.controller.controlBorderColor
          context.lineWidth = root.selected ? 1.3 : 1
          context.beginPath()
          if (atTop) {
            context.moveTo(compactX, shellY)
            context.lineTo(compactX, shellY + shellHeight - radius)
            context.quadraticCurveTo(compactX, shellY + shellHeight,
              compactX + radius, shellY + shellHeight)
            context.lineTo(
              compactX + compactWidth - radius, shellY + shellHeight)
            context.quadraticCurveTo(
              compactX + compactWidth, shellY + shellHeight,
              compactX + compactWidth, shellY + shellHeight - radius)
            context.lineTo(compactX + compactWidth, shellY)
          } else {
            context.moveTo(compactX, shellY + shellHeight)
            context.lineTo(compactX, shellY + radius)
            context.quadraticCurveTo(
              compactX, shellY, compactX + radius, shellY)
            context.lineTo(compactX + compactWidth - radius, shellY)
            context.quadraticCurveTo(compactX + compactWidth, shellY,
              compactX + compactWidth, shellY + radius)
            context.lineTo(
              compactX + compactWidth, shellY + shellHeight)
          }
          context.stroke()
          drawModules(context, compactX, shellY, compactWidth, shellHeight)
          return
        }

        const wing = Math.min(15, compactWidth / 5)
        const bodyInset = wing + 6
        context.beginPath()
        if (atTop) {
          context.moveTo(compactX, shellY)
          context.lineTo(compactX + compactWidth, shellY)
          context.bezierCurveTo(
            compactX + compactWidth - wing, shellY,
            compactX + compactWidth - wing, shellY + shellHeight,
            compactX + compactWidth - bodyInset, shellY + shellHeight)
          context.lineTo(compactX + bodyInset, shellY + shellHeight)
          context.bezierCurveTo(
            compactX + wing, shellY + shellHeight,
            compactX + wing, shellY, compactX, shellY)
        } else {
          context.moveTo(compactX, shellY + shellHeight)
          context.lineTo(compactX + compactWidth, shellY + shellHeight)
          context.bezierCurveTo(
            compactX + compactWidth - wing, shellY + shellHeight,
            compactX + compactWidth - wing, shellY,
            compactX + compactWidth - bodyInset, shellY)
          context.lineTo(compactX + bodyInset, shellY)
          context.bezierCurveTo(
            compactX + wing, shellY,
            compactX + wing, shellY + shellHeight,
            compactX, shellY + shellHeight)
        }
        context.closePath()
        context.fillStyle = Commons.Util.alpha(
          root.selected ? root.accent : root.foreground,
          root.selected ? 0.22 : 0.10)
        context.fill()
        context.strokeStyle = root.selected
          ? root.accent : root.controller.controlBorderColor
        context.lineWidth = root.selected ? 1.3 : 1
        context.beginPath()
        if (atTop) {
          context.moveTo(compactX, shellY)
          context.bezierCurveTo(
            compactX + wing, shellY,
            compactX + wing, shellY + shellHeight,
            compactX + bodyInset, shellY + shellHeight)
          context.lineTo(
            compactX + compactWidth - bodyInset, shellY + shellHeight)
          context.bezierCurveTo(
            compactX + compactWidth - wing, shellY + shellHeight,
            compactX + compactWidth - wing, shellY,
            compactX + compactWidth, shellY)
        } else {
          context.moveTo(compactX, shellY + shellHeight)
          context.bezierCurveTo(
            compactX + wing, shellY + shellHeight,
            compactX + wing, shellY,
            compactX + bodyInset, shellY)
          context.lineTo(compactX + compactWidth - bodyInset, shellY)
          context.bezierCurveTo(
            compactX + compactWidth - wing, shellY,
            compactX + compactWidth - wing, shellY + shellHeight,
            compactX + compactWidth, shellY + shellHeight)
        }
        context.stroke()
        drawModules(context, compactX + bodyInset, shellY,
          compactWidth - bodyInset * 2, shellHeight)
      }

      Connections {
        target: root
        function onSelectedChanged() { previewCanvas.requestPaint() }
        function onForegroundChanged() { previewCanvas.requestPaint() }
        function onAccentChanged() { previewCanvas.requestPaint() }
      }

      Connections {
        target: root.controller
        function onBarPositionChanged() { previewCanvas.requestPaint() }
      }

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }
  }

  Row {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Commons.Style.space(9)
    anchors.rightMargin: Commons.Style.space(9)
    anchors.bottomMargin: Commons.Style.space(5)
    spacing: Commons.Style.space(6)

    Column {
      width: parent.width - stateMark.width - parent.spacing
      spacing: 0

      Text {
        width: parent.width
        text: root.label
        color: root.foreground
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        font.weight: Font.DemiBold
      }

      Text {
        width: parent.width
        text: root.detail
        color: root.foreground
        opacity: 0.42
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }

    Text {
      id: stateMark
      anchors.verticalCenter: parent.verticalCenter
      text: root.selected ? "●" : ""
      color: root.accent
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.chosen(root.styleValue)
  }
}
