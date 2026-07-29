pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Panel {
  id: root

  moduleName: "hancore.shibumi.battery"
  manageIpc: false
  property url panelSource: Qt.resolvedUrl("BatteryPanel.qml")

  readonly property var powerService: bar ? bar.powerService : null
  readonly property var tokens: bar ? bar.visualTokens : null
  readonly property bool compact: setting("compact", false) === true
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
        : root.compact || root.bar.vertical ? compactContent : fullContent
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
        anchors.verticalCenter: parent.verticalCenter
        text: "BAT"
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
          root.bar.foreground.b, 0.6) : Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        font.letterSpacing: 0.5
        renderType: Text.NativeRendering
      }
      BatteryGauge {
        anchors.verticalCenter: parent.verticalCenter
        ratio: root.percent / 100
        charging: root.charging
        full: root.full
        low: root.low
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        paper: root.bar ? root.bar.background : Commons.Color.background
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.percent + "%"
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
      BatteryGauge {
        anchors.verticalCenter: parent.verticalCenter
        ratio: root.percent / 100
        charging: root.charging
        full: root.full
        low: root.low
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        paper: root.bar ? root.bar.background : Commons.Color.background
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.bar.vertical
        text: root.percent + "%"
        color: root.bar ? root.bar.urgent : Commons.Color.accent
        font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: root.tokens.labelSize
        renderType: Text.NativeRendering
      }
    }
  }

  component BatteryGauge: Item {
    id: gauge
    required property real ratio
    required property bool charging
    required property bool full
    required property bool low
    required property color color
    required property color paper

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
            color: Qt.rgba(1, 1, 1, 0.18)
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
            ctx.fillStyle = gauge.paper
            ctx.fill()
          }

          Component.onCompleted: requestPaint()
          Connections {
            target: gauge
            function onPaperChanged() { chargingBolt.requestPaint() }
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
