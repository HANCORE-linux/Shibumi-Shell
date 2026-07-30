pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  required property var pageOptions
  property string query: ""
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool motionActive: false
  readonly property string needle: query.trim().toLowerCase()
  readonly property var results: buildResults()
  readonly property bool ready: resultRepeater.count === results.length
  signal pageRequested(string pageId)
  signal widgetRequested(string groupId, string pluginId)

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(8)

  function matches(text) {
    return String(text || "").toLowerCase().indexOf(needle) >= 0
  }

  function buildResults() {
    void(controller.pluginEntries)
    const values = []
    if (needle === "") return values
    const pageKeywords = {
      main: "overview status position widgets plugins",
      bars: "bars shell omarchy shibumi switch continuity layout v1 v2 "
        + "split gap slots divider separator full fit dock notch",
      plugins: "widgets modules plugins add install enable",
      workspaces: "workspace workspaces count active marker style navigation",
      pickers: "picker pickers theme wallpaper screenshot video media browser",
      logo: "logo launcher identity wordmark icon",
      functions: "icons icon appearance widget color surface style",
      preferences: "advanced reload reset power lock suspend reboot shutdown"
    }
    for (let pageIndex = 0; pageIndex < pageOptions.length; pageIndex++) {
      const page = pageOptions[pageIndex]
      if (matches(page.label + " " + (pageKeywords[page.id] || ""))) {
        values.push({
          kind: "page",
          id: page.id === "main" ? "configure" : page.id,
          label: page.label,
          detail: "Control Center page",
          glyph: page.glyph
        })
      }
    }

    const entries = controller.pluginEntries || []
    for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      const entry = entries[entryIndex]
      if (entry.userToggleable !== true
          || !matches(entry.name + " " + entry.id + " "
            + entry.provider + " " + entry.compatibility))
        continue
      values.push({
        kind: "widget",
        id: entry.id,
        group: controller.shibumiWidgetGroup(entry.id),
        label: entry.name,
        detail: entry.provider + " · " + entry.compatibility,
        glyph: entry.glyph || "widgets"
      })
    }
    return values
  }

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "search:" + root.query.trim()
    eyebrow: "SEARCH"
    title: root.results.length + (root.results.length === 1
      ? " result" : " results")
    description: "Results for “" + root.query.trim() + "”"
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  Rectangle {
    width: parent.width
    height: 1
    color: root.controller.dividerColor
  }

  Repeater {
    id: resultRepeater
    model: root.results

    delegate: Rectangle {
      id: resultRow
      required property var modelData
      width: parent.width
      height: Commons.Style.space(48)
      radius: root.controller.controlRadius
      color: resultPointer.containsMouse
        ? root.controller.controlHoverFillColor : "transparent"

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: root.controller.dividerColor
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: Commons.Style.space(8)
        anchors.rightMargin: Commons.Style.space(8)
        spacing: Commons.Style.space(9)

        IconText {
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(22)
          text: resultRow.modelData.glyph
          color: root.foreground
          opacity: 0.72
          horizontalAlignment: Text.AlignHCenter
          font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
          fill: 0
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - x - resultArrow.width
          spacing: Commons.Style.space(2)

          Text {
            width: parent.width
            text: resultRow.modelData.label
            color: root.foreground
            elide: Text.ElideRight
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
            font.weight: Font.Medium
          }

          Text {
            width: parent.width
            text: resultRow.modelData.detail
            color: root.foreground
            opacity: 0.42
            elide: Text.ElideRight
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
          }
        }

        Text {
          id: resultArrow
          anchors.verticalCenter: parent.verticalCenter
          text: "›"
          color: root.accent
          opacity: resultPointer.containsMouse ? 1 : 0.46
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        }
      }

      MouseArea {
        id: resultPointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (resultRow.modelData.kind === "widget"
              && resultRow.modelData.group !== "") {
            root.widgetRequested(resultRow.modelData.group,
              resultRow.modelData.id)
          } else {
            root.pageRequested(resultRow.modelData.kind === "widget"
              ? "plugins" : resultRow.modelData.id)
          }
        }
      }
    }
  }

  Text {
    visible: root.results.length === 0
    width: parent.width
    topPadding: Commons.Style.space(28)
    text: "No matching settings or widgets."
    color: root.foreground
    opacity: 0.46
    horizontalAlignment: Text.AlignHCenter
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
  }
}
