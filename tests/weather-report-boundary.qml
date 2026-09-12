import QtQuick
import Quickshell
import "center" as Center
import "center/WeatherReportModel.js" as Model

ShellRoot {
  id: root
  Center.WeatherService { id: weather; enabled: false }

  function check(value, message) {
    if (value) return
    console.error("weather report boundary:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  function base() {
    return {
      current_condition: [{ weatherCode: "113", temp_C: "21", temp_F: "70",
        FeelsLikeC: "20", FeelsLikeF: "68", weatherDesc: [{value:"Clear"}],
        humidity: "50", windspeedKmph: "10", windspeedMiles: "6" }],
      nearest_area: [{areaName:[{value:"Testville"}],country:[{value:"Testland"}]}],
      weather: [{date:"2026-07-20",mintempC:"14",maxtempC:"24",mintempF:"57",maxtempF:"75",
        astronomy:[{sunrise:"06:00 AM",sunset:"09:00 PM"}],
        hourly:[{time:"1200",weatherCode:"113",chanceofrain:"0"}]}]
    }
  }
  function parse(value) { return Model.parse(JSON.stringify(value)) }
  function state() {
    return JSON.stringify([weather.icon, weather.tempC, weather.tempF, weather.feelsC,
      weather.feelsF, weather.description, weather.place, weather.country,
      weather.humidity, weather.windKmh, weather.windMph, weather.forecastDays, weather.loaded])
  }

  Timer { interval: 1; running: true; onTriggered: root.run() }

  function run() {
    check(!weather.enabled && !weather.refreshing && !weather.loaded,
      "disabled service started acquisition")
    var valid = base()
    var good = parse(valid)
    check(good !== null && good.tempC === "21" && good.place === "Testville"
      && good.forecastDays[0].rain === 0, "valid report")
    check(Object.keys(good.forecastDays[0]).sort().join(",")
      === "code,date,maxC,maxF,minC,minF,rain", "day projection")
    check(good.forecastDays[0].date === "2026-07-20"
      && good.forecastDays[0].minC === "14" && good.forecastDays[0].maxC === "24"
      && good.forecastDays[0].minF === "57" && good.forecastDays[0].maxF === "75"
      && good.forecastDays[0].code === "113", "forecast field projection")
    for (var length of [131071,131072,131073]) {
      var raw = JSON.stringify(valid)
      raw += " ".repeat(length - raw.length)
      check((Model.parse(raw) !== null) === (length <= 131072), "character budget " + length)
    }
    for (var length of [131071,131072,131073]) {
      var value = base()
      value.padding = ""
      var size = length - JSON.stringify(value).length
      value.padding = "🌧".repeat(Math.floor(size / 2)) + (size % 2 ? "x" : "")
      var raw = JSON.stringify(value)
      check(raw.length === length, "Unicode fixture budget")
      check((Model.parse(raw) !== null) === (length <= 131072), "UTF16 budget " + length)
    }
    for (var count of [0,1,3,4]) {
      var value = base()
      value.weather = []
      for (var i = 0; i < count; i++) {
        var day = base().weather[0]
        day.date = "2026-07-" + (20 + i)
        value.weather.push(day)
      }
      check((parse(value) !== null) === (count > 0 && count <= 3), "day budget " + count)
    }
    for (var count of [0,1,23,24,25]) {
      var value = base()
      value.weather[0].hourly = []
      for (var i = 0; i < count; i++)
        value.weather[0].hourly.push({time:String(i),weatherCode:"113",chanceofrain:String(i)})
      check((parse(value) !== null) === (count > 0 && count <= 24), "hour budget " + count)
    }
    for (var length of [159,160,161]) {
      var value = base()
      value.current_condition[0].weatherDesc[0].value = "x".repeat(length)
      check((parse(value) !== null) === (length <= 160), "label budget " + length)
    }
    for (var text of ["<i>Clear</i>", "bad\u0000", "bad\u061c", "bad\u200e", "bad\u200f",
                      "bad\u202e", "bad\ud800", "bad\udc00"]) {
      for (var field of ["description", "place", "country"]) {
        var value = base()
        if (field === "description") value.current_condition[0].weatherDesc[0].value = text
        if (field === "place") value.nearest_area[0].areaName[0].value = text
        if (field === "country") value.nearest_area[0].country[0].value = text
        check(parse(value) === null, "unsafe label " + field)
      }
    }
    var value = base()
    value.current_condition[0].weatherDesc[0].value = "St. John's & Malmö 東京 🌧"
    check(parse(value).description === "St. John's & Malmö 東京 🌧", "Unicode and punctuation")
    value.nearest_area = null
    value.current_condition[0].weatherDesc = null
    value.weather[0].astronomy = [{sunrise:"No sunrise",sunset:"No sunset"}]
    check(parse(value) !== null && parse(value).description === "", "optional labels/polar astronomy")
    value.nearest_area = []
    value.current_condition[0].weatherDesc = []
    value.weather[0].hourly[0].time = "0900"
    value.current_condition[0].temp_C = "021"
    check(parse(value) !== null && parse(value).tempC === "021", "empty metadata/padded decimal")
    for (var field of ["temp_C", "temp_F", "FeelsLikeC", "FeelsLikeF", "humidity", "windspeedKmph", "windspeedMiles", "weatherCode"]) {
      for (var bad of [null, true, [], {}, "12junk", "NaN", "Infinity", "1e2", "", " "]) {
        var value = base()
        value.current_condition[0][field] = bad
        check(parse(value) === null, "numeric schema " + field)
      }
      var value = base()
      value.current_condition[0][field] = 0
      check(parse(value) !== null, "numeric zero " + field)
    }
    for (var entry of [["temp_C",-150,150],["temp_F",-238,302],["humidity",0,100],
                      ["windspeedKmph",0,600],["windspeedMiles",0,400],["weatherCode",0,999]]) {
      for (var number of [entry[1]-1,entry[1],entry[2],entry[2]+1]) {
        var value = base()
        value.current_condition[0][entry[0]] = String(number)
        check((parse(value) !== null) === (number >= entry[1] && number <= entry[2]),
          "numeric range " + entry[0] + " " + number)
      }
    }
    for (var field of ["mintempC", "maxtempC", "mintempF", "maxtempF"]) {
      for (var bad of [null, true, [], {}, "12junk", "NaN", "Infinity", "1e2", "", " "]) {
        var value = base()
        value.weather[0][field] = bad
        check(parse(value) === null, "forecast numeric schema " + field)
      }
    }
    for (var units of [["C",-150,150],["F",-238,302]]) {
      for (var field of ["min", "max"]) {
        for (var number of [units[1]-1,units[1],units[2],units[2]+1]) {
          var value = base()
          value.weather[0]["mintemp" + units[0]] = String(field === "min" ? number : units[1])
          value.weather[0]["maxtemp" + units[0]] = String(field === "max" ? number : units[2])
          check((parse(value) !== null) === (number >= units[1] && number <= units[2]),
            "forecast numeric range " + field + units[0] + " " + number)
        }
      }
      var value = base()
      value.weather[0]["mintemp" + units[0]] = "21"
      value.weather[0]["maxtemp" + units[0]] = "20"
      check(parse(value) === null, "forecast min exceeds max " + units[0])
    }
    for (var field of ["time", "weatherCode", "chanceofrain"]) {
      var invalid = [null, true, [], {}, "12junk", "NaN", "Infinity", "1e2", "", " ", "-1"]
      if (field === "time") invalid = invalid.concat(["2360","2400","1260","1200.5"])
      if (field === "weatherCode") invalid = invalid.concat(["1000","113.5"])
      if (field === "chanceofrain") invalid.push("101")
      for (var bad of invalid) {
        var value = base()
        value.weather[0].hourly[0][field] = bad
        check(parse(value) === null, "hour field schema " + field)
      }
    }
    for (var pair of [["time","0000"],["time","2359"],["weatherCode","0"],
                     ["weatherCode","999"],["chanceofrain","0"],["chanceofrain","100"]]) {
      var value = base()
      value.weather[0].hourly[0][pair[0]] = pair[1]
      check(parse(value) !== null, "hour field boundary " + pair[0])
    }
    for (var time of ["1200","1100"]) {
      var value = base()
      value.weather[0].hourly.push({time:time,weatherCode:"113",chanceofrain:"0"})
      check(parse(value) === null, "unordered hours")
    }
    for (var date of ["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-01", "2026-12-00", "2026-7-20"]) {
      var value = base()
      value.weather[0].date = date
      check(parse(value) === null, "invalid date")
    }
    var value = base()
    value.weather[0].date = "2024-02-29"
    check(parse(value) !== null, "leap day")
    var value = base()
    value.weather[0].date = "2026-12-31"
    var tomorrow = base().weather[0]
    tomorrow.date = "2027-01-01"
    value.weather.push(tomorrow)
    check(parse(value) !== null, "year rollover")
    tomorrow.date = "2027-01-02"
    check(parse(value) === null, "nonconsecutive forecast dates")
    for (var malformed of [null,[],{},"hours",[{time:"2360",weatherCode:"113",chanceofrain:"0"}],
                          [{time:"1200",weatherCode:"113",chanceofrain:"101"}]]) {
      var value = base()
      value.weather[0].hourly = malformed
      check(parse(value) === null, "hour schema")
    }
    for (var clock of ["13:00 AM", "00:00 PM", "12:60 PM", "garbage", 0]) {
      var value = base()
      value.weather[0].astronomy[0].sunrise = clock
      check(parse(value) === null, "solar clock")
    }
    var value = base()
    value.weather[0].hourly = []
    for (var i = 0; i < 8; i++)
      value.weather[0].hourly.push({time:String(i*300),weatherCode:i === 4 ? "116" : "113",chanceofrain:i === 3 ? "72" : "0"})
    check(parse(value).forecastDays[0].code === "116" && parse(value).forecastDays[0].rain === 72,
      "representative code/rain maximum")
    value.weather[0].hourly = [{time:"0",weatherCode:"113",chanceofrain:"0"},
      {time:"300",weatherCode:"116",chanceofrain:"10"}]
    check(parse(value).forecastDays[0].code === "113", "short forecast representative changed")
    for (var raw of ["", "invalid", "null", "[]", "{}", "42"])
      check(Model.parse(raw) === null, "root schema")
    var value = base()
    value.error = true
    check(parse(value) === null, "error response")
    value = base()
    value.current_condition = {0:value.current_condition[0],length:1}
    check(parse(value) === null, "array-shaped object")

    // Actual public Service parser, with acquisition disabled before creation.
    check(weather.parseReport(JSON.stringify(base())) && weather.loaded, "service good publication")
    var before = state()
    var bad = base()
    bad.current_condition[0].temp_C = "99"
    bad.weather.push(null)
    check(!weather.parseReport(JSON.stringify(bad)) && weather.unavailable,
      "service invalid result")
    check(state() === before, "invalid report partially replaced publication")
    var fresh = base()
    fresh.current_condition[0].temp_C = "22"
    check(weather.parseReport(JSON.stringify(fresh)) && !weather.unavailable && weather.tempC === "22",
      "service recovered publication")
    console.log("weather report boundary passed; schema and parser publication, not acquisition/lifecycle")
    Qt.exit(0)
  }
}
