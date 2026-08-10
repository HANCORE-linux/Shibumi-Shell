pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.brightness"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }
  property url popupSource: Qt.resolvedUrl("BrightnessPanel.qml")
  property var monitorServiceOverride: null

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
  readonly property bool compactValueVisible: !!bar && !bar.vertical
    && (displayMode !== "icon" || tokens.v2Shell !== true)
  readonly property var monitorService: monitorServiceOverride
    || (bar && bar.shell && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("hancore.shibumi.brightness") : null)
  readonly property bool monitorReady: monitorService && monitorService.ready
  readonly property bool brightnessAvailable: monitorReady
    && monitorService.brightnessAvailable
  readonly property bool internalDisplay: monitorReady
    && hasInternalDisplay(monitorService.displays)
  readonly property int percent: monitorReady
    ? monitorService.brightnessPercent : 0
  readonly property int displayCount: monitorReady
    && Array.isArray(monitorService.displays) ? monitorService.displays.length : 0
  readonly property string displayGlyph: Quickshell.screens.length > 1
    ? "󰍺" : "󰍹"
  readonly property string tooltipText: !monitorReady ? "Display unavailable"
    : brightnessAvailable ? "Brightness · " + percent + "%"
    : "Display controls"
  readonly property var panelItem: popupLoader.item
  readonly property bool panelLoaded: panelItem !== null
  readonly property var interactionTarget: actionButton

  visible: monitorReady
  implicitWidth: visible ? (bar && bar.vertical ? bar.barSize : surface.implicitWidth) : 0
  implicitHeight: visible
    ? (bar && bar.vertical ? surface.implicitHeight : bar ? bar.barSize : 28) : 0

  function setting(name, fallback) {
    const value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function hasInternalDisplay(displays) {
    const rows = Array.isArray(displays) ? displays : []
    for (let i = 0; i < rows.length; i++) {
      if (/^(eDP|LVDS|DSI)-/.test(String(rows[i] && rows[i].name || "")))
        return true
    }
    return false
  }

  function childPanelWidget(pluginId) {
    const id = String(pluginId || "")
    return id === moduleName || id === "omarchy.monitor" ? root : null
  }

  function ownsPanelWidget(owner) { return owner === root }

  function adjustBrightness(delta) {
    return monitorService && monitorService.setBrightness(percent + Number(delta || 0))
  }

  function syncPanelLoader() {
    popupLoader.source = ""
    if (!opened || !monitorReady || !String(popupSource)) return
    monitorService.refresh()
    popupLoader.setSource(popupSource, {
      anchorItem: surface,
      bar: root.bar,
      ownerWidget: root,
      monitorService: monitorService
    })
  }

  onOpenedChanged: syncPanelLoader()
  onMonitorReadyChanged: syncPanelLoader()
  onPopupSourceChanged: syncPanelLoader()
  Component.onDestruction: close()

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
      sourceComponent: !root.bar || !root.tokens ? null
        : root.internalDisplay
        ? (root.bar.vertical || root.displayMode === "icon"
          ? compactBrightnessContent
          : root.tokens.v2Shell === true && root.displayMode === "full"
            ? compactBrightnessContent
          : root.displayMode === "text"
            ? textBrightnessContent : fullBrightnessContent)
        : displayContent
    }

    Ui.WidgetButton {
      id: actionButton
      anchors.fill: parent
      bar: root.monitorReady ? root.bar : null
      text: " "
      keepSpace: true
      horizontalMargin: 0
      verticalPadding: 0
      fixedWidth: surface.width
      fixedHeight: surface.height
      tooltipText: root.tooltipText
      onPressed: function(_button) { root.toggle() }
      onWheelMoved: function(delta) {
        if (root.brightnessAvailable)
          root.adjustBrightness(delta > 0 ? 5 : -5)
      }
    }
  }

  Component {
    id: fullBrightnessContent

    Row {
      spacing: root.tokens.contentGap

      Text {
        visible: root.displayMode === "full"
        anchors.verticalCenter: parent.verticalCenter
        text: "BRI"
        color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
          root.widgetInk.b, 0.68)
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }

      SunIndicator {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        ratio: root.percent / 100
        color: root.widgetInk
      }

      Text {
        visible: root.displayMode !== "icon"
        anchors.verticalCenter: parent.verticalCenter
        text: root.percent + "%"
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }

  Component {
    id: compactBrightnessContent

    Row {
      spacing: root.tokens.compactGap

      SunIndicator {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        ratio: root.percent / 100
        color: root.widgetInk
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.compactValueVisible
        text: root.percent + "%"
        color: root.widgetInk
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }

  Component {
    id: textBrightnessContent

    Text {
      text: root.percent + "%"
      color: root.widgetInk
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.tokens.labelSize
      renderType: Text.NativeRendering
    }
  }

  Component {
    id: displayContent

    Text {
      text: root.displayGlyph
      color: root.widgetInk
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.tokens.iconSize
      renderType: Text.NativeRendering
    }
  }

  component SunIndicator: Item {
    id: sun

    required property real ratio
    required property color color

    width: Commons.Style.space(13)
    height: Commons.Style.space(13)

    Rectangle {
      anchors.centerIn: parent
      width: Commons.Style.space(6.5)
      height: width
      radius: width / 2
      color: sun.color
      Behavior on color { ColorAnimation { duration: 200 } }
    }

    Repeater {
      model: 8
      delegate: Item {
        required property int index
        anchors.fill: parent
        rotation: index * 45

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: Commons.Style.space(1.5)
          height: Commons.Style.space(2 + 1.4 * sun.ratio)
          radius: width / 2
          color: sun.color
          opacity: 0.35 + 0.65 * sun.ratio
        }
      }
    }
  }
}
