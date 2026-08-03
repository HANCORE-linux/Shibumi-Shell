pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons as Commons
import "gpu" as Gpu
import "presentation" as Presentation

ShellRoot {
  id: root

  property int phase: 0

  function fail(message) {
    console.error("presentation-icon-scaling-smoke:", message)
    Qt.exit(1)
  }

  function closeEnough(actual, expected, tolerance) {
    return Math.abs(Number(actual) - Number(expected)) <= tolerance
  }

  function checkGpuBounds(expectedScale, label) {
    if (gpuIcon.children.length !== 1)
      return fail(label + " GPU artwork owner changed")
    const artwork = gpuIcon.children[0]
    const topLeft = artwork.mapToItem(gpuIcon, 0, 0)
    const bottomRight = artwork.mapToItem(
      gpuIcon, artwork.width, artwork.height)
    if (!closeEnough(artwork.scale, expectedScale, 0.001)
        || topLeft.x < -0.01 || topLeft.y < -0.01
        || bottomRight.x > gpuIcon.width + 0.01
        || bottomRight.y > gpuIcon.height + 0.01)
      return fail(label + " GPU artwork escapes its scaled slot: "
        + JSON.stringify({
          scale: artwork.scale,
          slot: [gpuIcon.width, gpuIcon.height],
          topLeft: [topLeft.x, topLeft.y],
          bottomRight: [bottomRight.x, bottomRight.y]
        }))
  }

  function checkScale(label, slotWidth, slotHeight, markerWidth,
      markerHeight, glyphSize, pelletSize, eatOffset, gpuScale) {
    if (gpuIcon.width !== slotWidth || gpuIcon.height !== slotHeight)
      return fail(label + " GPU slot did not follow Commons.Style.space")
    checkGpuBounds(gpuScale, label)
    if (pacmanMarker.implicitWidth !== markerWidth
        || pacmanMarker.implicitHeight !== markerHeight
        || pacmanMarker.glyphSize !== glyphSize
        || pacmanMarker.pelletSize !== pelletSize
        || !closeEnough(pacmanMarker.eatOffset, eatOffset, 0.001))
      return fail(label + " Pacman geometry did not follow the spacing scale: "
        + JSON.stringify({
          marker: [pacmanMarker.implicitWidth, pacmanMarker.implicitHeight],
          glyph: pacmanMarker.glyphSize,
          pellet: pacmanMarker.pelletSize,
          eatOffset: pacmanMarker.eatOffset
        }))
  }

  Item {
    id: probes
    visible: false

    Gpu.GpuCardIcon {
      id: gpuIcon
      width: Commons.Style.space(20)
      height: Commons.Style.space(14)
      color: "white"
    }

    Presentation.PacmanWorkspaceMarker {
      id: pacmanMarker
      focused: true
      occupied: true
      activeColor: "#ffda44"
      occupiedColor: "white"
      emptyColor: "white"
      hoverColor: "white"
    }
  }

  Timer {
    interval: 180
    repeat: true
    running: true
    onTriggered: {
      if (root.phase === 0) {
        Commons.Style.spacingScaleWithFont = false
        Commons.Style.spacingScale = 0.8
      } else if (root.phase === 1) {
        root.checkScale("0.8x", 16, 11, 18, 14, 11, 4, 2.4, 11 / 14)
        Commons.Style.spacingScale = 1
      } else if (root.phase === 2) {
        root.checkScale("1.0x", 20, 14, 22, 18, 14, 5, 3, 1)
        Commons.Style.spacingScale = 1.5
      } else if (root.phase === 3) {
        root.checkScale("1.5x", 30, 21, 33, 27, 21, 8, 4.5, 1.5)
        Commons.Style.spacingScale = 1
        pacmanMarker.hovered = true
      } else if (root.phase === 4) {
        if (!root.closeEnough(pacmanMarker.scale, 1.08, 0.01)
            || pacmanMarker.hoverFactor !== 1.08)
          return root.fail("Pacman hover effect did not settle")
        pacmanMarker.eatProgress = 1
      } else if (root.phase === 5) {
        if (!root.closeEnough(pacmanMarker.scale, 0.55, 0.01)
            || pacmanMarker.opacity !== 0
            || pacmanMarker.hoverFactor !== 1)
          return root.fail("Pacman eat animation did not override hover")
        stop()
        console.log("presentation icon scaling smoke passed")
        Qt.quit()
      }
      root.phase++
    }
  }
}
