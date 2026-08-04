pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../adapters" as Adapters

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.audio"
  manageIpc: false
  property url popupSource: Qt.resolvedUrl("AudioPanel.qml")
  readonly property url backendPanelSource: registeredSource("omarchy.audio")
  property Component panelComponent: String(backendPanelSource) ? null
    : registeredComponent("omarchy.audio")

  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property bool compact: setting("compact", false) === true
  readonly property var audioPanel: audioBridge.panel
  readonly property var panelItem: popupLoader.item
  readonly property bool panelLoaded: panelItem !== null
  readonly property bool audioReady: audioBridge.ready
  property bool wheelAdjustmentPending: false
  property real wheelTargetVolume: 0
  readonly property real displayedOutputVolume: wheelAdjustmentPending
    ? wheelTargetVolume : audioBridge.outputVolume
  readonly property int volume: Math.round(displayedOutputVolume * 100)
  readonly property bool muted: audioBridge.outputMuted
  readonly property string tooltipText: !audioReady ? "Audio unavailable"
    : muted ? "Muted · " + volume + "%" : "Audio " + volume + "%"
  readonly property var interactionTarget: actionButton

  visible: audioReady
  implicitWidth: visible ? (bar && bar.vertical ? bar.barSize : audioSurface.implicitWidth) : 0
  implicitHeight: visible
    ? (bar && bar.vertical ? audioSurface.implicitHeight : bar ? bar.barSize : 28) : 0

  function setting(name, fallback) {
    const value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function registeredComponent(id) {
    if (bar && typeof bar.registeredWidgetComponent === "function")
      return bar.registeredWidgetComponent(id)
    const registry = bar ? bar.barWidgetRegistry : null
    if (registry) void(registry.revision)
    const widgets = registry && registry.widgets ? registry.widgets : ({})
    const entry = widgets[id]
    return entry ? entry.component : null
  }

  function registeredSource(id) {
    return bar && typeof bar.registeredWidgetSource === "function"
      ? bar.registeredWidgetSource(id) : ""
  }

  function officialSettings() {
    return bar && typeof bar.widgetSettings === "function"
      ? bar.widgetSettings("G6", "omarchy.audio") : ({})
  }

  function childPanelWidget(pluginId) {
    return String(pluginId || "") === "omarchy.audio" ? root : null
  }

  function ownsPanelWidget(owner) {
    return !!owner && (owner === root || owner === audioPanel)
  }

  function toggleOutputMute() { return audioBridge.toggleOutputMute() }
  function setOutputVolume(value) { return audioBridge.setOutputVolume(value) }
  function adjustVolume(delta) {
    if (!audioReady || Number(delta || 0) === 0) return false
    const base = wheelAdjustmentPending
      ? wheelTargetVolume : audioBridge.outputVolume
    wheelTargetVolume = Math.max(0, Math.min(1,
      Math.round((base + Number(delta)) * 100) / 100))
    wheelAdjustmentPending = true
    wheelCommitTimer.restart()
    return true
  }

  function syncPanelLoader() {
    popupLoader.source = ""
    if (!opened || !audioReady || !String(popupSource)) return
    popupLoader.setSource(popupSource, {
      anchorItem: audioSurface,
      bar: root.bar,
      ownerWidget: root,
      audioBackend: audioBridge
    })
  }

  onOpenedChanged: syncPanelLoader()
  onAudioReadyChanged: {
    if (opened) syncPanelLoader()
    if (!audioReady) {
      wheelCommitTimer.stop()
      wheelSettleTimer.stop()
      wheelAdjustmentPending = false
    }
  }
  onPopupSourceChanged: if (opened) syncPanelLoader()
  Component.onDestruction: close()

  Adapters.AudioPanelBridge {
    id: audioBridge
    anchors.fill: audioSurface
    bar: root.bar
    ownerWidget: root
    panelComponent: root.panelComponent
    panelSource: root.backendPanelSource
    panelSettings: root.officialSettings()
  }

  Loader { id: popupLoader }

  Timer {
    id: wheelCommitTimer
    interval: 70
    onTriggered: {
      if (!root.setOutputVolume(root.wheelTargetVolume)) {
        root.wheelAdjustmentPending = false
        return
      }
      wheelSettleTimer.restart()
    }
  }

  Timer {
    id: wheelSettleTimer
    interval: 300
    onTriggered: root.wheelAdjustmentPending = false
  }

  Item {
    id: audioSurface
    anchors.centerIn: parent
    implicitWidth: !root.bar || !root.tokens ? 0
      : root.bar.vertical
      ? root.bar.barSize : content.implicitWidth + 2 * root.tokens.pillPaddingX
    implicitHeight: !root.bar || !root.tokens ? 0
      : root.bar.vertical
      ? content.implicitHeight + Commons.Style.space(10)
      : root.tokens.slotHeight
    width: implicitWidth
    height: implicitHeight

    Loader {
      anchors.fill: parent
      anchors.topMargin: root.tokens
        ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
      anchors.bottomMargin: root.tokens
        ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
      active: root.bar !== null && root.tokens !== null
      sourceComponent: Component {
        PillSurface {
          anchors.fill: parent
          bar: root.bar
        }
      }
    }

    Loader {
      id: content
      anchors.centerIn: parent
      sourceComponent: !root.bar || !root.tokens ? null
        : root.bar.vertical ? verticalContent
        : root.compact ? compactHorizontalContent : fullHorizontalContent
    }

    Ui.WidgetButton {
      id: actionButton
      anchors.fill: parent
      bar: root.audioReady ? root.bar : null
      text: " "
      keepSpace: true
      horizontalMargin: 0
      verticalPadding: 0
      fixedWidth: audioSurface.width
      fixedHeight: audioSurface.height
      tooltipText: root.tooltipText
      onPressed: function(button) {
        if (button === Qt.RightButton) root.toggleOutputMute()
        else root.toggle()
      }
      onWheelMoved: function(delta) {
        if (delta !== 0) root.adjustVolume(delta > 0 ? 0.05 : -0.05)
      }
    }
  }

  Component {
    id: fullHorizontalContent

    Row {
      spacing: root.tokens.contentGap

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "VOL"
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, root.muted ? 0.25 : 0.6) : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(34)
        height: Commons.Style.space(14)

        readonly property real ratio: root.muted ? 0 : Math.min(root.volume / 100, 1)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: Commons.Style.space(8)
          radius: height / 2
          color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
            root.bar.foreground.b, 0.18) : Commons.Color.background
        }

        Rectangle {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(parent.ratio > 0 ? Commons.Style.space(8) : 0,
            parent.width * parent.ratio)
          height: Commons.Style.space(8)
          radius: height / 2
          color: root.bar ? root.bar.urgent : Commons.Color.accent

          Behavior on width {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(30)
        text: String(root.volume).padStart(2, "0") + "%"
        color: root.bar ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
          root.bar.urgent.b, root.muted ? 0.35 : 1) : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        horizontalAlignment: Text.AlignRight
        renderType: Text.NativeRendering

        Behavior on color { ColorAnimation { duration: 160 } }
      }
    }
  }

  Component {
    id: compactHorizontalContent

    Row {
      spacing: root.tokens.compactGap

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: "graphic_eq"
        color: root.bar ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
          root.bar.urgent.b, root.muted ? 0.35 : 1) : Commons.Color.accent
        font.pixelSize: root.tokens.iconSize
        font.weight: Font.Medium
        fill: 1
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(30)
        text: String(root.volume).padStart(2, "0") + "%"
        color: root.bar ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
          root.bar.urgent.b, root.muted ? 0.35 : 1) : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        horizontalAlignment: Text.AlignLeft
        renderType: Text.NativeRendering

        Behavior on color { ColorAnimation { duration: 160 } }
      }
    }
  }

  Component {
    id: verticalContent

    Column {
      spacing: Commons.Style.space(2)

      IconText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "graphic_eq"
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.pixelSize: root.tokens.iconSize
        font.weight: Font.Medium
        fill: 1
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: String(root.volume).padStart(2, "0") + "%"
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }
}
