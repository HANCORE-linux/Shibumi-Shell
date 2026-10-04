pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/lib/presentation" as Presentation

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
  readonly property string fontFamily: bar
    ? String(bar.fontFamily || Commons.Style.font.family)
    : Commons.Style.font.family
  readonly property bool hasMaterialSymbols:
    Qt.fontFamilies().indexOf("Material Symbols Rounded") !== -1
  readonly property bool panelLoaded: panelLoader.item !== null
  readonly property rect iconInk: {
    for (let item = updateIcon; item && item !== root; item = item.parent) {
      void(item.x); void(item.width)
    }
    return updateIcon.mapToItem(root, updateIcon.symbolInk)
  }

  Presentation.HostTokens { id: hostTokens; bar: root.bar }
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property bool countVisible: !vertical && updateCount > 0
  Presentation.BarInk { id: countPlacement; target: root }
  // Fit rounds its origin in logical pixels. Keep both the full expansion and
  // its centered half integral in logical AND physical pixels (Wayland /120).
  readonly property real countQuantum: {
    let numerator = Math.max(1, Math.round(countPlacement.dpr * 120))
    let denominator = 120
    while (denominator !== 0) {
      const remainder = numerator % denominator
      numerator = denominator
      denominator = remainder
    }
    return 240 / numerator
  }
  readonly property real countGap: Commons.Style.space(6)
  readonly property real leadingWidth: countVisible
    ? Math.ceil((Math.ceil(updateValue.implicitWidth) + countGap
        - ((button.implicitWidth - updateIcon.width) / 2 + updateIcon.inkLeft))
      / countQuantum) * countQuantum : 0
  TextMetrics {
    id: countInk
    text: updateValue.text
    font: Qt.font({ family: updateValue.font.family,
      pixelSize: updateValue.font.pixelSize * countPlacement.metricScale,
      weight: updateValue.font.weight, hintingPreference: Font.PreferNoHinting })
  }

  implicitWidth: button.implicitWidth + leadingWidth
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
      anchorItem: panelAnchor,
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

  Presentation.IconText {
    id: updateValue
    visible: root.countVisible
    barText: true
    x: {
      const iconLeft = root.iconInk.x
      const first = Math.floor((countPlacement.origin.x + iconLeft)
        * countPlacement.dpr + 1e-7)
      const end = Math.ceil((countInk.tightBoundingRect.x
        + countInk.tightBoundingRect.width) * countPlacement.dpr
        / countPlacement.metricScale)
      return (first - Math.round(root.countGap * countPlacement.dpr) - end)
        / countPlacement.dpr - countPlacement.origin.x
    }
    anchors.verticalCenter: parent.verticalCenter
    text: root.updateCount > 99 ? "99+" : String(root.updateCount)
    color: root.contentColor
    font.family: root.fontFamily
    font.pixelSize: root.tokens.labelSize
    renderType: Text.NativeRendering
  }

  // Keep the panel/caret on the original icon slot while input spans the count.
  Item {
    id: panelAnchor
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: button.implicitWidth
    height: parent.height
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
      anchors.right: parent.right
      anchors.rightMargin: button.implicitWidth - width
        - Math.round((button.implicitWidth - width) / 2)
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(20)
      height: Commons.Style.space(20)

      Presentation.BarGlyph {
        id: updateIcon
        optical: !root.bar || !root.bar.vertical
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
