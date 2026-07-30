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
  property bool widgetDetailOpen: false
  readonly property var widgetOptions: WidgetCatalog.AppearanceOptions
  readonly property bool workbenchReady: appearanceWorkbench.ready
  readonly property int widgetOptionCount: widgetOptions.length
  readonly property int activeWidgetCount:
    appearanceWorkbench.visibleOptionCount
  readonly property string selectedWidgetMode:
    appearanceWorkbench.selectedDisplayMode
  readonly property string selectedWidgetSurface:
    appearanceWorkbench.selectedSurfaceMode
  readonly property string selectedWidgetTone:
    appearanceWorkbench.selectedContentTone
  readonly property real selectedWidgetOpacity:
    appearanceWorkbench.selectedSurfaceOpacity
  readonly property real selectedWidgetOutlineWidth:
    appearanceWorkbench.selectedOutlineWidth
  readonly property bool allWidgetModesReady: widgetOptions.every(
    function(option) {
      return option.modes.join(",") === "full,icon,text"
    })
  readonly property bool ready: appearanceWorkbench.ready

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  function cycleSelectedWidgetMode() {
    return appearanceWorkbench.cycleWidgetMode()
  }

  function cycleSelectedWidgetOpacity() {
    return appearanceWorkbench.cycleWidgetOpacity()
  }

  function cycleSelectedWidgetSurface() {
    return appearanceWorkbench.cycleWidgetSurface()
  }

  function openWidgetDetails(groupId, pluginId) {
    const group = String(groupId || "")
    if (!appearanceWorkbench.isActiveWidget(group)) return false
    selectedWidgetGroup = group
    appearanceWorkbench.selectedWidgetId = String(pluginId || "")
    widgetDetailOpen = true
    return true
  }

  function showWidgetOverview() {
    widgetDetailOpen = false
    return true
  }

  PageHeaderHero {
    visible: !root.widgetDetailOpen
    controller: root.controller
    active: root.motionActive
    pageKey: "appearance"
    eyebrow: "WIDGET VISUALS"
    title: "Icons"
    description: "Tune each widget's icon, label, surface, and color."
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    preferredHeight: Commons.Style.space(80)
    previewWidth: Commons.Style.space(150)
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
    detailOpen: root.widgetDetailOpen
    onSelectedWidgetGroupChanged:
      root.selectedWidgetGroup = selectedWidgetGroup
    onWidgetRequested: function(groupId, pluginId) {
      root.openWidgetDetails(groupId, pluginId)
    }
    onOverviewRequested: root.showWidgetOverview()
  }
}
