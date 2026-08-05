pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var audioBackend

  property var displaySinks: []
  property var displaySources: []
  property var displayStreams: []
  readonly property real outputVolume: audioBackend
    ? Number(audioBackend.outputVolume || 0) : 0
  readonly property bool outputMuted: audioBackend
    ? audioBackend.outputMuted === true : false
  readonly property real inputVolume: audioBackend
    ? Number(audioBackend.inputVolume || 0) : 0
  readonly property bool inputMuted: audioBackend
    ? audioBackend.inputMuted === true : false
  readonly property real microphoneLevel: inputMuted || !audioBackend
    ? 0 : peakToMeter(inputPeakMonitor.peak)
  readonly property int renderedSinkCount: displaySinks.length
  readonly property int renderedSourceCount: displaySources.length
  readonly property int renderedStreamCount: displayStreams.length

  owner: ownerWidget
  open: ownerWidget.opened && audioBackend && audioBackend.ready
  focusTarget: keyCatcher
  gap: 8
  padding: 12
  contentWidth: fittedContentWidth(280)
  contentHeight: fittedContentHeight(contentColumn.implicitHeight,
    Commons.Style.space(580))

  function listSnapshot(values) {
    const result = []
    if (!values) return result
    for (let i = 0; i < values.length; i++) {
      if (values[i]) result.push(values[i])
    }
    return result
  }

  function refreshModels() {
    if (!open || !audioBackend) return
    displaySinks = listSnapshot(audioBackend.audioSinks)
    displaySources = listSnapshot(audioBackend.audioSources)
    displayStreams = listSnapshot(audioBackend.audioStreams)
  }

  function scheduleRefresh() {
    if (open) modelRefresh.restart()
  }

  function clearModels() {
    modelRefresh.stop()
    displaySinks = []
    displaySources = []
    displayStreams = []
  }

  function sameNode(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return left.id !== undefined && right.id !== undefined
      && String(left.id) === String(right.id)
  }

  function peakToMeter(peak) {
    const value = Number(peak || 0)
    if (!isFinite(value) || value <= 0) return 0
    const amplitude = value * value * value
    const db = 20 * Math.log(amplitude) / Math.LN10
    const noiseFloor = -55
    if (db <= noiseFloor) return 0
    return Math.max(0, Math.min(1, (db - noiseFloor) / -noiseFloor))
  }

  function adjustOutput(delta) {
    if (audioBackend) audioBackend.setOutputVolume(outputVolume + delta)
  }

  function sliderKnobColor(muted, sliderEnabled) {
    const stateOpacity = (muted ? 0.55 : 1)
      * (sliderEnabled ? 1 : 0.5)
    return Commons.Util.alpha(controlAccent, controlAccent.a * stateOpacity)
  }

  onOpenChanged: {
    if (open) {
      refreshModels()
      Qt.callLater(refreshModels)
    } else {
      clearModels()
    }
  }

  Item {
    width: 0
    height: 0
    visible: false

    Connections {
      target: panel.audioBackend
      function onAudioSinksChanged() { panel.scheduleRefresh() }
      function onAudioSourcesChanged() { panel.scheduleRefresh() }
      function onAudioStreamsChanged() { panel.scheduleRefresh() }
    }

    Timer {
      id: modelRefresh
      interval: 75
      repeat: false
      onTriggered: panel.refreshModels()
    }

    PwNodePeakMonitor {
      id: inputPeakMonitor
      node: panel.audioBackend ? panel.audioBackend.source : null
      enabled: panel.open && panel.audioBackend && panel.audioBackend.source !== null
    }
  }

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) { panel.ownerWidget.switchPanel(direction) }
    onMoveRequested: function(dx, _dy) {
      if (dx !== 0) panel.adjustOutput(dx * 0.05)
    }

    Flickable {
      id: scroller
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: scroller.width
        spacing: 8

        Item {
          width: parent.width
          height: 24

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Volume"
            color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
            font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
            font.pixelSize: 13
            font.letterSpacing: 2
            font.weight: Font.Medium
            renderType: Text.NativeRendering
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "\u2715"
            color: closeMouse.containsMouse
              ? panel.controlAccent : panel.controlMuted
            font.family: panel.bar ? panel.bar.fontFamily
              : Commons.Style.font.family
            font.pixelSize: 12
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: panel.ownerWidget.close()
            }
          }
        }

        PanelDivider {}

        Column {
          id: outputControl
          width: parent.width
          spacing: Commons.Style.space(2)

          SectionLabel { text: "OUTPUT" }

          Item {
            width: parent.width
            height: Commons.Style.space(30)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              text: panel.outputMuted ? "Muted"
                : Math.round(panel.outputVolume * 100) + "%"
              color: panel.outputMuted
                ? Commons.Util.alpha(panel.controlAccent, 0.4)
                : panel.controlAccent
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: 11
              font.weight: Font.Medium
              renderType: Text.NativeRendering
            }

            Ui.PanelSlider {
              id: outputSlider
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              bar: panel.bar
              maximum: 1
              value: panel.outputVolume
              trackColor: panel.controlActiveFillColor
              fillColor: panel.outputMuted
                ? Commons.Util.alpha(panel.controlAccent, 0.4)
                : panel.controlAccent
              knobColor: panel.sliderKnobColor(panel.outputMuted,
                outputSlider.enabled)
              enabled: panel.audioBackend && panel.audioBackend.sink !== null
              onMoved: function(value) {
                panel.audioBackend.setOutputVolume(value)
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: panel.displaySinks.length > 0
          text: "OUTPUT DEVICE"
          color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
            panel.bar.foreground.g, panel.bar.foreground.b, 0.52)
            : Commons.Color.foreground
          font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 10
          font.letterSpacing: 1
          renderType: Text.NativeRendering
        }

        Column {
          width: parent.width
          spacing: 4
          visible: panel.displaySinks.length > 0
          Repeater {
            model: panel.displaySinks

            DeviceRow {
              required property var modelData
              required property int index
              width: contentColumn.width
              node: modelData
              sourceDevice: false
              rowIndex: index
            }
          }
        }

        PanelDivider {}

        ActionButton {
          label: panel.outputMuted ? "Unmute volume" : "Mute volume"
          active: panel.outputMuted
          action: function() { panel.audioBackend.toggleOutputMute() }
        }

        PanelDivider { visible: panel.displayStreams.length > 0 }

        Column {
          width: parent.width
          spacing: Commons.Style.space(8)
          visible: panel.displayStreams.length > 0

          SectionLabel { text: "APPS" }

          Repeater {
            model: panel.displayStreams

            StreamRow {
              required property var modelData
              required property int index
              width: contentColumn.width
              node: modelData
              rowIndex: index
            }
          }
        }

        PanelDivider { visible: panel.audioBackend && panel.audioBackend.source !== null }

        Column {
          width: parent.width
          spacing: 8
          visible: panel.audioBackend && panel.audioBackend.source !== null

          Column {
            id: inputControl
            width: parent.width
            spacing: Commons.Style.space(2)

            SectionLabel { text: "INPUT" }

            Item {
              width: parent.width
              height: inputState.implicitHeight + Commons.Style.space(4)
                + inputSlider.implicitHeight + Commons.Style.space(8)

              Row {
                id: inputState
                width: parent.width

                Text {
                  width: parent.width / 2
                  text: "Microphone"
                  color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
                    panel.bar.foreground.g, panel.bar.foreground.b, 0.68)
                    : Commons.Color.foreground
                  font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                  font.pixelSize: 11
                  renderType: Text.NativeRendering
                }

                Text {
                  width: parent.width / 2
                  text: panel.inputMuted ? "Muted"
                    : Math.round(panel.inputVolume * 100) + "%"
                  color: panel.inputMuted
                    ? Commons.Util.alpha(panel.controlAccent, 0.4)
                    : panel.controlAccent
                  font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
                  font.pixelSize: 11
                  font.weight: Font.Medium
                  horizontalAlignment: Text.AlignRight
                  renderType: Text.NativeRendering
                }
              }

              Ui.PanelSlider {
                id: inputSlider
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: inputState.bottom
                anchors.topMargin: Commons.Style.space(4)
                bar: panel.bar
                maximum: 1
                value: panel.inputVolume
                trackColor: panel.controlActiveFillColor
                fillColor: panel.inputMuted
                  ? Commons.Util.alpha(panel.controlAccent, 0.4)
                  : panel.controlAccent
                knobColor: panel.sliderKnobColor(panel.inputMuted,
                  inputSlider.enabled)
                enabled: panel.audioBackend && panel.audioBackend.source !== null
                onMoved: function(value) {
                  panel.audioBackend.setInputVolume(value)
                }
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: inputSlider.bottom
                anchors.topMargin: Commons.Style.space(4)
                height: Commons.Style.space(4)
                radius: height / 2
                color: panel.controlFillColor
                border.color: panel.controlBorderColor
                border.width: 1

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: parent.width * panel.microphoneLevel
                  radius: parent.radius
                  color: panel.inputMuted
                    ? Commons.Util.alpha(panel.controlAccent, 0.25)
                    : panel.controlAccent
                  Behavior on width {
                    NumberAnimation { duration: 70; easing.type: Easing.OutCubic }
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Commons.Style.space(4)
            visible: panel.displaySources.length > 1

            Text {
              text: "INPUT DEVICE"
              color: panel.bar ? Qt.rgba(panel.bar.foreground.r,
                panel.bar.foreground.g, panel.bar.foreground.b, 0.52)
                : Commons.Color.foreground
              font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
              font.pixelSize: Commons.Style.font.caption
              font.letterSpacing: 1
              renderType: Text.NativeRendering
            }

            Repeater {
              model: panel.displaySources

              DeviceRow {
                required property var modelData
                required property int index
                width: contentColumn.width
                node: modelData
                sourceDevice: true
                rowIndex: index
              }
            }
          }

          ActionButton {
            label: panel.inputMuted ? "Unmute mic" : "Mute mic"
            active: panel.inputMuted
            action: function() { panel.audioBackend.toggleInputMute() }
          }
        }
      }
    }
  }

  component SectionLabel: Text {
    color: panel.controlMutedHigh
    font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: 10
    font.letterSpacing: 1
    renderType: Text.NativeRendering
  }

  component PanelDivider: Rectangle {
    width: contentColumn.width
    height: 1
    color: panel.dividerColor
  }

  component ActionButton: Rectangle {
    id: actionButton
    required property string label
    required property var action
    property bool active: false
    width: contentColumn.width
    height: 28
    radius: panel.controlRadius
    color: active
      ? panel.controlActiveFillColor
      : actionMouse.containsMouse ? panel.controlHoverFillColor
        : panel.controlFillColor
    border.width: panel.controlBorderWidth
    border.color: active
      ? panel.bar ? panel.bar.urgent : Commons.Color.accent
      : actionMouse.containsMouse ? panel.controlHoverBorderColor
        : panel.controlBorderColor

    Text {
      anchors.centerIn: parent
      text: actionButton.label
      color: parent.active || actionMouse.containsMouse
        ? panel.bar ? panel.bar.urgent : Commons.Color.accent
        : panel.bar ? panel.bar.foreground : Commons.Color.foreground
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: 11
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: actionButton.action()
    }
  }

  component DeviceRow: Rectangle {
    id: deviceRow
    required property var node
    required property bool sourceDevice
    required property int rowIndex
    readonly property var activeNode: sourceDevice
      ? panel.audioBackend.source : panel.audioBackend.sink
    readonly property bool current: panel.sameNode(node, activeNode)
    width: contentColumn.width
    height: 26
    radius: panel.controlRadius
    color: current
      ? panel.controlActiveFillColor
      : deviceMouse.containsMouse ? panel.controlHoverFillColor
        : panel.controlFillColor
    border.width: panel.controlBorderWidth
    border.color: current
      ? panel.bar ? panel.bar.urgent : Commons.Color.accent
      : deviceMouse.containsMouse ? panel.controlHoverBorderColor
        : panel.controlBorderColor

    Row {
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      spacing: 6

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: deviceRow.current ? "●" : "○"
        color: deviceRow.current
          ? panel.controlAccent : panel.controlMuted
        font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: 10
        renderType: Text.NativeRendering
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 22
        text: panel.audioBackend.nodeLabel(deviceRow.node)
        color: deviceRow.current || deviceMouse.containsMouse
          ? panel.controlAccent : panel.controlForeground
        font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: 11
        font.weight: deviceRow.current ? Font.Medium : Font.Normal
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }
    }

    MouseArea {
      id: deviceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (deviceRow.sourceDevice)
          panel.audioBackend.setDefaultSource(deviceRow.node)
        else panel.audioBackend.setDefaultSink(deviceRow.node)
      }
    }
  }

  component StreamRow: Item {
    id: streamRow
    required property var node
    required property int rowIndex
    readonly property var audio: node ? node.audio : null
    width: contentColumn.width
    height: Commons.Style.space(32)

    IconText {
      id: muteIcon
      anchors.left: parent.left
      anchors.top: parent.top
      width: Commons.Style.space(20)
      text: streamRow.audio && streamRow.audio.muted ? "volume_off" : "volume_up"
      color: streamRow.audio && streamRow.audio.muted && panel.bar
        ? Qt.rgba(panel.bar.foreground.r, panel.bar.foreground.g,
          panel.bar.foreground.b, 0.4)
        : panel.bar ? panel.bar.urgent : Commons.Color.accent
      font.pixelSize: Commons.Style.font.body
      fill: 1

      MouseArea {
        anchors.fill: parent
        anchors.margins: -Commons.Style.space(3)
        cursorShape: Qt.PointingHandCursor
        onClicked: panel.audioBackend.toggleStreamMute(streamRow.node)
      }
    }

    Text {
      anchors.left: muteIcon.right
      anchors.leftMargin: Commons.Style.space(5)
      anchors.right: streamPercent.left
      anchors.rightMargin: Commons.Style.space(5)
      anchors.verticalCenter: muteIcon.verticalCenter
      text: panel.audioBackend.streamLabel(streamRow.node)
      color: panel.bar ? panel.bar.foreground : Commons.Color.foreground
      opacity: streamRow.audio && streamRow.audio.muted ? 0.46 : 1
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.body
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    Text {
      id: streamPercent
      anchors.right: parent.right
      anchors.verticalCenter: muteIcon.verticalCenter
      text: Math.round(Number(streamRow.audio ? streamRow.audio.volume : 0) * 100) + "%"
      color: panel.bar ? panel.bar.urgent : Commons.Color.accent
      font.family: panel.bar ? panel.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.body
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }

    Ui.PanelSlider {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      bar: panel.bar
      maximum: 1
      value: streamRow.audio ? Number(streamRow.audio.volume || 0) : 0
      trackColor: panel.controlActiveFillColor
      fillColor: streamRow.audio && streamRow.audio.muted
        ? Commons.Util.alpha(panel.controlAccent, 0.4)
        : panel.controlAccent
      knobColor: streamRow.audio && streamRow.audio.muted
        ? Commons.Util.alpha(panel.controlAccent, 0.55)
        : panel.controlAccent
      onMoved: function(value) {
        panel.audioBackend.setStreamVolume(streamRow.node, value)
      }
    }
  }
}
