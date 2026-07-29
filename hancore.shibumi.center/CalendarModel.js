.pragma library

var MonthNames = [
  "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
  "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
]

function validDate(value) {
  return value instanceof Date && !isNaN(value.getTime())
}

function normalizedDate(value) {
  return validDate(value) ? value : new Date()
}

function monthDate(value, offset) {
  var date = normalizedDate(value)
  return new Date(date.getFullYear(), date.getMonth() + Number(offset || 0), 1)
}

function monthName(value, offset) {
  return MonthNames[monthDate(value, offset).getMonth()]
}

function year(value, offset) {
  return String(monthDate(value, offset).getFullYear())
}

function dateLabel(value) {
  var date = normalizedDate(value)
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  return days[date.getDay()] + " " + date.getDate()
}

function cells(value, offset) {
  var today = normalizedDate(value)
  var first = monthDate(today, offset)
  var currentYear = first.getFullYear()
  var currentMonth = first.getMonth()
  var lastDay = new Date(currentYear, currentMonth + 1, 0).getDate()
  var startDay = (first.getDay() + 6) % 7
  var isCurrentMonth = currentYear === today.getFullYear()
    && currentMonth === today.getMonth()
  var result = []

  for (var i = 0; i < startDay; i++)
    result.push({ day: 0, today: false })
  for (var day = 1; day <= lastDay; day++)
    result.push({ day: day, today: isCurrentMonth && day === today.getDate() })
  while (result.length < 42) result.push({ day: 0, today: false })
  return result
}
