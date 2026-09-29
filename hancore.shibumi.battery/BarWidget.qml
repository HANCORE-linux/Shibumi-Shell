pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../hancore.shibumi.state/runtime" as SuiteRuntime
import "../hancore.shibumi.state/lib/presentation" as Presentation

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.battery"
  manageIpc: false
  SuiteRuntime.HostShell { id: suiteShell; host: root.bar ? root.bar.shell : null }
  Presentation.HostTokens { id: hostTokens; bar: root.bar; serviceShell: suiteShell }
  property url panelSource: Qt.resolvedUrl("BatteryPanel.qml")
  property var powerServiceOverride: null

  readonly property var powerService: powerServiceOverride !== null ? powerServiceOverride
    : suiteShell.serviceFor("hancore.shibumi.power-state")
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
  readonly property color chargingDetailColor: v1CustomToneActive && tokens
    && typeof tokens.widgetFillColor === "function"
    ? tokens.widgetFillColor(settings)
    : bar ? bar.background : Commons.Color.background
  readonly property color chargingShimmerColor: v1CustomToneActive
    ? Qt.rgba(chargingDetailColor.r, chargingDetailColor.g,
        chargingDetailColor.b, chargingDetailColor.a * 0.18)
    : Qt.rgba(1, 1, 1, 0.18)
  readonly property string displayMode: String(
    setting("displayMode", setting("compact", false) ? "icon" : "full"))
  readonly property bool compact: displayMode === "icon"
  readonly property bool compactValueVisible: !!bar && !bar.vertical
    && (displayMode !== "icon" || tokens.v2Shell !== true)
  readonly property bool hasBattery: !!(powerService && powerService.hasBattery)
  readonly property int percent: powerService ? powerService.percent : 0
  readonly property bool charging: !!(powerService && powerService.charging)
  readonly property bool full: !!(powerService && powerService.fullyCharged)
  readonly property bool low: hasBattery && !charging && !full && percent <= 20
  readonly property string tooltipText: powerService
    ? powerService.batteryStatus + " · " + percent + "%"
      + (powerService.timeText ? " · " + powerService.timeText : "")
    : "Battery unavailable"
  property var detailOwner: null
  readonly property var interactionTarget: interaction
  readonly property var panelItem: panelLoader.item

  visible: hasBattery
  implicitWidth: visible ? (bar && bar.vertical ? bar.barSize : surface.implicitWidth) : 0
  implicitHeight: visible
    ? (bar && bar.vertical ? surface.implicitHeight : bar ? bar.barSize : 28) : 0

  function syncDetailLease() {
    var wanted = opened && hasBattery ? powerService : null
    if (wanted === detailOwner) return
    if (detailOwner) detailOwner.releaseBatteryDetails()
    detailOwner = wanted && wanted.acquireBatteryDetails() !== false ? wanted : null
  }

  function syncPanelLoader() {
    if (!opened || !hasBattery) {
      panelLoader.source = ""
      return
    }
    panelLoader.setSource(panelSource, {
      anchorItem: surface,
      bar: Qt.binding(function() { return root.bar }),
      ownerWidget: root,
      powerService: Qt.binding(function() { return root.powerService })
    })
  }

  function activate() {
    if (!hasBattery) return false
    toggle()
    return true
  }

  function openSystemMonitor() {
    if (!bar || typeof bar.run !== "function") return false
    bar.run("omarchy-launch-or-focus-tui btop")
    return true
  }

  onOpenedChanged: {
    syncDetailLease()
    syncPanelLoader()
  }
  onHasBatteryChanged: {
    if (!hasBattery && opened) close()
    syncDetailLease()
  }
  onPowerServiceChanged: {
    syncDetailLease()
    if (!powerService && opened) close()
    if (opened && !panelLoader.item) syncPanelLoader()
  }
  Component.onDestruction: {
    if (detailOwner) detailOwner.releaseBatteryDetails()
    detailOwner = null
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

    Presentation.PillSurface {
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
        : root.displayMode === "text" ? textContent
        : root.bar.vertical || root.displayMode === "icon" ? compactContent
        : root.tokens.v2Shell === true && root.displayMode === "full" ? compactContent : fullContent
    }

    MouseArea {
      id: interaction
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(surface, root.tooltipText)
      onExited: if (root.bar) root.bar.hideTooltip(surface)
      onClicked: {
        if (root.bar) root.bar.hideTooltip(surface)
        root.activate()
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
        text: "BAT"
        color: Qt.rgba(root.widgetInk.r, root.widgetInk.g,
          root.widgetInk.b, 0.68)
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }
      BatteryGauge {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        ratio: root.percent / 100
        charging: root.charging
        full: root.full
        low: root.low
        color: root.widgetInk
        detailColor: root.chargingDetailColor
        shimmerColor: root.chargingShimmerColor
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
    id: compactContent
    Row {
      spacing: root.tokens.compactGap
      BatteryGauge {
        visible: root.displayMode !== "text"
        anchors.verticalCenter: parent.verticalCenter
        ratio: root.percent / 100
        charging: root.charging
        full: root.full
        low: root.low
        color: root.widgetInk
        detailColor: root.chargingDetailColor
        shimmerColor: root.chargingShimmerColor
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
    id: textContent

    Text {
      text: root.percent + "%"
      color: root.widgetInk
      font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: root.tokens.labelSize
      renderType: Text.NativeRendering
    }
  }

  component BatteryGauge: Item {
    id: gauge
    required property real ratio
    required property bool charging
    required property bool full
    required property bool low
    required property color color
    required property color detailColor
    required property color shimmerColor

    width: Commons.Style.space(19)
    height: Commons.Style.space(10)
    opacity: low ? pulse : 1
    property real pulse: 1

    SequentialAnimation on pulse {
      running: gauge.visible && gauge.low
      loops: Animation.Infinite
      NumberAnimation { from: 1; to: 0.35; duration: 1100; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.35; to: 1; duration: 1100; easing.type: Easing.InOutSine }
    }

    Presentation.BarGlyph {
      anchors.fill: parent
      nativeText: batteryIcon(gauge.ratio * 100, gauge.charging, gauge.full)
      color: gauge.color
    }

    Presentation.BarGlyph {
      anchors.fill: parent
      visible: gauge.charging && !gauge.full
      nativeText: "\uF0E7"
      color: root.bar ? root.bar.foreground : Commons.Color.foreground
    }
  }
}
