pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property bool playing
  property color tint: "white"
  property real barH1: 0.08
  property real barH2: 0.08
  property real barH3: 0.08

  implicitWidth: 16
  implicitHeight: 14

  function reset() { restAnimation.restart() }

  onPlayingChanged: if (!playing) reset()

  SequentialAnimation {
    running: root.visible && root.playing
    loops: Animation.Infinite
    NumberAnimation { target: root; property: "barH1"; to: 0.85; duration: 220; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH1"; to: 0.18; duration: 300; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH1"; to: 0.70; duration: 260; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH1"; to: 0.10; duration: 280; easing.type: Easing.InOutSine }
  }

  SequentialAnimation {
    running: root.visible && root.playing
    loops: Animation.Infinite
    NumberAnimation { target: root; property: "barH2"; to: 0.45; duration: 310; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH2"; to: 0.92; duration: 280; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH2"; to: 0.28; duration: 340; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH2"; to: 0.65; duration: 290; easing.type: Easing.InOutSine }
  }

  SequentialAnimation {
    running: root.visible && root.playing
    loops: Animation.Infinite
    NumberAnimation { target: root; property: "barH3"; to: 0.60; duration: 380; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH3"; to: 0.12; duration: 320; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH3"; to: 0.95; duration: 350; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "barH3"; to: 0.32; duration: 400; easing.type: Easing.InOutSine }
  }

  ParallelAnimation {
    id: restAnimation
    NumberAnimation { target: root; property: "barH1"; to: 0.08; duration: 380; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "barH2"; to: 0.08; duration: 430; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "barH3"; to: 0.08; duration: 480; easing.type: Easing.OutCubic }
  }

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
