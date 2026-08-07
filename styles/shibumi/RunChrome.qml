pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

Item {
  id: root

  required property var bar
  property var runs: []
  property string screenName: ""
  property real screenX: 0
  readonly property string shellStyle:
    ["shibumi", "full", "fit", "dock", "notch"]
      .indexOf(String(bar.visualTokens.shellStyle || "")) >= 0
      ? String(bar.visualTokens.shellStyle) : "shibumi"
  readonly property real cornerRadius: shellStyle === "fit"
    ? Math.min(height / 2, bar.visualTokens.shellFitRadius)
    : shellStyle === "dock"
      ? Math.min(height / 2, bar.visualTokens.shellDockRadius)
      : Math.min(height / 2, bar.visualTokens.islandRadius)
  readonly property real wing: shellStyle === "notch"
    ? bar.visualTokens.shellWingWidth : 0
  readonly property real notchBodyRadius: shellStyle === "notch" ? 9 : 0
  readonly property real notchCurveKappa: 0.55228475
  // The flowing shoulder and the straight desktop edge must meet at the
  // exact same x-coordinate. Keeping that seam as one geometry token makes
  // it independent from widget content width and per-group padding.
  readonly property real notchShoulderInset: wing + notchBodyRadius
  readonly property bool atTop: bar.position !== "bottom"
  readonly property real desktopEdgeInset: shellStyle === "notch"
    ? notchShoulderInset
    : shellStyle === "fit" || shellStyle === "dock" ? cornerRadius : 0
  readonly property color shellBorder:
    bar.visualTokens.shellBorder !== undefined
      ? bar.visualTokens.shellBorder : bar.visualTokens.islandBorder
  readonly property var connectedPanelRecord:
    typeof bar.connectedPanelForScreen === "function"
      ? bar.connectedPanelForScreen(screenName) : ({
          owner: bar.connectedPanelOwner,
          screenName: bar.connectedPanelScreenName,
          reveal: bar.connectedPanelReveal,
          x: bar.connectedPanelX
        })
  readonly property bool connectedPanelActive:
    shellStyle !== "shibumi"
    && screenName !== ""
    && connectedPanelRecord.screenName === screenName
    && Number(connectedPanelRecord.reveal || 0) > 0.001
  readonly property real connectedReveal: connectedPanelActive
    ? Math.max(0, Math.min(1,
        Number(connectedPanelRecord.reveal) || 0)) : 0
  readonly property real connectedCenterX: Math.max(13,
    Math.min(width - 13,
      Number(connectedPanelRecord.x || 0) - screenX))
  readonly property real connectedCurveHalfWidth: 7 * connectedReveal
  readonly property real connectedTangentControl: 4.25 * connectedReveal
  readonly property real connectedTipControl: 2 * connectedReveal
  readonly property real connectedDepth: 5 * connectedReveal
  readonly property real notchConnectedCenterX: connectedPanelActive
    ? Math.max(desktopEdgeInset + connectedCurveHalfWidth,
        Math.min(width - desktopEdgeInset - connectedCurveHalfWidth,
          connectedCenterX))
    : width / 2
  readonly property real connectedEdgeY: atTop ? height : 0
  readonly property real connectedInnerY: atTop
    ? height - connectedDepth : connectedDepth
  readonly property real borderEdgeY: atTop ? height - 0.5 : 0.5
  readonly property real borderInnerY: atTop
    ? borderEdgeY - connectedDepth : borderEdgeY + connectedDepth

  // V2 owns one shadow for the complete shell. Individual widget shadows are
  // a V1/Shibumi presentation option and must not fragment Full/Fit/Dock.
  RectangularShadow {
    anchors.fill: parent
    visible: root.shellStyle !== "shibumi" && root.shellStyle !== "notch"
    radius: root.shellStyle === "full" ? 0 : root.cornerRadius
    blur: 9
    spread: 0
    offset: Qt.vector2d(0, root.atTop ? 2 : -2)
    color: root.bar.visualTokens.shellShadow !== undefined
      ? root.bar.visualTokens.shellShadow : Qt.rgba(0, 0, 0, 0.46)
    z: -1
  }

  // The approved Shibumi/V1 surface is a 5px-inset rounded island. Its run
  // model also preserves the original optional split-island language.
  Repeater {
    model: root.shellStyle === "shibumi" ? root.runs : []

    delegate: Rectangle {
      required property var modelData
      x: Number(modelData.x || 0)
      y: 0
      width: Math.max(0, Number(modelData.width || 0))
      height: root.height
      radius: Math.min(height / 2, root.bar.visualTokens.islandRadius)
      color: root.bar.background
      border.width: root.bar.visualTokens.pillBorderWidth
      border.color: root.bar.visualTokens.islandBorder

      RectangularShadow {
        anchors.fill: parent
        visible: root.bar.visualTokens.shadowEnabled === true
        radius: parent.radius
        blur: 8
        spread: 0
        offset: Qt.vector2d(0, root.atTop ? 1 : -1)
        color: root.bar.visualTokens.pillShadow !== undefined
          ? root.bar.visualTokens.pillShadow : Qt.rgba(0, 0, 0, 0.55)
        z: -1
      }
    }
  }

  Shape {
    anchors.fill: parent
    visible: (root.shellStyle === "full" || root.shellStyle === "fit")
      && root.atTop
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      id: topCompactPath
      readonly property real r: root.shellStyle === "fit"
        ? root.cornerRadius : 0
      strokeColor: "transparent"
      strokeWidth: 0
      fillColor: root.bar.background
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.RoundJoin
      startX: topCompactPath.r
      startY: 0
      PathLine { x: root.width - topCompactPath.r; y: 0 }
      PathQuad {
        x: root.width
        y: topCompactPath.r
        controlX: root.width
        controlY: 0
      }
      PathLine { x: root.width; y: root.height - topCompactPath.r }
      PathQuad {
        x: root.width - topCompactPath.r
        y: root.height
        controlX: root.width
        controlY: root.height
      }
      PathLine {
        x: root.connectedCenterX + root.connectedCurveHalfWidth
        y: root.height
      }
      PathCubic {
        x: root.connectedCenterX
        y: root.connectedInnerY
        control1X: root.connectedCenterX + root.connectedTangentControl
        control1Y: root.height
        control2X: root.connectedCenterX + root.connectedTipControl
        control2Y: root.connectedInnerY
      }
      PathCubic {
        x: root.connectedCenterX - root.connectedCurveHalfWidth
        y: root.height
        control1X: root.connectedCenterX - root.connectedTipControl
        control1Y: root.connectedInnerY
        control2X: root.connectedCenterX - root.connectedTangentControl
        control2Y: root.height
      }
      PathLine { x: topCompactPath.r; y: root.height }
      PathQuad {
        x: 0
        y: root.height - topCompactPath.r
        controlX: 0
        controlY: root.height
      }
      PathLine { x: 0; y: topCompactPath.r }
      PathQuad {
        x: topCompactPath.r
        y: 0
        controlX: 0
        controlY: 0
      }
    }
  }

  Shape {
    anchors.fill: parent
    visible: (root.shellStyle === "full" || root.shellStyle === "fit")
      && !root.atTop
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      id: bottomCompactPath
      readonly property real r: root.shellStyle === "fit"
        ? root.cornerRadius : 0
      strokeColor: "transparent"
      strokeWidth: 0
      fillColor: root.bar.background
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.RoundJoin
      startX: bottomCompactPath.r
      startY: 0
      PathLine {
        x: root.connectedCenterX - root.connectedCurveHalfWidth
        y: 0
      }
      PathCubic {
        x: root.connectedCenterX
        y: root.connectedInnerY
        control1X: root.connectedCenterX - root.connectedTangentControl
        control1Y: 0
        control2X: root.connectedCenterX - root.connectedTipControl
        control2Y: root.connectedInnerY
      }
      PathCubic {
        x: root.connectedCenterX + root.connectedCurveHalfWidth
        y: 0
        control1X: root.connectedCenterX + root.connectedTipControl
        control1Y: root.connectedInnerY
        control2X: root.connectedCenterX + root.connectedTangentControl
        control2Y: 0
      }
      PathLine { x: root.width - bottomCompactPath.r; y: 0 }
      PathQuad {
        x: root.width
        y: bottomCompactPath.r
        controlX: root.width
        controlY: 0
      }
      PathLine { x: root.width; y: root.height - bottomCompactPath.r }
      PathQuad {
        x: root.width - bottomCompactPath.r
        y: root.height
        controlX: root.width
        controlY: root.height
      }
      PathLine { x: bottomCompactPath.r; y: root.height }
      PathQuad {
        x: 0
        y: root.height - bottomCompactPath.r
        controlX: 0
        controlY: root.height
      }
      PathLine { x: 0; y: bottomCompactPath.r }
      PathQuad {
        x: bottomCompactPath.r
        y: 0
        controlX: 0
        controlY: 0
      }
    }
  }

  // Fit's fill terminates on the item boundary. Its border is inset by half a
  // pixel and leaves the panel-facing edge to the straight/connected contour
  // below, so the curve renderer cannot produce a second parallel edge row.
  Shape {
    id: fitOuterBorder
    anchors.fill: parent
    visible: root.shellStyle === "fit"
      && root.bar.visualTokens.pillBorderWidth > 0
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    z: 5

    ShapePath {
      strokeColor: root.shellBorder
      strokeWidth: root.bar.visualTokens.pillBorderWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.RoundJoin
      startX: root.cornerRadius
      startY: root.atTop ? root.height - 0.5 : 0.5
      PathQuad {
        x: 0.5
        y: root.atTop
          ? root.height - root.cornerRadius : root.cornerRadius
        controlX: 0.5
        controlY: root.atTop ? root.height - 0.5 : 0.5
      }
      PathLine {
        x: 0.5
        y: root.atTop
          ? root.cornerRadius : root.height - root.cornerRadius
      }
      PathQuad {
        x: root.cornerRadius
        y: root.atTop ? 0.5 : root.height - 0.5
        controlX: 0.5
        controlY: root.atTop ? 0.5 : root.height - 0.5
      }
      PathLine {
        x: root.width - root.cornerRadius
        y: root.atTop ? 0.5 : root.height - 0.5
      }
      PathQuad {
        x: root.width - 0.5
        y: root.atTop
          ? root.cornerRadius : root.height - root.cornerRadius
        controlX: root.width - 0.5
        controlY: root.atTop ? 0.5 : root.height - 0.5
      }
      PathLine {
        x: root.width - 0.5
        y: root.atTop
          ? root.height - root.cornerRadius : root.cornerRadius
      }
      PathQuad {
        x: root.width - root.cornerRadius
        y: root.atTop ? root.height - 0.5 : 0.5
        controlX: root.width - 0.5
        controlY: root.atTop ? root.height - 0.5 : 0.5
      }
    }
  }

  Shape {
    anchors.fill: parent
    visible: root.shellStyle === "dock" && root.atTop
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillColor: root.bar.background
      startX: 0
      startY: 0
      PathLine { x: root.width; y: 0 }
      PathLine { x: root.width; y: root.height - root.cornerRadius }
      PathQuad {
        x: root.width - root.cornerRadius
        y: root.height
        controlX: root.width
        controlY: root.height
      }
      PathLine {
        x: root.connectedCenterX + root.connectedCurveHalfWidth
        y: root.height
      }
      PathCubic {
        x: root.connectedCenterX
        y: root.connectedInnerY
        control1X: root.connectedCenterX + root.connectedTangentControl
        control1Y: root.height
        control2X: root.connectedCenterX + root.connectedTipControl
        control2Y: root.connectedInnerY
      }
      PathCubic {
        x: root.connectedCenterX - root.connectedCurveHalfWidth
        y: root.height
        control1X: root.connectedCenterX - root.connectedTipControl
        control1Y: root.connectedInnerY
        control2X: root.connectedCenterX - root.connectedTangentControl
        control2Y: root.height
      }
      PathLine { x: root.cornerRadius; y: root.height }
      PathQuad {
        x: 0
        y: root.height - root.cornerRadius
        controlX: 0
        controlY: root.height
      }
      PathLine { x: 0; y: 0 }
    }
  }

  Shape {
    anchors.fill: parent
    visible: root.shellStyle === "dock" && !root.atTop
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillColor: root.bar.background
      startX: root.cornerRadius
      startY: 0
      PathLine {
        x: root.connectedCenterX - root.connectedCurveHalfWidth
        y: 0
      }
      PathCubic {
        x: root.connectedCenterX
        y: root.connectedInnerY
        control1X: root.connectedCenterX - root.connectedTangentControl
        control1Y: 0
        control2X: root.connectedCenterX - root.connectedTipControl
        control2Y: root.connectedInnerY
      }
      PathCubic {
        x: root.connectedCenterX + root.connectedCurveHalfWidth
        y: 0
        control1X: root.connectedCenterX + root.connectedTipControl
        control1Y: root.connectedInnerY
        control2X: root.connectedCenterX + root.connectedTangentControl
        control2Y: 0
      }
      PathLine { x: root.width - root.cornerRadius; y: 0 }
      PathQuad {
        x: root.width
        y: root.cornerRadius
        controlX: root.width
        controlY: 0
      }
      PathLine { x: root.width; y: root.height }
      PathLine { x: 0; y: root.height }
      PathLine { x: 0; y: root.cornerRadius }
      PathQuad {
        x: root.cornerRadius
        y: 0
        controlX: 0
        controlY: 0
      }
    }
  }

  // Original V2 notch: a content-width lobe flows out of the active screen
  // edge. Each shoulder is one continuous cubic, without a neck or outer frame.
  Shape {
    anchors.fill: parent
    visible: root.shellStyle === "notch"
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillColor: root.bar.background
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.RoundJoin
      startX: 0.5
      startY: root.atTop ? 0 : root.height

      PathLine {
        x: root.width
        y: root.atTop ? 0 : root.height
      }
      PathCubic {
        x: root.width - root.desktopEdgeInset
        y: root.atTop ? root.height : 0
        control1X: root.width - root.wing
          + (1 - root.notchCurveKappa) * root.wing
        control1Y: root.atTop ? 0 : root.height
        control2X: root.width - root.wing
          + (1 - root.notchCurveKappa) * root.notchBodyRadius
        control2Y: root.atTop ? root.height : 0
      }
      PathLine {
        x: root.notchConnectedCenterX + root.connectedCurveHalfWidth
        y: root.connectedEdgeY
      }
      PathCubic {
        x: root.notchConnectedCenterX
        y: root.connectedInnerY
        control1X: root.notchConnectedCenterX
          + root.connectedTangentControl
        control1Y: root.connectedEdgeY
        control2X: root.notchConnectedCenterX + root.connectedTipControl
        control2Y: root.connectedInnerY
      }
      PathCubic {
        x: root.notchConnectedCenterX - root.connectedCurveHalfWidth
        y: root.connectedEdgeY
        control1X: root.notchConnectedCenterX - root.connectedTipControl
        control1Y: root.connectedInnerY
        control2X: root.notchConnectedCenterX
          - root.connectedTangentControl
        control2Y: root.connectedEdgeY
      }
      PathLine {
        x: root.desktopEdgeInset
        y: root.atTop ? root.height : 0
      }
      PathCubic {
        x: 0
        y: root.atTop ? 0 : root.height
        control1X: root.wing
          - (1 - root.notchCurveKappa) * root.notchBodyRadius
        control1Y: root.atTop ? root.height : 0
        control2X: root.wing
          - (1 - root.notchCurveKappa) * root.wing
        control2Y: root.atTop ? 0 : root.height
      }
    }
  }

  // Only Fit owns a closed perimeter. Dock keeps the screen-facing edge open
  // and draws two side/corner runs. Notch owns one fused path from its left
  // shoulder through the connected inset to its right shoulder.
  Shape {
    anchors.fill: parent
    visible: root.bar.visualTokens.pillBorderWidth > 0
      && (root.shellStyle === "dock" || root.shellStyle === "notch")
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    z: 5

    ShapePath {
      strokeColor: root.shellStyle === "dock"
        ? root.shellBorder : "transparent"
      strokeWidth: root.bar.visualTokens.pillBorderWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      startX: 0
      startY: root.atTop ? 0 : root.height
      PathLine {
        x: 0.5
        y: root.atTop ? root.height - root.cornerRadius : root.cornerRadius
      }
      PathQuad {
        x: root.cornerRadius
        y: root.atTop ? root.height - 0.5 : 0.5
        controlX: 0.5
        controlY: root.atTop ? root.height - 0.5 : 0.5
      }
    }

    ShapePath {
      strokeColor: root.shellStyle === "dock"
        ? root.shellBorder : "transparent"
      strokeWidth: root.bar.visualTokens.pillBorderWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      startX: root.width - 0.5
      startY: root.atTop ? 0 : root.height
      PathLine {
        x: root.width - 0.5
        y: root.atTop ? root.height - root.cornerRadius : root.cornerRadius
      }
      PathQuad {
        x: root.width - root.cornerRadius
        y: root.atTop ? root.height - 0.5 : 0.5
        controlX: root.width - 0.5
        controlY: root.atTop ? root.height - 0.5 : 0.5
      }
    }

    ShapePath {
      id: notchBorderPath
      strokeColor: root.shellStyle === "notch"
        ? root.shellBorder : "transparent"
      strokeWidth: root.bar.visualTokens.pillBorderWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      startX: 0
      startY: root.atTop ? 0.5 : root.height - 0.5
      PathCubic {
        x: root.desktopEdgeInset
        y: root.atTop ? root.height - 0.5 : 0.5
        control1X: root.wing
          - (1 - root.notchCurveKappa) * root.wing
        control1Y: root.atTop ? 0.5 : root.height - 0.5
        control2X: root.wing
          - (1 - root.notchCurveKappa) * root.notchBodyRadius
        control2Y: root.atTop ? root.height - 0.5 : 0.5
      }
      PathLine {
        x: root.notchConnectedCenterX - root.connectedCurveHalfWidth
        y: root.borderEdgeY
      }
      PathCubic {
        x: root.notchConnectedCenterX
        y: root.borderInnerY
        control1X: root.notchConnectedCenterX
          - root.connectedTangentControl
        control1Y: root.borderEdgeY
        control2X: root.notchConnectedCenterX - root.connectedTipControl
        control2Y: root.borderInnerY
      }
      PathCubic {
        x: root.notchConnectedCenterX + root.connectedCurveHalfWidth
        y: root.borderEdgeY
        control1X: root.notchConnectedCenterX + root.connectedTipControl
        control1Y: root.borderInnerY
        control2X: root.notchConnectedCenterX
          + root.connectedTangentControl
        control2Y: root.borderEdgeY
      }
      PathLine {
        x: root.width - root.desktopEdgeInset
        y: root.borderEdgeY
      }
      PathCubic {
        x: root.width
        y: root.atTop ? 0.5 : root.height - 0.5
        control1X: root.width - root.wing
          + (1 - root.notchCurveKappa) * root.notchBodyRadius
        control1Y: root.atTop ? root.height - 0.5 : 0.5
        control2X: root.width - root.wing
          + (1 - root.notchCurveKappa) * root.wing
        control2Y: root.atTop ? 0.5 : root.height - 0.5
      }
    }
  }

  Rectangle {
    visible: root.shellStyle !== "shibumi"
      && root.shellStyle !== "notch"
      && root.bar.visualTokens.pillBorderWidth > 0
    x: root.desktopEdgeInset
    y: root.atTop ? root.height - 1 : 0
    width: root.connectedPanelActive
      ? Math.max(0, root.connectedCenterX - 12 - x)
      : Math.max(0, root.width - 2 * root.desktopEdgeInset)
    height: 1
    color: root.shellBorder
    z: 6
  }

  Rectangle {
    visible: root.connectedPanelActive
      && root.shellStyle !== "notch"
      && root.bar.visualTokens.pillBorderWidth > 0
    x: Math.max(root.desktopEdgeInset,
      root.connectedCenterX + 12)
    y: root.atTop ? root.height - 1 : 0
    width: Math.max(0, root.width - root.desktopEdgeInset - x)
    height: 1
    color: root.shellBorder
    z: 6
  }

  // V2's connected popover contract: the fill itself owns the negative-space
  // cutout. Splitting the straight edge keeps that space genuinely transparent
  // instead of painting it with the bar color, which looked like a shadow.
  Shape {
    id: connectedInset
    visible: root.connectedPanelActive && root.shellStyle !== "notch"
    x: Math.round(root.connectedCenterX - 13)
    y: root.atTop ? root.height - 6 : 0
    width: 26
    height: 6
    z: 21
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: true
    layer.samples: 8
    layer.smooth: true
    layer.mipmap: true
    layer.textureSize: Qt.size(Math.ceil(width * 4), Math.ceil(height * 4))

    readonly property real curveHalfWidth: 7 * root.connectedReveal
    readonly property real tangentControl: 4.25 * root.connectedReveal
    readonly property real tipControl: 2 * root.connectedReveal
    readonly property real baselineY: root.atTop ? 5.5 : 0.5
    readonly property real innerY: root.atTop
      ? baselineY - 5 * root.connectedReveal
      : baselineY + 5 * root.connectedReveal

    ShapePath {
      strokeColor: root.bar.visualTokens.pillBorderWidth > 0
        ? root.shellBorder : "transparent"
      strokeWidth: root.bar.visualTokens.pillBorderWidth
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.RoundJoin
      startX: 0
      startY: connectedInset.baselineY
      PathLine {
        x: 13 - connectedInset.curveHalfWidth
        y: connectedInset.baselineY
      }
      PathCubic {
        x: 13
        y: connectedInset.innerY
        control1X: 13 - connectedInset.tangentControl
        control1Y: connectedInset.baselineY
        control2X: 13 - connectedInset.tipControl
        control2Y: connectedInset.innerY
      }
      PathCubic {
        x: 13 + connectedInset.curveHalfWidth
        y: connectedInset.baselineY
        control1X: 13 + connectedInset.tipControl
        control1Y: connectedInset.innerY
        control2X: 13 + connectedInset.tangentControl
        control2Y: connectedInset.baselineY
      }
      PathLine { x: 26; y: connectedInset.baselineY }
    }
  }
}
