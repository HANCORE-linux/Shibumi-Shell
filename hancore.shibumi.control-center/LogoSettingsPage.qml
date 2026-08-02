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
  readonly property string activeMode:
    String(controller.launcherConfig.mode || "text")
  readonly property var activeOptions: activeMode === "icon"
    ? controller.launcherIconOptions : controller.launcherTextOptions
  readonly property int optionRowCount: Math.ceil(activeOptions.length / 4)
  readonly property bool ready: modeRepeater.count === 2
    && optionRepeater.count === activeOptions.length

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  function glyph(value) {
    const id = String(value)
    if (id === "shibumi") return ""
    if (id === "omarchy") return String.fromCodePoint(0xE900)
    if (id === "hyprland") return ""
    if (id === "arch") return ""
    if (id === "grid") return ""
    if (id === "spark") return ""
    if (id === "power") return ""
    if (id === "dragon") return "⻯"
    if (id === "mark") return ""
    if (id === "nix") return ""
    if (id === "branch") return ""
    if (id === "rebel") return ""
    return String.fromCodePoint(0xE900)
  }

  PageHeaderHero {
    controller: root.controller
    active: root.motionActive
    pageKey: "logo"
    eyebrow: "BAR IDENTITY"
    title: "Logo"
    description: "Choose the launcher mark shown on the Shibumi bar."
    foreground: root.foreground
    accent: root.accent
    uiScale: root.uiScale
  }

  SectionLabel { text: "FORMAT" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(7)

    Repeater {
      id: modeRepeater
      model: [
        { value: "text", label: "Wordmark" },
        { value: "icon", label: "Icon" }
      ]

      delegate: Rectangle {
        id: modeCard
        required property var modelData
        readonly property bool selected: root.activeMode === modelData.value
        width: (parent.width - parent.spacing) / 2
        height: Commons.Style.space(58)
        radius: root.controller.controlRadius
        color: selected || modePointer.containsMouse
          ? root.controller.controlHoverFillColor
          : root.controller.controlFillColor
        border.width: selected ? Math.max(
          1, root.controller.controlBorderWidth) : 1
        border.color: selected
          ? root.accent : root.controller.controlBorderColor

        WordmarkPreview {
          visible: modeCard.modelData.value === "text"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Commons.Style.space(5)
          width: parent.width - Commons.Style.space(20)
          height: Commons.Style.space(24)
          value: root.controller.launcherConfig.text || "shibumi"
          foreground: root.foreground
          fontFamily: root.controller.marketFont
        }

        Image {
          visible: modeCard.modelData.value === "icon"
            && root.controller.launcherConfig.icon === "shibumi"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Commons.Style.space(5)
          width: Commons.Style.space(22)
          height: width
          source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
        }

        Text {
          visible: modeCard.modelData.value === "icon"
            && root.controller.launcherConfig.icon !== "shibumi"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Commons.Style.space(6)
          text: root.glyph(root.controller.launcherConfig.icon || "omarchy")
          color: root.foreground
          font.family: root.controller.launcherConfig.icon === "omarchy"
            ? "omarchy" : root.controller.marketFont
          font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Commons.Style.space(6)
          text: modeCard.modelData.label
          color: modeCard.selected ? root.accent : root.foreground
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: modePointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.controller.setLauncherSelection(
            modeCard.modelData.value,
            modeCard.modelData.value === "text"
              ? root.controller.launcherConfig.text
              : root.controller.launcherConfig.icon)
        }
      }
    }
  }

  SectionLabel {
    text: root.activeMode === "text" ? "WORDMARK" : "ICON"
  }

  Flow {
    width: parent.width
    spacing: Commons.Style.space(7)

    Repeater {
      id: optionRepeater
      model: root.activeOptions

      delegate: Rectangle {
        id: optionCard
        required property string modelData
        readonly property bool selected: String(
          root.activeMode === "text"
            ? root.controller.launcherConfig.text
            : root.controller.launcherConfig.icon) === modelData
        width: (parent.width - parent.spacing * 3) / 4
        height: Commons.Style.space(56)
        radius: root.controller.controlRadius
        color: selected || optionPointer.containsMouse
          ? root.controller.controlHoverFillColor
          : root.controller.controlFillColor
        border.width: selected ? Math.max(
          1, root.controller.controlBorderWidth) : 1
        border.color: selected
          ? root.accent : root.controller.controlBorderColor

        WordmarkPreview {
          visible: root.activeMode === "text"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Commons.Style.space(3)
          width: parent.width - Commons.Style.space(12)
          height: Commons.Style.space(25)
          value: optionCard.modelData
          foreground: root.foreground
          fontFamily: root.controller.marketFont
        }

        Image {
          visible: root.activeMode === "icon"
            && optionCard.modelData === "shibumi"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Commons.Style.space(4)
          width: Commons.Style.space(23)
          height: width
          source: Qt.resolvedUrl("assets/shibumi-icon-hikiryo.svg")
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
        }

        Text {
          visible: root.activeMode === "icon"
            && optionCard.modelData !== "shibumi"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Commons.Style.space(6)
          text: root.glyph(optionCard.modelData)
          color: root.foreground
          font.family: optionCard.modelData === "omarchy"
            ? "omarchy" : root.controller.marketFont
          font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Commons.Style.space(5)
          text: root.controller.launcherLabel(optionCard.modelData)
          color: optionCard.selected ? root.accent : root.foreground
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          elide: Text.ElideRight
        }

        MouseArea {
          id: optionPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.controller.setLauncherSelection(
            root.activeMode, optionCard.modelData)
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
}
