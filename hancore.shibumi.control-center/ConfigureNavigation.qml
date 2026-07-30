pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  required property var pageOptions
  required property string currentPage
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool barGroupOpen: true
  property bool lookGroupOpen: true
  property bool systemGroupOpen: false
  readonly property bool ready: true
  signal selected(string pageId)

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(2)

  function hasPage(pageId) {
    return pageOptions.some(function(page) { return page.id === pageId })
  }

  function activeIn(ids) {
    const page = currentPage === "widget-editor" ? "plugins" : currentPage
    return ids.indexOf(page) >= 0
  }

  NavRow {
    visible: root.hasPage("main")
    pageId: "main"
    label: "Overview"
    glyph: "radio_button_checked"
  }

  GroupLabel {
    label: "ON THIS BAR"
    expanded: root.barGroupOpen
    visible: root.hasPage("plugins") || root.hasPage("splits")
    onToggled: root.barGroupOpen = !root.barGroupOpen
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(2)
    visible: root.barGroupOpen || root.activeIn(["plugins", "splits"])

    NavRow {
      visible: root.hasPage("plugins")
      pageId: "plugins"
      label: "Widgets"
      glyph: "widgets"
      indented: true
    }

    NavRow {
      visible: root.hasPage("splits")
      pageId: "splits"
      label: root.controller.v2LayoutActive ? "V2 Layout" : "V1 Layout"
      glyph: "view_week"
      indented: true
    }
  }

  GroupLabel {
    label: "LOOK & FEEL"
    expanded: root.lookGroupOpen
    visible: root.hasPage("functions")
    onToggled: root.lookGroupOpen = !root.lookGroupOpen
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(2)
    visible: root.lookGroupOpen || root.activeIn(["functions"])

    NavRow {
      visible: root.hasPage("functions")
      pageId: "functions"
      label: "Icons"
      glyph: "brush"
      indented: true
    }
  }

  GroupLabel {
    label: "SYSTEM"
    expanded: root.systemGroupOpen
    visible: root.hasPage("bars") || root.hasPage("preferences")
    onToggled: root.systemGroupOpen = !root.systemGroupOpen
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(2)
    visible: root.systemGroupOpen
      || root.activeIn(["bars", "preferences"])

    NavRow {
      visible: root.hasPage("bars")
      pageId: "bars"
      label: "Bars"
      glyph: "align_vertical_center"
      indented: true
    }

    NavRow {
      visible: root.hasPage("preferences")
      pageId: "preferences"
      label: "Advanced"
      glyph: "settings"
      indented: true
    }
  }

  Item { width: 1; height: Commons.Style.space(8) }

  Rectangle {
    width: parent.width
    height: 1
    color: root.controller.dividerColor
  }

  Text {
    width: parent.width
    topPadding: Commons.Style.space(6)
    text: root.controller.pluginsScanning
      ? "Refreshing plugin index …"
      : root.controller.availablePluginCount + " Plugins · Quattro"
    color: root.foreground
    opacity: 0.38
    wrapMode: Text.WordWrap
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  component GroupLabel: Item {
    id: groupLabel
    required property string label
    property bool expanded: true
    signal toggled()

    width: root.width
    height: Commons.Style.space(28)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: groupLabel.label
      color: root.foreground
      opacity: 0.36
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.DemiBold
      font.letterSpacing: 1.2
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: groupLabel.expanded ? "⌄" : "›"
      color: root.foreground
      opacity: 0.36
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: groupLabel.toggled()
    }
  }

  component NavRow: Rectangle {
    id: navRow
    required property string pageId
    required property string label
    required property string glyph
    property bool indented: false
    readonly property bool active:
      root.currentPage === navRow.pageId
      || (root.currentPage === "widget-editor"
        && navRow.pageId === "plugins")

    width: root.width
    height: Commons.Style.space(34)
    radius: root.controller.controlRadius
    color: navRow.active
      ? root.controller.buttonFillColor
      : navPointer.containsMouse
        ? root.controller.controlHoverFillColor : "transparent"

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 2
      visible: navRow.active
      color: root.accent
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(navRow.indented ? 10 : 4)
      spacing: Commons.Style.space(8)

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(18)
        text: navRow.glyph
        color: root.foreground
        opacity: navRow.active ? 1 : 0.58
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
        font.weight: Font.Medium
        fill: 0
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x
        text: navRow.label
        color: root.foreground
        opacity: navRow.active ? 1 : 0.62
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.subtitle * root.uiScale
        font.weight: navRow.active ? Font.Medium : Font.Normal
      }
    }

    MouseArea {
      id: navPointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.selected(navRow.pageId)
    }
  }
}
