pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.bluetooth"
  manageIpc: false
  property url popupSource: Qt.resolvedUrl("BluetoothPanel.qml")
  property var bluetoothServiceOverride: null
  property var sessionService: null

  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property bool compact: setting("compact", false) === true
  readonly property var bluetoothService: bluetoothServiceOverride
    || (bar ? bar.bluetoothService : null)
  readonly property bool bluetoothReady: bluetoothService && bluetoothService.ready
  readonly property bool adapterAvailable: bluetoothReady
    && bluetoothService.adapterAvailable
  readonly property bool radioEnabled: adapterAvailable
    && bluetoothService.radioEnabled
  readonly property int connectedCount: bluetoothReady
    ? bluetoothService.connectedCount : 0
  readonly property bool connected: connectedCount > 0
  readonly property bool showConnectedCount: connected
    && bar && !bar.vertical
  readonly property string stateIcon: !radioEnabled ? "\uE1A9"
    : connected ? "\uE1A8" : "\uE1A7"
  readonly property string tooltipText: !bluetoothReady ? "Bluetooth unavailable"
    : !adapterAvailable ? "No Bluetooth adapter"
    : connected ? "Bluetooth · " + connectedCount + " connected"
    : radioEnabled ? "Bluetooth on" : "Bluetooth off"
  readonly property var panelItem: popupLoader.item
  readonly property bool panelLoaded: panelItem !== null
  readonly property var interactionTarget: actionButton

  visible: bluetoothReady && adapterAvailable
  implicitWidth: visible ? (bar && bar.vertical ? bar.barSize : surface.implicitWidth) : 0
  implicitHeight: visible
    ? (bar && bar.vertical ? surface.implicitHeight : bar ? bar.barSize : 28) : 0

  function childPanelWidget(pluginId) {
    const id = String(pluginId || "")
    return id === moduleName || id === "omarchy.bluetooth" ? root : null
  }

  function ownsPanelWidget(owner) { return owner === root }

  function releaseSession() {
    if (sessionService && typeof sessionService.endSession === "function")
      sessionService.endSession(root)
    sessionService = null
  }

  function syncPanelLoader() {
    popupLoader.source = ""
    if (!opened || !bluetoothReady || !adapterAvailable || !String(popupSource)) {
      releaseSession()
      return
    }
    if (sessionService !== bluetoothService) {
      releaseSession()
      sessionService = bluetoothService
      sessionService.beginSession(root)
    }
    popupLoader.setSource(popupSource, {
      anchorItem: surface,
      bar: root.bar,
      ownerWidget: root,
      bluetoothService: bluetoothService
    })
  }

  function toggleBluetooth() {
    return bluetoothService && bluetoothService.toggleBluetooth()
  }

  onOpenedChanged: syncPanelLoader()
  onBluetoothReadyChanged: syncPanelLoader()
  onAdapterAvailableChanged: syncPanelLoader()
  onPopupSourceChanged: syncPanelLoader()
  Component.onDestruction: {
    close()
    releaseSession()
  }

  Loader { id: popupLoader }

  Item {
    id: surface
    anchors.centerIn: parent
    implicitWidth: !root.bar || !root.tokens ? 0
      : root.bar.vertical ? root.bar.barSize
      : content.implicitWidth + 2 * root.tokens.pillPaddingX
    implicitHeight: !root.bar || !root.tokens ? 0
      : root.bar.vertical ? content.implicitHeight + Commons.Style.space(10)
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
        PillSurface { anchors.fill: parent; bar: root.bar }
      }
    }

    Loader {
      id: content
      anchors.centerIn: parent
      sourceComponent: !root.bar || !root.tokens ? null
        : root.compact || root.bar.vertical ? compactContent : fullContent
    }

    Ui.WidgetButton {
      id: actionButton
      anchors.fill: parent
      bar: root.visible ? root.bar : null
      text: " "
      keepSpace: true
      horizontalMargin: 0
      verticalPadding: 0
      fixedWidth: surface.width
      fixedHeight: surface.height
      tooltipText: root.tooltipText
      onPressed: function(button) {
        if (button === Qt.RightButton) root.toggleBluetooth()
        else root.toggle()
      }
    }
  }

  Component {
    id: fullContent

    Row {
      spacing: root.tokens.contentGap

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "BT"
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.6) : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.stateIcon
        color: root.bar ? (root.connected ? root.bar.urgent
          : root.bar.foreground) : Commons.Color.accent
        opacity: root.radioEnabled ? (root.connected ? 1 : 0.7) : 0.35
        font.pixelSize: 14
        font.weight: Font.Medium
        fill: 1
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showConnectedCount
        text: String(root.connectedCount)
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }

  Component {
    id: compactContent

    Row {
      spacing: root.tokens.compactGap

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.stateIcon
        color: root.bar ? (root.connected ? root.bar.urgent
          : root.bar.foreground) : Commons.Color.accent
        opacity: root.radioEnabled ? (root.connected ? 1 : 0.7) : 0.35
        font.pixelSize: 14
        font.weight: Font.Medium
        fill: 1
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showConnectedCount
        text: String(root.connectedCount)
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }
}
