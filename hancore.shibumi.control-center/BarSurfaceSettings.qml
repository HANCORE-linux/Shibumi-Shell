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
  property bool showSurface: true
  property bool showAccent: true
  readonly property var effectOptions: v2Active
    ? [
        {
          key: "border",
          label: "Bar border",
          detail: "Outline the V2 bar shell",
          fallback: true
        },
        {
          key: "panelBorder",
          label: "Panel + tooltip",
          detail: "Outline connected panels and tooltips",
          fallback: true
        }
      ]
    : [
        {
          key: "border",
          label: "Border",
          detail: "One pixel outline around V1 surfaces",
          fallback: true
        },
        {
          key: "frost",
          label: "Frost",
          detail: "Translucent V1 islands",
          fallback: false
        },
        {
          key: "shadow",
          label: "Shadow",
          detail: "Soft depth behind V1 surfaces",
          fallback: false
        }
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
    { value: "foreground", label: "FG" }
  ]
  readonly property int previewEffectOptionCount:
    showSurface && !v2Active ? effectOptions.length : 0
  readonly property bool ready:
    effectRepeater.count === (showSurface ? effectOptions.length : 0)
    && radiusRepeater.count === (showSurface ? radiusOptions.length : 0)
    && colorRepeater.count === (showAccent ? colorOptions.length : 0)

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(8)

  SectionLabel {
    visible: root.showSurface
    text: "BAR SURFACE"
  }

  Row {
    id: effectRow
    width: parent.width
    height: Commons.Style.space(root.v2Active ? 30 : 52)
    spacing: Commons.Style.space(8)
    visible: root.showSurface

    Repeater {
      id: effectRepeater
      model: root.showSurface ? root.effectOptions : []

      delegate: Loader {
        id: effectLoader

        required property var modelData
        width: (parent.width
          - parent.spacing * (root.effectOptions.length - 1))
          / root.effectOptions.length
        height: effectRow.height
        sourceComponent: root.v2Active ? compactEffect : previewEffect

        readonly property bool effectSelected:
          root.controller.barPresentation[modelData.key] === undefined
            ? modelData.fallback
            : root.controller.barPresentation[modelData.key] === true

        Component {
          id: compactEffect

          CompactSettingChoice {
            controller: root.controller
            label: effectLoader.modelData.label
            selected: effectLoader.effectSelected
            foreground: root.foreground
            accent: root.accent
            uiScale: root.uiScale
            controlHeight: effectRow.height
            onClicked: root.controller.setBarPresentation(
              effectLoader.modelData.key, !selected)
          }
        }

        Component {
          id: previewEffect

          SurfaceEffectChoice {
            controller: root.controller
            effectKey: effectLoader.modelData.key
            label: effectLoader.modelData.label
            detail: effectLoader.modelData.detail
            selected: effectLoader.effectSelected
            foreground: root.foreground
            accent: root.accent
            uiScale: root.uiScale
            onClicked: root.controller.setBarPresentation(
              effectLoader.modelData.key, !selected)
          }
        }
      }
    }
  }

  Row {
    id: radiusRow
    width: parent.width
    height: visible ? Commons.Style.space(30) : 0
    spacing: Commons.Style.space(4)
    visible: root.showSurface && root.radiusOptions.length > 0

    Repeater {
      id: radiusRepeater
      model: root.showSurface ? root.radiusOptions : []

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
        controlHeight: radiusRow.height
        onClicked: root.controller.setBarPresentation(
          "radius", modelData.value)
      }
    }
  }

  SectionLabel {
    visible: root.showAccent
    text: "BAR ACCENT"
  }

  Grid {
    width: parent.width
    columns: 8
    columnSpacing: Commons.Style.space(6)
    visible: root.showAccent

    Repeater {
      id: colorRepeater
      model: root.showAccent ? root.colorOptions : []

      delegate: Rectangle {
        id: swatch
        required property var modelData
        readonly property bool selected:
          String(root.controller.barPresentation.accent || "color01")
          === modelData.value
        readonly property bool hovered: swatchMouse.containsMouse
        width: (parent.width - parent.columnSpacing * 7) / 8
        height: Commons.Style.space(26)
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: "Bar accent " + swatch.modelData.label
        radius: root.controller.controlRadius
        color: root.controller.accentColor(modelData.value)
        border.width: 1
        border.color: swatch.activeFocus
          ? root.accent : root.controller.controlBorderColor
        scale: hovered ? 1.04 : 1
        z: hovered ? 1 : 0

        Behavior on scale {
          NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Text {
          anchors.centerIn: parent
          text: swatch.modelData.label
          color: root.controller.contrastColor(swatch.modelData.value)
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.Medium
        }

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Commons.Style.space(3)
          width: Commons.Style.space(18)
          height: 2
          radius: 1
          visible: swatch.selected
          color: root.controller.contrastColor(swatch.modelData.value)
        }

        MouseArea {
          id: swatchMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.controller.setBarPresentation(
            "accent", swatch.modelData.value)
        }

        Keys.onReturnPressed: root.controller.setBarPresentation(
          "accent", swatch.modelData.value)
        Keys.onEnterPressed: root.controller.setBarPresentation(
          "accent", swatch.modelData.value)
        Keys.onSpacePressed: root.controller.setBarPresentation(
          "accent", swatch.modelData.value)
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
