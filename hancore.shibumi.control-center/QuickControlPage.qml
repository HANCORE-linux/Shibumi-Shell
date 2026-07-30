pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool motionActive: false
  property int hoveredBarIndex: -1
  readonly property bool ready: barRepeater.count === 3
    && toggleRepeater.count === 5
  readonly property string shellStyle: String(
    controller.barPresentation.shellStyle || "shibumi")
  readonly property bool v2Active: controller.v2LayoutActive === true
  readonly property int activeBarIndex:
    controller.activeShell === "omarchy" ? 2 : v2Active ? 1 : 0
  readonly property color activeStateColor:
    typeof controller.paletteColor === "function"
      ? controller.paletteColor("color04") : accent
  readonly property real labelFontSize:
    Commons.Style.font.caption * uiScale
  readonly property real valueFontSize:
    Commons.Style.font.bodySmall * uiScale
  readonly property real detailFontSize:
    Commons.Style.font.caption * uiScale
  readonly property int labelFontWeight: Font.DemiBold
  readonly property int valueFontWeight: Font.DemiBold
  readonly property int detailFontWeight: Font.Normal

  function surfaceFill(active, hovered) {
    if (hovered) return controller.controlHoverFillColor
    return active ? Commons.Util.alpha(accent, 0.09)
      : controller.controlFillColor
  }

  function surfaceBorder(active, hovered) {
    if (active) return Commons.Util.alpha(accent, 0.52)
    return hovered ? controller.controlHoverBorderColor
      : controller.controlBorderColor
  }

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  SectionLabel { text: "BAR" }

  Item {
    id: barLanding
    property real routeGap: Commons.Style.space(34)
    property real portOffset: Commons.Style.space(6)
    width: parent.width
    height: Commons.Style.space(142)

    Canvas {
      id: routeCanvas
      anchors.fill: parent
      z: 2
      antialiasing: true

      function drawRoute(context, index, emphasized) {
        const buttonHeight = (barButtonColumn.height
          - barButtonColumn.spacing * 2) / 3
        const startX = barButtonColumn.width + barLanding.portOffset
        const startY = index * (buttonHeight + barButtonColumn.spacing)
          + buttonHeight / 2
        const endX = motionStage.x
        const endY = motionStage.height / 2
        const preview = index === root.hoveredBarIndex
        const routeColor = emphasized
          ? root.accent
          : preview ? Commons.Util.alpha(root.accent, 0.54)
            : Commons.Util.alpha(root.foreground, 0.16)

        context.beginPath()
        context.moveTo(startX, startY)
        context.bezierCurveTo(
          startX + (endX - startX) * 0.55, startY,
          endX - (endX - startX) * 0.55, endY,
          endX, endY)
        context.strokeStyle = routeColor
        context.lineWidth = emphasized ? 1.7 : preview ? 1.25 : 1
        context.stroke()

        context.beginPath()
        context.arc(startX, startY, 3.6, 0, Math.PI * 2)
        context.fillStyle = routeColor
        context.fill()
      }

      onPaint: {
        const context = getContext("2d")
        context.reset()
        context.clearRect(0, 0, width, height)
        for (let index = 0; index < 3; index++) {
          if (index !== root.activeBarIndex)
            drawRoute(context, index, false)
        }
        drawRoute(context, root.activeBarIndex, true)
        context.beginPath()
        context.arc(motionStage.x, motionStage.height / 2, 4.4,
          0, Math.PI * 2)
        context.fillStyle = root.accent
        context.fill()
      }

      Connections {
        target: root
        function onActiveBarIndexChanged() { routeCanvas.requestPaint() }
        function onHoveredBarIndexChanged() { routeCanvas.requestPaint() }
        function onForegroundChanged() { routeCanvas.requestPaint() }
        function onAccentChanged() { routeCanvas.requestPaint() }
      }

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    Column {
      id: barButtonColumn
      z: 1
      anchors.left: parent.left
      width: Math.min(Commons.Style.space(270), parent.width * 0.42)
      height: parent.height
      spacing: Commons.Style.space(7)

      Repeater {
        id: barRepeater
        model: [
          {
            id: "v1",
            label: "V1",
            detail: "Shibumi split bar",
            active: root.controller.activeShell === "shibumi"
              && !root.v2Active
          },
          {
            id: "v2",
            label: "V2",
            detail: "Shibumi full bar",
            active: root.controller.activeShell === "shibumi"
              && root.v2Active
          },
          {
            id: "omarchy",
            label: "Omarchy",
            detail: "Stock bar · guarded handoff",
            active: root.controller.activeShell === "omarchy"
          }
        ]

        delegate: Rectangle {
          id: barOption
          required property var modelData
          required property int index
          readonly property color optionFill: modelData.active
            ? root.surfaceFill(true, optionPointer.containsMouse)
            : root.surfaceFill(false, optionPointer.containsMouse)
          width: parent.width
          height: (barButtonColumn.height
            - barButtonColumn.spacing * 2) / 3
          radius: root.controller.controlRadius
          color: barOption.optionFill
          border.width: root.controller.controlBorderWidth
          border.color: root.surfaceBorder(
            barOption.modelData.active, optionPointer.containsMouse)

          function activate() {
            if (modelData.id === "omarchy"
                || root.controller.activeShell !== "shibumi") {
              root.controller.showSettingsPage("bars")
              return
            }
            if (modelData.active) {
              root.controller.showSettingsPage("bars")
              return
            }
            root.controller.setBarPresentation("shellStyle",
              modelData.id === "v1" ? "shibumi" : "full")
          }

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Commons.Style.space(11)
            anchors.rightMargin: Commons.Style.space(10)
            spacing: 0

            Text {
              text: barOption.modelData.label
              color: root.foreground
              opacity: barOption.modelData.active ? 1 : 0.76
              font.family: root.controller.marketFont
              font.pixelSize: root.valueFontSize
              font.weight: root.valueFontWeight
            }

            Text {
              width: parent.width
              text: barOption.modelData.detail
              color: root.foreground
              opacity: 0.42
              elide: Text.ElideRight
              font.family: root.controller.marketFont
              font.pixelSize: root.detailFontSize
              font.weight: root.detailFontWeight
            }
          }

          MouseArea {
            id: optionPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hoveredBarIndex = barOption.index
            onExited: {
              if (root.hoveredBarIndex === barOption.index)
                root.hoveredBarIndex = -1
            }
            onClicked: barOption.activate()
          }
        }
      }
    }

    PageMotionStage {
      id: motionStage
      z: 1
      anchors.right: parent.right
      width: parent.width - barButtonColumn.width - barLanding.routeGap
      height: parent.height
      controller: root.controller
      active: root.motionActive
      pageKey: "quick"
      label: "ACTIVE BAR"
      detail: root.controller.activeShell === "omarchy"
        ? "Omarchy"
        : root.v2Active ? "Shibumi · V2" : "Shibumi · V1"
      foreground: root.foreground
      accent: root.accent
      interactive: true
      onClicked: root.controller.showSettingsPage("bars")
    }
  }

  Text {
    width: parent.width
    text: "V1 ⇄ V2 applies immediately. Omarchy opens the guarded "
      + "snapshot → apply → verify handoff."
    color: root.foreground
    opacity: 0.42
    wrapMode: Text.WordWrap
    font.family: root.controller.marketFont
    font.pixelSize: root.detailFontSize
    font.weight: root.detailFontWeight
  }

  SectionLabel { text: "BAR WIDGETS" }

  Row {
    id: toggleRow
    width: parent.width
    height: Commons.Style.space(76)
    spacing: Commons.Style.space(6)

    Repeater {
      id: toggleRepeater
      model: [
        {
          pluginId: "hancore.shibumi.network",
          label: "WI-FI",
          value: root.controller.quickWidgetVisible(
            "hancore.shibumi.network") ? "Shown" : "Hidden",
          detail: root.controller.quickNetworkLabel,
          active: root.controller.quickWidgetVisible(
            "hancore.shibumi.network"),
          available: root.controller.quickWidgetAvailable(
            "hancore.shibumi.network")
        },
        {
          pluginId: "hancore.shibumi.bluetooth",
          label: "BLUETOOTH",
          value: root.controller.quickWidgetVisible(
            "hancore.shibumi.bluetooth") ? "Shown" : "Hidden",
          detail: root.controller.quickBluetoothLabel,
          active: root.controller.quickWidgetVisible(
            "hancore.shibumi.bluetooth"),
          available: root.controller.quickWidgetAvailable(
            "hancore.shibumi.bluetooth")
        },
        {
          pluginId: "hancore.shibumi.audio",
          label: "VOLUME",
          value: root.controller.quickWidgetVisible(
            "hancore.shibumi.audio") ? "Shown" : "Hidden",
          detail: root.controller.quickAudioLabel,
          active: root.controller.quickWidgetVisible(
            "hancore.shibumi.audio"),
          available: root.controller.quickWidgetAvailable(
            "hancore.shibumi.audio")
        },
        {
          pluginId: "hancore.shibumi.brightness",
          label: "BRIGHTNESS",
          value: root.controller.quickWidgetVisible(
            "hancore.shibumi.brightness") ? "Shown" : "Hidden",
          detail: root.controller.quickBrightnessLabel,
          active: root.controller.quickWidgetVisible(
            "hancore.shibumi.brightness"),
          available: root.controller.quickWidgetAvailable(
            "hancore.shibumi.brightness")
        },
        {
          pluginId: "hancore.shibumi.power-profile",
          label: "PROFILE",
          value: root.controller.quickWidgetVisible(
            "hancore.shibumi.power-profile") ? "Shown" : "Hidden",
          detail: root.controller.quickProfileLabel,
          active: root.controller.quickWidgetVisible(
            "hancore.shibumi.power-profile"),
          available: root.controller.quickWidgetAvailable(
            "hancore.shibumi.power-profile")
        }
      ]

      delegate: Rectangle {
        id: quickTile
        required property var modelData
        width: (toggleRow.width - toggleRow.spacing * 4) / 5
        height: parent.height
        radius: root.controller.controlRadius
        color: root.surfaceFill(
          quickTile.modelData.active, tilePointer.containsMouse)
        opacity: quickTile.modelData.available ? 1 : 0.46
        border.width: root.controller.controlBorderWidth
        border.color: root.surfaceBorder(
          quickTile.modelData.active, tilePointer.containsMouse)

        Column {
          anchors.fill: parent
          anchors.margins: Commons.Style.space(8)
          spacing: Commons.Style.space(3)

          Row {
            width: parent.width

            Text {
              text: quickTile.modelData.label
              color: root.foreground
              opacity: 0.54
              font.family: root.controller.marketFont
              font.pixelSize: root.labelFontSize
              font.weight: root.labelFontWeight
              font.letterSpacing: 0.8
            }

            Item {
              width: parent.width - x - stateDot.width
              height: 1
            }

            Rectangle {
              id: stateDot
              anchors.verticalCenter: parent.verticalCenter
              width: Commons.Style.space(6)
              height: width
              radius: width / 2
              color: quickTile.modelData.active
                ? root.activeStateColor : root.controller.dividerColor
            }
          }

          Text {
            width: parent.width
            text: quickTile.modelData.value
            color: root.foreground
            elide: Text.ElideRight
            font.family: root.controller.marketFont
            font.pixelSize: root.valueFontSize
            font.weight: root.valueFontWeight
          }

          Text {
            width: parent.width
            text: quickTile.modelData.available
              ? quickTile.modelData.detail : "unavailable"
            color: root.foreground
            opacity: 0.42
            elide: Text.ElideRight
            font.family: root.controller.marketFont
            font.pixelSize: root.detailFontSize
            font.weight: root.detailFontWeight
          }
        }

        MouseArea {
          id: tilePointer
          anchors.fill: parent
          enabled: quickTile.modelData.available
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.controller.toggleQuickWidget(
            quickTile.modelData.pluginId)
        }
      }
    }
  }

  Row {
    width: parent.width
    height: Commons.Style.space(32)
    spacing: Commons.Style.space(8)

    CompactSettingChoice {
      width: (parent.width - parent.spacing) / 2
      controller: root.controller
      label: "+ Add widget"
      primary: true
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      controlHeight: parent.height
      fontSize: root.valueFontSize
      textWeight: root.valueFontWeight
      onClicked: root.controller.openWidgetPicker()
    }

    CompactSettingChoice {
      width: (parent.width - parent.spacing) / 2
      controller: root.controller
      label: "Reload Shibumi"
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      controlHeight: parent.height
      fontSize: root.valueFontSize
      textWeight: root.valueFontWeight
      onClicked: root.controller.reloadShell()
    }
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.46
    font.family: root.controller.marketFont
    font.pixelSize: root.labelFontSize
    font.weight: root.labelFontWeight
    font.letterSpacing: 1.2
  }
}
