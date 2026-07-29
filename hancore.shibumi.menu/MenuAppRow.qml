pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons as Commons
import qs.Ui as Ui

Ui.CursorSurface {
  id: root

  required property var rowData
  required property int rowIndex
  required property bool selected
  required property bool editMode
  required property bool showIcon
  required property var controller
  property string selectionStyle: "default"
  property real uiScale: 1
  property real controlRadius: Commons.Style.cornerRadius

  hasCursor: selected && selectionStyle === "default"
  foreground: Commons.Color.menu.text
  accent: Commons.Color.menu.selectedText
  radius: controlRadius

  function iconSource(value) {
    const icon = String(value || "")
    if (!icon) return Quickshell.iconPath("application-x-executable", true)
    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    if (icon.charAt(0) === "/") return Commons.Util.fileUrl(icon)
    const themed = Quickshell.iconPath(icon, true)
    return themed || Quickshell.iconPath("application-x-executable", true)
  }

  Item {
    id: iconSlot
    visible: root.showIcon
    anchors.left: parent.left
    anchors.leftMargin: Commons.Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    width: visible ? Commons.Style.space(24) * root.uiScale : 0
    height: parent.height

    IconImage {
      anchors.centerIn: parent
      implicitSize: Commons.Style.space(20) * root.uiScale
      width: implicitSize
      height: implicitSize
      source: root.iconSource(root.rowData.icon)
      asynchronous: true
      mipmap: true
      opacity: root.rowData.hidden ? 0.35 : 1
    }
  }

  Column {
    anchors.left: iconSlot.visible ? iconSlot.right : parent.left
    anchors.leftMargin: Commons.Style.spacing.sm
    anchors.right: editActions.visible ? editActions.left : favoriteMark.left
    anchors.rightMargin: Commons.Style.spacing.xs
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Text {
      width: parent.width
      text: String(root.rowData.label || "")
      color: Commons.Color.menu.text
      opacity: root.rowData.hidden ? 0.42 : 1
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.body * root.uiScale
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: String(root.rowData.detail || "") !== ""
      text: String(root.rowData.detail || "")
      color: Commons.Color.menu.text
      opacity: root.rowData.hidden ? 0.3 : 0.5
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      elide: Text.ElideRight
    }
  }

  Text {
    id: favoriteMark
    visible: !root.editMode && root.rowData.favorite === true
    anchors.right: parent.right
    anchors.rightMargin: Commons.Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    text: "★"
    color: Commons.Color.menu.selectedText
    opacity: 0.72
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  Row {
    id: editActions
    visible: root.editMode
    anchors.right: parent.right
    anchors.rightMargin: Commons.Style.spacing.xs
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Ui.PanelActionButton {
      size: Math.max(Commons.Style.space(18), Commons.Style.space(22) * root.uiScale)
      iconText: root.rowData.favorite ? "★" : "☆"
      fontSize: Commons.Style.font.body * root.uiScale
      foreground: root.rowData.favorite
        ? Commons.Color.menu.selectedText : Commons.Color.menu.text
      tooltipText: root.rowData.favorite ? "Remove favorite" : "Add favorite"
      radius: root.controlRadius
      onClicked: root.controller.toggleFavorite(root.rowData.id)
    }

    Ui.PanelActionButton {
      size: Math.max(Commons.Style.space(18), Commons.Style.space(22) * root.uiScale)
      iconText: root.rowData.hidden ? "×" : "●"
      fontSize: Commons.Style.font.body * root.uiScale
      foreground: root.rowData.hidden
        ? Commons.Color.urgent : Commons.Color.menu.text
      tooltipText: root.rowData.hidden ? "Show app" : "Hide app"
      radius: root.controlRadius
      onClicked: root.controller.toggleHidden(root.rowData.id)
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: !root.editMode
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.controller.selectIndex(root.rowIndex)
    onClicked: {
      root.controller.selectIndex(root.rowIndex)
      root.controller.activateIndex(root.rowIndex)
    }
  }
}
