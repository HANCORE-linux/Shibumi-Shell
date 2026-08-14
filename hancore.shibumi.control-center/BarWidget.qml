pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Ui as Ui
import "HostIdentity.js" as HostIdentity

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.control-center"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var tokens: bar && "visualTokens" in bar
    && bar.visualTokens ? bar.visualTokens : hostTokens
  readonly property color widgetInk: tokens
    && typeof tokens.widgetContentColor === "function"
    ? tokens.widgetContentColor(settings, bar ? bar.urgent : "white")
    : (bar ? bar.urgent : "white")
  readonly property string shellStyle: tokens
    && tokens.shellStyle !== undefined ? String(tokens.shellStyle) : "shibumi"
  readonly property bool customDecorated: !!(tokens
    && ((typeof tokens.widgetHasFill === "function"
          && tokens.widgetHasFill(settings))
      || (typeof tokens.widgetHasBorder === "function"
          && tokens.widgetHasBorder(settings))))
  readonly property bool surfaceDisabled: !!(tokens
    && typeof tokens.widgetColorMode === "function"
    && tokens.widgetColorMode(settings) === "none")
  readonly property bool stockOmarchyHost:
    HostIdentity.isStockOmarchyHost(bar)
  readonly property bool nativePillSurfaceVisible: !stockOmarchyHost
    && !!tokens && shellStyle === "shibumi"
  readonly property bool v1CustomFill: nativePillSurfaceVisible && !!(tokens
    && typeof tokens.widgetHasFill === "function"
    && tokens.widgetHasFill(settings))
  readonly property color v1FillColor: v1CustomFill
    && typeof tokens.widgetFillColor === "function"
    ? tokens.widgetFillColor(settings) : "transparent"
  readonly property real v1FillOpacity: v1CustomFill
    && typeof tokens.widgetSurfaceOpacity === "function"
    ? tokens.widgetSurfaceOpacity(settings) : 1
  readonly property color renderedPillFillColor: v1CustomFill
    ? Qt.rgba(v1FillColor.r, v1FillColor.g, v1FillColor.b,
        v1FillColor.a * v1FillOpacity)
    : tokens && tokens.pill !== undefined ? tokens.pill : "transparent"
  readonly property var stateService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor("hancore.shibumi.state") : null
  readonly property bool vertical: bar ? bar.vertical === true : false
  readonly property int barSize: bar ? Number(bar.barSize || 0) : 0
  readonly property bool panelLoaded: panelLoader.item !== null
  readonly property var panelItem: panelLoader.item
  readonly property bool v1TintedLauncherIconVisible:
    v1TintedLauncherIcon.visible
  readonly property bool animationActive: pointer.containsMouse
  readonly property var launcherConfig: stateService && stateService.config
    && stateService.config.launcher
    ? stateService.config.launcher
    : ({ mode: "text", text: "shibumi", icon: "omarchy" })
  readonly property bool iconMode: stockOmarchyHost
    || String(launcherConfig.mode || "text") === "icon"
  readonly property string effectiveLauncherText:
    String(launcherConfig.text || "shibumi")
  readonly property bool shibumiWordmark: !iconMode
    && effectiveLauncherText === "shibumi"
  readonly property bool archWordmark: !iconMode && effectiveLauncherText === "arch"
  readonly property bool hyprlandWordmark: !iconMode
    && effectiveLauncherText === "hyprland"
  readonly property bool omacomWordmark: !iconMode
    && effectiveLauncherText === "omacom"
  readonly property url wordmarkSource: omacomWordmark
    ? Qt.resolvedUrl("assets/omacom-text.png")
    : hyprlandWordmark
      ? Qt.resolvedUrl("assets/bob3.png")
      : Qt.resolvedUrl("assets/bob2.png")
  readonly property real wordmarkAspect: omacomWordmark ? 550 / 112
    : archWordmark ? 86 / 17 : hyprlandWordmark ? 948 / 154 : 656 / 192
  readonly property real logoHeight: iconMode ? 18
    : shibumiWordmark ? 14 : hyprlandWordmark ? 16
      : omacomWordmark ? 14 : archWordmark ? 17 : 20
  readonly property real logoPadding: iconMode ? 8
    : shibumiWordmark ? 12 : hyprlandWordmark ? 10
      : omacomWordmark ? 12 : archWordmark ? 8 : 12
  readonly property real archWordHeight: 13
  readonly property real archWordLogoWidth: 15
  readonly property real archWordLeftPad: 1
  readonly property real archWordRightPad: 3
  readonly property real archWordGap: 3
  readonly property real archWordJoinGap: 3
  readonly property real archWordArchWidth: Math.round(archWordHeight * 605 / 231)
  readonly property real archWordLinuxWidth: Math.round(archWordHeight * 549 / 230)
  readonly property real archWordmarkWidth: archWordLeftPad + archWordRightPad
    + archWordLogoWidth + archWordGap + archWordArchWidth + archWordJoinGap
    + archWordLinuxWidth
  readonly property real logoWidth: iconMode ? 16
    : shibumiWordmark ? Math.ceil(shibumiMetrics.advanceWidth)
      : archWordmark ? archWordmarkWidth : Math.round(logoHeight * wordmarkAspect)
  property url panelSource: Qt.resolvedUrl("ControlCenterPanel.qml")
  property var pluginUpdateServiceOverride: null
  readonly property var activePluginUpdateService:
    pluginUpdateServiceOverride || (hostShell
      && typeof hostShell.serviceFor === "function"
      ? hostShell.serviceFor("hancore.shibumi.control-center") : null)
  property real phase: 0
  property var registeredBar: null
  property string pendingPage: ""
  property url loadedPanelSource: ""

  HealthService { id: healthState }
  SwitchService { id: switchState }

  implicitWidth: vertical ? barSize : logoWidth + logoPadding
  implicitHeight: vertical ? logoWidth + logoPadding : barSize

  TextMetrics {
    id: shibumiMetrics
    text: "SHIBUMI"
    font.family: root.bar ? root.bar.fontFamily : "monospace"
    font.pixelSize: 11
    font.weight: Font.Medium
    font.letterSpacing: 1.2
  }

  function injectPanel(item) {
    if (!item) return
    if ("anchorItem" in item) item.anchorItem = pill
    if ("bar" in item) item.bar = root.bar
    if ("ownerWidget" in item) item.ownerWidget = root
    if ("stateService" in item) item.stateService = root.stateService
    if ("healthService" in item) item.healthService = healthState
    if ("switchService" in item) item.switchService = switchState
    if ("pluginUpdateService" in item)
      item.pluginUpdateService = activePluginUpdateService
  }

  function syncPanelLoader() {
    const source = String(panelSource || "")
    if (!opened || !stateService || !stateService.ready || source === "") {
      loadedPanelSource = ""
      panelLoader.source = ""
      return
    }
    if (String(loadedPanelSource) === source
        && (panelLoader.item || panelLoader.status === Loader.Loading)) {
      injectPanel(panelLoader.item)
      return
    }
    loadedPanelSource = panelSource
    panelLoader.setSource(panelSource, {
      anchorItem: pill,
      bar: root.bar,
      ownerWidget: root,
      stateService: root.stateService,
      healthService: healthState,
      switchService: switchState,
      pluginUpdateService: activePluginUpdateService
    })
  }

  onOpenedChanged: {
    if (opened) healthState.ensureFresh(300)
    syncPanelLoader()
  }
  onStateServiceChanged: syncPanelLoader()
  onPanelSourceChanged: syncPanelLoader()
  onPanelLoadedChanged: {
    if (!panelLoaded || pendingPage === "") return
    const requested = pendingPage
    pendingPage = ""
    if (panelItem && typeof panelItem.showSettingsPage === "function")
      panelItem.showSettingsPage(requested)
  }

  function openPage(page) {
    const requested = String(page || "")
    if (requested === "") return false
    pendingPage = requested
    open()
    if (panelLoaded) {
      pendingPage = ""
      return panelItem.showSettingsPage(requested)
    }
    return true
  }

  function close() {
    if (bar && typeof bar.cancelWidgetRestore === "function") {
      const window = root.QsWindow ? root.QsWindow.window : null
      const outputName = window && window.screen
        ? String(window.screen.name || "") : ""
      bar.cancelWidgetRestore(moduleName, root, outputName)
    }
    controller.hide()
  }

  function triggerPress(mouseButton) {
    if (mouseButton !== Qt.LeftButton) return false
    if (bar) bar.hideTooltip(root)
    root.toggle()
    return true
  }

  function syncClickRegistration() {
    if (registeredBar && typeof registeredBar.unregisterClickTarget === "function")
      registeredBar.unregisterClickTarget(root)
    registeredBar = bar
    if (registeredBar && typeof registeredBar.registerClickTarget === "function")
      registeredBar.registerClickTarget(root)
  }

  function iconGlyph(id) {
    if (id === "omarchy") return String.fromCodePoint(0xE900)
    if (id === "hyprland") return ""
    if (id === "arch") return ""
    if (id === "grid") return ""
    if (id === "spark") return ""
    if (id === "power") return ""
    if (id === "dragon") return "⻯"
    if (id === "mark") return ""
    if (id === "nix") return ""
    if (id === "branch") return ""
    if (id === "rebel") return ""
    return String.fromCodePoint(0xE900)
  }

  function iconFont(id) { return id === "omarchy" ? "omarchy" : bar.fontFamily }
  function iconSize(id) {
    if (id === "omarchy") return 15
    if (id === "arch") return 17
    if (id === "dragon") return 16
    return 16
  }
  function iconXOffset(id) {
    if (id === "omarchy" || id === "mark") return 0.5
    if (id === "arch") return 1
    if (id === "grid") return -1
    return 0
  }
  function iconYOffset(id) {
    return id === "mark" ? 0.5 : 0
  }

  onBarChanged: {
    syncClickRegistration()
    syncPanelLoader()
  }
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    if (registeredBar && typeof registeredBar.unregisterClickTarget === "function")
      registeredBar.unregisterClickTarget(root)
  }

  NumberAnimation on phase {
    from: 0
    to: 2 * Math.PI
    duration: 2600
    loops: Animation.Infinite
    running: root.animationActive
  }

  RectangularShadow {
    anchors.fill: pill
    radius: pill.radius
    visible: root.nativePillSurfaceVisible
      && root.tokens.shadowEnabled === true
    blur: 8
    spread: 0
    offset: Qt.vector2d(0, root.bar && root.bar.position === "bottom" ? -1 : 1)
    color: root.tokens ? root.tokens.pillShadow : "transparent"
    z: -1
  }

  Rectangle {
    id: pill
    anchors.centerIn: parent
    width: root.logoWidth + root.logoPadding
    height: root.tokens ? root.tokens.pillHeight : 24
    radius: root.tokens ? root.tokens.pillRadius : 12
    color: root.nativePillSurfaceVisible
      ? root.renderedPillFillColor : "transparent"
    border.color: root.nativePillSurfaceVisible
      ? root.tokens.pillBorder : "transparent"
    border.width: root.nativePillSurfaceVisible
      ? root.tokens.pillBorderWidth : 0
    clip: true

    Canvas {
      id: wave
      anchors.fill: parent
      opacity: root.animationActive ? 0.55 : 0
      visible: opacity > 0.001

      Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }

      onPaint: {
        const context = getContext("2d")
        context.clearRect(0, 0, width, height)
        const centerY = height / 2
        const amplitude = 3
        const frequency = 4 * Math.PI / width

        function drawWave(offset, alpha) {
          context.beginPath()
          for (let x = 0; x <= width; x += 2) {
            const y = centerY + Math.sin(x * frequency + root.phase + offset)
              * amplitude
            if (x === 0) context.moveTo(x, y)
            else context.lineTo(x, y)
          }
          context.strokeStyle = Qt.rgba(root.widgetInk.r, root.widgetInk.g,
            root.widgetInk.b, alpha)
          context.lineWidth = 1.5
          context.lineCap = "round"
          context.stroke()
        }

        drawWave(0, 0.45)
        drawWave(Math.PI, 0.22)
      }

      Connections {
        target: root
        function onPhaseChanged() { wave.requestPaint() }
      }
      Connections {
        target: root.bar
        function onUrgentChanged() { wave.requestPaint() }
      }
      Component.onCompleted: requestPaint()
    }
  }

  Item {
    visible: !root.iconMode
    anchors.centerIn: parent
    width: root.logoWidth
    height: root.logoHeight

    Item {
      visible: root.archWordmark
      anchors.fill: parent

      Text {
        id: archLogo
        anchors.left: parent.left
        anchors.leftMargin: root.archWordLeftPad
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 0.5
        width: root.archWordLogoWidth
        horizontalAlignment: Text.AlignHCenter
        text: ""
        color: root.widgetInk
        renderType: Text.QtRendering
        font.family: root.bar ? root.bar.fontFamily : "sans-serif"
        font.pixelSize: 15
      }

      FlatTintedImage {
        anchors.left: archLogo.right
        anchors.leftMargin: root.archWordGap
        anchors.verticalCenter: parent.verticalCenter
        width: root.archWordArchWidth
        height: root.archWordHeight
        source: Qt.resolvedUrl("assets/arch-header-arch.png")
        tint: root.widgetInk
      }

      FlatTintedImage {
        anchors.right: parent.right
        anchors.rightMargin: root.archWordRightPad
        anchors.verticalCenter: parent.verticalCenter
        width: root.archWordLinuxWidth
        height: root.archWordHeight
        source: Qt.resolvedUrl("assets/arch-header-linux.png")
        tint: root.widgetInk
      }
    }

    Text {
      visible: root.shibumiWordmark
      anchors.centerIn: parent
      text: "SHIBUMI"
      color: root.widgetInk
      renderType: Text.NativeRendering
      font.family: root.bar ? root.bar.fontFamily : "monospace"
      font.pixelSize: 11
      font.weight: Font.Medium
      font.letterSpacing: 1.2
    }

    FlatTintedImage {
      visible: !root.archWordmark && !root.shibumiWordmark
      anchors.fill: parent
      source: root.wordmarkSource
      tint: root.widgetInk
    }
  }

  Item {
    visible: root.iconMode
    anchors.centerIn: parent
    width: root.stockOmarchyHost ? 18 : 16
    height: root.tokens ? root.tokens.pillHeight : 24

    Text {
      visible: !root.stockOmarchyHost
        && root.launcherConfig.icon !== "shibumi"
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.iconXOffset(root.launcherConfig.icon)
      anchors.verticalCenterOffset: root.iconYOffset(root.launcherConfig.icon)
      text: root.iconGlyph(root.launcherConfig.icon)
      color: root.widgetInk
      renderType: Text.QtRendering
      font.family: root.iconFont(root.launcherConfig.icon)
      font.pixelSize: root.iconSize(root.launcherConfig.icon)
    }

    Image {
      visible: root.stockOmarchyHost
        || (root.launcherConfig.icon === "shibumi" && !root.v1CustomFill)
      anchors.centerIn: parent
      width: 18
      height: 18
      source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")
      fillMode: Image.PreserveAspectFit
      sourceSize.width: 24
      sourceSize.height: 24
      smooth: true
      mipmap: true
    }

    FlatTintedImage {
      id: v1TintedLauncherIcon
      visible: !root.stockOmarchyHost
        && root.launcherConfig.icon === "shibumi"
        && root.v1CustomFill
      anchors.centerIn: parent
      width: 18
      height: 18
      source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")
      tint: root.widgetInk
    }
  }

  Loader {
    id: panelLoader

    onLoaded: root.injectPanel(item)
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, "Shibumi settings")
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) { root.triggerPress(mouse.button) }
  }
}
