pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
  id: root

  moduleName: "omarchy.weather"
  required property var weatherService
  property url panelSource: Qt.resolvedUrl("WeatherPanel.qml")
  property bool panelOpen: false

  readonly property var panelItem: panelLoader.item
  readonly property bool panelLoaded: panelItem !== null
  readonly property bool opened: panelOpen
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property string unitSetting: String(setting("unit", "") || "").toLowerCase()
  readonly property bool useImperial: unitSetting === "imperial"
    || (unitSetting !== "metric" && /^en[_-]US/.test(Qt.locale().name))
  readonly property string temperature: weatherService
    ? (useImperial ? weatherService.tempF : weatherService.tempC) : ""
  readonly property string unitSuffix: useImperial ? "°F" : "°C"
  readonly property real iconSlotWidth: 20
  readonly property string tooltipText: {
    if (!weatherService) return "Weather unavailable"
    if (!weatherService.loaded)
      return weatherService.unavailable ? "Weather offline" : "Loading weather"
    const details = (weatherService.place ? weatherService.place + " · " : "")
      + temperature + unitSuffix
      + (weatherService.description ? " / " + weatherService.description : "")
    return weatherService.unavailable ? "Weather stale · " + details : details
  }

  implicitWidth: bar && bar.vertical ? bar.barSize : iconSlotWidth
  implicitHeight: bar ? bar.barSize : Commons.Style.space(35)

  function refresh() {
    if (weatherService) weatherService.refresh(true)
  }

  function syncPanelLoader() {
    panelLoader.source = ""
    if (!panelOpen || !weatherService || !String(panelSource)) return
    panelLoader.setSource(panelSource, {
      ownerWidget: root,
      weatherService: root.weatherService,
      anchorItem: root,
      bar: root.bar
    })
  }

  function open() {
    if (!weatherService || !String(panelSource)) return false
    panelOpen = true
    return true
  }

  function close() {
    panelOpen = false
  }

  function toggle() {
    if (panelOpen) close()
    else return open()
    return true
  }

  function togglePanel() {
    return toggle()
  }

  function toggleUnit() {
    return stateService && typeof stateService.setWidgetSetting === "function"
      ? stateService.setWidgetSetting("G8", moduleName, "unit",
          useImperial ? "metric" : "imperial") : false
  }

  function switchPanel(direction) {
    return bar && typeof bar.switchPanelFrom === "function"
      ? bar.switchPanelFrom(root, direction) : false
  }

  function ownsPanelWidget(item) {
    return item === root || item === panelItem
  }

  onPanelOpenChanged: syncPanelLoader()
  onPanelSourceChanged: if (panelOpen) syncPanelLoader()
  onWeatherServiceChanged: if (panelOpen) syncPanelLoader()
  onBarChanged: if (panelOpen) syncPanelLoader()

  Text {
    id: weatherIcon
    anchors.centerIn: parent
    text: root.weatherService && root.weatherService.loaded
      ? root.weatherService.icon
      : root.weatherService && root.weatherService.unavailable ? "?" : "·"
    color: root.weatherService && root.weatherService.unavailable
      && !root.weatherService.loaded && root.bar
      ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.4)
      : root.bar ? root.bar.foreground : Commons.Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: 14
    renderType: Text.NativeRendering
  }

  Ui.WidgetButton {
    anchors.fill: parent
    bar: root.bar
    text: " "
    keepSpace: true
    horizontalMargin: 0
    verticalPadding: 0
    tooltipText: root.tooltipText
    onPressed: function(button) {
      if (button === Qt.RightButton || button === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }

  Loader { id: panelLoader }
}
