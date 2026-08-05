pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Item {
  id: root

  required property var bar
  required property var statusService

  readonly property var stateService: bar && "shell" in bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property bool hasActive: statusService
    && (statusService.stayAwake || statusService.notificationsSilenced
      || statusService.recording || statusService.voxtypeActive)
  readonly property string idleIconFamily: idleIcon.font.family
  readonly property string dndIconFamily: dndIcon.font.family
  readonly property string recordingIconFamily: recordingIcon.fontFamily
  readonly property string recordingIconGlyph: recordingIcon.text
  readonly property color recordingIconColor: stateService
    && typeof stateService.paletteColor === "function"
    ? stateService.paletteColor("color01")
    : bar ? bar.urgent : Commons.Color.urgent
  readonly property string voxtypeIconFamily: voxtypeIcon.font.family
  readonly property real dndOpticalCenterOffset: 1
  readonly property int activeCount: (statusService && statusService.stayAwake ? 1 : 0)
    + (statusService && statusService.notificationsSilenced ? 1 : 0)
    + (statusService && statusService.recording ? 1 : 0)
    + (statusService && statusService.voxtypeActive ? 1 : 0)
  readonly property real activeWidth:
    (statusService && statusService.stayAwake ? 20 : 0)
    + (statusService && statusService.notificationsSilenced ? 20 : 0)
    + (statusService && statusService.recording ? recordingIndicator.implicitWidth : 0)
    + (statusService && statusService.voxtypeActive ? 20 : 0)
    + Math.max(0, activeCount - 1) * Commons.Style.space(8)

  implicitWidth: hasActive ? activeWidth : 0
  implicitHeight: bar ? bar.barSize : Commons.Style.space(35)
  visible: hasActive

  function pad(value) {
    return Number(value) < 10 ? "0" + Number(value) : String(Number(value))
  }

  function elapsedText() {
    const elapsed = statusService ? Number(statusService.recordingElapsed || 0) : 0
    const hours = Math.floor(elapsed / 3600)
    const minutes = Math.floor((elapsed % 3600) / 60)
    const seconds = Math.floor(elapsed % 60)
    return hours > 0
      ? hours + ":" + pad(minutes) + ":" + pad(seconds)
      : pad(minutes) + ":" + pad(seconds)
  }

  function toggleStayAwake() {
    return statusService && typeof statusService.toggleStayAwake === "function"
      ? statusService.toggleStayAwake() : false
  }

  function toggleNotifications() {
    return statusService && typeof statusService.toggleNotifications === "function"
      ? statusService.toggleNotifications() : false
  }

  function stopRecording() {
    return statusService && typeof statusService.stopRecording === "function"
      ? statusService.stopRecording() : false
  }

  function activateVoxtype(button) {
    if (!statusService) return false
    if (button === Qt.RightButton
        && typeof statusService.openVoxtypeConfig === "function")
      return statusService.openVoxtypeConfig()
    if (typeof statusService.openVoxtypeModel === "function")
      return statusService.openVoxtypeModel()
    return false
  }

  Row {
    id: indicatorRow
    anchors.centerIn: parent
    spacing: Commons.Style.space(8)

    Item {
      id: idleIndicator
      visible: root.statusService && root.statusService.stayAwake
      implicitWidth: visible ? 20 : 0
      implicitHeight: root.implicitHeight
      width: implicitWidth
      height: implicitHeight

      Text {
        id: idleIcon
        anchors.centerIn: parent
        text: "\udb86\uded6"
        color: root.bar ? root.bar.urgent : Commons.Color.urgent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: 13
      }

      Ui.WidgetButton {
        anchors.fill: parent
        bar: root.bar
        text: " "
        keepSpace: true
        horizontalMargin: 0
        verticalPadding: 0
        tooltipText: "Idle lock disabled"
        onPressed: root.toggleStayAwake()
      }
    }

    Item {
      id: dndIndicator
      visible: root.statusService && root.statusService.notificationsSilenced
      implicitWidth: visible ? 20 : 0
      implicitHeight: root.implicitHeight
      width: implicitWidth
      height: implicitHeight

      IconText {
        id: dndIcon
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.dndOpticalCenterOffset
        text: "\ue7f6"
        color: root.bar ? root.bar.urgent : Commons.Color.urgent
        font.pixelSize: 14
      }

      Ui.WidgetButton {
        anchors.fill: parent
        bar: root.bar
        text: " "
        keepSpace: true
        horizontalMargin: 0
        verticalPadding: 0
        tooltipText: "Notifications silenced"
        onPressed: root.toggleNotifications()
      }
    }

    Item {
      id: recordingIndicator
      visible: root.statusService && root.statusService.recording
      implicitWidth: visible ? recordingRow.implicitWidth + 6 : 0
      implicitHeight: root.implicitHeight
      width: implicitWidth
      height: implicitHeight

      Component.onCompleted: if (root.bar) root.bar.registerClickTarget(recordingIndicator)
      Component.onDestruction: if (root.bar) root.bar.unregisterClickTarget(recordingIndicator)

      Row {
        id: recordingRow
        anchors.centerIn: parent
        spacing: Commons.Style.space(5)

        Ui.OpticalGlyph {
          id: recordingIcon
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(16)
          height: width
          text: "󰻂"
          color: root.recordingIconColor
          fontFamily: root.bar ? root.bar.fontFamily : Commons.Style.font.family
          fontSize: 13

          SequentialAnimation on opacity {
            running: recordingIndicator.visible
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.elapsedText()
          color: root.bar ? root.bar.urgent : Commons.Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 11
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root.bar) root.bar.showTooltip(recordingIndicator,
          "Recording · " + root.elapsedText() + "\nClick to stop")
        onExited: if (root.bar) root.bar.hideTooltip(recordingIndicator)
        onClicked: {
          if (root.bar) root.bar.hideTooltip(recordingIndicator)
          root.stopRecording()
        }
      }
    }

    Item {
      id: voxtypeIndicator
      visible: root.statusService && root.statusService.voxtypeActive
      implicitWidth: visible ? 20 : 0
      implicitHeight: root.implicitHeight
      width: implicitWidth
      height: implicitHeight

      IconText {
        id: voxtypeIcon
        anchors.centerIn: parent
        text: root.statusService && root.statusService.voxtypeState === "recording"
          ? "\ue029" : "\ue65f"
        color: root.statusService
          && root.statusService.voxtypeState === "recording" && root.bar
          ? root.bar.urgent : root.bar ? root.bar.foreground : Commons.Color.foreground
        font.pixelSize: 14

        SequentialAnimation on opacity {
          running: voxtypeIndicator.visible && root.statusService
            && root.statusService.voxtypeState === "recording"
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
        }
      }

      Ui.WidgetButton {
        anchors.fill: parent
        bar: root.bar
        text: " "
        keepSpace: true
        horizontalMargin: 0
        verticalPadding: 0
        tooltipText: root.statusService && root.statusService.voxtypeHint
          ? root.statusService.voxtypeHint
          : root.statusService && root.statusService.voxtypeState === "recording"
            ? "Voxtype recording" : "Voxtype transcribing"
        onPressed: function(button) {
          root.activateVoxtype(button)
        }
      }
    }
  }
}
