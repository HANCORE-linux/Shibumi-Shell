pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool powerOpen: false

  readonly property bool ready: powerRepeater.count === 4

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(8)

  Text {
    text: "SYSTEM OPERATIONS"
    color: root.accent
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Bold
    font.letterSpacing: 1.8
  }

  Text {
    text: "advanced"
    color: root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.space(24) * root.uiScale
    font.weight: Font.Bold
  }

  Text {
    width: parent.width
    text: "Maintenance, session actions and recovery."
    color: root.foreground
    opacity: 0.58
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  Separator {}
  SectionLabel { text: "MAINTENANCE" }

  CompactSettingChoice {
    width: parent.width
    controller: root.controller
    label: "Reload Shibumi"
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onClicked: root.controller.reloadShell()
  }

  CompactSettingChoice {
    width: parent.width
    controller: root.controller
    label: "Reset bar layout"
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onClicked: root.controller.resetBarLayout()
  }

  Separator {}
  SectionLabel { text: "SESSION" }

  CompactSettingChoice {
    width: parent.width
    controller: root.controller
    label: root.powerOpen ? "Power actions  ▾" : "Power actions  ▸"
    selected: root.powerOpen
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onClicked: root.powerOpen = !root.powerOpen
  }

  Grid {
    width: parent.width
    visible: root.powerOpen
    columns: 2
    columnSpacing: Commons.Style.space(8)
    rowSpacing: Commons.Style.space(8)

    Repeater {
      id: powerRepeater
      model: [
        { id: "lock", label: "Lock" },
        { id: "suspend", label: "Suspend" },
        { id: "reboot", label: "Reboot" },
        { id: "shutdown", label: "Shutdown" }
      ]

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.columnSpacing) / 2
        controller: root.controller
        label: modelData.label
        foreground: root.foreground
        accent: modelData.id === "shutdown"
          ? (root.controller.bar
              ? root.controller.bar.urgent : root.accent)
          : root.accent
        uiScale: root.uiScale
        onClicked: root.controller.runSystemAction(modelData.id)
      }
    }
  }

  Separator {}
  SectionLabel { text: "SHORTCUTS" }

  CompactSettingChoice {
    width: parent.width
    controller: root.controller
    label: "Appearance  →"
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onClicked: root.controller.showSettingsPage("functions")
  }

  CompactSettingChoice {
    width: parent.width
    controller: root.controller
    label: "Layout  →"
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
    onClicked: root.controller.showSettingsPage("splits")
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.58
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Medium
    font.letterSpacing: 1
  }

  component Separator: Rectangle {
    width: root.width
    height: 1
    color: root.controller.dividerColor
  }
}
