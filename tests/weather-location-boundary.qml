import QtQuick
import "../hancore.shibumi.center/WeatherLocationModel.js" as Model

QtObject {
  function check(value, message) {
    if (value) return
    console.error("weather-location-boundary:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  function row(name, latitude, longitude) {
    return {name: name, latitude: latitude, longitude: longitude,
      country: "Deutschland", country_code: "DE", feature_code: "PPL"}
  }
  function parse(rows) { return Model.parseGeocodingResults(JSON.stringify({results: rows}), "Town") }
  Component.onCompleted: {
    for (var count = 4; count <= 6; count++) {
      var rows = []
      for (var i = 0; i < count; i++) rows.push(row("Town " + i, 52, 13))
      check(parse(rows).length === (count <= 5 ? count : 0), "result count boundary " + count)
    }
    var badCoordinates = [null, "52", true, {}, [], 90.0001, -90.0001]
    for (var c = 0; c < badCoordinates.length; c++)
      check(parse([row("Town", badCoordinates[c], 13)]).length === 0, "latitude rejected " + c)
    for (var lat of [-90, 0, 90])
      for (var lon of [-180, 0, 180]) check(parse([row("Town", lat, lon)]).length === 1, "coordinate edges")
    check(parse([row("Town", 1, 180.0001)]).length === 0
      && parse([row("Town", 1, -180.0001)]).length === 0, "longitude bounds")
    check(Model.parseGeocodingResults('{"results":{"0":{"name":"Town","latitude":1,"longitude":2},"length":1}}').length === 0,
      "array-shaped object accepted")
    check(Model.parseGeocodingResults(JSON.stringify({error: true, results: [row("Town", 1, 2)]})).length === 0,
      "error response published suggestions")
    var valid = JSON.stringify({results: [row("Town", 1, 2)]})
    for (var size = 65535; size <= 65537; size++)
      check(Model.parseGeocodingResults(valid + " ".repeat(size - valid.length)).length === (size <= 65536 ? 1 : 0),
        "parser character budget " + size)
    for (var length = 159; length <= 161; length++) {
      var name = "Town" + "a".repeat(length - 4)
      check(Model.isMeaningfulQuery(name) === (length <= 160), "query length " + length)
      check(parse([row(name, 1, 2)]).length === (length <= 160 ? 1 : 0), "name length " + length)
    }
    var badText = ["Town\u0000", "Town\n", "<img src='fixture.invalid'>", "Town\u202e", "Town\ud800", "Town\udc00", "Town\u061c", "Town\u200e", "Town\u200f"]
    for (var t = 0; t < badText.length; t++) {
      check(parse([row(badText[t], 1, 2)]).length === 0, "unsafe name " + t)
      check(!Model.isMeaningfulQuery(badText[t]), "unsafe query " + t)
      check(Model.locationCommit(badText[t], [], 0) === null, "unsafe raw name " + t)
      for (var metadata of ["country", "admin1"]) {
        var badMetadata = row("Town", 1, 2)
        badMetadata[metadata] = badText[t]
        check(parse([badMetadata]).length === 0, "unsafe metadata " + metadata + t)
      }
    }
    check(parse([row("Malmö 東京 🌧", 1, 2)]).length === 1, "valid Unicode rejected")
    var optional = row("St. John's & Town", 1, 2)
    optional.country = null
    optional.country_code = null
    optional.admin1 = null
    check(parse([optional]).length === 1, "optional null metadata or punctuation rejected")
    for (var field of ["country", "admin1"]) {
      for (var limit = 159; limit <= 161; limit++) {
        var bounded = row("Town", 1, 2)
        bounded[field] = "Region" + "a".repeat(limit - 6)
        check(parse([bounded]).length === (limit <= 160 ? 1 : 0), "optional text bound " + field + limit)
      }
    }
    var broken = row("Broken", "1", 2)
    check(parse([row("Town", 1, 2), broken]).length === 1, "valid sibling was discarded")
    check(Model.locationCommit("Town", [broken], 0) === null, "invalid chosen coordinate persisted")
    check(Model.locationCommit("<Town>", [], 0) === null, "unsafe raw fallback")
    for (var missing of [null, false, 0])
      check(Model.locationCommit("Town", [missing], 0) === null, "invalid selection became raw-name fallback")
    var raw = Model.locationCommit("  Malmö  ", [], 0)
    check(raw.name === "Malmö" && raw.latitude === null && raw.longitude === null, "raw-name fallback changed")
    var selected = Model.locationCommit("Town", parse([row("Town", 1, 2)]), 0)
    check(selected.name === "Town" && selected.latitude === 1 && selected.longitude === 2, "validated selection changed")
    check(Object.keys(selected).sort().join(",") === "latitude,longitude,name", "commit projection leaked metadata")
    console.log("weather location boundary passed; parser budget is not transfer byte bound")
    Qt.exit(0)
  }
}
