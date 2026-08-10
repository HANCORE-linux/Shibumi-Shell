pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.power-profile"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }
  property url panelSource: Qt.resolvedUrl("PowerProfilePanel.qml")
  property var powerServiceOverride: null

  readonly property var powerService: powerServiceOverride
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("hancore.shibumi.power-state") : null)
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
  readonly property bool profileAvailable: !!(powerService && powerService.profileAvailable)
  readonly property string profile: powerService ? powerService.activeProfile : ""
  readonly property string shortName: powerService
    ? powerService.activeProfileShortName : "---"
  readonly property string profileLabel: powerService
    ? powerService.activeProfileLabel : "Power profiles unavailable"
  readonly property string profileIcon: profile === "power-saver" ? "\uF06C"
    : profile === "performance" ? "\uF0E7" : "\uF24E"
  readonly property var interactionTarget: interaction
  readonly property bool panelLoaded: panelLoader.item !== null
  readonly property var panelItem: panelLoader.item
  property var profileOwner: null

  visible: profileAvailable
  implicitWidth: visible ? (bar && bar.vertical ? bar.barSize : surface.implicitWidth) : 0
  implicitHeight: visible
    ? (bar && bar.vertical ? surface.implicitHeight : bar ? bar.barSize : 28) : 0

  function childPanelWidget(pluginId) {
    return String(pluginId || "") === "omarchy.power" ? root : null
  }

  function syncProfileLease() {
    if (powerService === profileOwner) return
    if (profileOwner) profileOwner.releaseProfiles()
    profileOwner = powerService
    if (profileOwner) profileOwner.acquireProfiles()
  }

  function syncPanelLoader() {
    if (!opened || !profileAvailable) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(panelSource, {
      anchorItem: surface,
      bar: root.bar,
      ownerWidget: root,
      powerService: root.powerService
    })
  }

  function activate(button) {
    if (!powerService) return false
    if (button === Qt.RightButton) return powerService.cycleProfile()
    toggle()
    return true
  }

  onOpenedChanged: syncPanelLoader()
  onProfileAvailableChanged: if (!profileAvailable && opened) close()
  onPowerServiceChanged: syncProfileLease()
  Component.onCompleted: syncProfileLease()
  Component.onDestruction: {
    if (profileOwner) profileOwner.releaseProfiles()
    profileOwner = null
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

    PillSurface {
      tokenSource: root.tokens
      settings: root.settings
      v1AppearanceEnabled: true
      anchors.fill: parent
      anchors.topMargin: root.tokens
        ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
      anchors.bottomMargin: root.tokens
        ? Math.round((parent.height - root.tokens.pillHeight) / 2) : 0
      bar: root.bar
    }

    Loader {
      id: content
      anchors.centerIn: parent
      sourceComponent: !root.bar || !root.tokens ? null
        : root.bar.vertical || root.displayMode === "icon" ? compactContent
        : root.tokens.v2Shell === true && root.displayMode === "full" ? compactContent
        : root.displayMode === "text" ? textContent : fullContent
    }

    MouseArea {
      id: interaction
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(surface, root.profileLabel)
      onExited: if (root.bar) root.bar.hideTooltip(surface)
      onClicked: function(event) {
        if (root.bar) root.bar.hideTooltip(surface)
        root.activate(event.button)
      }
    }
  }

  Loader { id: panelLoader }

  Component {
    id: fullContent
    Row {
      spacing: root.tokens.contentGap
      Text {
        visible: root.displayMode === "full"
        anchors.verticalCenter: parent.verticalCenter
        text: "PWR"
        color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
          root.widgetInk.b, 0.68)
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.shortName
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }

  Component {
    id: compactContent
    Text {
      text: root.profileIcon
      color: root.widgetInk
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.profile === "balanced" ? 13 : 14
      renderType: Text.QtRendering
    }
  }

  Component {
    id: textContent

    Text {
      text: root.shortName
      color: root.widgetInk
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.tokens.labelSize
      renderType: Text.NativeRendering
    }
  }
}
