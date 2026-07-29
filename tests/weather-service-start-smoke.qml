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
      if (weather.loaded) {
        if (weather.icon === "·" || weather.tempC !== "21"
            || weather.place !== "Testville") {
          console.error("weather start smoke: invalid initial report")
          Qt.exit(1)
          return
        }
        stop()
        console.log("weather service start smoke passed")
        Qt.exit(0)
        return
      }
      if (root.attempts >= 100) {
        console.error("weather start smoke: service did not load without interaction")
        Qt.exit(1)
      }
    }
  }
}
