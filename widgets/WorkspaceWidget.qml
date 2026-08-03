pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "omarchy.workspaces"
  manageIpc: false
  property url panelSource: Qt.resolvedUrl("WorkspacePanel.qml")
  readonly property var workspaceService: bar ? bar.workspaceService : null
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property var workspaceIds: workspaceService
    ? workspaceService.visibleWorkspaceIds : []
  readonly property string workspaceStyle: workspaceService
    ? workspaceService.style : "default"
  readonly property color pacmanActiveColor:
    paletteColor("color03", bar ? bar.urgent : Commons.Color.accent)
  readonly property color pacmanBarColor: bar
    ? bar.foreground : Commons.Color.foreground
  readonly property color pacmanOccupiedColor: pacmanBarColor
  readonly property color pacmanEmptyColor: pacmanBarColor
  readonly property color pacmanHoverColor: pacmanBarColor
  readonly property int renderedWorkspaceCount: workspaceRepeater.count
  readonly property bool panelLoaded: panelLoader.item !== null
  readonly property bool panelLoaderReady: panelLoader.item
    ? panelLoader.item.ready === true : false
  readonly property int workspacePadding: tokens
    ? tokens.workspacePillPadding(workspaceStyle) : 4
  readonly property int workspaceGap: workspaceStyle === "rings"
    || workspaceStyle === "aurora" ? Commons.Style.space(3)
    : workspaceStyle === "pacman" ? Commons.Style.space(2)
    : tokens ? tokens.contentGap : Commons.Style.space(5)
  readonly property real workspaceContentWidth: {
    void(workspaceIds)
    void(workspaceStyle)
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

  Item {
    id: workspaceSurface
    anchors.centerIn: parent
    implicitWidth: root.workspaceContentWidth + 2 * root.workspacePadding
    implicitHeight: root.bar ? root.bar.barSize : Commons.Style.space(28)
    width: implicitWidth
    height: implicitHeight

    PillSurface {
      bar: root.bar
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

    Row {
      id: workspaceRow
      anchors.centerIn: parent
      spacing: root.workspaceGap
      width: root.workspaceContentWidth

      Repeater {
        id: workspaceRepeater
        model: root.workspaceIds

        delegate: Item {
          id: cell
          required property int modelData
          readonly property var workspaceInfo: root.workspaceState(modelData)
          readonly property bool focused: workspaceInfo.focused === true
          readonly property bool occupied: workspaceInfo.occupied === true
          readonly property bool empty: !focused && !occupied
          readonly property int numberWidth: Commons.Style.space(20)

          implicitWidth: root.workspaceStyle === "numbers" ? Commons.Style.space(22)
            : root.workspaceStyle === "kanji" ? Commons.Style.space(22)
            : root.workspaceStyle === "magic"
              ? Commons.Style.space(focused ? 20 : 18)
            : root.workspaceStyle === "rings" ? Commons.Style.space(19)
            : root.workspaceStyle === "aurora"
              ? Commons.Style.space(focused ? 38 : 20)
            : root.workspaceStyle === "pacman"
              ? Commons.Style.space(22)
              : Commons.Style.space(focused ? 32 : 16)
          implicitHeight: workspaceSurface.height

          Behavior on implicitWidth {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
          }
          Behavior on scale { NumberAnimation { duration: 120 } }

          Rectangle {
            visible: root.workspaceStyle === "default"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 34 : 16)
            height: Commons.Style.space(16)
            radius: height / 2
            color: root.bar ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
              root.bar.urgent.b, cell.focused ? 0.20 : cell.occupied ? 0.18 : 0.06)
              : "transparent"
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          }

          Rectangle {
            visible: root.workspaceStyle === "default"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 26 : 8)
            height: Commons.Style.space(8)
            radius: height / 2
            color: root.bar ? (cell.focused || cell.occupied
              ? root.bar.urgent : Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
                root.bar.urgent.b, 0.25)) : Commons.Color.accent
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          }

          Rectangle {
            visible: root.workspaceStyle === "numbers"
            anchors.centerIn: parent
            width: cell.numberWidth
            height: Commons.Style.space(20)
            radius: root.tokens.presentation.radius === "small"
              ? Commons.Style.space(5) : height / 2
            color: root.bar ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
              root.bar.urgent.b, cell.focused ? 0.30 : cell.occupied ? 0.12 : 0.04)
              : "transparent"

            Text {
              anchors.centerIn: parent
              text: cell.modelData
              color: root.bar ? (cell.focused
                ? Qt.lighter(root.bar.urgent, 1.3)
                : Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
                  root.bar.urgent.b, cell.occupied ? 0.5 : 0.28))
                : Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: cell.focused
                ? Commons.Style.font.subtitle : root.tokens.labelSize
              font.weight: cell.focused ? Font.Bold : Font.Normal
              renderType: Text.NativeRendering
            }
          }

          Text {
            visible: root.workspaceStyle === "magic"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: cell.focused ? 0 : 1
            text: cell.focused ? "✦" : cell.occupied ? "✧" : "·"
            color: root.bar ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
              root.bar.urgent.b, cell.focused ? 1 : cell.occupied ? 0.7 : 0.3)
              : Commons.Color.foreground
            font.family: "Adwaita Mono"
            font.pixelSize: Commons.Style.space(cell.focused ? 22 : 18)
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Text {
            visible: root.workspaceStyle === "kanji"
            anchors.centerIn: parent
            text: cell.modelData >= 1 && cell.modelData <= 10
              ? ["一", "二", "三", "四", "五",
                 "六", "七", "八", "九", "十"][cell.modelData - 1]
              : String(cell.modelData)
            color: root.bar ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
              root.bar.urgent.b, cell.focused ? 1 : cell.occupied ? 0.7 : 0.3)
              : Commons.Color.foreground
            font.family: "Noto Sans CJK JP"
            font.pixelSize: Commons.Style.space(cell.focused ? 15 : 13)
            font.weight: Font.Normal
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Rectangle {
            id: ringsMark
            visible: root.workspaceStyle === "rings"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 13 : 12)
            height: width
            radius: width / 2
            color: cell.focused && root.bar ? root.bar.urgent : "transparent"
            border.width: cell.focused ? 0 : 1
            border.color: root.bar ? root.bar.urgent : Commons.Color.accent
            opacity: cellPointer.containsMouse ? 0.4
              : cell.focused ? 1 : cell.occupied ? 0.45 : 0.10
            antialiasing: true

            Behavior on width {
              NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
              NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
            }
          }

          Rectangle {
            visible: root.workspaceStyle === "aurora"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 36 : 18)
            height: Commons.Style.space(16)
            radius: height / 2
            antialiasing: true
            color: root.bar ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
              root.bar.urgent.b,
              cell.empty ? (cellPointer.containsMouse ? 0.25 : 0.10)
                : (cellPointer.containsMouse ? 0.55 : 1))
              : Commons.Color.accent

            Behavior on width {
              NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: 250 } }
          }

          PacmanWorkspaceMarker {
            visible: root.workspaceStyle === "pacman"
            anchors.centerIn: parent
            focused: cell.focused
            occupied: cell.occupied
            hovered: cellPointer.containsMouse
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
              cell.scale = root.workspaceStyle === "rings" ? 1.06
                : root.workspaceStyle === "aurora"
                    || root.workspaceStyle === "pacman" ? 1.03 : 1.15
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
  }

  Loader { id: panelLoader }
}
