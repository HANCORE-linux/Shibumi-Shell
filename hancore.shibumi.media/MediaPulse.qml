pragma ComponentBehavior: Bound

import QtQuick
import "MediaMotion.js" as Motion

Item {
  id: root

  required property bool playing
  property color tint: "white"
  property real barH1: 0.08
  property real barH2: 0.08
  property real barH3: 0.08

  implicitWidth: 16
  implicitHeight: 14

  property real elapsed: 0
  property bool admitted: true
  property bool settling: false
  property real restElapsed: 0
  property var restStart: [0.08, 0.08, 0.08]
  property var pulseStart: [0.08, 0.08, 0.08]

  function advance(milliseconds) {
    if (playing) {
      elapsed += milliseconds
      barH1 = Motion.pulse(elapsed, 0, pulseStart[0])
      barH2 = Motion.pulse(elapsed, 1, pulseStart[1])
      barH3 = Motion.pulse(elapsed, 2, pulseStart[2])
    } else if (settling) {
      restElapsed = Math.min(480, restElapsed + milliseconds)
      barH1 = Motion.pulseRest(restElapsed, 0, restStart[0])
      barH2 = Motion.pulseRest(restElapsed, 1, restStart[1])
      barH3 = Motion.pulseRest(restElapsed, 2, restStart[2])
      settling = barH1 !== 0.08 || barH2 !== 0.08 || barH3 !== 0.08
    }
  }

  function cancelRest() {
    settling = false
    if (!playing) { barH1 = 0.08; barH2 = 0.08; barH3 = 0.08 }
  }

  // The parent's existing cadence may finish this bounded OutCubic tail, but
  // hiding/revoking the surface cancels it immediately. No primitive clock.
  onPlayingChanged: {
    elapsed = 0
    if (playing) {
      settling = false
      pulseStart = [barH1, barH2, barH3]
    } else if (visible && admitted) {
      restElapsed = 0
      restStart = [barH1, barH2, barH3]
      settling = barH1 !== 0.08 || barH2 !== 0.08 || barH3 !== 0.08
    } else cancelRest()
  }
  onVisibleChanged: if (!visible) cancelRest()
  onAdmittedChanged: if (!admitted) cancelRest()

  Row {
    anchors.fill: parent
    spacing: 2

    Repeater {
      model: 3

      delegate: Item {
        required property int index
        readonly property real level: index === 0 ? root.barH1
          : index === 1 ? root.barH2 : root.barH3
        width: 4
        height: parent.height

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: 3
          height: Math.max(width, parent.height * parent.level)
          radius: width / 2
          color: root.tint
        }
      }
    }
  }
}
