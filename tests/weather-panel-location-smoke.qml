pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "center" as Center

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0

  function fail(message) {
    console.error("weather-panel-location-smoke:", message)
    Qt.exit(1)
  }

  Item {
    id: anchorItem
    width: 20
    height: 20
  }

  QtObject {
    id: fakeBar
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color background: "#181818"
    property color urgent: "#d75f5f"
    property int barSize: 35
    property bool vertical: false
    property var activePopout: null
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    function switchPanelFrom(_owner, _direction) { return true }
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
  }

  Item {
    id: fakeOwner
    property bool panelOpen: true
    property bool useImperial: false
    property string temperature: "21"
    property string unitSuffix: "°C"
    function close() { panelOpen = false }
    function switchPanel(_direction) { return true }
    function toggleUnit() { return true }
  }

  QtObject {
    id: fakeWeather
    property bool loaded: true
    property bool unavailable: false
    property bool refreshing: false
    property string place: "Testville"
    property string description: "Clear"
    property string feelsC: "20"
    property string feelsF: "68"
    property string humidity: "50"
    property string windKmh: "10"
    property string windMph: "6"
    property var configuredLocation: ({
      name: "Hamburg",
      latitude: 53.55,
      longitude: 10.0
    })
    property var forecastDays: [{
      date: "2026-08-05", minC: "14", maxC: "24",
      minF: "57", maxF: "75", code: "113", rain: 0
    }]
    property int refreshCount: 0
    property int reloadCount: 0
    function refresh(_force) { refreshCount++ }
    function reloadLocation() { reloadCount++ }
    function glyphForCode(_code, _night) { return "sunny" }
  }

  Center.WeatherPanel {
    id: weatherPanel
    anchorItem: anchorItem
    bar: fakeBar
    ownerWidget: fakeOwner
    weatherService: fakeWeather
  }

  Component.onCompleted: {
    if (weatherPanel.displayLocation !== "Hamburg")
      return fail("configured location does not override detected place")
    weatherPanel.startEditingLocation()
  }

  Timer {
    interval: 30
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      if (root.ticks > 150)
        return root.fail("timed out in phase " + root.phase)

      if (root.phase === 0) {
        if (!weatherPanel.editingLocation) return
        if (!weatherPanel.locationInputReady
            || weatherPanel.locationEditorText !== "Hamburg")
          return root.fail("location editor initial value/readiness")
        if (!weatherPanel.dismissLocationEditorAt(
              weatherPanel.contentWidth - 1,
              weatherPanel.contentHeight - 1)
            || weatherPanel.editingLocation)
          return root.fail("location editor click-away dismissal")
        weatherPanel.startEditingLocation()
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (!weatherPanel.editingLocation) return
        weatherPanel.locationEditorText = "xxx"
        weatherPanel.requestGeocode()
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (weatherPanel.locationError !== "No matching location") return
        if (weatherPanel.locationSuggestions.length !== 0
            || weatherPanel.locationCanCommit)
          return root.fail("unknown location remains saveable")
        if (weatherPanel.commitLocation())
          return root.fail("unknown location commit was accepted")
        if (fakeWeather.reloadCount !== 0 || fakeWeather.refreshCount !== 0)
          return root.fail("unknown location was persisted")
        weatherPanel.locationEditorText = "Ber"
        weatherPanel.requestGeocode()
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (weatherPanel.locationSuggestions.length !== 2) return
        const first = weatherPanel.locationSuggestions[0]
        if (first.name !== "Berlin"
            || first.description !== "Berlin, Deutschland")
          return root.fail("geocoding suggestions")
        if (!weatherPanel.locationCanCommit)
          return root.fail("matching location cannot be committed")
        if (weatherPanel.contentHeight <= 0
            || weatherPanel.contentHeight > 520)
          return root.fail("location editor panel geometry")
        if (!weatherPanel.commitLocation())
          return root.fail("matching location commit was rejected")
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (weatherPanel.savingLocation || weatherPanel.editingLocation) return
        if (fakeWeather.reloadCount !== 1 || fakeWeather.refreshCount !== 1)
          return root.fail("saved location does not reload weather")
        weatherPanel.startEditingLocation()
        weatherPanel.clearLocation()
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (weatherPanel.savingLocation || weatherPanel.editingLocation) return
        if (fakeWeather.reloadCount !== 2 || fakeWeather.refreshCount !== 2)
          return root.fail("automatic location does not reload weather")
        stop()
        console.log("weather panel location smoke passed")
        Qt.exit(0)
      }
    }
  }
}
