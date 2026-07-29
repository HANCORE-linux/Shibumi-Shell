pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property string icon: "·"
  property string place: ""
  property string tempC: ""
  property string tempF: ""
  property string feelsC: ""
  property string feelsF: ""
  property string description: ""
  property string country: ""
  property string humidity: ""
  property string windKmh: ""
  property string windMph: ""
  property var forecastDays: []
  property var configuredLocation: ({
    name: "",
    latitude: null,
    longitude: null
  })
  property bool loaded: false
  property bool unavailable: false
  property bool refreshPending: false
  readonly property bool refreshing: weatherProc.running
  readonly property string locationQuery: {
    const latitude = parseFloat(String(configuredLocation.latitude))
    const longitude = parseFloat(String(configuredLocation.longitude))
    if (!isNaN(latitude) && !isNaN(longitude))
      return latitude + "," + longitude
    const name = String(configuredLocation.name || "").trim()
    return name ? encodeURIComponent(name) : ""
  }
  readonly property string requestUrl: "https://wttr.in/"
    + locationQuery + "?format=j1"

  function parseLocation(raw) {
    try {
      const value = JSON.parse(String(raw || ""))
      const latitude = parseFloat(value && value.latitude)
      const longitude = parseFloat(value && value.longitude)
      configuredLocation = {
        name: value && typeof value.name === "string"
          ? value.name.trim() : "",
        latitude: !isNaN(latitude) ? latitude : null,
        longitude: !isNaN(longitude) ? longitude : null
      }
    } catch (_error) {
      configuredLocation = { name: "", latitude: null, longitude: null }
    }
  }

  function chanceOfRain(day) {
    const hourly = day && day.hourly ? day.hourly : []
    let maximum = 0
    for (let index = 0; index < hourly.length; index++) {
      const chance = parseFloat(hourly[index].chanceofrain)
      if (!isNaN(chance) && chance > maximum) maximum = chance
    }
    return maximum
  }

  function forecastCode(day) {
    const hourly = day && day.hourly ? day.hourly : []
    const representative = hourly.length > 4
      ? hourly[4] : hourly.length > 0 ? hourly[0] : null
    return representative ? String(representative.weatherCode || "") : ""
  }

  function minutesForClock(value) {
    const match = String(value || "").match(/^(\d{1,2}):(\d{2})\s*([AP]M)$/i)
    if (!match) return -1
    let hours = parseInt(match[1]) || 0
    const minutes = parseInt(match[2]) || 0
    const suffix = match[3].toUpperCase()
    if (suffix === "PM" && hours !== 12) hours += 12
    if (suffix === "AM" && hours === 12) hours = 0
    return hours * 60 + minutes
  }

  function isNight(sunrise, sunset) {
    const rise = minutesForClock(sunrise)
    const set = minutesForClock(sunset)
    if (rise < 0 || set < 0) return false
    const now = new Date()
    const minutes = now.getHours() * 60 + now.getMinutes()
    return minutes < rise || minutes >= set
  }

  function glyphForCode(code, night) {
    const value = parseInt(code) || 0
    if (value === 113) return night ? "\ue32b" : "\ue30d"
    if (value === 116) return night ? "\ue32e" : "\ue302"
    if (value === 119 || value === 122) return "\ue33d"
    if (value === 143 || value === 248 || value === 260) return "\ue313"
    if ([176, 263, 266, 293, 296, 353].indexOf(value) >= 0)
      return night ? "\ue333" : "\ue308"
    if ([179, 227, 230, 323, 326, 368].indexOf(value) >= 0)
      return night ? "\ue327" : "\ue30a"
    if ([182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377]
        .indexOf(value) >= 0) return "\ue3ad"
    if ([200, 386, 389, 392, 395].indexOf(value) >= 0) return "\ue31d"
    if ([299, 302, 305, 308, 356, 359].indexOf(value) >= 0) return "\ue318"
    if ([329, 332, 335, 338, 371].indexOf(value) >= 0) return "\ue31a"
    return "\ue33d"
  }

  function refresh(force) {
    if (!enabled) return
    if (weatherProc.running) {
      if (force === true) refreshPending = true
      return
    }
    weatherProc.running = true
  }

  function parseReport(raw) {
    const text = String(raw || "").trim()
    if (!text) {
      unavailable = true
      return
    }

    try {
      const report = JSON.parse(text)
      const current = report.current_condition && report.current_condition[0]
        ? report.current_condition[0] : null
      const area = report.nearest_area && report.nearest_area[0]
        ? report.nearest_area[0] : null
      const astronomy = report.weather && report.weather[0]
        && report.weather[0].astronomy && report.weather[0].astronomy[0]
        ? report.weather[0].astronomy[0] : null
      if (!current) {
        unavailable = true
        return
      }

      icon = glyphForCode(current.weatherCode,
        isNight(astronomy ? astronomy.sunrise : "", astronomy ? astronomy.sunset : ""))
      tempC = String(current.temp_C || "")
      tempF = String(current.temp_F || "")
      feelsC = String(current.FeelsLikeC || "")
      feelsF = String(current.FeelsLikeF || "")
      description = current.weatherDesc && current.weatherDesc[0]
        ? String(current.weatherDesc[0].value || "") : ""
      place = area && area.areaName && area.areaName[0]
        ? String(area.areaName[0].value || "") : ""
      country = area && area.country && area.country[0]
        ? String(area.country[0].value || "") : ""
      humidity = String(current.humidity || "")
      windKmh = String(current.windspeedKmph || "")
      windMph = String(current.windspeedMiles || "")

      const days = []
      const reportDays = report.weather || []
      for (let index = 0; index < reportDays.length && index < 3; index++) {
        const day = reportDays[index]
        days.push({
          date: String(day.date || ""),
          minC: String(day.mintempC || ""),
          maxC: String(day.maxtempC || ""),
          minF: String(day.mintempF || ""),
          maxF: String(day.maxtempF || ""),
          code: forecastCode(day),
          rain: chanceOfRain(day)
        })
      }
      forecastDays = days
      loaded = true
      unavailable = false
    } catch (_error) {
      unavailable = true
    }
  }

  Process {
    id: weatherProc
    command: ["curl", "-fsS", "--max-time", "5", root.requestUrl]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseReport(text)
    }
    onRunningChanged: {
      if (running || !root.refreshPending) return
      root.refreshPending = false
      Qt.callLater(function() { root.refresh(false) })
    }
  }

  FileView {
    id: locationFile
    path: Quickshell.env("HOME")
      + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseLocation(text())
    onLoadFailed: root.parseLocation("")
  }

  Timer {
    interval: 1500
    running: root.enabled
    onTriggered: locationFile.reload()
  }

  onLocationQueryChanged: refresh(true)

  Timer {
    interval: 15 * 60 * 1000
    running: root.enabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }
}
