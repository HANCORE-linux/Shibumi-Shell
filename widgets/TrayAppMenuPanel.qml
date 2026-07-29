pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui

// V1 tray-menu presentation over Quattro's authoritative SystemTrayItem.menu.
ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var trayItem

  readonly property var rootMenu: trayItem ? trayItem.menu : null
  property var menuStack: []
  readonly property var currentMenu: menuStack.length > 0
    ? menuStack[menuStack.length - 1] : null
  readonly property var currentMenuChildren: menuStack.length > 1
    ? submenuOpener.children : rootMenuOpener.children
  property real rootMenuImplicitHeight: 0
  readonly property string appName: ownerWidget
    && typeof ownerWidget.trayItemName === "function"
      ? ownerWidget.trayItemName(trayItem) : "App Menu"

  // Share the drawer's popout owner. A separate owner makes the coordinator
  // close the status group while this menu is still opening.
  owner: ownerWidget
  open: ownerWidget.trayAppMenuOpen
  focusTarget: keyCatcher
  padding: Commons.Style.space(8)
  contentWidth: fittedContentWidth(Commons.Style.space(220))
  contentHeight: fittedContentHeight(
    Math.max(menuColumn.implicitHeight, rootMenuImplicitHeight))

  function resetMenuStack() {
    rootMenuImplicitHeight = 0
    menuStack = open && rootMenu ? [rootMenu] : []
  }

  function closeMenu() {
    closeSubmenus()
    ownerWidget.closeTrayAppMenu()
  }

  function pushSubmenu(entry) {
    if (!entry || entry.hasChildren !== true) return false
    menuStack = menuStack.concat([entry])
    Qt.callLater(function() {
      if (panel.currentMenu !== entry) return
      if (typeof entry.updateLayout === "function") entry.updateLayout()
    })
    return true
  }

  function popSubmenu() {
    if (menuStack.length <= 1) return false
    menuStack = menuStack.slice(0, -1)
    return true
  }

  function closeSubmenus() {
    menuStack = []
  }

  function stripMnemonic(value) {
    return String(value || "").replace(/_([^_])/, "$1")
  }

  onOpenChanged: resetMenuStack()
  onRootMenuChanged: resetMenuStack()
  Component.onCompleted: resetMenuStack()

  Item {
    visible: false
    width: 0
    height: 0

    QsMenuOpener {
      // Keep the DBusMenuHandle referenced for the complete panel lifetime.
      // Releasing it while switching to a child destroys that child's tree.
      id: rootMenuOpener
      menu: panel.open ? panel.rootMenu : null
    }

    QsMenuOpener {
      id: submenuOpener
      menu: panel.menuStack.length > 1 ? panel.currentMenu : null
    }
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.closeMenu()

    Column {
      id: menuColumn
      width: parent.width
      spacing: Commons.Style.space(1)
      onImplicitHeightChanged: {
        if (panel.menuStack.length <= 1)
          panel.rootMenuImplicitHeight = implicitHeight
      }

      Item {
        width: parent.width
        height: Commons.Style.space(28)

        Image {
          id: appIcon
          anchors.left: parent.left
          anchors.leftMargin: Commons.Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: String(panel.trayItem ? panel.trayItem.icon || "" : "") !== ""
          source: panel.trayItem ? String(panel.trayItem.icon || "") : ""
          sourceSize.width: Commons.Style.space(16)
          sourceSize.height: Commons.Style.space(16)
          width: visible ? Commons.Style.space(16) : 0
          height: Commons.Style.space(16)
          fillMode: Image.PreserveAspectFit
          smooth: true
        }

        Text {
          anchors.left: appIcon.right
          anchors.leftMargin: appIcon.visible ? Commons.Style.space(8) : 0
          anchors.right: panel.shellStyle === "shibumi"
            ? closeText.left : closeAction.left
          anchors.rightMargin: Commons.Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: panel.appName !== "" ? panel.appName : "App Menu"
          color: panel.controlForeground
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.body
          font.weight: Font.Medium
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }

        Text {
          id: closeText
          anchors.right: parent.right
          anchors.rightMargin: Commons.Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: panel.shellStyle === "shibumi"
          text: "\u2715"
          color: closeMouse.containsMouse
            ? panel.controlAccent : panel.controlMuted
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 12
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 120 } }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.closeMenu()
          }
        }

        IconAction {
          id: closeAction
          anchors.right: parent.right
          anchors.rightMargin: Commons.Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: panel.shellStyle !== "shibumi"
          icon: "close"
          tooltip: "Close"
          onClicked: panel.closeMenu()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Rectangle {
        visible: panel.menuStack.length > 1
        width: parent.width
        height: visible ? Commons.Style.space(24) : 0
        radius: panel.controlRadius
        color: backMouse.containsMouse
          ? panel.controlHoverFillColor : "transparent"

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Commons.Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "\u2039  back"
          color: panel.controlMutedHigh
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: Commons.Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        MouseArea {
          id: backMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.popSubmenu()
        }
      }

      Rectangle {
        visible: panel.menuStack.length > 1
        width: parent.width
        height: visible ? 1 : 0
        color: panel.dividerColor
      }

      Repeater {
        model: panel.currentMenuChildren

        delegate: Item {
          id: menuEntry
          required property var modelData

          width: menuColumn.width
          height: modelData.isSeparator
            ? Commons.Style.space(7) : Commons.Style.space(26)

          Rectangle {
            visible: menuEntry.modelData.isSeparator
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: panel.dividerColor
          }

          Rectangle {
            visible: !menuEntry.modelData.isSeparator
            anchors.fill: parent
            radius: panel.controlRadius
            color: entryMouse.containsMouse && menuEntry.modelData.enabled
              ? panel.controlActiveFillColor : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
              id: checkMark
              anchors.left: parent.left
              anchors.leftMargin: Commons.Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Commons.Style.space(12)
              text: menuEntry.modelData.checkState === Qt.Checked ? "\u2713" : ""
              color: panel.controlAccent
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            Image {
              id: entryIcon
              anchors.left: checkMark.right
              anchors.leftMargin: Commons.Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              visible: String(menuEntry.modelData.icon || "") !== ""
              source: String(menuEntry.modelData.icon || "")
              sourceSize.width: Commons.Style.space(14)
              sourceSize.height: Commons.Style.space(14)
              width: visible ? Commons.Style.space(14) : 0
              height: Commons.Style.space(14)
              fillMode: Image.PreserveAspectFit
              smooth: true
            }

            Text {
              anchors.left: entryIcon.right
              anchors.leftMargin: Commons.Style.space(6)
              anchors.right: submenuArrow.left
              anchors.rightMargin: Commons.Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              text: panel.stripMnemonic(menuEntry.modelData.text)
              color: menuEntry.modelData.enabled
                ? panel.controlForeground
                : Commons.Util.alpha(panel.controlForeground, 0.35)
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.bodySmall
              elide: Text.ElideRight
              renderType: Text.NativeRendering
            }

            Text {
              id: submenuArrow
              anchors.right: parent.right
              anchors.rightMargin: Commons.Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              visible: menuEntry.modelData.hasChildren
              text: "\u203a"
              color: panel.controlMutedHigh
              font.family: panel.bar ? panel.bar.fontFamily
                : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.heading
              renderType: Text.NativeRendering
            }

            MouseArea {
              id: entryMouse
              anchors.fill: parent
              enabled: menuEntry.modelData.enabled
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                if (menuEntry.modelData.hasChildren) {
                  panel.pushSubmenu(menuEntry.modelData)
                } else {
                  menuEntry.modelData.triggered()
                  panel.closeMenu()
                }
              }
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
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent

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
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
