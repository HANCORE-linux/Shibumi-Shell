pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons
import qs.Ui as Ui

// Quattro-compatible keyboard panel with one Shibumi-owned visible surface.
// Keep this lifecycle aligned with Ui.KeyboardPanel when its contract changes.
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Commons.Style.gapsOut
  property int padding: Commons.Style.spacing.popupPadding
  property int contentWidth: Commons.Style.space(280)
  property int contentHeight: Commons.Style.space(200)
  property bool centerOnBar: false
  property real centerOnBarOffset: 0
  property bool open: false
  // Preserve the reference panel offset across both shell variants:
  // V1 panels sit 8 px beyond the 35 px bar; V2 connected panels use 6 px.
  property int gap: shellStyle === "shibumi" ? 8 : 6
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property Item focusTarget: null
  property bool focusPrimed: false
  property bool surfaceOverrideEnabled: false
  property color surfaceColorOverride: "transparent"
  property color surfaceBorderColorOverride: "transparent"
  property real surfaceBorderWidthOverride: -1
  property real surfaceRadiusOverride: -1
  property real controlRadiusOverride: -1
  property color controlForegroundOverride: "transparent"
  property color controlAccentOverride: "transparent"
  property color controlFillOverride: "transparent"
  property color controlHoverFillOverride: "transparent"
  property color controlBorderOverride: "transparent"
  property color controlHoverBorderOverride: "transparent"

  default property alias panelContent: shibumiContent.children

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem
    ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"
  readonly property string popoutScreenName: screen
    ? String(screen.name || "") : ""
  readonly property var shibumiTokens: bar && "visualTokens" in bar
    ? bar.visualTokens : null
  readonly property string shellStyle: shibumiTokens
    ? String(shibumiTokens.shellStyle || "shibumi") : "shibumi"
  readonly property bool connectedSurfaceEnabled:
    shellStyle !== "shibumi"
    && (barPos === "top" || barPos === "bottom")
  property real connectionReveal: connectedSurfaceEnabled
    && (open || popoutSwitching) ? 1 : 0
  readonly property int shibumiBorderWidth: surfaceOverrideEnabled
    && surfaceBorderWidthOverride >= 0
    ? surfaceBorderWidthOverride : shibumiTokens
      ? shibumiTokens.panelBorderWidth : 0
  property var borderSpec: surfaceOverrideEnabled
    ? Commons.Border.flat(surfaceBorderColorOverride, shibumiBorderWidth)
    : shibumiTokens
    ? Commons.Border.flat(shibumiTokens.panelBorder, shibumiBorderWidth)
    : Commons.Border.surfaceSpec("popups", "border",
        Commons.Color.popups.border, Math.max(1, Commons.Style.space(2)))

  readonly property color renderedSurfaceColor: card.color
  readonly property real renderedSurfaceRadius: card.radius
  readonly property real renderedBorderWidth: Commons.Border.top(card.borderSpec)
  readonly property real renderedContentInset: card.contentTopInset
  readonly property int renderedContentCount: shibumiContent.children.length
  readonly property int renderedSurfaceCount: 1
  readonly property real controlRadius: controlRadiusOverride >= 0
    ? controlRadiusOverride : shibumiTokens
    ? root.shibumiTokens.tileRadius
    : Math.min(Commons.Style.space(6), Commons.Style.cornerRadius)
  readonly property color controlForeground: surfaceOverrideEnabled
    ? controlForegroundOverride : bar
    ? bar.foreground : Commons.Color.popups.text
  readonly property color controlAccent: surfaceOverrideEnabled
    ? controlAccentOverride : bar
    ? bar.urgent : Commons.Color.accent
  readonly property color controlMuted: shibumiTokens
    && shibumiTokens.sumi !== undefined
    ? shibumiTokens.sumi : Commons.Color.muted
  readonly property color controlMutedHigh: shibumiTokens
    && shibumiTokens.sumiHi !== undefined
    ? shibumiTokens.sumiHi : Commons.Util.alpha(controlForeground, 0.72)
  readonly property color controlBorderColor: surfaceOverrideEnabled
    ? controlBorderOverride : shibumiTokens
    && shibumiTokens.separator !== undefined
    ? shibumiTokens.separator : Commons.Util.alpha(controlForeground, 0.18)
  readonly property color controlHoverBorderColor: surfaceOverrideEnabled
    ? controlHoverBorderOverride : controlAccent
  readonly property real controlBorderWidth: 1
  readonly property color controlFillColor: surfaceOverrideEnabled
    ? controlFillOverride : shibumiTokens
    && shibumiTokens.fillIdle !== undefined
    ? shibumiTokens.fillIdle : Qt.rgba(0, 0, 0, 0.12)
  readonly property color controlHoverFillColor: surfaceOverrideEnabled
    ? controlHoverFillOverride : shibumiTokens
    && shibumiTokens.fillHover !== undefined
    ? shibumiTokens.fillHover : Commons.Util.alpha(controlAccent, 0.10)
  readonly property color controlActiveFillColor: shibumiTokens
    && shibumiTokens.fillActive !== undefined
    ? shibumiTokens.fillActive : Commons.Util.alpha(controlAccent, 0.18)
  readonly property color controlPrimaryHoverColor: shibumiTokens
    && shibumiTokens.fillPrimaryHover !== undefined
    ? shibumiTokens.fillPrimaryHover : Qt.lighter(controlAccent, 1.15)
  readonly property color dividerColor: controlBorderColor

  Behavior on connectionReveal {
    NumberAnimation {
      duration: root.open || root.popoutSwitching ? 160 : 120
      easing.type: root.open || root.popoutSwitching
        ? Easing.OutCubic : Easing.InCubic
    }
  }

  function publishConnectedGeometry(resolvedX) {
    if (!bar || typeof bar.publishConnectedPanel !== "function") return
    const screenName = screen ? String(screen.name || "") : ""
    bar.publishConnectedPanel(coordinatorKey, screenName,
      resolvedX, connectionReveal)
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }

  function requestKeyboardFocus(target) {
    if (!open || !target) return
    focusPrimed = false
    beginFocusPrime()
    Qt.callLater(function() {
      if (root.open && target) target.forceActiveFocus()
    })
  }

  screen: anchorWindow ? anchorWindow.screen : null
  visible: open || card.opacity > 0 || popoutSwitching
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  onBackingWindowVisibleChanged: beginFocusPrime()

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  readonly property real _barStripSize: {
    if (!bar) return 0
    const actual = (root.barPos === "top" || root.barPos === "bottom")
      ? root.barH : root.barW
    return Math.max(bar.barSize, actual) + root.gap
  }

  mask: Region {
    width: root.screenW
    height: root.screenH
  }

  TransformWatcher {
    id: anchorWatcher
    a: anchorWindow ? anchorWindow.contentItem : null
    b: anchorItem
  }

  readonly property point anchorScreenPos: {
    anchorWatcher.transform
    if (!anchorItem || !anchorWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((barPos === "left" || barPos === "right")
        ? barW + gap + margin : margin * 2))
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom")
        ? barH + gap + margin : margin * 2))
    : 0
  readonly property real verticalContentInset:
    Math.max(padding, Commons.Border.top(borderSpec))
      + Math.max(padding, Commons.Border.bottom(borderSpec))

  function fittedContentWidth(width, cap) {
    const desired = Math.max(1, Number(width) || 1)
    let maxWidth = root.availableCardWidth > 0
      ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0)
      maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    const desired = Math.max(root.verticalContentInset,
      (Number(implicitHeight) || 0) + root.verticalContentInset)
    let maxHeight = root.availableCardHeight > 0
      ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0)
      maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    const desired = Math.max(root.padding * 2,
      Number(height) || root.padding * 2)
    const maxHeight = root.availableCardHeight > 0
      ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  // The V1-compatible bar window is screen-sized so drag input remains stable.
  // Keep the layer-surface dimensions separate from the visible bar strip used
  // for panel placement and click forwarding.
  readonly property real anchorWindowW: anchorWindow
    ? Math.max(0, Number(anchorWindow.width) || 0) : 0
  readonly property real anchorWindowH: anchorWindow
    ? Math.max(0, Number(anchorWindow.height) || 0) : 0
  readonly property real barW: barPos === "left" || barPos === "right"
    ? Math.max(1, Number(bar ? bar.barSize : 0) || 0)
    : anchorWindowW || screenW
  readonly property real barH: barPos === "top" || barPos === "bottom"
    ? Math.max(1, Number(bar ? bar.barSize : 0) || 0)
    : anchorWindowH || screenH
  readonly property point cardOrigin: {
    if (!anchorItem || !bar) return Qt.point(margin, margin)
    let x = 0
    let y = 0
    if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
      x = screenW / 2 - contentWidth / 2 + centerOnBarOffset
      y = barPos === "bottom"
        ? screenH - barH - contentHeight - gap : barH + gap
    } else if (centerOnBar) {
      x = barPos === "left"
        ? barW + gap : screenW - barW - contentWidth - gap
      y = screenH / 2 - contentHeight / 2 + centerOnBarOffset
    } else if (barPos === "bottom") {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = screenH - barH - contentHeight - gap
    } else if (barPos === "left") {
      x = barW + gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else if (barPos === "right") {
      x = screenW - barW - contentWidth - gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = barH + gap
    }
    x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))
    y = Math.max(margin, Math.min(y, screenH - contentHeight - margin))
    return Qt.point(Math.round(x), Math.round(y))
  }

  onOpenChanged: {
    if (open) {
      focusPrimed = false
      beginFocusPrime()
      if (focusTarget) requestKeyboardFocus(focusTarget)
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
    }
    if (!bar) return
    const activeOwner = typeof bar.activePopoutForScreen === "function"
      ? bar.activePopoutForScreen(popoutScreenName) : bar.activePopout
    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = activeOwner && activeOwner !== coordinatorKey
      bar.requestPopout(coordinatorKey, popoutScreenName)
      if (popoutSwitching) popoutSwitchTimer.restart()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (activeOwner === coordinatorKey)
        bar.releasePopout(coordinatorKey, popoutScreenName)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
    }
  }

  Component.onDestruction: {
    if (bar && typeof bar.releasePopout === "function")
      bar.releasePopout(coordinatorKey, popoutScreenName)
    if (bar && typeof bar.clearConnectedPanel === "function")
      bar.clearConnectedPanel(coordinatorKey)
  }

  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (root.open) root.focusPrimed = true
  }

  Timer {
    id: popoutSwitchTimer
    interval: 150
    onTriggered: root.popoutSwitching = false
  }

  Timer {
    id: closeSwitchTimer
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }

  MouseArea {
    id: dismissArea
    anchors.fill: parent
    enabled: root.open
    hoverEnabled: true
    property bool hoveringBar: false
    cursorShape: hoveringBar ? Qt.PointingHandCursor : Qt.ArrowCursor

    function inBarRegion(px, py) {
      if (root.barPos === "bottom")
        return py >= root.screenH - root._barStripSize
      if (root.barPos === "left") return px <= root._barStripSize
      if (root.barPos === "right") return px >= root.screenW - root._barStripSize
      return py <= root._barStripSize
    }

    function barPoint(px, py) {
      if (root.barPos === "bottom")
        return Qt.point(px,
          py - Math.max(0, root.screenH - root.anchorWindowH))
      if (root.barPos === "right")
        return Qt.point(
          px - Math.max(0, root.screenW - root.anchorWindowW), py)
      return Qt.point(px, py)
    }

    function pressTargetAt(px, py) {
      if (!root.anchorWindow || !root.anchorWindow.contentItem
          || !root.bar || !root.bar.clickTargets) return null
      const point = barPoint(px, py)
      const targets = root.bar.clickTargets
      for (let i = targets.length - 1; i >= 0; i--) {
        const target = targets[i]
        if (!target || !target.triggerPress || target.visible === false
            || target.opacity === 0 || !target.mapToItem) continue
        if (root.bar.targetBelongsToWindow
            && !root.bar.targetBelongsToWindow(target, root.anchorWindow))
          continue
        const position = root.anchorWindow.itemPosition(target)
        if (point.x >= position.x && point.x <= position.x + target.width
            && point.y >= position.y && point.y <= position.y + target.height)
          return target
      }
      return null
    }

    function forwardBarClick(px, py, button) {
      const target = pressTargetAt(px, py)
      if (!target) return false
      target.triggerPress(button)
      return true
    }

    onPositionChanged: function(mouse) {
      hoveringBar = inBarRegion(mouse.x, mouse.y)
    }
    onExited: hoveringBar = false
    onClicked: function(mouse) {
      if (inBarRegion(mouse.x, mouse.y)
          && forwardBarClick(mouse.x, mouse.y, mouse.button)) return
      root.close()
    }
  }

  RectangularShadow {
    x: card.x
    y: card.y
    width: card.width
    height: card.height
    // Original V2 panels and their connected bar notch are shadowless.
    // Only the Shibumi/V1 presentation owns the optional panel shadow.
    visible: root.shibumiTokens && root.shibumiTokens.shadowEnabled
      && root.shellStyle === "shibumi"
    opacity: card.opacity
    radius: card.radius
    blur: 8
    spread: 0
    offset: Qt.vector2d(0,
      root.bar && root.bar.position === "bottom" ? -1 : 1)
    color: root.shibumiTokens
      ? root.shibumiTokens.pillShadow : "transparent"
  }

  // Original V2 connected silhouette: the card edge and its caret are one
  // antialiased filled/stroked path. The resolved, edge-clamped caret center is
  // published to the bar so both curves animate at the exact same screen X.
  Item {
    id: connectedSurface

    x: card.x
    y: card.y
    width: card.width
    height: card.height
    visible: root.connectedSurfaceEnabled && card.opacity > 0
    opacity: card.opacity
    z: 0

    readonly property bool pointsUp: root.barPos !== "bottom"
    readonly property real centerX: Math.max(10, Math.min(width - 10,
      Math.round(root.anchorScreenPos.x + root.anchorW / 2 - x)))
    readonly property real resolvedScreenX: x + centerX
    readonly property real radius: root.surfaceOverrideEnabled
      && root.surfaceRadiusOverride >= 0 ? root.surfaceRadiusOverride
      : root.shibumiTokens
      ? root.shibumiTokens.panelRadius : Commons.Style.cornerRadius
    readonly property real progress:
      Math.max(0, Math.min(1, root.connectionReveal))
    readonly property real maxCaretDepth: 5
    readonly property real caretHalfWidth: 6 * progress
    readonly property real caretDepth: maxCaretDepth * progress
    readonly property real caretTangentControl: 3.75 * progress
    readonly property real caretTipControl: 1.75 * progress
    readonly property real topBaseY: maxCaretDepth + 0.5
    readonly property real topTipY: topBaseY - caretDepth
    readonly property real bottomBaseY: height - 0.5
    readonly property real bottomTipY: bottomBaseY + caretDepth
    readonly property color surfaceColor: root.surfaceOverrideEnabled
      ? root.surfaceColorOverride : root.shibumiTokens
      ? root.shibumiTokens.panelBackground : Commons.Color.popups.background
    readonly property color strokeColor: root.shibumiBorderWidth > 0
      ? root.surfaceOverrideEnabled ? root.surfaceBorderColorOverride
        : root.shibumiTokens ? root.shibumiTokens.panelBorder : "transparent"
      : "transparent"

    onResolvedScreenXChanged:
      root.publishConnectedGeometry(resolvedScreenX)
    onProgressChanged:
      root.publishConnectedGeometry(resolvedScreenX)
    Component.onCompleted:
      root.publishConnectedGeometry(resolvedScreenX)

    Shape {
      x: 0
      y: -connectedSurface.maxCaretDepth
      width: connectedSurface.width
      height: connectedSurface.height + connectedSurface.maxCaretDepth
      visible: connectedSurface.pointsUp
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer
      layer.enabled: true
      layer.samples: 8
      layer.smooth: true
      layer.mipmap: true
      layer.textureSize: Qt.size(Math.ceil(width * 4), Math.ceil(height * 4))

      ShapePath {
        strokeColor: connectedSurface.strokeColor
        strokeWidth: root.shibumiBorderWidth
        fillColor: connectedSurface.surfaceColor
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.MiterJoin
        startX: connectedSurface.radius
        startY: connectedSurface.topBaseY
        PathLine {
          x: connectedSurface.centerX - connectedSurface.caretHalfWidth
          y: connectedSurface.topBaseY
        }
        PathCubic {
          x: connectedSurface.centerX
          y: connectedSurface.topTipY
          control1X: connectedSurface.centerX
            - connectedSurface.caretTangentControl
          control1Y: connectedSurface.topBaseY
          control2X: connectedSurface.centerX
            - connectedSurface.caretTipControl
          control2Y: connectedSurface.topTipY
        }
        PathCubic {
          x: connectedSurface.centerX + connectedSurface.caretHalfWidth
          y: connectedSurface.topBaseY
          control1X: connectedSurface.centerX
            + connectedSurface.caretTipControl
          control1Y: connectedSurface.topTipY
          control2X: connectedSurface.centerX
            + connectedSurface.caretTangentControl
          control2Y: connectedSurface.topBaseY
        }
        PathLine {
          x: connectedSurface.width - connectedSurface.radius
          y: connectedSurface.topBaseY
        }
        PathArc {
          x: connectedSurface.width - 0.5
          y: connectedSurface.radius + connectedSurface.topBaseY
          radiusX: connectedSurface.radius
          radiusY: connectedSurface.radius
        }
        PathLine {
          x: connectedSurface.width - 0.5
          y: connectedSurface.height + connectedSurface.maxCaretDepth
            - 0.5 - connectedSurface.radius
        }
        PathArc {
          x: connectedSurface.width - connectedSurface.radius
          y: connectedSurface.height + connectedSurface.maxCaretDepth - 0.5
          radiusX: connectedSurface.radius
          radiusY: connectedSurface.radius
        }
        PathLine {
          x: connectedSurface.radius
          y: connectedSurface.height + connectedSurface.maxCaretDepth - 0.5
        }
        PathArc {
          x: 0.5
          y: connectedSurface.height + connectedSurface.maxCaretDepth
            - 0.5 - connectedSurface.radius
          radiusX: connectedSurface.radius
          radiusY: connectedSurface.radius
        }
        PathLine {
          x: 0.5
          y: connectedSurface.radius + connectedSurface.topBaseY
        }
        PathArc {
          x: connectedSurface.radius
          y: connectedSurface.topBaseY
          radiusX: connectedSurface.radius
          radiusY: connectedSurface.radius
        }
      }
    }

    Shape {
      x: 0
      y: 0
      width: connectedSurface.width
      height: connectedSurface.height + connectedSurface.maxCaretDepth
      visible: !connectedSurface.pointsUp
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer
      layer.enabled: true
      layer.samples: 8
      layer.smooth: true
      layer.mipmap: true
      layer.textureSize: Qt.size(Math.ceil(width * 4), Math.ceil(height * 4))

      ShapePath {
        strokeColor: connectedSurface.strokeColor
        strokeWidth: root.shibumiBorderWidth
        fillColor: connectedSurface.surfaceColor
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.MiterJoin
        startX: connectedSurface.radius
        startY: 0.5
        PathLine {
          x: connectedSurface.width - connectedSurface.radius
          y: 0.5
        }
        PathArc {
          x: connectedSurface.width - 0.5
          y: connectedSurface.radius + 0.5
          radiusX: connectedSurface.radius
          radiusY: connectedSurface.radius
        }
        PathLine {
          x: connectedSurface.width - 0.5
          y: connectedSurface.height - connectedSurface.radius - 0.5
        }
        PathArc {
          x: connectedSurface.width - connectedSurface.radius
          y: connectedSurface.height - 0.5
          radiusX: connectedSurface.radius
          radiusY: connectedSurface.radius
        }
        PathLine {
          x: connectedSurface.centerX + connectedSurface.caretHalfWidth
          y: connectedSurface.bottomBaseY
        }
        PathCubic {
          x: connectedSurface.centerX
          y: connectedSurface.bottomTipY
          control1X: connectedSurface.centerX
            + connectedSurface.caretTangentControl
          control1Y: connectedSurface.bottomBaseY
          control2X: connectedSurface.centerX
            + connectedSurface.caretTipControl
          control2Y: connectedSurface.bottomTipY
        }
        PathCubic {
          x: connectedSurface.centerX - connectedSurface.caretHalfWidth
          y: connectedSurface.bottomBaseY
          control1X: connectedSurface.centerX
            - connectedSurface.caretTipControl
          control1Y: connectedSurface.bottomTipY
          control2X: connectedSurface.centerX
            - connectedSurface.caretTangentControl
          control2Y: connectedSurface.bottomBaseY
        }
        PathLine {
          x: connectedSurface.radius
          y: connectedSurface.height - 0.5
        }
        PathArc {
          x: 0.5
          y: connectedSurface.height - connectedSurface.radius - 0.5
          radiusX: connectedSurface.radius
          radiusY: connectedSurface.radius
        }
        PathLine {
          x: 0.5
          y: connectedSurface.radius + 0.5
        }
        PathArc {
          x: connectedSurface.radius
          y: 0.5
          radiusX: connectedSurface.radius
          radiusY: connectedSurface.radius
        }
      }
    }
  }

  Ui.BorderSurface {
    id: card
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.contentWidth
    height: root.contentHeight
    color: root.connectedSurfaceEnabled ? "transparent"
      : root.surfaceOverrideEnabled ? root.surfaceColorOverride
      : root.shibumiTokens ? root.shibumiTokens.panelBackground
      : Commons.Color.popups.background
    borderSpec: root.connectedSurfaceEnabled
      ? Commons.Border.flat("transparent", 0) : root.borderSpec
    padding: 0
    topPadding: Math.max(0, root.padding - borderTop)
    rightPadding: Math.max(0, root.padding - borderRight)
    bottomPadding: Math.max(0, root.padding - borderBottom)
    leftPadding: Math.max(0, root.padding - borderLeft)
    radius: root.surfaceOverrideEnabled && root.surfaceRadiusOverride >= 0
      ? root.surfaceRadiusOverride : root.shibumiTokens
      ? root.shibumiTokens.panelRadius : Commons.Style.cornerRadius
    opacity: root.open || root.popoutSwitching ? 1 : 0

    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    MouseArea { anchors.fill: parent }

    Item {
      id: shibumiContent
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      opacity: root.popoutSwitching ? (root.open ? 1 : 0) : 1

      Behavior on opacity {
        enabled: root.popoutSwitching
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
}
