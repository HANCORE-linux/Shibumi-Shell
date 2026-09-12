import QtQuick
import Quickshell
import "center" as Center

ShellRoot {
  id: root

  property int phase: 0
  property int attempts: 0
  property bool teardownArmed: false
  property double destroyedAt: 0

  Component {
    id: weatherComponent
    Center.WeatherService { enabled: true }
  }

  Loader {
    id: weatherLoader
    active: true
    sourceComponent: weatherComponent
  }

  Connections {
    target: weatherLoader.item
    function onRefreshingChanged() {
      if (!root.teardownArmed || !weatherLoader.item
          || weatherLoader.item.refreshing) return
      weatherLoader.active = false
      root.destroyedAt = Date.now()
    }
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.attempts++
      if (root.attempts >= 150) {
        console.error("weather teardown smoke: timed out in phase " + root.phase)
        Qt.exit(1)
        throw new Error("weather teardown smoke timed out")
      }
      if (root.phase === 0) {
        if (!weatherLoader.item || !weatherLoader.item.refreshing) return
        root.teardownArmed = true
        weatherLoader.item.refresh(true)
        root.phase = 1
        return
      }
      if (root.phase === 1 && !weatherLoader.item
          && Date.now() - root.destroyedAt >= 400) {
        stop()
        console.log("weather pending refresh teardown passed")
        Qt.exit(0)
      }
    }
  }
}
