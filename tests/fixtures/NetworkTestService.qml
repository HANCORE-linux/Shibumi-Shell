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
  property var sessionOwners: []
  property int beginCount: 0
  property int endCount: 0
  property int refreshCount: 0
  property bool lastScanWifi: false
  property int viewLoadCount: 0
  readonly property int sessionCount: sessionOwners.length

  function beginSession(owner) {
    if (!owner || sessionOwners.indexOf(owner) >= 0) return
    const next = sessionOwners.slice()
    next.push(owner)
    sessionOwners = next
    beginCount++
  }

  function endSession(owner) {
    if (!owner || sessionOwners.indexOf(owner) < 0) return
    sessionOwners = sessionOwners.filter(candidate => candidate !== owner)
    endCount++
  }

  function refresh(scanWifi) {
    refreshCount++
    lastScanWifi = scanWifi === true
    return true
  }
}
