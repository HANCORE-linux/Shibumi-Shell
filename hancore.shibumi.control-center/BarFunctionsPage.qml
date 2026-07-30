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
  readonly property var widgetOptions: WidgetCatalog.AppearanceOptions
  readonly property bool workbenchReady: appearanceWorkbench.ready
  readonly property int widgetOptionCount: widgetOptions.length
  readonly property bool allWidgetModesReady: widgetOptions.every(
    function(option) {
      return option.modes.join(",") === "full,icon,text"
    })
  readonly property bool ready: appearanceWorkbench.ready

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  function setWidgetMode(group, mode) {
    controller.setGroupSetting(group, "displayMode", String(mode))
    controller.setGroupSetting(group, "compact",
      group === "G9" ? mode === "full" : mode === "icon")
  }

  function setWidgetSurface(group, mode) {
    const value = String(mode)
    controller.setGroupSetting(group, "colorMode", value)
    controller.setGroupSetting(group, "widgetBorder",
      value === "border" || value === "both")
  }

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "appearance"
    eyebrow: "WIDGET VISUALS"
    title: "Appearance"
    description: "Choose a widget, then adjust only that widget's presentation."
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  WidgetAppearanceWorkbench {
    id: appearanceWorkbench
    width: parent.width
    controller: root.controller
    widgetOptions: root.widgetOptions
    uiScale: root.uiScale
    foreground: root.foreground
    accent: root.accent
    selectedWidgetGroup: root.selectedWidgetGroup
    onSelectedWidgetGroupChanged:
      root.selectedWidgetGroup = selectedWidgetGroup
  }
}
