pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.workspaces"
  manageIpc: false
  property url panelSource: Qt.resolvedUrl("WorkspacePanel.qml")
  property var workspaceService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.workspaces") : null
  readonly property var tokens: bar ? bar.visualTokens : null
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
  readonly property string renderStyle: displayMode === "icon" ? "rings"
    : displayMode === "text" ? "numbers" : workspaceStyle
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
    || renderStyle === "frame" ? Commons.Style.space(3)
    : renderStyle === "aurora-streak" ? Commons.Style.space(4)
    : renderStyle === "aurora" ? Commons.Style.space(3)
    : tokens ? tokens.contentGap : Commons.Style.space(5)
  readonly property int focusedDisplayIndex: {
    for (var index = 0; index < displayedWorkspaceIds.length; index++) {
      if (workspaceState(displayedWorkspaceIds[index]).focused) return index
    }
    return -1
  }
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
      settings: root.settings
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

    Rectangle {
      id: frameMotion
      z: 0
      visible: root.renderStyle === "frame" && root.frameTarget !== null
      x: workspaceRow.x + (root.frameTarget ? root.frameTarget.x : 0)
        + (root.frameTarget ? (root.frameTarget.width - width) / 2 : 0)
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(18)
      height: width
      radius: Commons.Style.space(5)
      color: "transparent"
      border.width: 1
      border.color: root.widgetInk
      antialiasing: true

      Behavior on x {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
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
            : root.renderStyle === "rings" ? Commons.Style.space(19)
            : root.renderStyle === "frame" ? Commons.Style.space(20)
            : root.renderStyle === "aurora"
              ? Commons.Style.space(focused ? 38 : 20)
            : root.renderStyle === "aurora-streak"
              ? Commons.Style.space(focused ? 34 : 12)
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
            radius: root.tokens.presentation.radius === "small"
              ? Commons.Style.space(5) : height / 2
            color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
              root.widgetInk.b,
              cell.focused ? 0.30 : cell.occupied ? 0.12 : 0.04)

            Text {
              anchors.centerIn: parent
              text: cell.modelData
              color: cell.focused
                ? root.widgetInk
                : Qt.rgba(root.widgetInk.r, root.widgetInk.g,
                  root.widgetInk.b, cell.occupied ? 0.58 : 0.32)
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

          Rectangle {
            id: ringsMark
            visible: root.renderStyle === "rings"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 13 : 12)
            height: width
            radius: width / 2
            color: cell.focused ? root.widgetInk : "transparent"
            border.width: cell.focused ? 0 : 1
            border.color: root.widgetInk
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

          Text {
            visible: root.renderStyle === "frame"
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

          Rectangle {
            visible: root.renderStyle === "aurora"
            anchors.centerIn: parent
            width: Commons.Style.space(cell.focused ? 36 : 18)
            height: Commons.Style.space(16)
            radius: height / 2
            antialiasing: true
            color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
              root.widgetInk.b,
              cell.empty ? (cellPointer.containsMouse ? 0.25 : 0.10)
                : (cellPointer.containsMouse ? 0.55 : 1))

            Behavior on width {
              NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: 250 } }
          }

          Item {
            visible: root.renderStyle === "aurora-streak"
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

          MouseArea {
            id: cellPointer
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: {
              cell.scale = root.renderStyle === "frame" ? 1
                : root.renderStyle === "rings" ? 1.06
                : root.renderStyle === "aurora" ? 1.03
                : root.renderStyle === "aurora-streak" ? 1.04 : 1.15
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
