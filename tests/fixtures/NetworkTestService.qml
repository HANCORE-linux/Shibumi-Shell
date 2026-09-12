pragma ComponentBehavior: Bound

import QtQuick

QtObject {
  id: root

  property bool ready: true
  property bool backendAvailable: true
  property string kind: "wifi"
  property string label: "Test Network"
  property int signalStrength: 73
  property real downloadRate: 0
  property real uploadRate: 0
  property bool scanning: false
  property bool busy: false
  property bool speedTestReady: true
  property bool speedTestRunning: false
  property int speedRunCount: 0
  property var sessionOwners: []
  property int beginCount: 0
  property int beginFailuresRemaining: 0
  property int endCount: 0
  property int refreshCount: 0
  property bool lastScanWifi: false
  property int viewLoadCount: 0
  property var trafficOwners: []
  property int trafficBeginCount: 0
  property int trafficFailuresRemaining: 0
  property int trafficEndCount: 0
  readonly property int sessionCount: sessionOwners.length
  readonly property int trafficConsumerCount: trafficOwners.length

  function beginSession(owner) {
    if (!owner) return false
    if (sessionOwners.indexOf(owner) >= 0) return true
    if (beginFailuresRemaining > 0) {
      beginFailuresRemaining--
      return false
    }
    const next = sessionOwners.slice()
    next.push(owner)
    sessionOwners = next
    beginCount++
    return true
  }

  function endSession(owner) {
    if (!owner || sessionOwners.indexOf(owner) < 0) return false
    sessionOwners = sessionOwners.filter(candidate => candidate !== owner)
    endCount++
    return true
  }

  function beginTrafficConsumer(owner) {
    if (!owner) return false
    if (trafficOwners.indexOf(owner) >= 0) return true
    if (trafficFailuresRemaining > 0) {
      trafficFailuresRemaining--
      return false
    }
    trafficOwners = trafficOwners.concat([owner])
    trafficBeginCount++
    return true
  }

  function endTrafficConsumer(owner) {
    if (!owner || trafficOwners.indexOf(owner) < 0) return false
    trafficOwners = trafficOwners.filter(candidate => candidate !== owner)
    trafficEndCount++
    return true
  }

  function runSpeedTest(_owner) {
    if (!speedTestReady || speedTestRunning) return false
    speedTestRunning = true
    speedRunCount++
    return true
  }

  function refresh(scanWifi) {
    refreshCount++
    lastScanWifi = scanWifi === true
    return true
  }
}
