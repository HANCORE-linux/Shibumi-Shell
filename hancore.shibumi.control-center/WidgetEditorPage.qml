pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "WidgetCatalog.js" as WidgetCatalog

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool motionActive: false
  property string selectedWidgetGroup: "G4"
  property string selectedWidgetId: ""
  property string scopeMode: "shared"
  readonly property var selectedOption: {
    for (let index = 0; index < WidgetCatalog.AppearanceOptions.length; index++) {
      const option = WidgetCatalog.AppearanceOptions[index]
      if (option.group === selectedWidgetGroup) return option
    }
    return WidgetCatalog.AppearanceOptions[0]
  }
  readonly property bool ready: scopeRepeater.count === 3 && editor.ready

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  Row {
    width: parent.width
    height: Commons.Style.space(30)
    spacing: Commons.Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "‹  Widgets"
      color: backPointer.containsMouse ? root.accent : root.foreground
      opacity: backPointer.containsMouse ? 1 : 0.62
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale

      MouseArea {
        id: backPointer
        anchors.fill: parent
        anchors.margins: -Commons.Style.space(6)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.controller.showSettingsPage("plugins")
      }
    }

    Item {
      width: parent.width - x - widgetTitle.implicitWidth
      height: 1
    }

    Text {
      id: widgetTitle
      anchors.verticalCenter: parent.verticalCenter
      text: root.selectedOption.label
      color: root.foreground
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.subtitle * root.uiScale
      font.weight: Font.DemiBold
    }
  }

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "widget-editor:" + root.selectedWidgetGroup
    eyebrow: "WIDGET EDITOR"
    title: root.selectedOption.label
    description: "Shared settings affect V1 and V2. Layout-specific controls "
      + "stay separated."
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  Row {
    width: parent.width
    height: Commons.Style.space(34)
    spacing: Commons.Style.space(18)

    Repeater {
      id: scopeRepeater
      model: [
        { value: "shared", label: "BOTH · V1 + V2" },
        { value: "v1", label: "V1 ONLY" },
        { value: "v2", label: "V2 ONLY" }
      ]

      delegate: Item {
        id: scopeTab
        required property var modelData
        width: scopeLabel.implicitWidth
        height: parent.height

        Text {
          id: scopeLabel
          anchors.verticalCenter: parent.verticalCenter
          text: scopeTab.modelData.label
          color: root.foreground
          opacity: root.scopeMode === scopeTab.modelData.value ? 1 : 0.42
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.letterSpacing: 0.8
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 2
          visible: root.scopeMode === scopeTab.modelData.value
          color: root.accent
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.scopeMode = scopeTab.modelData.value
        }
      }
    }

    Item { width: parent.width - x; height: 1 }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: root.controller.dividerColor
  }

  WidgetAppearanceWorkbench {
    id: editor
    width: parent.width
    controller: root.controller
    widgetOptions: WidgetCatalog.AppearanceOptions
    uiScale: root.uiScale
    foreground: root.foreground
    accent: root.accent
    selectedWidgetGroup: root.selectedWidgetGroup
    selectedWidgetId: root.selectedWidgetId
    editorOnly: true
    scopeMode: root.scopeMode
  }
}
