pragma ComponentBehavior: Bound

import QtQuick

Item {
  property var shell: null
  property var manifest: null
  property bool running: false
  property string phase: ""
  property string downloadMbps: ""
  property string uploadMbps: ""
  property string error: ""
  property int runCount: 0
  property int closeCount: 0

  function runSpeedTest() {
    runCount++
    running = true
    phase = "down"
    downloadMbps = "42.5"
  }

  function close() {
    closeCount++
    running = false
    phase = ""
  }
}
