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
  property bool widgetDetailOpen: false
  property string resetConfirmationVariant: ""
  readonly property string activeResetVariant:
    controller.v2LayoutActive === true ? "v2" : "v1"
  readonly property bool resetActionVisible:
    motionActive && !widgetDetailOpen
      && String(controller.activeShell || "") === "shibumi"
  readonly property bool resetConfirmationPending:
    resetConfirmationVariant === activeResetVariant
  readonly property string resetVariantLabel:
    activeResetVariant.toUpperCase()
  readonly property string resetActionLabel: resetConfirmationPending
    ? "CONFIRM " + resetVariantLabel + " RESET"
    : "RESET " + resetVariantLabel + " DEFAULTS"
  readonly property color resetActionColor: controller.accentColor(
    resetConfirmationPending ? "color01" : "color03")
  readonly property var widgetOptions: WidgetCatalog.AppearanceOptions
  readonly property bool workbenchReady: appearanceWorkbench.ready
  readonly property int widgetOptionCount: widgetOptions.length
  readonly property int activeWidgetCount:
    appearanceWorkbench.visibleOptionCount
  readonly property int inactiveWidgetCount:
    appearanceWorkbench.inactiveOptionCount
  readonly property int widgetOverviewRowCount:
    appearanceWorkbench.overviewRowCount
  readonly property bool selectedWidgetActive:
    appearanceWorkbench.selectedActive
  readonly property string selectedWidgetMode:
    appearanceWorkbench.selectedDisplayMode
  readonly property var selectedWidgetModeOptions:
    appearanceWorkbench.selectedModeOptions
  readonly property bool selectedV1Appearance:
    appearanceWorkbench.selectedV1Appearance
  readonly property bool selectedV1CpuCompact:
    appearanceWorkbench.selectedV1CpuCompact
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

  onResetActionVisibleChanged: {
    if (!resetActionVisible) clearResetConfirmation()
  }
  onActiveResetVariantChanged: clearResetConfirmation()

  Timer {
    id: resetConfirmationTimer
    interval: 4200
    onTriggered: root.resetConfirmationVariant = ""
  }

  function clearResetConfirmation() {
    resetConfirmationTimer.stop()
    resetConfirmationVariant = ""
  }

  function requestAppearanceReset() {
    if (!resetActionVisible) return false
    const variant = activeResetVariant
    if (!resetConfirmationPending) {
      resetConfirmationVariant = variant
      resetConfirmationTimer.restart()
      return true
    }
    clearResetConfirmation()
    return typeof controller.resetAllGroupAppearances === "function"
      ? controller.resetAllGroupAppearances(variant) : false
  }

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
    const option = appearanceWorkbench.editableOption(groupId, pluginId)
    if (!option) return false
    selectedWidgetGroup = String(option.group || "")
    selectedWidgetId = String(option.id || "")
    if (typeof controller.trackWidgetDetails === "function")
      controller.trackWidgetDetails(selectedWidgetGroup, selectedWidgetId)
    widgetDetailOpen = true
    return true
  }

  function setWidgetEnabled(groupId, enabled) {
    const option = appearanceWorkbench.editableOption(groupId, "")
    return appearanceWorkbench.setWidgetActive(option, enabled === true)
  }

  function widgetUsesCustomAppearance(groupId) {
    const option = appearanceWorkbench.editableOption(groupId, "")
    return option
      ? appearanceWorkbench.widgetAppearanceChanged(option.group) : false
  }

  function showWidgetOverview() {
    if (typeof controller.clearWidgetDetails === "function")
      controller.clearWidgetDetails()
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
    description: "Style widget content and surfaces. Launcher identity stays under Logo."
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
    resetActionVisible: root.resetActionVisible
    resetActionLabel: root.resetActionLabel
    resetActionColor: root.resetActionColor
    selectedWidgetGroup: root.selectedWidgetGroup
    selectedWidgetId: root.selectedWidgetId
    detailOpen: root.widgetDetailOpen
    onSelectedWidgetGroupChanged:
      root.selectedWidgetGroup = selectedWidgetGroup
    onSelectedWidgetIdChanged:
      root.selectedWidgetId = selectedWidgetId
    onWidgetRequested: function(groupId, pluginId) {
      root.openWidgetDetails(groupId, pluginId)
    }
    onOverviewRequested: root.showWidgetOverview()
    onResetActionRequested: root.requestAppearanceReset()
  }
}
