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
  readonly property var workspaceStyleOptions: [
    { value: "default", label: "Default" },
    { value: "numbers", label: "Numbers" },
    { value: "magic", label: "Magic" },
    { value: "kanji", label: "Kanji" },
    { value: "rings", label: "Frame" },
    { value: "aurora", label: "Aurora" },
    { value: "pacman", label: "Pacman" }
  ]
  readonly property bool ready: workspaceModeRepeater.count === 3
    && workspaceStyleRepeater.count === workspaceStyleOptions.length

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "workspaces"
    eyebrow: "NAVIGATION"
    title: "Workspaces"
    description: "Choose how many workspaces the bar shows and how their markers look."
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  Separator {}
  SectionLabel { text: "VISIBLE WORKSPACES" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: workspaceModeRepeater
      model: [
        { value: "10", label: "Ten" },
        { value: "5", label: "Five" },
        { value: "active", label: "Active only" }
      ]

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: modelData.label
        selected: String(root.controller.workspaceConfig.mode || "10")
          === modelData.value
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setWorkspacePreference(
          "mode", modelData.value)
      }
    }
  }

  SectionLabel { text: "MARKER STYLE" }

  Flow {
    width: parent.width
    spacing: Commons.Style.space(7)

    Repeater {
      id: workspaceStyleRepeater
      model: root.workspaceStyleOptions

      delegate: WorkspaceMarkerPreviewCard {
        required property var modelData
        width: (parent.width - parent.spacing * 3) / 4
        controller: root.controller
        styleValue: modelData.value
        label: modelData.label
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onChosen: function(styleValue) {
          root.controller.setWorkspacePreference("style", styleValue)
        }
      }
    }
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
