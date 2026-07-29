pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText

  readonly property bool ready: statusRepeater.count === 3

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(12)

  Text {
    text: "SYSTEM REGISTRY"
    color: root.accent
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Bold
    font.letterSpacing: 1.8
  }

  Text {
    text: "control center"
    color: root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.space(26) * root.uiScale
    font.weight: Font.Bold
  }

  Text {
    width: parent.width
    text: "Your Shibumi bar, widgets, and Omarchy plugins in one place."
    color: root.foreground
    opacity: 0.62
    wrapMode: Text.WordWrap
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
  }

  Rectangle {
    width: parent.width
    height: 1
    color: root.controller.dividerColor
  }

  Grid {
    width: parent.width
    columns: 3
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      id: statusRepeater
      model: [
        {
          eyebrow: "BAR",
          value: root.controller.barPosition === "bottom" ? "Bottom" : "Top",
          detail: "Shibumi style"
        },
        {
          eyebrow: "WIDGETS",
          value: String(root.controller.enabledWidgetCount),
          detail: "in the bar"
        },
        {
          eyebrow: "PLUGINS",
          value: String(root.controller.availablePluginCount),
          detail: "discovered"
        }
      ]

      delegate: Rectangle {
        required property var modelData
        width: (parent.width - parent.columnSpacing * 2) / 3
        height: Commons.Style.space(82)
        radius: 0
        color: root.controller.controlFillColor
        border.width: root.controller.controlBorderWidth
        border.color: root.controller.controlBorderColor

        Column {
          anchors.fill: parent
          anchors.margins: Commons.Style.space(10)
          spacing: Commons.Style.space(3)

          Text {
            text: modelData.eyebrow
            color: root.foreground
            opacity: 0.48
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
            font.weight: Font.Medium
            font.letterSpacing: 1
          }

          Text {
            text: modelData.value
            color: root.foreground
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.heading * root.uiScale
            font.weight: Font.DemiBold
          }

          Text {
            text: modelData.detail
            color: root.foreground
            opacity: 0.58
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
          }
        }
      }
    }
  }

  SectionLabel { text: "QUICK ACTIONS" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(8)

    CompactSettingChoice {
      width: (parent.width - parent.spacing * 2) / 3
      controller: root.controller
      label: "Add widget"
      primary: true
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      onClicked: root.controller.openWidgetPicker()
    }

    CompactSettingChoice {
      width: (parent.width - parent.spacing * 2) / 3
      controller: root.controller
      label: "Reload Shibumi"
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      onClicked: root.controller.reloadShell()
    }

    CompactSettingChoice {
      width: (parent.width - parent.spacing * 2) / 3
      controller: root.controller
      label: "Appearance"
      foreground: root.foreground
      accent: root.accent
      uiScale: root.uiScale
      onClicked: root.controller.showSettingsPage("functions")
    }
  }

  SectionLabel { text: "DESIGN CONTRACT" }

  Rectangle {
    width: parent.width
    height: contractContent.implicitHeight + Commons.Style.space(24)
    radius: 0
    color: "transparent"
    border.width: root.controller.controlBorderWidth
    border.color: root.controller.controlBorderColor

    Column {
      id: contractContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Commons.Style.space(12)
      spacing: Commons.Style.space(6)

      Text {
        text: "Native → Adaptive → Original"
        color: root.foreground
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
        font.weight: Font.Medium
      }

      Text {
        width: parent.width
        text: "Shibumi plugins use every design token. Compatible Omarchy widgets inherit bar and tooltip chrome; third-party panels retain their own surface."
        color: root.foreground
        opacity: 0.62
        wrapMode: Text.WordWrap
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
      }
    }
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.48
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Medium
    font.letterSpacing: 1
  }
}
