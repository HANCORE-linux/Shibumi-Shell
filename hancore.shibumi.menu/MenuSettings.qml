pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Item {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property real controlRadius: Commons.Style.cornerRadius
  readonly property var controlBorderSpec: Commons.Border.controlSpec(
    "normal", foreground, accent)
  readonly property color controlBorderColor: Commons.Border.color(
    controlBorderSpec)
  readonly property color controlFillColor: Commons.Style.normalFillFor(
    foreground, accent)
  readonly property bool ready: launcherModeGroup.options.length === 2
    && textLogo.options.length === 5
    && iconLogo.options.length === 11
    && selectionGroup.options.length === 3
    && scaleGroup.options.length === 3
    && backgroundGroup.options.length === 3
  readonly property bool fitsWidth: selectionGroup.implicitWidth <= width + 0.5
    && scaleGroup.implicitWidth <= width + 0.5
    && backgroundGroup.implicitWidth <= width + 0.5

  implicitHeight: settingsColumn.implicitHeight

  Column {
    id: settingsColumn
    width: Math.max(1, parent.width)
    spacing: Commons.Style.spacing.md

    Text {
      text: "LAUNCHER"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuButtonGroup {
      id: launcherModeGroup
      options: [
        { value: "text", label: "Wordmark" },
        { value: "icon", label: "Icon" }
      ]
      value: root.controller.launcherConfig.mode
      foreground: root.foreground
      background: root.controlFillColor
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onChanged: function(value) {
        root.controller.setLauncher("mode", value)
      }
    }

    MenuDropdown {
      id: textLogo
      width: parent.width
      visible: root.controller.launcherConfig.mode === "text"
      label: "Wordmark"
      value: root.controller.launcherConfig.text
      options: [
        { value: "shibumi", label: "Shibumi" },
        { value: "omarchy", label: "Omarchy" },
        { value: "hyprland", label: "Hyprland" },
        { value: "arch", label: "Arch Linux" },
        { value: "omacom", label: "Omacom" }
      ]
      foreground: root.foreground
      background: Commons.Color.menu.background
      popupBorder: root.controlBorderColor
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      onChanged: function(value) { root.controller.setLauncher("text", value) }
    }

    MenuDropdown {
      id: iconLogo
      width: parent.width
      visible: root.controller.launcherConfig.mode === "icon"
      label: "Icon"
      value: root.controller.launcherConfig.icon
      options: [
        { value: "omarchy", label: "Omarchy" },
        { value: "hyprland", label: "Hyprland" },
        { value: "arch", label: "Arch" },
        { value: "grid", label: "Grid" },
        { value: "spark", label: "Spark" },
        { value: "power", label: "Power" },
        { value: "dragon", label: "Dragon" },
        { value: "mark", label: "Mark" },
        { value: "nix", label: "Nix" },
        { value: "branch", label: "Branch" },
        { value: "rebel", label: "Rebel" }
      ]
      foreground: root.foreground
      background: Commons.Color.menu.background
      popupBorder: root.controlBorderColor
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      onChanged: function(value) { root.controller.setLauncher("icon", value) }
    }

    Text {
      text: "APPLICATIONS"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuToggle {
      width: parent.width
      label: "Application icons"
      checked: root.controller.showIcons
      foreground: root.foreground
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      titleSize: Commons.Style.font.body * root.uiScale
      descriptionSize: Commons.Style.font.caption * root.uiScale
      onClicked: root.controller.setPresentation(
        "icons", !root.controller.showIcons)
    }

    Text {
      text: "SELECTION"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuButtonGroup {
      id: selectionGroup
      options: [
        { value: "default", label: "Default" },
        { value: "gradient", label: "Gradient" },
        { value: "glide", label: "Glide" }
      ]
      value: root.controller.selectionStyle
      foreground: root.foreground
      background: root.controlFillColor
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onChanged: function(value) {
        root.controller.setPresentation("selectionStyle", value)
      }
    }

    Text {
      text: "SCALE"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuButtonGroup {
      id: scaleGroup
      options: [
        { value: "60", label: "60%" },
        { value: "80", label: "80%" },
        { value: "100", label: "100%" }
      ]
      value: String(root.controller.presentationScale)
      foreground: root.foreground
      background: root.controlFillColor
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onChanged: function(value) {
        root.controller.setPresentation("scale", Number(value))
      }
    }

    Text {
      text: "BACKGROUND"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuButtonGroup {
      id: backgroundGroup
      options: [
        { value: "off", label: "Off" },
        { value: "search", label: "Search" },
        { value: "full", label: "Full" }
      ]
      value: root.controller.backgroundMode
      foreground: root.foreground
      background: root.controlFillColor
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onChanged: function(value) {
        root.controller.setPresentation("background", value)
      }
    }

    Text {
      width: parent.width
      visible: root.controller.backgroundMode !== "off"
        && root.controller.backgroundUrl === ""
      text: "Wallpaper unavailable"
      color: Commons.Color.urgent
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      wrapMode: Text.Wrap
    }
  }

  component MenuButtonGroup: ShibumiButtonGroup {
    controlRadius: root.controlRadius
  }

  component MenuDropdown: ShibumiDropdown {
    controlRadius: root.controlRadius
  }

  component MenuToggle: Ui.Toggle {
    radius: root.controlRadius
  }

  component MenuButton: Ui.Button {
    radius: root.controlRadius
  }
}
