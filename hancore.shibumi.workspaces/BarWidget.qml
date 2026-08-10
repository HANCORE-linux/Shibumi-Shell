pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.workspaces"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }
  property url panelSource: Qt.resolvedUrl("WorkspacePanel.qml")
  property var workspaceService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.workspaces") : null
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property var workspaceIds: workspaceService
    ? workspaceService.visibleWorkspaceIds : []
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  readonly property string workspaceStyle: workspaceService
    ? workspaceService.style : "default"
  readonly property bool v2Mode: bar && bar.layoutController
    ? bar.layoutController.v2Mode === true : false
  readonly property string renderStyle: displayMode === "icon" ? "rings"
    : displayMode === "text" ? "numbers" : workspaceStyle
  // V1 keeps the original QS Rise radius contract. The later V2 renderer has
  // fixed marker geometry and must not inherit the V1 Radius 12/6 setting.
  readonly property real numberMarkerRadius: v2Mode
    ? Commons.Style.space(10)
    : tokens && tokens.presentation
      && tokens.presentation.radius === "small"
        ? Commons.Style.space(5) : Commons.Style.space(10)
  readonly property real frameMarkerRadius: v2Mode
    ? Commons.Style.space(5)
    : tokens && tokens.presentation
      && tokens.presentation.radius === "small"
        ? Commons.Style.space(6) : Commons.Style.space(9)
  readonly property var displayedWorkspaceIds: {
    if (displayMode === "full") return workspaceIds
    for (var index = 0; index < workspaceIds.length; index++) {
      if (workspaceState(workspaceIds[index]).focused)
        return [workspaceIds[index]]
    }
    return workspaceIds.length > 0 ? [workspaceIds[0]] : []
  }
  readonly property int renderedWorkspaceCount: workspaceRepeater.count
  readonly property bool panelLoaded: panelLoader.item !== null
  readonly property bool panelLoaderReady: panelLoader.item
    ? panelLoader.item.ready === true : false
  readonly property int workspacePadding: tokens
    ? tokens.workspacePillPadding(renderStyle) : 4
  readonly property int workspaceGap: renderStyle === "rings"
    ? Commons.Style.space(3)
    : renderStyle === "aurora" ? Commons.Style.space(4)
    : renderStyle === "pacman" ? Commons.Style.space(2)
    : tokens ? tokens.contentGap : Commons.Style.space(5)
  readonly property int focusedDisplayIndex: {
    for (var index = 0; index < displayedWorkspaceIds.length; index++) {
      if (workspaceState(displayedWorkspaceIds[index]).focused) return index
    }
    return -1
  }
  readonly property int focusedWorkspaceId: focusedDisplayIndex >= 0
    ? Number(displayedWorkspaceIds[focusedDisplayIndex]) || -1 : -1
  readonly property bool v1CustomToneActive: !!(tokens
    && tokens.v2Shell !== true
    && typeof tokens.widgetHasFill === "function"
    && tokens.widgetHasFill(settings))
  readonly property color pacmanActiveColor: v1CustomToneActive ? widgetInk
    : paletteColor("color03", tokens && tokens.seal !== undefined
      ? tokens.seal : widgetInk)
  readonly property color pacmanOccupiedColor: widgetInk
  readonly property color pacmanEmptyColor: widgetInk
  readonly property color pacmanHoverColor: widgetInk
  property int pacmanLastFocusedWorkspaceId: -1
  property int pacmanTargetWorkspaceId: -1
  property bool pacmanTraveling: false
  property real pacmanMouthClosure: 0
  property int pacmanTravelDirection: 1
  property int pacmanTravelSteps: 1
  property real pacmanTravelFromX: 0
  property real pacmanTravelTargetX: 0
  property real pacmanTravelX: 0
  property real pacmanEatProgress: 0
  readonly property int pacmanTravelDuration:
    Math.min(720, 320 + pacmanTravelSteps * 100)
  readonly property int pacmanBiteCount:
    Math.max(3, Math.min(5, pacmanTravelSteps + 2))
  readonly property int pacmanBiteHalfDuration: Math.max(60,
    Math.round(pacmanTravelDuration / (pacmanBiteCount * 2)))
  readonly property real pacmanMaxMouthClosure: 0.82
  readonly property int pacmanEatDuration: 240
  readonly property int pacmanEatLeadIn:
    Math.max(0, pacmanTravelDuration - pacmanEatDuration)
  readonly property var frameTarget: {
    void(renderedWorkspaceCount)
    return focusedDisplayIndex >= 0
      ? workspaceRepeater.itemAt(focusedDisplayIndex) : null
  }
  readonly property real workspaceContentWidth: {
    void(displayedWorkspaceIds)
    void(renderStyle)
    var total = 0
    var visibleCount = 0
    for (var i = 0; i < workspaceRepeater.count; i++) {
      var item = workspaceRepeater.itemAt(i)
      if (!item || item.implicitWidth <= 0) continue
      total += item.implicitWidth
      visibleCount++
    }
    return total + Math.max(0, visibleCount - 1) * workspaceGap
  }

  implicitWidth: bar && bar.vertical ? bar.barSize : workspaceSurface.implicitWidth
  implicitHeight: bar && bar.vertical
    ? workspaceSurface.implicitHeight : bar ? bar.barSize : 28

  function activateWorkspace(id) {
    return workspaceService ? workspaceService.focusWorkspace(id) : false
  }

  function paletteColor(id, fallback) {
    return stateService && typeof stateService.paletteColor === "function"
      ? stateService.paletteColor(id) : fallback
  }

  function workspaceCell(id) {
    for (var index = 0; index < workspaceRepeater.count; index++) {
      const item = workspaceRepeater.itemAt(index)
      if (item && Number(item.modelData) === Number(id)) return item
    }
    return null
  }

  function workspaceCellIndex(id) {
    for (var index = 0; index < workspaceRepeater.count; index++) {
      const item = workspaceRepeater.itemAt(index)
      if (item && Number(item.modelData) === Number(id)) return index
    }
    return -1
  }

  function pacmanCenterX(id) {
    const item = workspaceCell(id)
    return item ? workspaceRow.x + item.x + item.width / 2 : -1
  }

  function finishPacmanTravel() {
    pacmanTraveling = false
    pacmanMouthClosure = 0
    pacmanEatProgress = 0
    pacmanTargetWorkspaceId = -1
  }

  function resetPacmanTravel() {
    pacmanTravel.stop()
    finishPacmanTravel()
    pacmanLastFocusedWorkspaceId = focusedWorkspaceId
  }

  function beginPacmanTravel(sourceId, targetId) {
    if (renderStyle !== "pacman" || focusedWorkspaceId !== targetId) {
      resetPacmanTravel()
      return false
    }
    // A live V1/V2 or spacing change can leave freshly rebound Row delegates
    // at x=0 until the next polish pass. Resolve the positioner synchronously
    // before measuring the travel path so a valid focus change is not mistaken
    // for a zero-distance transition.
    if (typeof workspaceRow.forceLayout === "function")
      workspaceRow.forceLayout()
    const interrupted = pacmanTraveling
    const currentX = pacmanTravelX
    const sourceX = interrupted ? currentX : pacmanCenterX(sourceId)
    const targetX = pacmanCenterX(targetId)
    if (sourceX < 0 || targetX < 0 || sourceX === targetX) {
      finishPacmanTravel()
      return false
    }
    pacmanTravel.stop()
    pacmanTravelFromX = sourceX
    pacmanTravelTargetX = targetX
    pacmanTravelX = sourceX
    pacmanTravelDirection = targetX >= sourceX ? 1 : -1
    const sourceIndex = workspaceCellIndex(sourceId)
    const targetIndex = workspaceCellIndex(targetId)
    pacmanTravelSteps = sourceIndex >= 0 && targetIndex >= 0
      ? Math.max(1, Math.abs(targetIndex - sourceIndex)) : 1
    pacmanTargetWorkspaceId = targetId
    pacmanEatProgress = 0
    pacmanMouthClosure = 0
    pacmanTraveling = true
    pacmanTravel.restart()
    return true
  }

  function observePacmanFocus() {
    const targetId = focusedWorkspaceId
    if (targetId < 1) return
    if (renderStyle !== "pacman" || pacmanLastFocusedWorkspaceId < 1) {
      resetPacmanTravel()
      pacmanLastFocusedWorkspaceId = targetId
      return
    }
    if (targetId === pacmanLastFocusedWorkspaceId) return
    const sourceId = pacmanLastFocusedWorkspaceId
    pacmanLastFocusedWorkspaceId = targetId
    Qt.callLater(function() { root.beginPacmanTravel(sourceId, targetId) })
  }

  function workspaceState(id) {
    return workspaceService
      ? workspaceService.workspaceState(id)
      : ({ id: Number(id) || 0, focused: false, occupied: false, windowCount: 0 })
  }

  function workspaceTooltip(id) {
    const info = workspaceState(id)
    const windows = info.windowCount === 1 ? "1 window"
      : info.windowCount + " windows"
    return "Workspace " + info.id + " · " + windows
      + " · Right-click for workspace panel"
  }

  function syncPanelLoader() {
    if (!opened) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(panelSource, {
      anchorItem: workspaceSurface,
      bar: root.bar,
      ownerWidget: root,
      workspaceService: root.workspaceService
    })
  }

  onOpenedChanged: syncPanelLoader()
  onFocusedWorkspaceIdChanged: observePacmanFocus()
  onRenderStyleChanged: resetPacmanTravel()
  Component.onCompleted: pacmanLastFocusedWorkspaceId = focusedWorkspaceId

  Item {
    id: workspaceSurface
    anchors.centerIn: parent
    implicitWidth: root.workspaceContentWidth + 2 * root.workspacePadding
    implicitHeight: root.bar ? root.bar.barSize : Commons.Style.space(28)
    width: implicitWidth
    height: implicitHeight

    PillSurface {
      tokenSource: root.tokens
      bar: root.bar
      settings: root.settings
      v1AppearanceEnabled: true
      anchors.fill: parent
      anchors.topMargin: Math.round((parent.height - root.tokens.pillHeight) / 2)
      anchors.bottomMargin: Math.round((parent.height - root.tokens.pillHeight) / 2)
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggle()
    }

    Item {
      id: frameMotion
      z: 0
      visible: root.renderStyle === "rings" && root.frameTarget !== null
      x: workspaceRow.x + (root.frameTarget ? root.frameTarget.x : 0)
        + (root.frameTarget ? (root.frameTarget.width - width) / 2 : 0)
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(18)
      height: width

      Behavior on x {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
      }

      Shape {
        id: frameShape
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.samples: 8
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(
          Math.ceil(width * 4), Math.ceil(height * 4))
        readonly property real r: root.frameMarkerRadius

        ShapePath {
          strokeColor: root.widgetInk
          strokeWidth: 1
          fillColor: "transparent"
          capStyle: ShapePath.FlatCap
          joinStyle: ShapePath.RoundJoin
          startX: frameShape.r
          startY: 0.5
          PathLine { x: frameShape.width - frameShape.r; y: 0.5 }
          PathQuad {
            x: frameShape.width - 0.5
            y: frameShape.r
            controlX: frameShape.width - 0.5
            controlY: 0.5
          }
          PathLine {
            x: frameShape.width - 0.5
            y: frameShape.height - frameShape.r
          }
          PathQuad {
            x: frameShape.width - frameShape.r
            y: frameShape.height - 0.5
            controlX: frameShape.width - 0.5
            controlY: frameShape.height - 0.5
          }
          PathLine { x: frameShape.r; y: frameShape.height - 0.5 }
          PathQuad {
            x: 0.5
            y: frameShape.height - frameShape.r
            controlX: 0.5
            controlY: frameShape.height - 0.5
          }
          PathLine { x: 0.5; y: frameShape.r }
          PathQuad {
            x: frameShape.r
            y: 0.5
            controlX: 0.5
            controlY: 0.5
          }
        }
      }
    }

    Row {
      id: workspaceRow
      z: 1
      anchors.centerIn: parent
      spacing: root.workspaceGap
      width: root.workspaceContentWidth

      Repeater {
        id: workspaceRepeater
        model: root.displayedWorkspaceIds

        delegate: Item {
          id: cell
          required property int modelData
          readonly property var workspaceInfo: root.workspaceState(modelData)
          readonly property bool focused: workspaceInfo.focused === true
          readonly property bool occupied: workspaceInfo.occupied === true
          readonly property bool empty: !focused && !occupied
          readonly property int numberWidth: Commons.Style.space(20)

          implicitWidth: root.renderStyle === "numbers" ? Commons.Style.space(22)
            : root.renderStyle === "kanji" ? Commons.Style.space(22)
            : root.renderStyle === "magic"
              ? Commons.Style.space(focused ? 20 : 18)
            : root.renderStyle === "rings" ? Commons.Style.space(20)
            : root.renderStyle === "aurora"
              ? Commons.Style.space(focused ? 34 : 12)
            : root.renderStyle === "pacman"
              ? Commons.Style.space(22)
            : Commons.Style.space(focused ? 32 : 16)
          implicitHeight: workspaceSurface.height

          Behavior on implicitWidth {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
          }
          Behavior on scale { NumberAnimation { duration: 120 } }

          Rectangle {
            visible: root.renderStyle === "default"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 34 : 16)
            height: Commons.Style.space(16)
            radius: height / 2
            color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
              root.widgetInk.b,
              cell.focused ? 0.20 : cell.occupied ? 0.18 : 0.06)
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          }

          Rectangle {
            visible: root.renderStyle === "default"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 26 : 8)
            height: Commons.Style.space(8)
            radius: height / 2
            color: cell.focused || cell.occupied
              ? root.widgetInk : Qt.rgba(root.widgetInk.r,
                root.widgetInk.g, root.widgetInk.b, 0.25)
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          }

          Rectangle {
            visible: root.renderStyle === "numbers"
            anchors.centerIn: parent
            width: cell.numberWidth
            height: Commons.Style.space(20)
            radius: root.numberMarkerRadius
            color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
              root.widgetInk.b,
              cell.focused ? 0.30 : cell.occupied ? 0.12 : 0.04)

            Text {
              anchors.centerIn: parent
              text: cell.modelData
              color: cell.focused
                ? root.widgetInk
                : Qt.rgba(root.widgetInk.r, root.widgetInk.g,
                  root.widgetInk.b, cell.occupied ? 0.5 : 0.28)
              font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: cell.focused
                ? Commons.Style.font.subtitle : root.tokens.labelSize
              font.weight: cell.focused ? Font.Bold : Font.Normal
              renderType: Text.NativeRendering
            }
          }

          Text {
            visible: root.renderStyle === "magic"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: cell.focused ? 0 : 1
            text: cell.focused ? "✦" : cell.occupied ? "✧" : "·"
            color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
              root.widgetInk.b, cell.focused ? 1 : cell.occupied ? 0.7 : 0.3)
            font.family: "Adwaita Mono"
            font.pixelSize: Commons.Style.space(cell.focused ? 22 : 18)
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Text {
            visible: root.renderStyle === "kanji"
            anchors.centerIn: parent
            text: cell.modelData >= 1 && cell.modelData <= 10
              ? ["一", "二", "三", "四", "五",
                 "六", "七", "八", "九", "十"][cell.modelData - 1]
              : String(cell.modelData)
            color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
              root.widgetInk.b, cell.focused ? 1 : cell.occupied ? 0.7 : 0.3)
            font.family: "Noto Sans CJK JP"
            font.pixelSize: Commons.Style.space(cell.focused ? 15 : 13)
            font.weight: Font.Normal
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Text {
            visible: root.renderStyle === "rings"
            anchors.centerIn: parent
            text: cell.modelData
            color: root.widgetInk
            opacity: cellPointer.containsMouse ? 1
              : cell.focused ? 1 : cell.occupied ? 0.64 : 0.24
            font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: Commons.Style.space(12)
            font.weight: Font.Normal
            font.hintingPreference: Font.PreferNoHinting
            renderType: Text.QtRendering

            Behavior on opacity {
              NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
          }

          Item {
            visible: root.renderStyle === "aurora"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 32 : 10)
            height: Commons.Style.space(16)

            Behavior on width {
              NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Rectangle {
              anchors.centerIn: parent
              width: Commons.Style.space(
                cell.focused ? 28 : cell.occupied ? 6 : 4)
              height: Commons.Style.space(
                cell.focused ? 3 : cell.occupied ? 6 : 4)
              radius: height / 2
              color: root.widgetInk
              opacity: cellPointer.containsMouse ? 1
                : cell.focused ? 0.92 : cell.occupied ? 0.62 : 0.18
              antialiasing: true

              Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
              }
              Behavior on height {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
              }
              Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
              }
            }
          }

          PacmanWorkspaceMarker {
            visible: root.renderStyle === "pacman"
            anchors.centerIn: parent
            focused: cell.focused && !(root.pacmanTraveling
              && cell.modelData === root.pacmanTargetWorkspaceId)
            occupied: cell.occupied
            hovered: cellPointer.containsMouse
            eatProgress: root.pacmanTraveling
                && cell.modelData === root.pacmanTargetWorkspaceId
              ? root.pacmanEatProgress : 0
            eatDirection: root.pacmanTravelDirection
            activeColor: root.pacmanActiveColor
            occupiedColor: root.pacmanOccupiedColor
            emptyColor: root.pacmanEmptyColor
            hoverColor: root.pacmanHoverColor
          }

          MouseArea {
            id: cellPointer
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
              cell.scale = root.renderStyle === "rings" ? 1
                : root.renderStyle === "pacman" ? 1
                : root.renderStyle === "aurora" ? 1.04 : 1.15
              if (root.bar) root.bar.showTooltip(
                workspaceSurface, root.workspaceTooltip(cell.modelData))
            }
            onExited: {
              cell.scale = 1
              if (root.bar) root.bar.hideTooltip(workspaceSurface)
            }
            onClicked: function(mouse) {
              if (root.bar) root.bar.hideTooltip(workspaceSurface)
              if (mouse.button === Qt.RightButton) root.toggle()
              else root.activateWorkspace(cell.modelData)
            }
          }
        }
      }
    }

    Item {
      id: pacmanRunner
      visible: root.pacmanTraveling && root.renderStyle === "pacman"
      z: 4
      x: root.pacmanTravelX - width / 2
      y: Math.round((parent.height - height) / 2)
      width: Commons.Style.space(22)
      height: Commons.Style.space(18)

      Item {
        id: pacmanRunnerVisual
        anchors.fill: parent
        transform: Scale {
          origin.x: pacmanRunnerVisual.width / 2
          origin.y: pacmanRunnerVisual.height / 2
          xScale: root.pacmanTravelDirection
        }

        Text {
          id: pacmanRunnerGlyph
          anchors.centerIn: parent
          text: "󰮯"
          color: root.pacmanActiveColor
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: Commons.Style.space(14)
          font.weight: Font.Bold
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
        }

        Canvas {
          id: pacmanMouthFill
          anchors.centerIn: parent
          width: Commons.Style.space(16)
          height: width
          property real closure: root.pacmanMouthClosure
          property color fillColor: root.pacmanActiveColor

          onClosureChanged: requestPaint()
          onFillColorChanged: requestPaint()
          onPaint: {
            const context = getContext("2d")
            const centerX = width / 2
            const centerY = height / 2
            const radius = Math.min(width, height) * 0.38
            const angle = 0.70 * Math.max(0, Math.min(1, closure))
            context.clearRect(0, 0, width, height)
            if (angle <= 0.001) return
            context.fillStyle = String(fillColor)
            context.beginPath()
            context.moveTo(centerX, centerY)
            context.arc(centerX, centerY, radius,
              -angle, angle, false)
            context.closePath()
            context.fill()
          }
        }
      }
    }
  }

  SequentialAnimation {
    id: pacmanTravel
    running: false

    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "pacmanTravelX"
        from: root.pacmanTravelFromX
        to: root.pacmanTravelTargetX
        duration: root.pacmanTravelDuration
        easing.type: Easing.InOutSine
      }

      SequentialAnimation {
        loops: root.pacmanBiteCount
        NumberAnimation {
          target: root
          property: "pacmanMouthClosure"
          from: 0
          to: root.pacmanMaxMouthClosure
          duration: root.pacmanBiteHalfDuration
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          target: root
          property: "pacmanMouthClosure"
          from: root.pacmanMaxMouthClosure
          to: 0
          duration: root.pacmanBiteHalfDuration
          easing.type: Easing.InOutSine
        }
      }

      SequentialAnimation {
        PauseAnimation { duration: root.pacmanEatLeadIn }
        NumberAnimation {
          target: root
          property: "pacmanEatProgress"
          from: 0
          to: 1
          duration: root.pacmanEatDuration
          easing.type: Easing.InCubic
        }
      }
    }

    ScriptAction { script: root.finishPacmanTravel() }
  }

  Loader { id: panelLoader }
}
