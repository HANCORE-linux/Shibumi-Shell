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
    : v2Active
      ? activeStyle.charAt(0).toUpperCase() + activeStyle.slice(1)
        + " · slots and dividers"
      : "Split islands and gap motion"
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
  readonly property int surfaceRadiusOptionCount:
    barSurfaceSettings.radiusOptions.length
  readonly property var reactorOptions: [
    { value: 0, label: "Off" },
    { value: 1, label: "Stream" },
    { value: 5, label: "Stream 2" },
    { value: 2, label: "Surge" },
    { value: 6, label: "Surge 2" },
    { value: 3, label: "Bolt" },
    { value: 4, label: "Bolt 2" },
    { value: 7, label: "Reactor" },
    { value: 8, label: "Quotes" }
  ]
  readonly property bool ready:
    shellStyleRepeater.count === visibleShellStyleOptions.length
    && v2SlotRepeater.count === 3
    && reactorRepeater.count === reactorOptions.length
    && barSurfaceSettings.ready

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  Text {
    text: "ACTIVE BAR"
    color: root.accent
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.DemiBold
    font.letterSpacing: 1.2
  }

  Rectangle {
    width: parent.width
    height: Commons.Style.space(72)
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
        font.pixelSize: Commons.Style.space(22) * root.uiScale
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

  SectionLabel { text: "POSITION" }

  Row {
    width: parent.width
    height: Commons.Style.space(30)
    spacing: Commons.Style.space(8)

    CompactSettingChoice {
      width: (parent.width - parent.spacing) / 2
      controller: root.controller
      label: "Top"
      selected: root.controller.barPosition !== "bottom"
      controlHeight: parent.height
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
      controlHeight: parent.height
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      onClicked: root.controller.setBarPosition("bottom")
    }
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    visible: root.shibumiActive

    SectionLabel { text: "BAR FORM" }

    Text {
      width: parent.width
      text: root.v2Active
        ? "Choose the active V2 shape. The previews follow the current "
          + "top or bottom position."
        : "V1 uses the Islands form. Switch bar versions from Quick."
      color: root.foreground
      opacity: 0.48
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }

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

  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    visible: root.shibumiActive && !root.v2Active

    SectionLabel { text: "V1 LAYOUT" }

    Text {
      width: parent.width
      text: "V1 alone supports split islands and animated gaps."
      color: root.foreground
      opacity: 0.48
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }

    Row {
      width: parent.width
      height: Commons.Style.space(30)
      spacing: Commons.Style.space(7)

      CompactSettingChoice {
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: "Split all"
        controlHeight: parent.height
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setAllSplits(true)
      }

      CompactSettingChoice {
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: "Merge all"
        controlHeight: parent.height
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setAllSplits(false)
      }

      CompactSettingChoice {
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: "Restore"
        controlHeight: parent.height
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.resetBarLayout()
      }
    }

    SectionLabel { text: "GAP ANIMATION" }

    Grid {
      width: parent.width
      columns: 3
      columnSpacing: Commons.Style.space(5)
      rowSpacing: Commons.Style.space(6)

      Repeater {
        id: reactorRepeater
        model: root.reactorOptions

        delegate: CompactSettingChoice {
          required property var modelData
          width: (parent.width - parent.columnSpacing * 2) / 3
          controller: root.controller
          label: modelData.label
          selected: root.controller.reactorMode === modelData.value
          foreground: root.foreground
          accent: root.accent
          fontSize: Commons.Style.font.caption * root.uiScale
          horizontalPadding: Commons.Style.space(3)
          onClicked: root.controller.setReactorMode(modelData.value)
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Commons.Style.space(8)
    visible: root.v2Active

    SectionLabel { text: "V2 LAYOUT" }

    Text {
      width: parent.width
      text: "V2 uses three slot regions and persistent dividers. "
        + "V1 split and gap controls are intentionally hidden."
      color: root.foreground
      opacity: 0.48
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }

    Row {
      width: parent.width
      height: Commons.Style.space(50)
      spacing: Commons.Style.space(7)

      ActionCard {
        width: (parent.width - parent.spacing) / 2
        controller: root.controller
        glyph: "splitscreen"
        label: "Edit dividers"
        detail: "Choose boundaries on the bar"
        foreground: root.foreground
        accent: root.accent
        onClicked: root.controller.beginBarEditing()
      }

      ActionCard {
        width: (parent.width - parent.spacing) / 2
        controller: root.controller
        glyph: "restart_alt"
        label: "Restore layout"
        detail: "Reset slots and dividers"
        foreground: root.foreground
        accent: root.accent
        onClicked: root.controller.resetBarLayout()
      }
    }

    SectionLabel { text: "SLOT CAPACITY" }

    Repeater {
      id: v2SlotRepeater
      model: [
        { id: "left", label: "Left", min: 10, max: 13 },
        { id: "center", label: "Center", min: 1, max: 4 },
        { id: "right", label: "Right", min: 7, max: 13 }
      ]

      delegate: Rectangle {
        id: slotRow
        required property var modelData
        readonly property int slotCount:
          root.controller.v2LayoutSlots
          && Array.isArray(root.controller.v2LayoutSlots[modelData.id])
            ? root.controller.v2LayoutSlots[modelData.id].length : 0
        readonly property int emptyCount:
          root.controller.v2LayoutSlots
          && Array.isArray(root.controller.v2LayoutSlots[modelData.id])
            ? root.controller.v2LayoutSlots[modelData.id].filter(
              function(value) { return String(value || "") === "" }).length
            : 0
        width: parent.width
        height: Commons.Style.space(46)
        radius: root.controller.controlRadius
        color: root.controller.controlFillColor
        border.width: root.controller.controlBorderWidth
        border.color: root.controller.controlBorderColor

        Row {
          anchors.fill: parent
          anchors.margins: Commons.Style.space(8)
          spacing: Commons.Style.space(8)

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Commons.Style.space(82)
            spacing: 0

            Text {
              text: slotRow.modelData.label
              color: root.foreground
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
              font.weight: Font.DemiBold
            }

            Text {
              text: slotRow.slotCount + " / " + slotRow.modelData.max
              color: root.foreground
              opacity: 0.42
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.caption * root.uiScale
            }
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - removeSlot.width - addSlot.width
              - parent.spacing * 2
            height: Commons.Style.space(12)

            Row {
              anchors.centerIn: parent
              spacing: Commons.Style.space(3)

              Repeater {
                model: slotRow.modelData.max

                delegate: Rectangle {
                  required property int index
                  width: Commons.Style.space(5)
                  height: Commons.Style.space(10)
                  radius: Math.min(root.controller.controlRadius, width / 2)
                  color: index < slotRow.slotCount
                    ? Commons.Util.alpha(root.accent, 0.74)
                    : Commons.Util.alpha(root.foreground, 0.10)
                }
              }
            }
          }

          StepButton {
            id: removeSlot
            controller: root.controller
            symbol: "−"
            enabled: slotRow.slotCount > slotRow.modelData.min
              && slotRow.emptyCount > 0
            foreground: root.foreground
            accent: root.accent
            onClicked: root.controller.removeV2Slot(slotRow.modelData.id)
          }

          StepButton {
            id: addSlot
            controller: root.controller
            symbol: "+"
            enabled: slotRow.slotCount < slotRow.modelData.max
            foreground: root.foreground
            accent: root.accent
            onClicked: root.controller.addV2Slot(slotRow.modelData.id)
          }
        }
      }
    }
  }

  BarSurfaceSettings {
    id: barSurfaceSettings
    width: parent.width
    visible: root.shibumiActive
    controller: root.controller
    v2Active: root.v2Active
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  SectionLabel { text: "HOST BAR" }

  ActionCard {
    width: parent.width
    controller: root.controller
    glyph: "swap_horiz"
    label: "Switch to " + (root.shibumiActive ? "Omarchy" : "Shibumi")
    detail: "Snapshot · apply · verify with rollback"
    foreground: root.foreground
    accent: root.accent
    onClicked: root.controller.switchShell(
      root.shibumiActive ? "omarchy" : "shibumi")
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.54
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.DemiBold
    font.letterSpacing: 1
  }

  component ActionCard: Rectangle {
    id: actionCard
    required property var controller
    property string glyph: ""
    property string label: ""
    property string detail: ""
    property color foreground: "white"
    property color accent: "white"
    signal clicked()

    height: Commons.Style.space(50)
    radius: controller.controlRadius
    color: actionPointer.containsMouse
      ? controller.controlHoverFillColor : controller.controlFillColor
    border.width: controller.controlBorderWidth
    border.color: actionPointer.containsMouse
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
          width: parent.width
          text: actionCard.label
          color: actionCard.foreground
          elide: Text.ElideRight
          font.family: actionCard.controller.marketFont
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
          font.weight: Font.DemiBold
        }

        Text {
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
  }

  component StepButton: Rectangle {
    id: stepButton
    required property var controller
    property string symbol: ""
    property color foreground: "white"
    property color accent: "white"
    signal clicked()

    anchors.verticalCenter: parent.verticalCenter
    width: Commons.Style.space(30)
    height: width
    radius: controller.controlRadius
    color: stepPointer.containsMouse && enabled
      ? controller.controlHoverFillColor : controller.controlFillColor
    opacity: enabled ? 1 : 0.34
    border.width: controller.controlBorderWidth
    border.color: stepPointer.containsMouse && enabled
      ? accent : controller.controlBorderColor

    Text {
      anchors.centerIn: parent
      text: stepButton.symbol
      color: stepButton.foreground
      font.family: stepButton.controller.marketFont
      font.pixelSize: Commons.Style.font.body * root.uiScale
      font.weight: Font.Medium
    }

    MouseArea {
      id: stepPointer
      anchors.fill: parent
      enabled: stepButton.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: stepButton.clicked()
    }
  }
}
