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
  property int hoveredShibumiActionIndex: -1
  property int hoveredSystemActionIndex: -1
  property string pendingAction: ""
  readonly property int confirmationButtonCount:
    pendingAction === "reboot" || pendingAction === "shutdown" ? 2 : 0
  readonly property string confirmationActionLabel:
    pendingAction === "reboot" ? "Reboot now"
      : pendingAction === "shutdown" ? "Shutdown now" : ""
  readonly property bool ready: barRepeater.count === 3
    && actionCount === (returnOnly ? 0 : 8)
  readonly property int barOptionCount: barRepeater.count
  readonly property int actionCount: shibumiActionRepeater.count
    + systemActionRepeater.count
  readonly property bool returnOnly: controller.stockOmarchyHost === true
  readonly property string shellStyle: String(
    controller.barPresentation.shellStyle || "shibumi")
  readonly property string v2ShellStyle:
    ["full", "fit", "dock", "notch"].indexOf(shellStyle) >= 0
      ? shellStyle : ["full", "fit", "dock", "notch"].indexOf(
        String(controller.barPresentation.v2ShellStyle || "")) >= 0
        ? String(controller.barPresentation.v2ShellStyle) : "full"
  readonly property bool v2Active: controller.v2LayoutActive === true
  readonly property string activeBarId:
    controller.activeShell === "omarchy" ? "omarchy" : v2Active ? "v2" : "v1"
  readonly property string rememberedBarId:
    shellStyle === "shibumi" ? "v1" : "v2"
  readonly property bool switchBusy: controller.switchBusy === true
  readonly property var barOptions: [
    {
      id: "v1",
      label: "V1",
      detail: "Shibumi split bar",
      active: root.activeBarId === "v1"
    },
    {
      id: "v2",
      label: "V2",
      detail: "Shibumi " + root.v2ShellStyle + " bar",
      active: root.activeBarId === "v2"
    },
    {
      id: "omarchy",
      label: "Omarchy Bar",
      detail: "Stock Omarchy bar",
      active: root.activeBarId === "omarchy"
    }
  ]
  readonly property var shibumiActions: [
    {
      id: "add-plugin", label: "+ Add plugin", detail: "From Git",
      glyph: "add_circle"
    },
    {
      id: "reload", label: "Reload Shibumi", detail: "Reload shell",
      glyph: "refresh"
    },
    {
      id: "bars", label: "Bars", detail: "Configure",
      glyph: "align_vertical_center"
    },
    {
      id: "pickers", label: "Pickers", detail: "Media & images",
      glyph: "collections"
    }
  ]
  readonly property var systemActions: [
    {
      id: "screensaver", label: "Screensaver", detail: "Start now",
      glyph: "slideshow"
    },
    {
      id: "lock", label: "Lock", detail: "Lock session",
      glyph: "lock"
    },
    {
      id: "reboot", label: "Reboot", detail: "System",
      glyph: "restart_alt", destructive: true
    },
    {
      id: "shutdown", label: "Shutdown", detail: "Power off",
      glyph: "power_settings_new", destructive: true
    }
  ]
  readonly property int activeBarIndex:
    activeBarId === "omarchy" ? 2 : activeBarId === "v2" ? 1 : 0
  readonly property var previewBar: hoveredBarIndex >= 0
    && hoveredBarIndex < barOptions.length
    ? barOptions[hoveredBarIndex] : barOptions[activeBarIndex]
  readonly property bool previewing: hoveredBarIndex >= 0
  readonly property string previewRoute: previewBar.id === "v2"
    ? "bar-v2-" + v2ShellStyle : "bar-" + String(previewBar.id || "v1")
  readonly property string previewDetail: previewBar.id === "v2"
    ? "V2 · " + v2ShellStyle.charAt(0).toUpperCase()
      + v2ShellStyle.slice(1) : String(previewBar.label || "V1")
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
    return active ? Commons.Util.alpha(activeStateColor, 0.09)
      : controller.controlFillColor
  }

  function surfaceBorder(active, hovered) {
    if (active) return Commons.Util.alpha(activeStateColor, 0.52)
    return hovered ? controller.controlHoverBorderColor
      : controller.controlBorderColor
  }

  function barStatus(option) {
    if (switchBusy && String(controller.switchTarget || "") === option.id)
      return "SWITCHING"
    if (option.active) return "ACTIVE"
    if (returnOnly && rememberedBarId === option.id) return "RETURN TARGET"
    return ""
  }

  function activateBar(target) {
    const requested = String(target || "")
    if (switchBusy || requested === activeBarId) return false
    if (requested === "omarchy")
      return controller.switchShell("omarchy")
    if (requested !== "v1" && requested !== "v2") return false
    if (controller.activeShell === "omarchy")
      return controller.switchShell(requested)
    return controller.setBarVariant(requested)
  }

  function activateAction(actionId) {
    const requested = String(actionId || "")
    if (returnOnly) return false
    if (requested === "reboot" || requested === "shutdown") {
      if (pendingAction === requested) return confirmPendingAction()
      pendingAction = requested
      confirmationReset.restart()
      return true
    }
    cancelPendingAction()
    if (requested === "bars") return controller.showSettingsPage("bars")
    if (requested === "pickers") return controller.showSettingsPage("pickers")
    if (requested === "add-plugin") return controller.openPluginInstaller()
    if (requested === "reload") return controller.reloadShell()
    return controller.runQuickSystemAction(requested)
  }

  function cancelPendingAction() {
    if (pendingAction === "") return false
    pendingAction = ""
    confirmationReset.stop()
    return true
  }

  function confirmPendingAction() {
    const requested = pendingAction
    if (requested !== "reboot" && requested !== "shutdown") return false
    pendingAction = ""
    confirmationReset.stop()
    return controller.runQuickSystemAction(requested)
  }

  component ActionTile: Rectangle {
    id: actionTile

    required property var modelData
    required property string routeSide
    required property int routeIndex
    readonly property bool confirmation:
      root.pendingAction === String(modelData.id || "")
    readonly property bool primary: modelData.primary === true

    height: Commons.Style.space(56)
    radius: root.controller.controlRadius
    color: actionPointer.containsMouse
      ? root.controller.controlHoverFillColor
      : primary ? Commons.Util.alpha(root.activeStateColor, 0.08)
        : root.controller.controlFillColor
    border.width: root.controller.controlBorderWidth
    border.color: confirmation
      ? root.controller.accentColor("color01")
      : primary ? Commons.Util.alpha(root.activeStateColor, 0.62)
        : actionPointer.containsMouse
          ? root.controller.controlHoverBorderColor
          : root.controller.controlBorderColor
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: confirmation
      ? "Confirm " + modelData.label : modelData.label

    Row {
      id: actionContent
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(9)
      anchors.rightMargin: Commons.Style.space(8)
      spacing: Commons.Style.space(8)
      visible: !actionTile.confirmation

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(18)
        text: actionTile.modelData.glyph
        color: actionTile.confirmation
          ? root.controller.accentColor("color01")
          : actionTile.primary ? root.activeStateColor : root.foreground
        opacity: 0.88
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
        font.weight: Font.Medium
        fill: 0
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x
        spacing: 0

        Text {
          width: parent.width
          text: actionTile.confirmation
            ? "Confirm " + actionTile.modelData.label
            : actionTile.modelData.label
          color: actionTile.confirmation
            ? root.controller.accentColor("color01") : root.foreground
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: root.valueFontSize
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: actionTile.confirmation
            ? "Click again" : actionTile.modelData.detail
          color: root.foreground
          opacity: 0.42
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: root.detailFontSize
          font.weight: root.detailFontWeight
        }
      }
    }

    Row {
      anchors.fill: parent
      anchors.margins: Commons.Style.space(5)
      spacing: Commons.Style.space(5)
      visible: actionTile.confirmation

      Rectangle {
        id: cancelConfirmation
        width: Math.round((parent.width - parent.spacing) * 0.38)
        height: parent.height
        radius: Math.max(2, root.controller.controlRadius - 2)
        color: cancelConfirmationPointer.containsMouse
          ? root.controller.controlHoverFillColor
          : root.controller.controlFillColor
        border.width: root.controller.controlBorderWidth
        border.color: cancelConfirmationPointer.containsMouse
          ? root.controller.controlHoverBorderColor
          : root.controller.controlBorderColor

        Text {
          anchors.centerIn: parent
          text: "Cancel"
          color: root.foreground
          font.family: root.controller.marketFont
          font.pixelSize: root.detailFontSize
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: cancelConfirmationPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cancelPendingAction()
        }
      }

      Rectangle {
        id: executeConfirmation
        width: parent.width - cancelConfirmation.width - parent.spacing
        height: parent.height
        radius: Math.max(2, root.controller.controlRadius - 2)
        color: executeConfirmationPointer.containsMouse
          ? Commons.Util.alpha(root.controller.accentColor("color01"), 0.2)
          : Commons.Util.alpha(root.controller.accentColor("color01"), 0.11)
        border.width: root.controller.controlBorderWidth
        border.color: root.controller.accentColor("color01")

        Text {
          anchors.centerIn: parent
          text: root.confirmationActionLabel
          color: root.controller.accentColor("color01")
          font.family: root.controller.marketFont
          font.pixelSize: root.detailFontSize
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: executeConfirmationPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.confirmPendingAction()
        }
      }
    }

    MouseArea {
      id: actionPointer
      anchors.fill: parent
      enabled: !actionTile.confirmation
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        if (actionTile.routeSide === "shibumi")
          root.hoveredShibumiActionIndex = actionTile.routeIndex
        else
          root.hoveredSystemActionIndex = actionTile.routeIndex
      }
      onExited: {
        if (actionTile.routeSide === "shibumi"
            && root.hoveredShibumiActionIndex === actionTile.routeIndex)
          root.hoveredShibumiActionIndex = -1
        if (actionTile.routeSide === "system"
            && root.hoveredSystemActionIndex === actionTile.routeIndex)
          root.hoveredSystemActionIndex = -1
      }
      onClicked: root.activateAction(actionTile.modelData.id)
    }

    Keys.onReturnPressed: root.activateAction(modelData.id)
    Keys.onEnterPressed: root.activateAction(modelData.id)
    Keys.onSpacePressed: root.activateAction(modelData.id)
  }

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  Item {
    id: barLanding
    property real routeGap: Commons.Style.space(34)
    property real portOffset: Commons.Style.space(6)
    width: parent.width
    height: Commons.Style.space(130)

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
          ? root.activeStateColor
          : preview ? Commons.Util.alpha(root.activeStateColor, 0.54)
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
        context.fillStyle = root.activeStateColor
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
        model: root.barOptions

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
          activeFocusOnTab: true
          Accessible.role: Accessible.RadioButton
          Accessible.name: barOption.modelData.label
          Accessible.description: barOption.modelData.detail
          Accessible.checked: barOption.modelData.active

          function activate() {
            root.activateBar(modelData.id)
          }

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Commons.Style.space(11)
            anchors.rightMargin: Commons.Style.space(10)
            spacing: 0

            Row {
              width: parent.width

              Text {
                width: parent.width - statusLabel.width
                text: barOption.modelData.label
                color: root.foreground
                opacity: barOption.modelData.active ? 1 : 0.76
                elide: Text.ElideRight
                font.family: root.controller.marketFont
                font.pixelSize: root.valueFontSize
                font.weight: root.valueFontWeight
              }

              Text {
                id: statusLabel
                text: root.barStatus(barOption.modelData)
                color: root.activeStateColor
                opacity: text === "" ? 0 : 0.82
                font.family: root.controller.marketFont
                font.pixelSize: root.labelFontSize
                font.weight: Font.DemiBold
                font.letterSpacing: 0.7
              }
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
            cursorShape: root.switchBusy || barOption.modelData.active
              ? Qt.ArrowCursor : Qt.PointingHandCursor
            onEntered: root.hoveredBarIndex = barOption.index
            onExited: {
              if (root.hoveredBarIndex === barOption.index)
                root.hoveredBarIndex = -1
            }
            onClicked: barOption.activate()
          }

          Keys.onReturnPressed: barOption.activate()
          Keys.onEnterPressed: barOption.activate()
          Keys.onSpacePressed: barOption.activate()
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
      pageKey: root.previewRoute
      label: root.switchBusy ? "SWITCHING"
        : root.previewing ? "BAR PREVIEW" : "ACTIVE BAR"
      detail: root.switchBusy
        ? "Target · " + String(root.controller.switchTarget || "").toUpperCase()
        : root.previewDetail
      foreground: root.foreground
      accent: root.activeStateColor
      interactive: !root.returnOnly && !root.previewing
      onClicked: root.controller.showSettingsPage("bars")
    }
  }

  Rectangle {
    width: parent.width
    height: visible ? Commons.Style.space(42) : 0
    visible: root.controller.switchPhase === "error"
    radius: root.controller.controlRadius
    color: Commons.Util.alpha(root.controller.accentColor("color01"), 0.08)
    border.width: 1
    border.color: Commons.Util.alpha(
      root.controller.accentColor("color01"), 0.48)

    Text {
      anchors.fill: parent
      anchors.margins: Commons.Style.space(9)
      text: "Switch failed · " + String(root.controller.switchDetail
        || "The previous bar was restored.")
      color: root.controller.accentColor("color01")
      elide: Text.ElideRight
      verticalAlignment: Text.AlignVCenter
      font.family: root.controller.marketFont
      font.pixelSize: root.detailFontSize
      font.weight: Font.Medium
    }
  }

  Item {
    id: actionDeck
    width: parent.width
    height: visible ? Commons.Style.space(155) : 0
    visible: !root.returnOnly

    Column {
      id: shibumiActionColumn
      anchors.left: parent.left
      width: Math.min(Commons.Style.space(270), actionDeck.width * 0.42)
      height: parent.height
      spacing: Commons.Style.space(5)

      Repeater {
        id: shibumiActionRepeater
        model: root.returnOnly ? [] : root.shibumiActions

        delegate: ActionTile {
          required property int index
          width: parent.width
          height: (shibumiActionColumn.height
            - shibumiActionColumn.spacing * 3) / 4
          routeSide: "shibumi"
          routeIndex: index
        }
      }
    }

    Canvas {
      id: actionConnector
      x: shibumiActionColumn.width
      width: Commons.Style.space(34)
      height: parent.height
      z: 2
      antialiasing: true

      onPaint: {
        const context = getContext("2d")
        context.reset()
        context.clearRect(0, 0, width, height)
        const rowHeight = (height - Commons.Style.space(5) * 3) / 4
        const activeColor = root.activeStateColor
        const idleColor = Commons.Util.alpha(root.foreground, 0.18)
        const centerX = width / 2
        const firstY = rowHeight / 2
        const lastY = height - rowHeight / 2

        context.beginPath()
        context.moveTo(centerX, firstY)
        context.lineTo(centerX, lastY)
        context.strokeStyle = idleColor
        context.lineWidth = 1
        context.stroke()

        for (let index = 0; index < 4; index++) {
          const y = rowHeight / 2 + index * (rowHeight + Commons.Style.space(5))
          const leftHovered = root.hoveredShibumiActionIndex === index
          const rightHovered = root.hoveredSystemActionIndex === index

          if (leftHovered) {
            context.beginPath()
            context.moveTo(0, y)
            context.bezierCurveTo(width * 0.25, y, width * 0.32, y,
              centerX, y)
            context.strokeStyle = activeColor
            context.lineWidth = 1.35
            context.stroke()
            context.beginPath()
            context.arc(0, y, 3.4, 0, Math.PI * 2)
            context.fillStyle = activeColor
            context.fill()
          }

          if (rightHovered) {
            context.beginPath()
            context.moveTo(centerX, y)
            context.bezierCurveTo(width * 0.68, y, width * 0.75, y,
              width, y)
            context.strokeStyle = activeColor
            context.lineWidth = 1.35
            context.stroke()
            context.beginPath()
            context.arc(width, y, 3.4, 0, Math.PI * 2)
            context.fillStyle = activeColor
            context.fill()
          }

          context.beginPath()
          context.arc(centerX, y,
            leftHovered || rightHovered ? 3.2 : 2.7, 0, Math.PI * 2)
          context.fillStyle = leftHovered || rightHovered
            ? activeColor : idleColor
          context.fill()
        }
      }

      Connections {
        target: root
        function onForegroundChanged() { actionConnector.requestPaint() }
        function onActiveStateColorChanged() { actionConnector.requestPaint() }
        function onHoveredShibumiActionIndexChanged() {
          actionConnector.requestPaint()
        }
        function onHoveredSystemActionIndexChanged() {
          actionConnector.requestPaint()
        }
      }

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    Column {
      id: systemActionColumn
      anchors.right: parent.right
      width: actionDeck.width - shibumiActionColumn.width
        - actionConnector.width
      height: parent.height
      spacing: Commons.Style.space(5)

      Repeater {
        id: systemActionRepeater
        model: root.returnOnly ? [] : root.systemActions

        delegate: ActionTile {
          required property int index
          width: parent.width
          height: (systemActionColumn.height
            - systemActionColumn.spacing * 3) / 4
          routeSide: "system"
          routeIndex: index
        }
      }
    }
  }

  Timer {
    id: confirmationReset
    interval: 5000
    onTriggered: root.cancelPendingAction()
  }
}
