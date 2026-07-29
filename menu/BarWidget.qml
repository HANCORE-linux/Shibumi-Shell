pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Ui as Ui

Ui.BarWidget {
  id: root

  moduleName: "hancore.shibumi.bar"

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property var menuService: hostShell
    && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor(moduleName) : null
  readonly property bool menuActive: menuService
    ? menuService.menuOpen === true : false
  readonly property bool animationActive: pointer.containsMouse || menuActive
  readonly property var launcherConfig: bar && bar.shibumiConfig
    && bar.shibumiConfig.menu && bar.shibumiConfig.menu.launcher
    ? bar.shibumiConfig.menu.launcher
    : ({ mode: "text", text: "shibumi", icon: "omarchy" })
  readonly property bool iconMode: launcherConfig.mode === "icon"
  readonly property bool shibumiWordmark: !iconMode
    && launcherConfig.text === "shibumi"
  readonly property bool archWordmark: !iconMode && launcherConfig.text === "arch"
  readonly property bool hyprlandWordmark: !iconMode && launcherConfig.text === "hyprland"
  readonly property bool omacomWordmark: !iconMode && launcherConfig.text === "omacom"
  readonly property url wordmarkSource: omacomWordmark
    ? Qt.resolvedUrl("../assets/omacom-text.png")
    : hyprlandWordmark
      ? Qt.resolvedUrl("../assets/bob3.png")
      : Qt.resolvedUrl("../assets/bob2.png")
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
  property real phase: 0
  property var registeredBar: null

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

  function invocationScreenName() {
    if (!bar || typeof bar.targetWindow !== "function") return ""
    const window = bar.targetWindow(root)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  function summonMenu() {
    if (!hostShell || typeof hostShell.toggle !== "function") return false
    hostShell.toggle(moduleName, JSON.stringify({
      menu: "root",
      screen: invocationScreenName()
    }))
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

  onBarChanged: syncClickRegistration()
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
    visible: root.tokens && root.tokens.shadowEnabled
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
    color: root.tokens ? root.tokens.pill : "transparent"
    border.color: root.tokens ? root.tokens.pillBorder : "transparent"
    border.width: root.tokens ? root.tokens.pillBorderWidth : 0
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
          context.strokeStyle = Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
            root.bar.urgent.b, alpha)
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
        color: root.bar.urgent
        renderType: Text.QtRendering
        font.family: root.bar.fontFamily
        font.pixelSize: 15
      }

      FlatTintedImage {
        anchors.left: archLogo.right
        anchors.leftMargin: root.archWordGap
        anchors.verticalCenter: parent.verticalCenter
        width: root.archWordArchWidth
        height: root.archWordHeight
        source: Qt.resolvedUrl("../assets/arch-header-arch.png")
        tint: root.bar.urgent
      }

      FlatTintedImage {
        anchors.right: parent.right
        anchors.rightMargin: root.archWordRightPad
        anchors.verticalCenter: parent.verticalCenter
        width: root.archWordLinuxWidth
        height: root.archWordHeight
        source: Qt.resolvedUrl("../assets/arch-header-linux.png")
        tint: root.bar.urgent
      }
    }

    Text {
      visible: root.shibumiWordmark
      anchors.centerIn: parent
      text: "SHIBUMI"
      color: root.bar ? root.bar.urgent : "white"
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
      tint: root.bar.urgent
    }
  }

  Item {
    visible: root.iconMode
    anchors.centerIn: parent
    width: 16
    height: root.tokens ? root.tokens.pillHeight : 24

    Text {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.iconXOffset(root.launcherConfig.icon)
      anchors.verticalCenterOffset: root.iconYOffset(root.launcherConfig.icon)
      text: root.iconGlyph(root.launcherConfig.icon)
      color: root.bar.urgent
      renderType: Text.QtRendering
      font.family: root.iconFont(root.launcherConfig.icon)
      font.pixelSize: root.iconSize(root.launcherConfig.icon)
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, "Shibumi menu")
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: {
      if (root.bar) root.bar.hideTooltip(root)
      root.summonMenu()
    }
  }
}
