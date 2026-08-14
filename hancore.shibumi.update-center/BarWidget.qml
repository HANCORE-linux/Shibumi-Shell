pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.update-center"
  manageIpc: false

  property url panelSource: Qt.resolvedUrl("UpdateCenterPanel.qml")
  property var registeredBar: null

  readonly property bool vertical: bar ? bar.vertical === true : false
  readonly property int barSize: bar ? Number(bar.barSize || 0) : 0
  readonly property var updateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.update-center") : null
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property var widgetPreferences: {
    const config = stateService && stateService.config
      ? stateService.config : ({})
    const widgets = config.widgets || ({})
    const group = widgets.G3 || ({})
    return group[moduleName] || ({})
  }
  readonly property bool packageBadgeEnabled:
    widgetPreferences.packageBadge !== false
  readonly property bool themeBadgeEnabled:
    widgetPreferences.themeBadge !== false
  readonly property int actualUpdateCount: updateService
    ? updateService.totalUpdateCount : 0
  readonly property int updateCount: updateService
    ? (packageBadgeEnabled ? updateService.packageCount : 0)
      + (themeBadgeEnabled ? updateService.themeCount : 0)
    : 0
  readonly property color foreground: bar
    ? bar.foreground : Commons.Color.foreground
  readonly property color activeColor: bar
    ? bar.urgent : Commons.Color.bar.active
  property color contentColor: activeColor
  property bool customToneActive: false
  property color badgeContrastColor: bar
    ? bar.background : Commons.Color.background
  readonly property color badgeFillColor: updateBadge.color
  readonly property color badgeTextColor: badgeText.color
  readonly property real badgeLayer: updateBadge.z
  readonly property string fontFamily: bar
    ? String(bar.fontFamily || Commons.Style.font.family)
    : Commons.Style.font.family
  readonly property bool hasMaterialSymbols:
    Qt.fontFamilies().indexOf("Material Symbols Rounded") !== -1
  readonly property bool panelLoaded: panelLoader.item !== null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function tooltipText() {
    if (!updateService) return "Update center is loading"
    if (updateService.packageRefreshing || updateService.themeRefreshing)
      return "Checking for updates"
    const parts = []
    if (updateService.packageCount > 0)
      parts.push(updateService.packageCount + " package"
        + (updateService.packageCount === 1 ? "" : "s"))
    if (updateService.themeCount > 0)
      parts.push(updateService.themeCount + " theme"
        + (updateService.themeCount === 1 ? "" : "s"))
    if (updateService.packageError !== ""
        || updateService.packageState.state === "unavailable"
        || updateService.packageState.state === "invalid")
      parts.push("package check unavailable")
    if (updateService.themeError !== ""
        || updateService.themeState.degraded === true)
      parts.push("theme check incomplete")
    else if (Number(updateService.themeState.review || 0) > 0)
      parts.push(updateService.themeState.review + " theme review")
    if (parts.length === 0
        && (updateService.packageState.state === "loading"
          || Number(updateService.themeState.checkedEpoch || 0) <= 0))
      return "Update status has not been checked"
    return parts.length === 0
      ? "System and user themes are up to date" : parts.join(" · ")
  }

  function triggerPress(mouseButton) {
    if (!updateService) return false
    if (mouseButton === Qt.RightButton) updateService.refreshAll()
    else toggle()
    return true
  }

  function syncPanelLoader() {
    if (!opened) {
      if (bar && bar.activePopout === root
          && typeof bar.releasePopout === "function")
        bar.releasePopout(root)
      if (bar && typeof bar.clearConnectedPanel === "function")
        bar.clearConnectedPanel(root)
    }
    panelLoader.source = ""
    if (!opened || !updateService) return
    panelLoader.setSource(panelSource, {
      anchorItem: button,
      bar: root.bar,
      open: true,
      ownerWidget: root,
      updateService: root.updateService,
      stateService: root.stateService
    })
  }

  function syncClickRegistration() {
    if (registeredBar
        && typeof registeredBar.unregisterClickTarget === "function")
      registeredBar.unregisterClickTarget(root)
    registeredBar = bar
    if (registeredBar
        && typeof registeredBar.registerClickTarget === "function")
      registeredBar.registerClickTarget(root)
  }

  // Queue construction to the next event-loop turn so the inherited widget
  // controller settles before the panel starts its one-way open lifecycle.
  onOpenedChanged: panelSyncTimer.restart()
  onUpdateServiceChanged: panelSyncTimer.restart()
  onBarChanged: syncClickRegistration()
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    if (registeredBar
        && typeof registeredBar.unregisterClickTarget === "function")
      registeredBar.unregisterClickTarget(root)
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Commons.Style.bar.statusSlot
    fixedHeight: root.vertical ? Commons.Style.bar.statusSlot : -1
    active: root.actualUpdateCount > 0
      || (root.updateService && root.updateService.needsAttention)
    activeColor: root.activeColor
    tooltipText: root.tooltipText()

    onPressed: function(mouseButton) { root.triggerPress(mouseButton) }

    Item {
      anchors.centerIn: parent
      width: Commons.Style.space(20)
      height: Commons.Style.space(20)

      Text {
        id: updateIcon
        anchors.centerIn: parent
        text: root.hasMaterialSymbols ? "\uF569" : "\uf466"
        color: root.contentColor
        font.family: root.hasMaterialSymbols
          ? "Material Symbols Rounded" : root.fontFamily
        font.pixelSize: root.hasMaterialSymbols
          ? Commons.Style.bar.iconFont + 1 : Commons.Style.bar.iconFont
        font.variableAxes: root.hasMaterialSymbols ? { "FILL": 0 } : ({})
        renderType: root.hasMaterialSymbols
          ? Text.QtRendering : Text.NativeRendering
      }

      Rectangle {
        id: updateBadge
        visible: root.updateCount > 0
        anchors.verticalCenter: updateIcon.verticalCenter
        anchors.verticalCenterOffset: -Commons.Style.space(6)
        anchors.horizontalCenter: updateIcon.horizontalCenter
        anchors.horizontalCenterOffset: Commons.Style.space(7)
        width: Math.max(Commons.Style.space(12),
          badgeText.implicitWidth + Commons.Style.space(6))
        height: Commons.Style.space(12)
        radius: height / 2
        color: root.contentColor
        border.width: 0
        border.color: "transparent"
        z: 10

        Text {
          id: badgeText
          anchors.centerIn: parent
          text: root.updateCount > 99 ? "99+" : String(root.updateCount)
          color: root.customToneActive
            ? root.badgeContrastColor : Commons.Color.background
          font.family: root.fontFamily
          font.pixelSize: Math.max(Commons.Style.space(7),
            Commons.Style.font.caption - 3)
          font.bold: true
        }
      }
    }
  }

  Timer {
    id: panelSyncTimer
    interval: 0
    repeat: false
    onTriggered: root.syncPanelLoader()
  }

  Loader { id: panelLoader }
}
