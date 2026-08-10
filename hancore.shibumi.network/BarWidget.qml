pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.network"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }
  property url popupSource: Qt.resolvedUrl("NetworkPanel.qml")
  property var networkServiceOverride: null
  property var sessionService: null

  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings,
      bar ? bar.urgent : Commons.Color.accent)
    : (bar ? bar.urgent : Commons.Color.accent)
  readonly property bool v1CustomToneActive: !!(tokens
    && tokens.v2Shell !== true
    && typeof tokens.widgetHasFill === "function"
    && tokens.widgetHasFill(settings))
  readonly property color v1Ink: v1CustomToneActive ? widgetInk
    : tokens && "ink" in tokens ? tokens.ink : widgetInk
  readonly property color v1Seal: v1CustomToneActive ? widgetInk
    : tokens && "seal" in tokens ? tokens.seal : widgetInk
  readonly property color v1Indigo: v1CustomToneActive ? widgetInk
    : tokens && tokens.stateService
      && typeof tokens.stateService.paletteColor === "function"
      ? tokens.stateService.paletteColor("color04")
      : Qt.rgba(v1Ink.r, v1Ink.g, v1Ink.b, 0.58)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  readonly property var networkService: networkServiceOverride
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("hancore.shibumi.network") : null)
  readonly property bool networkReady: networkService && networkService.ready
  readonly property bool backendAvailable: networkReady
    && networkService.backendAvailable
  readonly property string mode: !networkReady ? "none"
    : networkService.kind === "wifi" ? "wifi"
    : networkService.kind === "ethernet" ? "ethernet" : "none"
  readonly property string label: networkReady ? networkService.label : ""
  readonly property string displayLabel: mode === "none"
    ? "Offline" : mode === "ethernet" ? "Ethernet" : (label || "Wi-Fi")
  readonly property int signal: networkReady ? networkService.signalStrength : 0
  readonly property real downloadRate: networkReady
    ? Math.max(0, Number(networkService.downloadRate || 0)) : 0
  readonly property real uploadRate: networkReady
    ? Math.max(0, Number(networkService.uploadRate || 0)) : 0
  readonly property bool v2Presentation: tokens && tokens.v2Shell === true
  readonly property string v2MonoFont: "JetBrainsMono Nerd Font"
  readonly property bool v1TrafficPresentation: mode === "ethernet"
    && displayMode === "full" && !v2Presentation
  readonly property bool v2TrafficPresentation: mode === "ethernet"
    && displayMode === "full" && v2Presentation
  property var downloadHistory: []
  property var uploadHistory: []
  readonly property int trafficHistoryLimit: 30
  readonly property string wifiIcon: signal <= 0 ? "signal_wifi_off"
    : signal < 22 ? "network_wifi_1_bar"
    : signal < 44 ? "network_wifi_2_bar"
    : signal < 66 ? "network_wifi_3_bar" : "signal_wifi_4_bar"
  readonly property string stateIcon: mode === "wifi" ? wifiIcon
    : mode === "ethernet" ? "lan" : "signal_wifi_off"
  readonly property string stateGlyph: stateIcon === "lan" ? "\uEB2F"
    : stateIcon === "network_wifi_1_bar" ? "\uEBE4"
    : stateIcon === "network_wifi_2_bar" ? "\uEBD6"
    : stateIcon === "network_wifi_3_bar" ? "\uEBE1"
    : stateIcon === "signal_wifi_4_bar" ? "\uF065" : "\uE1DA"
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

  function compactRate(bytesPerSecond) {
    const value = Math.max(0, Number(bytesPerSecond) || 0)
    if (value >= 1024 * 1024 * 1024)
      return (value / (1024 * 1024 * 1024)).toFixed(value < 10 * 1024 * 1024 * 1024 ? 1 : 0) + "G"
    if (value >= 1024 * 1024)
      return (value / (1024 * 1024)).toFixed(value < 10 * 1024 * 1024 ? 1 : 0) + "M"
    if (value >= 1024)
      return (value / 1024).toFixed(value < 10 * 1024 ? 1 : 0) + "K"
    return "0K"
  }

  function v1Rate(bytesPerSecond) {
    const mebibytes = Math.max(0, Number(bytesPerSecond) || 0) / (1024 * 1024)
    const value = mebibytes < 10 ? mebibytes.toFixed(2) : mebibytes.toFixed(1)
    return value.padStart(5, " ") + "M"
  }

  function appendTrafficSample() {
    if (mode !== "ethernet") return
    const nextDownload = downloadHistory.slice()
    const nextUpload = uploadHistory.slice()
    nextDownload.push(downloadRate)
    nextUpload.push(uploadRate)
    while (nextDownload.length > trafficHistoryLimit) nextDownload.shift()
    while (nextUpload.length > trafficHistoryLimit) nextUpload.shift()
    downloadHistory = nextDownload
    uploadHistory = nextUpload
  }

  function resetTrafficHistory() {
    downloadHistory = []
    uploadHistory = []
  }

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
  onModeChanged: if (mode !== "ethernet") resetTrafficHistory()
  Component.onDestruction: {
    close()
    releaseSession()
  }

  Loader { id: popupLoader }

  Timer {
    id: trafficSample
    interval: 2000
    repeat: true
    running: root.mode === "ethernet" && !root.v2Presentation
    onTriggered: root.appendTrafficSample()
  }

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
      sourceComponent: !root.bar || !root.tokens ? null
        : root.bar.vertical ? verticalContent
        : root.displayMode === "icon" ? compactContent
        : root.displayMode === "text" ? textContent : fullContent
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

    Loader {
      sourceComponent: root.tokens.v2Shell !== true
        ? v1FullContent : v2FullContent
    }
  }

  Component {
    id: v1FullContent

    Row {
      spacing: 5

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "NET"
        color: root.mode === "none"
          ? Qt.rgba(root.v1Seal.r, root.v1Seal.g, root.v1Seal.b, 0.7)
          : Qt.rgba(root.v1Ink.r, root.v1Ink.g, root.v1Ink.b, 0.6)
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: 12
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      Canvas {
        id: v1TrafficChart
        visible: root.mode === "ethernet"
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? 36 : 0
        height: 14

        function paintSeries(context, values, tint, maximum,
            fillOpacity, strokeWidth) {
          if (!Array.isArray(values) || values.length < 2) return
          const points = []
          for (let index = 0; index < values.length; index++) {
            points.push({
              x: index * width / Math.max(1, root.trafficHistoryLimit - 1),
              y: height - (Math.max(0, Number(values[index]) || 0)
                / maximum) * height
            })
          }
          context.beginPath()
          context.moveTo(points[0].x, height)
          context.lineTo(points[0].x, points[0].y)
          for (let index = 1; index < points.length; index++) {
            const midpoint = (points[index - 1].x + points[index].x) / 2
            context.bezierCurveTo(midpoint, points[index - 1].y,
              midpoint, points[index].y, points[index].x, points[index].y)
          }
          context.lineTo(points[points.length - 1].x, height)
          context.closePath()
          context.fillStyle = Qt.rgba(tint.r, tint.g, tint.b, fillOpacity)
          context.fill()
          context.beginPath()
          context.moveTo(points[0].x, points[0].y)
          for (let index = 1; index < points.length; index++) {
            const midpoint = (points[index - 1].x + points[index].x) / 2
            context.bezierCurveTo(midpoint, points[index - 1].y,
              midpoint, points[index].y, points[index].x, points[index].y)
          }
          context.strokeStyle = tint
          context.lineWidth = strokeWidth
          context.lineCap = "round"
          context.lineJoin = "round"
          context.stroke()
        }

        onPaint: {
          const context = getContext("2d")
          context.clearRect(0, 0, width, height)
          let maximum = 1
          for (let index = 0; index < root.downloadHistory.length; index++)
            maximum = Math.max(maximum, Number(root.downloadHistory[index]) || 0)
          for (let index = 0; index < root.uploadHistory.length; index++)
            maximum = Math.max(maximum, Number(root.uploadHistory[index]) || 0)
          maximum *= 1.15
          paintSeries(context, root.downloadHistory,
            root.v1Seal, maximum, 0.12, 1.5)
          paintSeries(context, root.uploadHistory,
            root.v1Indigo, maximum, 0.10, 1.0)
        }

        Connections {
          target: root
          function onDownloadHistoryChanged() { v1TrafficChart.requestPaint() }
          function onUploadHistoryChanged() { v1TrafficChart.requestPaint() }
          function onV1SealChanged() { v1TrafficChart.requestPaint() }
          function onV1IndigoChanged() { v1TrafficChart.requestPaint() }
        }

        Component.onCompleted: requestPaint()
      }

      Column {
        visible: root.mode === "ethernet"
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          width: 54
          height: 11
          text: "↓" + root.v1Rate(root.downloadRate)
          color: root.v1Seal
          font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
        }

        Text {
          width: 54
          height: 11
          text: "↑" + root.v1Rate(root.uploadRate)
          color: root.v1Indigo
          font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
          font.pixelSize: 10
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
        }
      }

      IconText {
        visible: root.mode === "wifi"
        anchors.verticalCenter: parent.verticalCenter
        text: root.stateGlyph
        color: root.v1Ink
        font.pixelSize: 14
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.mode === "wifi"
        text: root.label
        color: root.v1Seal
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: 12
        font.letterSpacing: 1
        renderType: Text.NativeRendering
      }
    }
  }

  Component {
    id: v2FullContent

    Row {
      spacing: 4

      IconText {
        visible: root.mode === "wifi"
        anchors.verticalCenter: parent.verticalCenter
        text: root.stateGlyph
        color: root.widgetInk
        font.pixelSize: 15
        Behavior on color { ColorAnimation { duration: 160 } }
      }

      IconText {
        visible: root.mode !== "wifi"
        anchors.verticalCenter: parent.verticalCenter
        text: root.stateGlyph
        color: root.mode === "ethernet" ? root.widgetInk
          : Qt.rgba(root.widgetInk.r, root.widgetInk.g, root.widgetInk.b, 0.65)
        font.pixelSize: root.mode === "ethernet" ? 14 : 15
        Behavior on color { ColorAnimation { duration: 160 } }
      }

      BoundedLabel {
        visible: root.mode === "wifi"
        anchors.verticalCenter: parent.verticalCenter
        maximumWidth: 88
        text: root.label !== "" ? root.label : "Wi-Fi"
        color: root.widgetInk
        font.family: root.v2MonoFont
        font.pixelSize: 11
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }

      Item {
        visible: root.mode === "ethernet"
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? 16 : 0
        height: 20

        readonly property real downloadLevel: Math.min(1,
          Math.log(1 + root.downloadRate / 1024) / Math.log(1 + 100 * 1024))
        readonly property real uploadLevel: Math.min(1,
          Math.log(1 + root.uploadRate / 1024) / Math.log(1 + 100 * 1024))

        V2TrafficMeter {
          anchors.fill: parent
          rxLevel: parent.downloadLevel
          txLevel: parent.uploadLevel
          ink: root.widgetInk
        }
      }
    }
  }

  component BoundedLabel: Text {
    id: boundedLabel

    required property real maximumWidth

    width: visible ? Math.min(maximumWidth, labelMetrics.advanceWidth) : 0

    TextMetrics {
      id: labelMetrics
      font: boundedLabel.font
      text: boundedLabel.text
    }
  }

  component V2TrafficMeter: Item {
    required property real rxLevel
    required property real txLevel
    required property color ink
    width: 16
    height: 20

    Text {
      x: 0
      y: 0
      width: 8
      height: 8
      text: "RX"
      color: Qt.rgba(parent.ink.r, parent.ink.g, parent.ink.b, 0.72)
      font.family: root.v2MonoFont
      font.pixelSize: 7
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      renderType: Text.NativeRendering
      Behavior on color { ColorAnimation { duration: 160 } }
    }

    Column {
      x: 2
      y: 8
      spacing: 1
      Repeater {
        model: 4
        delegate: Rectangle {
          required property int index
          width: 4
          height: 2
          radius: 1
          color: parent.parent.rxLevel > index / 4
            ? parent.parent.ink
            : Qt.rgba(parent.parent.ink.r, parent.parent.ink.g,
                parent.parent.ink.b, 0.18)
          Behavior on color { ColorAnimation { duration: 160 } }
        }
      }
    }

    Column {
      x: 10
      y: 1
      spacing: 1
      Repeater {
        model: 4
        delegate: Rectangle {
          required property int index
          width: 4
          height: 2
          radius: 1
          color: parent.parent.txLevel > (3 - index) / 4
            ? parent.parent.ink
            : Qt.rgba(parent.parent.ink.r, parent.parent.ink.g,
                parent.parent.ink.b, 0.18)
          Behavior on color { ColorAnimation { duration: 160 } }
        }
      }
    }

    Text {
      x: 8
      y: 13
      width: 8
      height: 8
      text: "TX"
      color: Qt.rgba(parent.ink.r, parent.ink.g, parent.ink.b, 0.72)
      font.family: root.v2MonoFont
      font.pixelSize: 7
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      renderType: Text.NativeRendering
      Behavior on color { ColorAnimation { duration: 160 } }
    }
  }

  Component {
    id: compactContent

    IconText {
      text: root.stateGlyph
      color: root.v2Presentation ? (root.mode === "none"
          ? Qt.rgba(root.widgetInk.r, root.widgetInk.g, root.widgetInk.b, 0.65)
          : root.widgetInk)
        : root.mode === "none"
          ? Qt.rgba(root.v1Seal.r, root.v1Seal.g, root.v1Seal.b, 0.65)
          : root.v1Seal
      font.pixelSize: root.mode === "none" ? 15 : 14
    }
  }

  Component {
    id: textContent

    BoundedLabel {
      maximumWidth: Commons.Style.space(128)
      text: root.displayLabel
      color: root.widgetInk
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.tokens.labelSize
      font.letterSpacing: root.mode === "wifi" ? 1 : 0
      elide: Text.ElideRight
      maximumLineCount: 1
      renderType: Text.NativeRendering
    }
  }

  Component {
    id: verticalContent

    IconText {
      text: root.stateGlyph
      color: root.widgetInk
      opacity: root.mode === "none" ? 0.58 : 1
      font.pixelSize: root.mode === "none" ? 15 : 14
    }
  }
}
