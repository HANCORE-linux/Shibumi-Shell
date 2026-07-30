pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool v2Active: false
  readonly property var effectOptions: v2Active
    ? [
        {
          key: "border",
          label: "Bar border",
          fallback: true
        },
        {
          key: "panelBorder",
          label: "Panel & tooltip border",
          fallback: true
        }
      ]
    : [
        { key: "border", label: "Border", fallback: true },
        { key: "frost", label: "Frost", fallback: false },
        { key: "shadow", label: "Shadow", fallback: false }
      ]
  readonly property var radiusOptions: v2Active
    ? []
    : [
        { value: "large", label: "Radius 12" },
        { value: "small", label: "Radius 6" }
      ]
  readonly property var colorOptions: [
    { value: "color01", label: "01" },
    { value: "color02", label: "02" },
    { value: "color03", label: "03" },
    { value: "color04", label: "04" },
    { value: "color05", label: "05" },
    { value: "color06", label: "06" },
    { value: "color07", label: "07" },
    { value: "color08", label: "08" },
    { value: "foreground", label: "FG" }
  ]
  readonly property bool ready:
    effectRepeater.count === effectOptions.length
    && radiusRepeater.count === radiusOptions.length
    && colorRepeater.count === colorOptions.length

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(8)

  SectionLabel { text: "BAR SURFACE" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: effectRepeater
      model: root.effectOptions

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width
          - parent.spacing * (root.effectOptions.length - 1))
          / root.effectOptions.length
        controller: root.controller
        label: modelData.label
        selected: root.controller.barPresentation[modelData.key] === undefined
          ? modelData.fallback
          : root.controller.barPresentation[modelData.key] === true
        foreground: root.foreground
        accent: root.accent
        fontSize: Commons.Style.font.caption * root.uiScale * 0.92
        onClicked: root.controller.setBarPresentation(
          modelData.key, !selected)
      }
    }
  }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: radiusRepeater
      model: root.radiusOptions

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing) / 2
        controller: root.controller
        label: modelData.label
        selected: String(root.controller.barPresentation.radius || "large")
          === modelData.value
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setBarPresentation(
          "radius", modelData.value)
      }
    }
  }

  SectionLabel { text: "BAR ACCENT" }

  Grid {
    width: parent.width
    columns: 9
    columnSpacing: Commons.Style.space(6)

    Repeater {
      id: colorRepeater
      model: root.colorOptions

      delegate: Rectangle {
        id: swatch
        required property var modelData
        readonly property bool selected:
          String(root.controller.barPresentation.accent || "color01")
          === modelData.value
        width: (parent.width - parent.columnSpacing * 8) / 9
        height: Commons.Style.space(26)
        radius: root.controller.controlRadius
        color: root.controller.accentColor(modelData.value)
        border.width: selected ? 2 : 1
        border.color: selected ? root.foreground
          : root.controller.controlBorderColor

        Text {
          anchors.centerIn: parent
          text: swatch.modelData.label
          color: root.controller.contrastColor(swatch.modelData.value)
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.Medium
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.controller.setBarPresentation(
            "accent", swatch.modelData.value)
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
}
