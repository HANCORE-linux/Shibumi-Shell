pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.network"
  manageIpc: false
  property url popupSource: Qt.resolvedUrl("NetworkPanel.qml")
  property var networkServiceOverride: null
  property var sessionService: null

  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property bool compact: setting("compact", false) === true
  readonly property var networkService: networkServiceOverride
    || (bar ? bar.networkService : null)
  readonly property bool networkReady: networkService && networkService.ready
  readonly property bool backendAvailable: networkReady
    && networkService.backendAvailable
  readonly property string mode: !networkReady ? "none"
    : networkService.kind === "wifi" ? "wifi"
    : networkService.kind === "ethernet" ? "ethernet" : "none"
  readonly property string label: networkReady ? networkService.label : ""
  readonly property int signal: networkReady ? networkService.signalStrength : 0
  readonly property string wifiIcon: signal <= 0 ? "signal_wifi_off"
    : signal < 22 ? "network_wifi_1_bar"
    : signal < 44 ? "network_wifi_2_bar"
    : signal < 66 ? "network_wifi_3_bar" : "signal_wifi_4_bar"
  readonly property string stateIcon: mode === "wifi" ? wifiIcon
    : mode === "ethernet" ? "lan" : "signal_wifi_off"
  readonly property string tooltipText: !networkReady ? "Network unavailable"
    : mode === "wifi" ? (label || "Wi-Fi") + " · " + signal + "%"
    : mode === "ethernet" ? "Ethernet · " + (label || "connected")
    : backendAvailable ? "Offline" : "NetworkManager unavailable"
  readonly property var panelItem: popupLoader.item
  readonly property bool panelLoaded: panelItem !== null
  readonly property var interactionTarget: actionButton

  visible: networkReady
  implicitWidth: visible ? (bar && bar.vertical ? bar.barSize : surface.implicitWidth) : 0
  implicitHeight: visible
    ? (bar && bar.vertical ? surface.implicitHeight : bar ? bar.barSize : 28) : 0

  function childPanelWidget(pluginId) {
    const id = String(pluginId || "")
    return id === moduleName || id === "omarchy.network" ? root : null
  }

  function ownsPanelWidget(owner) { return owner === root }

  function releaseSession() {
    if (sessionService && typeof sessionService.endSession === "function")
      sessionService.endSession(root)
    sessionService = null
  }

  function syncPanelLoader() {
    popupLoader.source = ""
    if (!opened || !networkReady || !String(popupSource)) {
      releaseSession()
      return
    }
    if (sessionService !== networkService) {
      releaseSession()
      sessionService = networkService
      sessionService.beginSession(root)
    }
    popupLoader.setSource(popupSource, {
      anchorItem: surface,
      bar: root.bar,
      ownerWidget: root,
      networkService: networkService
    })
  }

  function openAndScan() {
    const alreadyOpen = opened
    open()
    return networkService && (alreadyOpen ? networkService.refresh(true) : true)
  }

  onOpenedChanged: syncPanelLoader()
  onNetworkReadyChanged: syncPanelLoader()
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
        : root.bar.vertical ? verticalContent
        : root.compact ? compactContent : fullContent
    }

    Ui.WidgetButton {
      id: actionButton
      anchors.fill: parent
      bar: root.networkReady ? root.bar : null
      text: " "
      keepSpace: true
      horizontalMargin: 0
      verticalPadding: 0
      fixedWidth: surface.width
      fixedHeight: surface.height
      tooltipText: root.tooltipText
      onPressed: function(button) {
        if (button === Qt.RightButton) root.openAndScan()
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
        text: "NET"
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, root.mode === "none" ? 0.38 : 0.6)
          : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.stateIcon
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        opacity: root.mode === "none" ? 0.58 : 1
        font.pixelSize: root.mode === "none" ? 15 : 14
        font.weight: Font.Medium
        fill: 1
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.mode !== "none"
        text: root.label
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: root.mode === "wifi" ? 1 : 0
        elide: Text.ElideRight
        maximumLineCount: 1
        width: Math.min(implicitWidth, Commons.Style.space(128))
        renderType: Text.NativeRendering
      }
    }
  }

  Component {
    id: compactContent

    IconText {
      text: root.stateIcon
      color: root.bar ? root.bar.urgent : Commons.Color.accent
      opacity: root.mode === "none" ? 0.58 : 1
      font.pixelSize: root.mode === "none" ? 15 : root.compact ? 15 : 14
      font.weight: Font.Medium
      fill: 1
    }
  }

  Component {
    id: verticalContent

    IconText {
      text: root.stateIcon
      color: root.bar ? root.bar.urgent : Commons.Color.accent
      opacity: root.mode === "none" ? 0.58 : 1
      font.pixelSize: root.mode === "none" ? 15 : 14
      font.weight: Font.Medium
      fill: 1
    }
  }
}
