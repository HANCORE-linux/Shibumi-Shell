import QtQuick
import "../widgets/CenterLayout.js" as CenterLayout
import "../widgets/CalendarModel.js" as CalendarModel

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

    console.log("center model regression passed")
    Qt.exit(0)
  }
}
