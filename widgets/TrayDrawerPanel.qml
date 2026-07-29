pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var trayBackend
  readonly property var drawerItems: trayBackend
    && Array.isArray(trayBackend.drawerItems) ? trayBackend.drawerItems : []
  readonly property int attentionCount: {
    let count = 0
    for (let index = 0; index < drawerItems.length; index++) {
      if (itemNeedsAttention(drawerItems[index])) count++
    }
    return count
  }

  owner: ownerWidget
  open: ownerWidget.trayDrawerOpen
  focusTarget: keyCatcher
  // V1 contract: 328px outer card with 304px usable row width.
  gap: 8
  padding: 12
  contentWidth: fittedContentWidth(328)
  contentHeight: fittedContentHeight(contentColumn.implicitHeight)

  function closePanel() { ownerWidget.closeTrayDrawer() }

  function itemName(item) {
    if (!item) return "Tray App"
    const title = String(item.title || "").trim()
    if (title !== "") return title
    const tooltipTitle = String(item.tooltipTitle || "").trim()
    if (tooltipTitle !== "") return tooltipTitle
    let fallback = String(item.id || "").trim()
    const slash = fallback.lastIndexOf("/")
    if (slash >= 0 && slash < fallback.length - 1)
      fallback = fallback.substring(slash + 1)
    fallback = fallback.replace(/^org\.(kde|ayatana|freedesktop)\./i, "")
      .replace(/[_-]+/g, " ")
    return fallback !== "" ? fallback : "Tray App"
  }

  function itemDescription(item, displayName) {
    if (!item) return ""
    const description = String(item.tooltipDescription || "").trim()
    const tooltipTitle = String(item.tooltipTitle || "").trim()
    const name = String(displayName || "").trim().toLowerCase()
    if (description !== "" && description.toLowerCase() !== name)
      return description
    if (tooltipTitle !== "" && tooltipTitle.toLowerCase() !== name)
      return tooltipTitle
    return ""
  }

  function itemNeedsAttention(item) {
    return !!item && item.status === Status.NeedsAttention
  }

  function itemHasMenu(item) {
    return !!item && (item.hasMenu === true || item.menu)
  }

  function togglePin(item) {
    const id = item ? String(item.id || "") : ""
    if (!id || !trayBackend || typeof trayBackend.togglePin !== "function")
      return false
    trayBackend.togglePin(id)
    return true
  }

  function openAppMenu(item, anchor, mouse) {
    if (!item || !anchor) return false
    if (ownerWidget && typeof ownerWidget.openTrayAppMenu === "function"
        && ownerWidget.openTrayAppMenu(item, anchor)) return true
    if (!trayBackend || typeof trayBackend.openTrayMenu !== "function")
      return false
    trayBackend.openTrayMenu(item, anchor, mouse)
    return true
  }

  function activateApp(item) {
    if (!item || typeof item.activate !== "function") return false
    closePanel()
    Qt.callLater(function() { item.activate() })
    return true
  }

  onDrawerItemsChanged: if (open && drawerItems.length === 0) closePanel()

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.closePanel()

      Column {
        id: contentColumn
        width: parent.width
        spacing: 8

      Item {
        width: parent.width
        height: 24

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Tray Apps"
          color: panel.controlForeground
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 13
          font.letterSpacing: 2
          font.weight: Font.Medium
          renderType: Text.NativeRendering
        }

        Text {
          anchors.right: panel.shellStyle === "shibumi"
            ? closeText.left : closeAction.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: panel.drawerItems.length
            + (panel.drawerItems.length === 1 ? " APP" : " APPS")
            + (panel.attentionCount > 0
              ? "  \u00b7  " + panel.attentionCount + " ATTENTION" : "")
          color: panel.attentionCount > 0
            ? panel.controlAccent : panel.controlMutedHigh
          font.family: panel.bar ? panel.bar.fontFamily
            : Commons.Style.font.family
          font.pixelSize: 10
          renderType: Text.NativeRendering
        }

        Text {
          id: closeText
          anchors.right: parent.right
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
            onClicked: panel.closePanel()
          }
        }

        IconAction {
          id: closeAction
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: panel.shellStyle !== "shibumi"
          icon: "close"
          tooltip: "Close"
          onClicked: panel.closePanel()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Item {
        width: parent.width
        height: Math.min(trayRows.implicitHeight, 320)

        Flickable {
          anchors.fill: parent
          contentHeight: trayRows.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: trayRows
            width: parent.width
            spacing: 6

            Repeater {
              model: panel.drawerItems

              delegate: Item {
                id: appRow
                required property var modelData

                readonly property string appName: panel.itemName(modelData)
                readonly property string appDescription:
                  panel.itemDescription(modelData, appName)
                readonly property bool needsAttention:
                  panel.itemNeedsAttention(modelData)
                readonly property bool hasMenu: panel.itemHasMenu(modelData)
                readonly property string statusDescription: needsAttention
                  ? "\u26a0 "
                    + (appDescription !== "" ? appDescription : "Needs attention")
                  : appDescription
                readonly property real cellWidth: 96

                width: trayRows.width
                height: 28

                Rectangle {
                  id: appButton
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: appRow.cellWidth
                  height: parent.height
                  radius: panel.controlRadius
                  color: activateMouse.containsMouse
                    ? panel.controlHoverFillColor : panel.controlFillColor
                  border.color: activateMouse.containsMouse
                    ? panel.controlHoverBorderColor : panel.controlBorderColor
                  border.width: panel.controlBorderWidth

                  Image {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    source: String(appRow.modelData.icon || "")
                    sourceSize.width: 16
                    sourceSize.height: 16
                    width: 16
                    height: 16
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                  }

                  Text {
                    anchors.left: appIcon.right
                    anchors.leftMargin: 6
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: (appRow.needsAttention ? "\u26a0 " : "") + appRow.appName
                    color: appRow.needsAttention || activateMouse.containsMouse
                      ? panel.controlAccent : panel.controlForeground
                    font.family: panel.bar ? panel.bar.fontFamily
                      : Commons.Style.font.family
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                  }

                  ShibumiPanelToolTip {
                    panel: panel
                    visible: activateMouse.containsMouse
                    text: appRow.statusDescription !== ""
                      ? appRow.appName + "\n" + appRow.statusDescription
                      : appRow.appName
                  }

                  MouseArea {
                    id: activateMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                      if (appRow.modelData.onlyMenu === true && appRow.hasMenu)
                        panel.openAppMenu(appRow.modelData, appButton, mouse)
                      else
                        panel.activateApp(appRow.modelData)
                    }
                  }
                }

                Rectangle {
                  id: pinButton
                  anchors.left: appButton.right
                  anchors.leftMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  width: appRow.cellWidth
                  height: parent.height
                  radius: panel.controlRadius
                  color: pinMouse.containsMouse
                    ? panel.controlHoverFillColor : panel.controlFillColor
                  border.color: pinMouse.containsMouse
                    ? panel.controlHoverBorderColor : panel.controlBorderColor
                  border.width: panel.controlBorderWidth

                  Text {
                    anchors.centerIn: parent
                    text: "Pin"
                    color: pinMouse.containsMouse
                      ? panel.controlAccent : panel.controlForeground
                    font.family: panel.bar ? panel.bar.fontFamily
                      : Commons.Style.font.family
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                  }

                  MouseArea {
                    id: pinMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.togglePin(appRow.modelData)
                  }
                }

                Rectangle {
                  id: menuButton
                  anchors.left: pinButton.right
                  anchors.leftMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  width: appRow.cellWidth
                  height: parent.height
                  radius: panel.controlRadius
                  color: !appRow.hasMenu ? "transparent"
                    : menuMouse.containsMouse
                      ? panel.controlHoverFillColor : panel.controlFillColor
                  border.color: !appRow.hasMenu
                    ? Commons.Util.alpha(panel.controlForeground, 0.10)
                    : menuMouse.containsMouse
                      ? panel.controlHoverBorderColor : panel.controlBorderColor
                  border.width: panel.controlBorderWidth
                  opacity: appRow.hasMenu ? 1 : 0.42

                  Text {
                    anchors.centerIn: parent
                    text: appRow.hasMenu ? "AppMenu" : "No Menu"
                    color: menuMouse.containsMouse && appRow.hasMenu
                      ? panel.controlAccent : panel.controlForeground
                    font.family: panel.bar ? panel.bar.fontFamily
                      : Commons.Style.font.family
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                  }

                  MouseArea {
                    id: menuMouse
                    anchors.fill: parent
                    enabled: appRow.hasMenu
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: function(mouse) {
                      panel.openAppMenu(appRow.modelData, menuButton, mouse)
                    }
                  }
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
