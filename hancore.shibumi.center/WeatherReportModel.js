.pragma library
.import "WeatherLocationModel.js" as Location

// Parser budget only. Actual acquisition bytes are the reader's responsibility.
function object(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function decimal(value, minimum, maximum, integral) {
  if (typeof value !== "string" && typeof value !== "number") return null
  var text = String(value)
  if (text.length > 16 || !/^-?[0-9]+(?:\.[0-9]+)?$/.test(text)) return null
  var number = Number(text)
  if (!isFinite(number) || number < minimum || number > maximum
      || (integral && Math.floor(number) !== number)) return null
  return text
}

function labelList(value) {
  // Absent descriptive metadata stays optional; malformed supplied metadata
  // does not become an empty successful label.
  if (value === undefined || value === null) return ""
  if (!Array.isArray(value) || value.length > 1) return null
  if (value.length === 0) return ""
  if (!object(value[0])) return null
  return Location.boundedText(value[0].value, true)
}

function dateKey(value) {
  if (typeof value !== "string" || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value)) return null
  var year = Number(value.slice(0, 4))
  var month = Number(value.slice(5, 7))
  var day = Number(value.slice(8, 10))
  if (year < 1 || month < 1 || month > 12 || day < 1) return null
  var date = new Date(0)
  date.setUTCFullYear(year, month - 1, day)
  date.setUTCHours(0, 0, 0, 0)
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1
    && date.getUTCDate() === day ? value : null
}

function solarClock(value, kind) {
  if (value === undefined || value === null || value === ""
      || value === "No " + kind) return ""
  if (typeof value !== "string") return null
  var match = value.match(/^(0?[1-9]|1[0-2]):([0-5][0-9])\s*([AP]M)$/i)
  return match ? value : null
}

function forecast(day) {
  if (!object(day)) return null
  var date = dateKey(day.date)
  var minC = decimal(day.mintempC, -150, 150, false)
  var maxC = decimal(day.maxtempC, -150, 150, false)
  var minF = decimal(day.mintempF, -238, 302, false)
  var maxF = decimal(day.maxtempF, -238, 302, false)
  if (date === null || minC === null || maxC === null || minF === null || maxF === null
      || Number(minC) > Number(maxC) || Number(minF) > Number(maxF)) return null
  var hourly = day.hourly
  if (!Array.isArray(hourly) || hourly.length < 1 || hourly.length > 24) return null
  var rain = 0
  var code = ""
  var previous = -1
  for (var index = 0; index < hourly.length; index++) {
    var hour = hourly[index]
    if (!object(hour)) return null
    var time = decimal(hour.time, 0, 2359, true)
    var chance = decimal(hour.chanceofrain, 0, 100, false)
    var hourCode = decimal(hour.weatherCode, 0, 999, true)
    if (time === null || chance === null || hourCode === null) return null
    var clock = Number(time)
    if (clock % 100 >= 60) return null
    var minutes = Math.floor(clock / 100) * 60 + clock % 100
    if (minutes <= previous) return null
    previous = minutes
    rain = Math.max(rain, Number(chance))
    // Preserve V1's fifth-hour record (or first for a short forecast).
    if (index === (hourly.length > 4 ? 4 : 0)) code = hourCode
  }
  var sunrise = ""
  var sunset = ""
  if (day.astronomy !== undefined && day.astronomy !== null) {
    if (!Array.isArray(day.astronomy) || day.astronomy.length > 1) return null
    if (day.astronomy.length === 1) {
      var astronomy = day.astronomy[0]
      if (!object(astronomy)) return null
      sunrise = solarClock(astronomy.sunrise, "sunrise")
      sunset = solarClock(astronomy.sunset, "sunset")
      if (sunrise === null || sunset === null) return null
    }
  }
  return { date: date, minC: minC, maxC: maxC, minF: minF, maxF: maxF,
    code: code, rain: rain, sunrise: sunrise, sunset: sunset }
}

function parse(raw) {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 131072) return null
  try {
    var report = JSON.parse(raw)
    if (!object(report) || (report.error !== undefined && report.error !== false)
        || !Array.isArray(report.current_condition) || report.current_condition.length !== 1
        || !object(report.current_condition[0])
        || !Array.isArray(report.weather) || report.weather.length < 1 || report.weather.length > 3) return null
    var current = report.current_condition[0]
    var candidate = {
      code: decimal(current.weatherCode, 0, 999, true),
      tempC: decimal(current.temp_C, -150, 150, false),
      tempF: decimal(current.temp_F, -238, 302, false),
      feelsC: decimal(current.FeelsLikeC, -150, 150, false),
      feelsF: decimal(current.FeelsLikeF, -238, 302, false),
      humidity: decimal(current.humidity, 0, 100, false),
      windKmh: decimal(current.windspeedKmph, 0, 600, false),
      windMph: decimal(current.windspeedMiles, 0, 400, false),
      description: labelList(current.weatherDesc), place: "", country: "",
      sunrise: "", sunset: "", forecastDays: []
    }
    for (var field in candidate) if (candidate[field] === null) return null
    if (report.nearest_area !== undefined && report.nearest_area !== null) {
      if (!Array.isArray(report.nearest_area) || report.nearest_area.length > 1) return null
      if (report.nearest_area.length === 1) {
        if (!object(report.nearest_area[0])) return null
        candidate.place = labelList(report.nearest_area[0].areaName)
        candidate.country = labelList(report.nearest_area[0].country)
        if (candidate.place === null || candidate.country === null) return null
      }
    }
    for (var index = 0; index < report.weather.length; index++) {
      var day = forecast(report.weather[index])
      if (day === null) return null
      if (index > 0) {
        var previous = new Date(candidate.forecastDays[index - 1].date + "T00:00:00Z").getTime()
        var currentDate = new Date(day.date + "T00:00:00Z").getTime()
        if (currentDate - previous !== 86400000) return null
      }
      if (index === 0) {
        candidate.sunrise = day.sunrise
        candidate.sunset = day.sunset
      }
      candidate.forecastDays.push({ date: day.date, minC: day.minC, maxC: day.maxC,
        minF: day.minF, maxF: day.maxF, code: day.code, rain: day.rain })
    }
    return candidate
  } catch (_error) {
    return null
  }
}
