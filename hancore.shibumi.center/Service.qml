pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/host" as ShibumiHost

Item {
  id: root

  readonly property var suiteHostShell: ShibumiHost.HostShell {
    pluginId: "hancore.shibumi.center"
    owner: root
  }

  property var shell: null
  property var manifest: null
  property bool runtimeWeatherEnabled: true

  readonly property var clock: clockState
  readonly property var weather: weatherState

  visible: false
  width: 0
  height: 0

  ClockService { id: clockState }

  WeatherService {
    id: weatherState
    enabled: root.runtimeWeatherEnabled
  }
}
