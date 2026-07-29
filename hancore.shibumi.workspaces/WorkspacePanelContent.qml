pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Item {
  id: root

  required property var controller
  readonly property Item focusTarget: keyCatcher
  readonly property int renderedRowCount: workspaceList.count
  readonly property bool controlsFitWidth: true
  readonly property var bar: controller.bar
  readonly property var workspaceService: controller.workspaceService

  // Keep the V1 71 px one-row content contract independent of whether this
  // component is hosted by a PanelWindow or an offscreen test Item.
  implicitHeight: 24 + 8 + 1 + 8 + workspaceList.height

  function positionAt(index) {
    if (index >= 0 && index < workspaceList.count)
      workspaceList.positionViewAtIndex(index, ListView.Contain)
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onMoveRequested: function(_dx, dy) {
      if (dy !== 0) root.controller.moveCursor(dy)
    }
    onActivateRequested: root.controller.activateCursor()
    onCloseRequested: root.controller.ownerWidget.close()
    onTabRequested: function(direction) {
      root.controller.ownerWidget.switchPanel(direction)
    }

    Column {
      id: panelColumn
      width: parent.width
      spacing: 8

      Item {
        width: parent.width
        height: 24

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Workspaces"
          color: root.bar ? root.bar.foreground : Commons.Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 13
          font.letterSpacing: 2
          font.weight: Font.Medium
          renderType: Text.NativeRendering
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.controller.shellStyle === "shibumi"
          text: "\u2715"
          color: closeMouse.containsMouse
            ? root.controller.controlAccent : root.controller.controlMuted
          font.family: root.bar ? root.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 12
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 120 } }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.controller.ownerWidget.close()
          }
        }

        IconAction {
          id: closeButton
          icon: "close"
          tooltip: "Close"
          visible: root.controller.shellStyle !== "shibumi"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.controller.ownerWidget.close()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.18) : Commons.Color.popups.border
      }

      ListView {
        id: workspaceList
        width: parent.width
        readonly property int visibleRows: Math.min(8, count)
        height: visibleRows > 0
          ? visibleRows * 30 + Math.max(0, visibleRows - 1) * 4 : 0
        model: root.controller.rows
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 4

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index
          readonly property bool hasCursor: root.controller.cursorIndex === index
          readonly property bool current: modelData.focused === true
          width: ListView.view.width
          height: 30
          radius: root.controller.controlRadius
          color: current ? root.controller.controlActiveFillColor
            : hasCursor ? root.controller.controlHoverFillColor
              : root.controller.controlFillColor
          border.width: root.controller.controlBorderWidth
          border.color: current || hasCursor ? root.controller.controlAccent
            : root.controller.controlBorderColor

          Behavior on color { ColorAnimation { duration: 120 } }

          Text {
            id: workspaceLabel
            anchors.left: parent.left
            anchors.right: windowCountLabel.left
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Workspace " + row.modelData.id
            color: row.current || row.hasCursor ? root.controller.controlAccent
              : root.bar ? root.bar.foreground : Commons.Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: 12
            font.weight: row.modelData.focused ? Font.Medium : Font.Normal
            renderType: Text.NativeRendering
            elide: Text.ElideRight
          }

          Text {
            id: windowCountLabel
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: String(row.modelData.windowCount)
            color: root.controller.controlMutedHigh
            font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: 10
            renderType: Text.NativeRendering
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.controller.cursorIndex = row.index
            onClicked: {
              root.controller.cursorIndex = row.index
              root.controller.activateCursor()
            }
          }
        }
      }
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: root.controller.controlRadius
    foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
    accent: root.bar ? root.bar.urgent : Commons.Color.accent

    IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: root.controller
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
