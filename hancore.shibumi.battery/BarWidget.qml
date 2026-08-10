pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.battery"
  manageIpc: false
  HostTokens { id: hostTokens; bar: root.bar }
  property url panelSource: Qt.resolvedUrl("BatteryPanel.qml")
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
    detailOwner = wanted
    if (detailOwner) detailOwner.acquireBatteryDetails()
  }

  function syncPanelLoader() {
    if (!opened || !hasBattery) {
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

  function activate() { toggle() }

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
  onPowerServiceChanged: syncDetailLease()
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

    Item {
      id: batteryVisual
      anchors.centerIn: parent
      width: Commons.Style.space(19)
      height: Commons.Style.space(10)

      Rectangle {
        id: batteryBody
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(16)
        height: Commons.Style.space(9)
        radius: Commons.Style.space(2.5)
        color: "transparent"
        border.width: Commons.Style.space(1.2)
        border.color: gauge.color

        Rectangle {
          visible: gauge.charging
          anchors.fill: parent
          anchors.margins: Commons.Style.space(1.8)
          radius: Commons.Style.space(1.2)
          color: Qt.rgba(gauge.color.r, gauge.color.g, gauge.color.b, 0.28)
        }

        Rectangle {
          id: batteryFill
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: Commons.Style.space(1.8)
          width: Math.max(gauge.ratio > 0 ? Commons.Style.space(1.5) : 0,
            (parent.width - Commons.Style.space(3.6)) * Math.max(0, Math.min(1, gauge.ratio)))
          radius: Commons.Style.space(1.2)
          clip: true
          color: gauge.color
          Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

          Rectangle {
            visible: gauge.charging && !gauge.full
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Commons.Style.space(6)
            radius: parent.radius
            color: gauge.shimmerColor
            property real pos: 0
            x: (parent.width + width) * pos - width

            NumberAnimation on pos {
              running: gauge.visible && gauge.charging && !gauge.full
              from: 0
              to: 1
              duration: 1100
              easing.type: Easing.InOutSine
            }
          }
        }

        Canvas {
          id: chargingBolt
          visible: gauge.charging || gauge.full
          anchors.centerIn: parent
          width: Commons.Style.space(6)
          height: Commons.Style.space(8)

          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.beginPath()
            ctx.moveTo(width * 0.55, 0)
            ctx.lineTo(width * 0.12, height * 0.55)
            ctx.lineTo(width * 0.45, height * 0.55)
            ctx.lineTo(width * 0.38, height)
            ctx.lineTo(width * 0.88, height * 0.45)
            ctx.lineTo(width * 0.55, height * 0.45)
            ctx.closePath()
            ctx.fillStyle = gauge.detailColor
            ctx.fill()
          }

          Component.onCompleted: requestPaint()
          Connections {
            target: gauge
            function onDetailColorChanged() { chargingBolt.requestPaint() }
          }
        }
      }

      Rectangle {
        anchors.left: batteryBody.right
        anchors.leftMargin: -Commons.Style.space(0.5)
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(2.5)
        height: Commons.Style.space(5)
        radius: Commons.Style.space(1.2)
        color: gauge.color
      }
    }
  }
}
