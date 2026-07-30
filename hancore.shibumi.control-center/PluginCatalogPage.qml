pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool motionActive: false
  property string selectedProvider: "All"
  signal editRequested(string groupId, string pluginId)
  readonly property var widgetEntries: (controller.pluginEntries || [])
    .filter(function(entry) {
      return entry.userToggleable === true
        && (root.selectedProvider === "All"
          || entry.provider === root.selectedProvider)
    })
  readonly property bool ready: true

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(12)

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "widgets"
    eyebrow: "WIDGET REGISTRY"
    title: "Widgets"
    description: "Your module bay · Shibumi and Omarchy Quattro"
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  Rectangle {
    width: parent.width
    height: 1
    color: root.controller.dividerColor
  }

  ProviderFilter {
    width: parent.width
    controller: root.controller
    selectedProvider: root.selectedProvider
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onSelected: function(provider) { root.selectedProvider = provider }
  }

  Text {
    visible: root.widgetEntries.length === 0
    width: parent.width
    text: root.controller.pluginsScanning
      ? "Scanning modules …" : "No widget modules discovered."
    color: root.foreground
    opacity: 0.62
    horizontalAlignment: Text.AlignHCenter
    font.family: Commons.Style.font.menuFamily
    font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
  }

  Flow {
    id: moduleDeck
    width: parent.width
    spacing: Commons.Style.space(8)

    Repeater {
      model: root.widgetEntries

      delegate: WidgetModuleTile {
        id: moduleTile
        required property var modelData
        width: (moduleDeck.width - moduleDeck.spacing) / 2
        controller: root.controller
        glyph: modelData.glyph
        label: modelData.name
        provider: modelData.provider
        relationship: modelData.replacementLabel || ""
        inserted: modelData.installedInBar === true
        editable: modelData.compatibility === "Native"
          && root.controller.shibumiWidgetGroup(modelData.id) !== ""
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onToggled: root.controller.setPluginEnabled(
          modelData.id, !inserted)
        onEditRequested: root.editRequested(
          root.controller.shibumiWidgetGroup(modelData.id), modelData.id)
      }
    }

    Rectangle {
      id: addModule
      width: (moduleDeck.width - moduleDeck.spacing) / 2
      height: Commons.Style.space(66)
      radius: root.controller.controlRadius
      color: addPointer.containsMouse
        ? root.controller.controlHoverFillColor : "transparent"
      border.width: 1
      border.color: root.controller.controlBorderColor

      Column {
        anchors.centerIn: parent
        spacing: Commons.Style.space(3)

        IconText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "add"
          color: root.accent
          font.pixelSize: Commons.Style.space(20) * root.uiScale
          font.weight: Font.Medium
          fill: 0
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Add module"
          color: root.foreground
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
          font.weight: Font.Medium
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Catalog"
          color: root.foreground
          opacity: 0.42
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
        }
      }

      MouseArea {
        id: addPointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.controller.openWidgetPicker()
      }
    }
  }
}
