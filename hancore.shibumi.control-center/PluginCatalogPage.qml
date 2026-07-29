pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property string selectedProvider: "All"
  readonly property var widgetEntries: (controller.pluginEntries || [])
    .filter(function(entry) {
      return entry.barWidget === true
        && (root.selectedProvider === "All"
          || entry.provider === root.selectedProvider)
    })
  readonly property bool ready: true

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(12)

  Text {
    text: "WIDGET REGISTRY"
    color: root.accent
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Bold
    font.letterSpacing: 1.8
  }

  Text {
    text: "browse widgets"
    color: root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.space(24) * root.uiScale
    font.weight: Font.Bold
  }

  Text {
    width: parent.width
    text: "Your module bay · Shibumi and Omarchy Quattro"
    color: root.foreground
    opacity: 0.58
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
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
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onToggled: root.controller.setPluginEnabled(
          modelData.id, !inserted)
      }
    }

    Rectangle {
      id: addModule
      width: (moduleDeck.width - moduleDeck.spacing) / 2
      height: Commons.Style.space(78)
      radius: 0
      color: addPointer.containsMouse
        ? root.controller.controlHoverFillColor : "transparent"
      border.width: 1
      border.color: root.controller.controlBorderColor

      Column {
        anchors.centerIn: parent
        spacing: Commons.Style.space(5)

        IconText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "add"
          color: root.accent
          font.pixelSize: Commons.Style.space(24) * root.uiScale
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
