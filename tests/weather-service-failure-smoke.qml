import QtQuick
import Quickshell
import "center" as Center

ShellRoot {
  id: root

  property int attempts: 0

  Center.WeatherService {
    id: weather
    enabled: true
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.attempts++
      if (weather.unavailable) {
        if (weather.loaded || weather.tempC !== ""
            || weather.place !== "" || weather.forecastDays.length !== 0) {
          console.error("weather failure smoke: failed transfer published data")
          Qt.exit(1)
          throw new Error("weather failure smoke: failed transfer published data")
        }
        stop()
        console.log("weather failed transfer stayed unpublished")
        Qt.exit(0)
        return
      }
      if (root.attempts >= 100) {
        console.error("weather failure smoke: service did not reject transfer")
        Qt.exit(1)
        throw new Error("weather failure smoke: service did not reject transfer")
      }
    }
  }
}
