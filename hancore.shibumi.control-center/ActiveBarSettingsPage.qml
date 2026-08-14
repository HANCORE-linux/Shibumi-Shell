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
  property bool motionDetailOpen: false

  readonly property bool shibumiActive:
    controller.activeShell === "shibumi"
  readonly property bool v2Active:
    shibumiActive && controller.v2LayoutActive === true
  readonly property string activeLabel: !shibumiActive
    ? "OMARCHY" : v2Active ? "V2" : "V1"
  readonly property string activeStyle: String(
    controller.barPresentation.shellStyle || "shibumi")
  readonly property string activeDetail: !shibumiActive
    ? "Stock Omarchy bar"
    : motionDetailOpen && !v2Active
      ? "Nine direct previews for V1 animated gaps"
    : v2Active
      ? activeStyle.charAt(0).toUpperCase() + activeStyle.slice(1)
        + " · slots and dividers"
      : "Split islands, slots and layout"
  readonly property string activeVariant: v2Active ? "v2" : "v1"
  readonly property bool activeLayoutProtected: v2Active
    ? controller.v2LayoutProtected === true
    : controller.v1LayoutProtected === true
  readonly property var shellStyleOptions: [
    {
      value: "shibumi", label: "V1 · Islands",
      detail: "Split rounded groups"
    },
    {
      value: "full", label: "V2 · Full",
      detail: "Edge to edge"
    },
    {
      value: "fit", label: "V2 · Fit",
      detail: "Inset rounded frame"
    },
    {
      value: "dock", label: "V2 · Dock",
      detail: "Open desktop edge"
    },
    {
      value: "notch", label: "V2 · Notch",
      detail: "Flowing shoulders"
    }
  ]
  readonly property var visibleShellStyleOptions: v2Active
    ? shellStyleOptions.slice(1) : [shellStyleOptions[0]]
  readonly property int surfaceEffectOptionCount:
    barSurfaceSettings.effectOptions.length
  readonly property int surfaceEffectPreviewCount:
    barSurfaceSettings.previewEffectOptionCount
  readonly property int surfaceRadiusOptionCount:
    barSurfaceSettings.radiusOptions.length
  readonly property int splitActionPreviewCount:
    v1SplitChoiceRow.visible ? 2 : 0
  readonly property int layoutActionCount:
    shibumiActive && mainSettingsVisible ? 3 : 0
  readonly property real layoutActionControlWidth: v2Active
    ? v2EditAction.width : v1EditAction.width
  readonly property bool layoutActionLabelsFit: v2Active
    ? v2EditAction.labelFits && v2LockToggle.labelFits
      && v2RestoreAction.labelFits
    : v1EditAction.labelFits && v1LockToggle.labelFits
      && v1RestoreAction.labelFits
  readonly property bool childRouteAvailable:
    shibumiActive && !v2Active
  readonly property string childRouteLabel: "Gap Animations"
  readonly property bool mainSettingsVisible:
    !motionDetailOpen || v2Active
  readonly property var reactorOptions: [
    { value: 0, label: "Off" },
    { value: 1, label: "Stream" },
    { value: 5, label: "Stream 2" },
    { value: 7, label: "Reactor" },
    { value: 2, label: "Surge" },
    { value: 6, label: "Surge 2" },
    { value: 8, label: "Quotes" },
    { value: 3, label: "Bolt" },
    { value: 4, label: "Bolt 2" }
  ]
  readonly property bool ready:
    shellStyleRepeater.count === visibleShellStyleOptions.length
    && reactorRepeater.count === reactorOptions.length
    && barSurfaceSettings.ready && barAccentSettings.ready

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  function toggleActiveLayoutProtection() {
    return shibumiActive
      && controller.setLayoutProtection(
        activeVariant, !activeLayoutProtected)
  }

  Rectangle {
    width: parent.width
    height: Commons.Style.space(62)
    radius: root.controller.controlRadius
    color: Commons.Util.alpha(root.accent, 0.09)
    border.width: root.controller.controlBorderWidth
    border.color: Commons.Util.alpha(root.accent, 0.52)

    Column {
      anchors.left: parent.left
      anchors.right: activeState.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Commons.Style.space(12)
      anchors.rightMargin: Commons.Style.space(12)
      spacing: Commons.Style.space(3)

      Text {
        text: root.activeLabel + " ACTIVE"
        color: root.foreground
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.space(20) * root.uiScale
        font.weight: Font.DemiBold
      }

      Text {
        width: parent.width
        text: root.activeDetail
        color: root.foreground
        opacity: 0.48
        elide: Text.ElideRight
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }

    Text {
      id: activeState
      anchors.right: parent.right
      anchors.rightMargin: Commons.Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "●  LIVE"
      color: root.accent
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.DemiBold
      font.letterSpacing: 0.8
    }
  }

  Row {
    id: primaryControlRow
    width: parent.width
    visible: root.mainSettingsVisible
    spacing: Commons.Style.space(8)

    Column {
      width: root.shibumiActive
        ? (primaryControlRow.width - primaryControlRow.spacing) / 2
        : primaryControlRow.width
      spacing: Commons.Style.space(8)

      SectionLabel {
        text: root.v2Active ? "POSITION" : "POSITION & LAYOUT"
      }

      Row {
        id: v1SplitChoiceRow
        width: parent.width
        height: visible ? Commons.Style.space(52) : 0
        spacing: Commons.Style.space(8)
        visible: !root.v2Active

        SplitLayoutChoice {
          width: (parent.width - parent.spacing) / 2
          controller: root.controller
          label: "Split all"
          detail: "Create separate islands for every V1 group"
          splitAll: true
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          onClicked: root.controller.setAllSplits(true)
        }

        SplitLayoutChoice {
          width: (parent.width - parent.spacing) / 2
          controller: root.controller
          label: "Merge all"
          detail: "Join all V1 groups into one island"
          splitAll: false
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          onClicked: root.controller.setAllSplits(false)
        }
      }

      Row {
        id: positionChoiceRow
        width: parent.width
        height: Commons.Style.space(30)
        spacing: Commons.Style.space(8)

        CompactSettingChoice {
          width: (parent.width - parent.spacing) / 2
          controller: root.controller
          label: "Top"
          selected: root.controller.barPosition !== "bottom"
          controlHeight: positionChoiceRow.height
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          onClicked: root.controller.setBarPosition("top")
        }

        CompactSettingChoice {
          width: (parent.width - parent.spacing) / 2
          controller: root.controller
          label: "Bottom"
          selected: root.controller.barPosition === "bottom"
          controlHeight: positionChoiceRow.height
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          onClicked: root.controller.setBarPosition("bottom")
        }
      }
    }

    BarSurfaceSettings {
      id: barSurfaceSettings
      width: (primaryControlRow.width - primaryControlRow.spacing) / 2
      visible: root.shibumiActive
      controller: root.controller
      v2Active: root.v2Active
      showSurface: true
      showAccent: false
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
    }
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    visible: root.shibumiActive && root.mainSettingsVisible

    SectionLabel { text: "BAR FORM" }

    Flow {
      id: styleFlow
      width: parent.width
      spacing: Commons.Style.space(7)

      Repeater {
        id: shellStyleRepeater
        model: root.visibleShellStyleOptions

        delegate: BarStylePreviewCard {
          required property var modelData
          width: root.v2Active
            ? (styleFlow.width - styleFlow.spacing) / 2
            : styleFlow.width
          controller: root.controller
          styleValue: modelData.value
          label: modelData.label
          detail: modelData.detail
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          onChosen: function(styleValue) {
            root.controller.setBarPresentation("shellStyle", styleValue)
          }
        }
      }
    }
  }

  BarSurfaceSettings {
    id: barAccentSettings
    width: parent.width
    visible: root.shibumiActive && root.mainSettingsVisible
    controller: root.controller
    v2Active: root.v2Active
    showSurface: false
    showAccent: true
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    visible: root.shibumiActive && !root.v2Active
      && root.mainSettingsVisible

    SectionLabel { text: "V1 LAYOUT" }

    Row {
      width: parent.width
      height: Commons.Style.space(50)
      spacing: Commons.Style.space(7)

      ActionCard {
        id: v1EditAction
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        glyph: "view_column"
        label: "Edit slots"
        detail: "Add, move and drag"
        foreground: root.foreground
        accent: root.accent
        onClicked: root.controller.beginBarEditing()
      }

      LayoutProtectionToggle {
        id: v1LockToggle
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: "Lock V1 layout"
        detail: root.activeLayoutProtected
          ? "Edit slots overrides"
          : "Direct splits on"
        accessibleDescription: root.activeLayoutProtected
          ? "Locked; use Edit slots to change splits"
          : "Direct V1 split changes are allowed"
        selected: root.activeLayoutProtected
        foreground: root.foreground
        accent: root.accent
        onClicked: root.toggleActiveLayoutProtection()
      }

      ActionCard {
        id: v1RestoreAction
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        glyph: "restart_alt"
        label: "Restore layout"
        detail: "Reset slots and splits"
        foreground: root.foreground
        accent: root.accent
        onClicked: root.controller.resetBarLayout()
      }
    }
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    visible: root.v2Active && root.mainSettingsVisible

    SectionLabel { text: "V2 LAYOUT" }

    Row {
      width: parent.width
      height: Commons.Style.space(50)
      spacing: Commons.Style.space(7)

      ActionCard {
        id: v2EditAction
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        glyph: "splitscreen"
        label: "Edit layout"
        detail: "Add slots and dividers"
        foreground: root.foreground
        accent: root.accent
        onClicked: root.controller.beginBarEditing()
      }

      LayoutProtectionToggle {
        id: v2LockToggle
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: "Lock V2 layout"
        detail: root.activeLayoutProtected
          ? "Edit layout overrides"
          : "Direct dividers on"
        accessibleDescription: root.activeLayoutProtected
          ? "Locked; use Edit layout to change dividers"
          : "Direct V2 divider changes are allowed"
        selected: root.activeLayoutProtected
        foreground: root.foreground
        accent: root.accent
        onClicked: root.toggleActiveLayoutProtection()
      }

      ActionCard {
        id: v2RestoreAction
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        glyph: "restart_alt"
        label: "Restore layout"
        detail: "Reset slots and dividers"
        foreground: root.foreground
        accent: root.accent
        onClicked: root.controller.resetBarLayout()
      }
    }
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    visible: root.motionDetailOpen && root.shibumiActive && !root.v2Active

    SectionLabel { text: "GAP ANIMATIONS" }

    Text {
      width: parent.width
      text: "Choose one V1 gap renderer directly. Only the selected or "
        + "hovered preview moves; Reactor and Quotes respond to live events."
      color: root.foreground
      opacity: 0.48
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }

    Grid {
      id: reactorGrid
      width: parent.width
      columns: 3
      columnSpacing: Commons.Style.space(7)
      rowSpacing: Commons.Style.space(7)

      Repeater {
        id: reactorRepeater
        model: root.reactorOptions

        delegate: GapAnimationChoice {
          required property var modelData
          width: (reactorGrid.width - reactorGrid.columnSpacing * 2) / 3
          controller: root.controller
          mode: modelData.value
          label: modelData.label
          selected: root.controller.reactorMode === modelData.value
          motionEnabled: root.motionActive
          foreground: root.foreground
          accent: root.accent
          onClicked: root.controller.setReactorMode(modelData.value)
        }
      }
    }
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.54
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.DemiBold
    font.letterSpacing: 1
  }

  component GapAnimationChoice: Rectangle {
    id: gapChoice

    required property var controller
    property int mode: 0
    property string label: ""
    property bool selected: false
    property bool motionEnabled: false
    property color foreground: "white"
    property color accent: "white"
    readonly property bool previewRunning:
      motionEnabled && (selected || previewPointer.containsMouse)
    signal clicked()

    height: Commons.Style.space(82)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label + " gap animation"
    Accessible.description: selected ? "Selected" : "Not selected"
    radius: controller.controlRadius
    color: selected || previewPointer.containsMouse
      ? controller.controlHoverFillColor : controller.controlFillColor
    border.width: selected || activeFocus
      ? Math.max(1, controller.controlBorderWidth)
      : controller.controlBorderWidth
    border.color: selected ? accent : activeFocus
      ? foreground : previewPointer.containsMouse
        ? controller.controlHoverBorderColor : controller.controlBorderColor

    Canvas {
      id: previewCanvas
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Commons.Style.space(8)
      height: Commons.Style.space(42)
      renderStrategy: Canvas.Threaded

      function repaint() { requestPaint() }

      onPaint: {
        const context = getContext("2d")
        context.reset()
        const cy = height / 2
        const leftEdge = width * 0.37
        const rightEdge = width * 0.63
        const phase = gapChoice.previewRunning
          ? (Date.now() % 2600) / 2600 : 0.56
        const pulse = 0.55 + 0.45 * Math.sin(phase * Math.PI * 2)

        context.fillStyle = gapChoice.controller.marketPanelRaised
        context.fillRect(0, cy - 7, leftEdge, 14)
        context.fillRect(rightEdge, cy - 7, width - rightEdge, 14)

        context.strokeStyle = gapChoice.accent
        context.fillStyle = gapChoice.foreground
        context.lineCap = "round"
        context.lineJoin = "round"

        if (gapChoice.mode === 0) {
          context.globalAlpha = 0.25
          context.lineWidth = 1
          context.beginPath()
          context.moveTo(leftEdge + 5, cy)
          context.lineTo(rightEdge - 5, cy)
          context.stroke()
        } else if (gapChoice.mode === 1 || gapChoice.mode === 5) {
          const travel = gapChoice.mode === 1
            ? phase : Math.min(1, Math.max(0, (phase - 0.12) / 0.72))
          const x = leftEdge + 4 + travel * (rightEdge - leftEdge - 8)
          context.globalAlpha = 0.38
          context.lineWidth = gapChoice.mode === 1 ? 1 : 1.5
          context.beginPath()
          context.moveTo(leftEdge + 3, cy)
          context.lineTo(x, cy)
          context.stroke()
          context.globalAlpha = 0.95
          context.beginPath()
          context.arc(x, cy, gapChoice.mode === 1 ? 2 : 2.6,
            0, Math.PI * 2)
          context.fill()
        } else if (gapChoice.mode === 2 || gapChoice.mode === 6) {
          const approach = Math.min(1, phase * 1.35)
          const middle = width / 2
          const lx = leftEdge + 3 + approach * (middle - leftEdge - 3)
          const rx = rightEdge - 3 - approach * (rightEdge - middle - 3)
          context.globalAlpha = 0.92
          context.beginPath()
          context.arc(lx, cy, 1.8, 0, Math.PI * 2)
          context.arc(rx, cy, 1.8, 0, Math.PI * 2)
          context.fill()
          if (gapChoice.mode === 6 && approach > 0.82) {
            context.globalAlpha = 0.72 * (1 - approach) / 0.18
            context.lineWidth = 1
            for (let shard = 0; shard < 4; shard++) {
              const angle = shard * Math.PI / 2 + phase
              context.beginPath()
              context.moveTo(middle, cy)
              context.lineTo(middle + Math.cos(angle) * 8,
                cy + Math.sin(angle) * 5)
              context.stroke()
            }
          }
        } else if (gapChoice.mode === 3 || gapChoice.mode === 4) {
          context.globalAlpha = gapChoice.mode === 3 ? 0.82 : 0.95 * pulse
          context.lineWidth = gapChoice.mode === 3 ? 1.2 : 1.6
          context.beginPath()
          context.moveTo(leftEdge + 2, cy)
          const segments = gapChoice.mode === 3 ? 8 : 5
          for (let index = 1; index <= segments; index++) {
            const x = leftEdge + 2
              + index / segments * (rightEdge - leftEdge - 4)
            const y = index === segments ? cy
              : cy + Math.sin(index * 4.7 + phase * Math.PI * 2)
                * (gapChoice.mode === 3 ? 3.2 : 6)
            context.lineTo(x, y)
          }
          context.stroke()
        } else {
          context.globalAlpha = 0.88
          context.font = "600 " + Math.round(height * 0.24) + "px "
            + gapChoice.controller.marketFont
          context.textAlign = "center"
          context.textBaseline = "middle"
          context.fillText(gapChoice.mode === 7 ? "EVENT" : "“  ”",
            width / 2, cy)
          context.globalAlpha = 0.34 + pulse * 0.28
          context.fillRect(leftEdge + 4, cy + 8,
            (rightEdge - leftEdge - 8) * phase, 1)
        }
        context.globalAlpha = 1
      }

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    Timer {
      interval: 33
      repeat: true
      running: gapChoice.previewRunning
      onTriggered: previewCanvas.requestPaint()
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Commons.Style.space(8)
      text: gapChoice.label
      color: gapChoice.selected ? gapChoice.accent : gapChoice.foreground
      opacity: gapChoice.selected || previewPointer.containsMouse
        || gapChoice.activeFocus ? 1 : 0.64
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      font.family: gapChoice.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: gapChoice.selected ? Font.DemiBold : Font.Medium
    }

    MouseArea {
      id: previewPointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        gapChoice.forceActiveFocus()
        gapChoice.clicked()
      }
      onContainsMouseChanged: previewCanvas.requestPaint()
    }

    onSelectedChanged: previewCanvas.requestPaint()
    onPreviewRunningChanged: previewCanvas.requestPaint()
    Keys.onReturnPressed: gapChoice.clicked()
    Keys.onEnterPressed: gapChoice.clicked()
    Keys.onSpacePressed: gapChoice.clicked()
  }

  component LayoutProtectionToggle: Rectangle {
    id: layoutToggle

    required property var controller
    property string label: ""
    property string detail: ""
    property string accessibleDescription: detail
    property bool selected: false
    property color foreground: "white"
    property color accent: "white"
    readonly property bool labelFits:
      toggleLabel.implicitWidth <= toggleLabel.width + 0.5
    signal clicked()

    height: Commons.Style.space(50)
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.description: accessibleDescription
    Accessible.checked: selected
    radius: controller.controlRadius
    color: togglePointer.containsMouse
      ? controller.controlHoverFillColor : controller.controlFillColor
    border.width: controller.controlBorderWidth
    // Selection owns the accent. Keyboard focus stays visible without making
    // an unlocked layout look locked after pointer activation.
    border.color: activeFocus ? foreground : selected
      ? accent : togglePointer.containsMouse
        ? controller.controlHoverBorderColor : controller.controlBorderColor

    Column {
      anchors.left: parent.left
      anchors.right: protectionTrack.left
      anchors.leftMargin: Commons.Style.space(12)
      anchors.rightMargin: Commons.Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        id: toggleLabel
        width: parent.width
        text: layoutToggle.label
        color: layoutToggle.foreground
        elide: Text.ElideRight
        font.family: layoutToggle.controller.marketFont
        font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        font.weight: Font.DemiBold
      }

      Text {
        id: toggleDetail
        width: parent.width
        text: layoutToggle.detail
        color: layoutToggle.foreground
        opacity: 0.42
        elide: Text.ElideRight
        font.family: layoutToggle.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }

    Rectangle {
      id: protectionTrack
      anchors.right: parent.right
      anchors.rightMargin: Commons.Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(34)
      height: Commons.Style.space(18)
      radius: height / 2
      color: layoutToggle.selected
        ? Commons.Util.alpha(layoutToggle.accent, 0.30)
        : Commons.Util.alpha(layoutToggle.foreground, 0.08)
      border.width: 1
      border.color: layoutToggle.selected
        ? Commons.Util.alpha(layoutToggle.accent, 0.76)
        : layoutToggle.controller.controlBorderColor

      Rectangle {
        width: Commons.Style.space(12)
        height: width
        radius: width / 2
        x: layoutToggle.selected
          ? parent.width - width - Commons.Style.space(3)
          : Commons.Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
        color: layoutToggle.selected
          ? layoutToggle.accent : layoutToggle.foreground
        opacity: layoutToggle.selected ? 1 : 0.58
      }
    }

    MouseArea {
      id: togglePointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        layoutToggle.focus = false
        layoutToggle.clicked()
      }
    }

    Keys.onReturnPressed: layoutToggle.clicked()
    Keys.onEnterPressed: layoutToggle.clicked()
    Keys.onSpacePressed: layoutToggle.clicked()
  }

  component ActionCard: Rectangle {
    id: actionCard
    required property var controller
    property string glyph: ""
    property string label: ""
    property string detail: ""
    property color foreground: "white"
    property color accent: "white"
    readonly property bool labelFits:
      actionLabel.implicitWidth <= actionLabel.width + 0.5
    signal clicked()

    height: Commons.Style.space(50)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: detail
    radius: controller.controlRadius
    color: actionPointer.containsMouse
      ? controller.controlHoverFillColor : controller.controlFillColor
    border.width: controller.controlBorderWidth
    border.color: activeFocus ? accent
      : actionPointer.containsMouse
        ? controller.controlHoverBorderColor : controller.controlBorderColor

    Row {
      anchors.fill: parent
      anchors.margins: Commons.Style.space(9)
      spacing: Commons.Style.space(8)

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(20)
        text: actionCard.glyph
        color: actionCard.accent
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
        fill: 0
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x
        spacing: 0

        Text {
          id: actionLabel
          width: parent.width
          text: actionCard.label
          color: actionCard.foreground
          elide: Text.ElideRight
          font.family: actionCard.controller.marketFont
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
          font.weight: Font.DemiBold
        }

        Text {
          id: actionDetail
          width: parent.width
          text: actionCard.detail
          color: actionCard.foreground
          opacity: 0.42
          elide: Text.ElideRight
          font.family: actionCard.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
        }
      }
    }

    MouseArea {
      id: actionPointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: actionCard.clicked()
    }

    Keys.onReturnPressed: actionCard.clicked()
    Keys.onEnterPressed: actionCard.clicked()
    Keys.onSpacePressed: actionCard.clicked()
  }

}
