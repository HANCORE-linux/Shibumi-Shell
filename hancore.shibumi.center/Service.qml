pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/runtime" as SuiteRuntime

Item {
  id: root

  property var shell: null
  property var manifest: null
  SuiteRuntime.Provider {
    pluginId: "hancore.shibumi.center"
    implementationVersion: "0.1.1-beta.15"
    owner: root
    host: root.shell
    manifest: root.manifest
  }
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
