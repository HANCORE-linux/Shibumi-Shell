pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.bluetooth"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }
  property url popupSource: Qt.resolvedUrl("BluetoothPanel.qml")
  property var bluetoothServiceOverride: null
  property var sessionService: null

  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  readonly property int iconSlotSize: tokens.v2Shell === true
    || displayMode !== "full" ? 14 : 16
  readonly property int contentHorizontalOffset: bar && !bar.vertical
    && tokens.v2Shell !== true && displayMode === "full" ? 2 : 0
  readonly property var bluetoothService: bluetoothServiceOverride
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("hancore.shibumi.bluetooth") : null)
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
        PillSurface {
          tokenSource: root.tokens
          anchors.fill: parent
          bar: root.bar
          settings: root.settings
          v1AppearanceEnabled: true
        }
      }
    }

    Loader {
      id: content
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.contentHorizontalOffset
      sourceComponent: !root.bar || !root.tokens ? null
        : root.bar.vertical || root.displayMode === "icon" ? compactContent
        : root.tokens.v2Shell === true && root.displayMode === "full" ? compactContent
        : root.displayMode === "text" ? textContent : fullContent
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
        visible: root.displayMode === "full"
        anchors.verticalCenter: parent.verticalCenter
        text: "BT"
        color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
          root.widgetInk.b, 0.68)
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      Item {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconSlotSize
        height: root.iconSlotSize

        IconText {
          anchors.centerIn: parent
          text: root.stateIcon
          color: root.widgetInk
          opacity: root.radioEnabled ? (root.connected ? 1 : 0.7) : 0.35
          font.pixelSize: 14
          font.weight: Font.Medium
          fill: 1
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showConnectedCount
        text: String(root.connectedCount)
        color: root.widgetInk
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

      Item {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconSlotSize
        height: root.iconSlotSize

        IconText {
          anchors.centerIn: parent
          text: root.stateIcon
          color: root.widgetInk
          opacity: root.radioEnabled ? (root.connected ? 1 : 0.7) : 0.35
          font.pixelSize: 14
          font.weight: Font.Medium
          fill: 1
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showConnectedCount
        text: String(root.connectedCount)
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }

  Component {
    id: textContent

    Text {
      text: root.connected ? String(root.connectedCount)
        : root.radioEnabled ? "On" : "Off"
      color: root.widgetInk
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.tokens.labelSize
      renderType: Text.NativeRendering
    }
  }
}
