import QtQuick
import "../widgets/CenterLayout.js" as CenterLayout
import "../widgets/CalendarModel.js" as CalendarModel
import "../hancore.shibumi.center/WeatherLocationModel.js" as WeatherLocationModel

QtObject {
  function fail(message) {
    console.error("center-model-regression:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    if (CenterLayout.nextStage(0, 500, 220, 160, true) !== 0
        || CenterLayout.nextStage(0, 190, 220, 160, true) !== 1
        || CenterLayout.nextStage(0, 180, 220, 160, true) !== 2
        || CenterLayout.nextStage(2, 500, 220, 160, true) !== 0
        || CenterLayout.nextStage(2, 80, 220, 160, false) !== 0) {
      fail("responsive stage hysteresis")
      return
    }

    const date = new Date(2026, 6, 16, 13, 5, 0)
    const cells = CalendarModel.cells(date, 0)
    if (CalendarModel.dateLabel(date) !== "Thu 16"
        || CalendarModel.monthName(date, 0) !== "JULY"
        || CalendarModel.year(date, 0) !== "2026"
        || cells.length !== 42) {
      fail("calendar labels/cell count")
      return
    }

    let todayCount = 0
    for (let i = 0; i < cells.length; i++) {
      if (cells[i].today) {
        todayCount++
        if (cells[i].day !== 16) {
          fail("wrong current day")
          return
        }
      }
    }
    if (todayCount !== 1 || CalendarModel.monthName(date, 6) !== "JANUARY"
        || CalendarModel.year(date, 6) !== "2027") {
      fail("calendar rollover")
      return
    }

    const locations = WeatherLocationModel.parseGeocodingResults(JSON.stringify({
      results: [
        { name: "Berlin", admin1: "Berlin", country: "Deutschland",
          feature_code: "PPLC", country_code: "DE",
          latitude: 52.52, longitude: 13.405 },
        { name: "Broken", country: "Nowhere" }
      ]
    }), "Ber")
    const norway = WeatherLocationModel.parseGeocodingResults(JSON.stringify({
      results: [
        { name: "Norwegen", admin1: "Niedersachsen", country: "Deutschland",
          feature_code: "PPL", country_code: "DE",
          latitude: 52.75983, longitude: 7.83682 },
        { name: "Norwegen", country: "Norwegen", feature_code: "PCLI",
          country_code: "NO", latitude: 62, longitude: 10 },
        { name: "Norwegen Airfield", country: "Deutschland",
          feature_code: "AIRF", latitude: 52.7, longitude: 7.8 }
      ]
    }), "Norwegen")
    const selected = WeatherLocationModel.locationCommit("Ber", locations, 0)
    const raw = WeatherLocationModel.locationCommit("  Malmö  ", [], 0)
    if (locations.length !== 1
        || locations[0].description !== "Berlin, Deutschland"
        || selected.name !== "Berlin" || selected.latitude !== 52.52
        || raw.name !== "Malmö" || raw.latitude !== null
        || norway.length !== 2 || norway[0].countryCode !== "NO"
        || norway[0].description !== "Country · NO"
        || norway[1].description !== "Niedersachsen, Deutschland"
        || WeatherLocationModel.isMeaningfulQuery("xxx")
        || !WeatherLocationModel.isMeaningfulQuery("Oslo")
        || WeatherLocationModel.parseGeocodingResults(
          JSON.stringify({ results: [{ name: "XXX", latitude: 1,
            longitude: 2, feature_code: "PPL" }] }), "xxx").length !== 0
        || WeatherLocationModel.parseGeocodingResults("invalid").length !== 0) {
      fail("weather location search model")
      return
    }

    console.log("center model regression passed")
    Qt.exit(0)
  }
}
