pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.CursorSurface {
  id: root

  required property var rowData
  required property int rowIndex
  required property bool selected
  required property bool showIcon
  required property var controller
  property string selectionStyle: "default"
  property real uiScale: 1
  property real controlRadius: Commons.Style.cornerRadius
  readonly property bool hasIcon: showIcon && String(rowData.icon || "") !== ""

  hasCursor: selected && selectionStyle === "default"
  foreground: Commons.Color.menu.text
  accent: Commons.Color.menu.selectedText
  radius: controlRadius

  Text {
    id: iconText
    visible: root.hasIcon
    anchors.left: parent.left
    anchors.leftMargin: Commons.Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    width: Commons.Style.space(24) * root.uiScale
    text: String(root.rowData.icon || "")
    color: root.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
    font.family: String(root.rowData.iconFont || "")
      || Commons.Style.font.menuFamily
    font.pixelSize: Commons.Style.font.icon * root.uiScale
    horizontalAlignment: Text.AlignHCenter
  }

  Column {
    anchors.left: root.hasIcon ? iconText.right : parent.left
    anchors.leftMargin: Commons.Style.spacing.sm
    anchors.right: trail.left
    anchors.rightMargin: Commons.Style.spacing.xs
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Text {
      width: parent.width
      text: String(root.rowData.label || "")
      color: root.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.body * root.uiScale
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: String(root.rowData.detail || "") !== ""
        && root.controller.query !== ""
      text: String(root.rowData.detail || "")
      color: Commons.Color.menu.text
      opacity: 0.52
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      elide: Text.ElideRight
    }
  }

  Row {
    id: trail
    anchors.right: parent.right
    anchors.rightMargin: Commons.Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Commons.Style.spacing.xs

    Text {
      visible: root.rowData.checkedState === true
      text: "✓"
      color: root.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.body * root.uiScale
    }

    Text {
      visible: root.rowData.kind === "menu" || root.rowData.kind === "link"
      text: "›"
      color: root.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
      opacity: 0.55
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.heading * root.uiScale
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.controller.selectIndex(root.rowIndex)
    onClicked: {
      root.controller.selectIndex(root.rowIndex)
      root.controller.activateIndex(root.rowIndex)
    }
  }
}
