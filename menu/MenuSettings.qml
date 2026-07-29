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
  readonly property var widgetOptions: [
    { group: "G4", label: "Memory", enabled: true },
    { group: "G13", label: "Brightness", enabled: true },
    { group: "G7", label: "AI usage", enabled: false },
    { group: "G14", label: "Power profile", enabled: false },
    { group: "G15", label: "Bluetooth", enabled: false },
    { group: "G11", label: "Network", enabled: true },
    { group: "G10", label: "Quick tools", enabled: true },
    { group: "G3", label: "Status", enabled: true },
    { group: "G5", label: "CPU", enabled: true },
    { group: "G6", label: "Volume", enabled: true },
    { group: "G9", label: "Now playing", enabled: true }
  ]
  readonly property var compactOptions: [
    { group: "G11", label: "Network" },
    { group: "G12", label: "Battery" },
    { group: "G13", label: "Brightness" },
    { group: "G15", label: "Bluetooth" },
    { group: "G14", label: "Power profile" },
    { group: "G5", label: "CPU" },
    { group: "G4", label: "Memory" },
    { group: "G6", label: "Volume" }
  ]
  readonly property bool ready: launcherModeGroup.options.length === 2
    && textLogo.options.length === 5
    && iconLogo.options.length === 11
    && selectionGroup.options.length === 3
    && scaleGroup.options.length === 3
    && backgroundGroup.options.length === 3
    && reactorModeControl.options.length === 9
    && positionGroup.options.length === 2
    && workspaceModeGroup.options.length === 3
    && workspaceStyleControl.options.length === 6
    && pickerStyleControl.options.length === 3
    && radiusGroup.options.length === 2
    && widgetToggleRepeater.count === widgetOptions.length
    && compactToggleRepeater.count === compactOptions.length
  readonly property bool fitsWidth: selectionGroup.implicitWidth <= width + 0.5
    && scaleGroup.implicitWidth <= width + 0.5
    && backgroundGroup.implicitWidth <= width + 0.5
    && positionGroup.implicitWidth <= width + 0.5
    && workspaceModeGroup.implicitWidth <= width + 0.5
    && radiusGroup.implicitWidth <= width + 0.5

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
      background: Commons.Color.menu.background
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
      popupBorder: Commons.Color.menu.border
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
      popupBorder: Commons.Color.menu.border
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
      background: Commons.Color.menu.background
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
      background: Commons.Color.menu.background
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onChanged: function(value) {
        root.controller.setPresentation("scale", Number(value))
      }
    }

    Text {
      text: "BAR"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuButtonGroup {
      id: positionGroup
      options: [
        { value: "top", label: "Top" },
        { value: "bottom", label: "Bottom" }
      ]
      value: root.controller.barPosition
      foreground: root.foreground
      background: Commons.Color.menu.background
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onChanged: function(value) { root.controller.setBarPosition(value) }
    }

    Text {
      text: "WORKSPACES"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuButtonGroup {
      id: workspaceModeGroup
      options: [
        { value: "10", label: "10" },
        { value: "5", label: "5" },
        { value: "active", label: "Active" }
      ]
      value: String(root.controller.workspaceConfig.mode || "10")
      foreground: root.foreground
      background: Commons.Color.menu.background
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onChanged: function(value) {
        root.controller.setWorkspacePreference("mode", value)
      }
    }

    MenuDropdown {
      id: workspaceStyleControl
      width: parent.width
      label: "Workspace style"
      value: String(root.controller.workspaceConfig.style || "default")
      options: [
        { value: "default", label: "Default" },
        { value: "numbers", label: "Numbers" },
        { value: "magic", label: "Magic" },
        { value: "kanji", label: "Kanji" },
        { value: "rings", label: "Rings" },
        { value: "aurora", label: "Aurora" }
      ]
      foreground: root.foreground
      background: Commons.Color.menu.background
      popupBorder: Commons.Color.menu.border
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      onChanged: function(value) {
        root.controller.setWorkspacePreference("style", value)
      }
    }

    Text {
      text: "PICKER"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuDropdown {
      id: pickerStyleControl
      width: parent.width
      label: "Image and media layout"
      value: root.controller.pickerStyle
      options: [
        { value: "tanzaku", label: "Tanzaku" },
        { value: "hearthstone", label: "Hearthstone" },
        { value: "carousel", label: "Carousel" }
      ]
      foreground: root.foreground
      background: Commons.Color.menu.background
      popupBorder: Commons.Color.menu.border
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      onChanged: function(value) { root.controller.setPickerStyle(value) }
    }

    Text {
      text: "WIDGETS"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    Repeater {
      id: widgetToggleRepeater
      model: root.widgetOptions

      delegate: MenuToggle {
        required property var modelData
        width: settingsColumn.width
        label: modelData.label
        checked: root.controller.groupSetting(
          modelData.group, "enabled", modelData.enabled) !== false
        foreground: root.foreground
        accent: root.accent
        fontFamily: Commons.Style.font.menuFamily
        titleSize: Commons.Style.font.body * root.uiScale
        descriptionSize: Commons.Style.font.caption * root.uiScale
        onClicked: root.controller.setGroupSetting(
          modelData.group, "enabled", !checked)
      }
    }

    Text {
      text: "COMPACT DISPLAY"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    Repeater {
      id: compactToggleRepeater
      model: root.compactOptions

      delegate: MenuToggle {
        required property var modelData
        width: settingsColumn.width
        label: modelData.label
        checked: root.controller.groupSetting(
          modelData.group, "compact", false) === true
        foreground: root.foreground
        accent: root.accent
        fontFamily: Commons.Style.font.menuFamily
        titleSize: Commons.Style.font.body * root.uiScale
        descriptionSize: Commons.Style.font.caption * root.uiScale
        onClicked: root.controller.setGroupSetting(
          modelData.group, "compact", !checked)
      }
    }

    Text {
      text: "LAYOUT"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    Row {
      width: parent.width
      spacing: Commons.Style.spacing.sm

      MenuButton {
        width: (parent.width - parent.spacing) / 2
        text: "Split all"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: Commons.Style.font.menuFamily
        fontSize: Commons.Style.font.caption * root.uiScale
        onClicked: root.controller.setAllSplits(true)
      }

      MenuButton {
        width: (parent.width - parent.spacing) / 2
        text: "Merge all"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: Commons.Style.font.menuFamily
        fontSize: Commons.Style.font.caption * root.uiScale
        onClicked: root.controller.setAllSplits(false)
      }
    }

    MenuButton {
      width: parent.width
      text: "Restore default layout"
      bordered: true
      foreground: root.foreground
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onClicked: root.controller.resetBarLayout()
    }

    Text {
      text: "REACTOR"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    MenuDropdown {
      id: reactorModeControl
      width: parent.width
      label: "Animation mode"
      value: String(root.controller.reactorMode)
      options: [
        { value: "0", label: "Off" },
        { value: "1", label: "Stream" },
        { value: "2", label: "Surge" },
        { value: "3", label: "Bolt" },
        { value: "4", label: "Bolt 2" },
        { value: "5", label: "Stream 2" },
        { value: "6", label: "Surge 2" },
        { value: "7", label: "Reactor" },
        { value: "8", label: "Quotes" }
      ]
      foreground: root.foreground
      background: Commons.Color.menu.background
      popupBorder: Commons.Color.menu.border
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      onChanged: function(value) {
        root.controller.setReactorMode(Number(value))
      }
    }

    Text {
      text: "APPEARANCE"
      color: root.foreground
      opacity: 0.58
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.caption * root.uiScale
      font.weight: Font.Medium
    }

    Row {
      id: accentRow
      width: parent.width
      spacing: Commons.Style.spacing.xs

      Repeater {
        model: [
          { value: "red", label: "Red" },
          { value: "accent", label: "Accent" },
          { value: "color02", label: "02" },
          { value: "color03", label: "03" }
        ]

        delegate: AccentChoice {
          required property var modelData
          width: (accentRow.width - accentRow.spacing * 3) / 4
          label: modelData.label
          swatch: root.controller.accentColor(modelData.value)
          selected: String(root.controller.barPresentation.accent || "red")
            === modelData.value
          foreground: root.foreground
          accent: root.accent
          onClicked: root.controller.setBarPresentation(
            "accent", modelData.value)
        }
      }
    }

    MenuToggle {
      width: parent.width
      label: "Borders"
      checked: root.controller.barPresentation.border !== false
      foreground: root.foreground
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      titleSize: Commons.Style.font.body * root.uiScale
      descriptionSize: Commons.Style.font.caption * root.uiScale
      onClicked: root.controller.setBarPresentation("border", !checked)
    }

    MenuToggle {
      width: parent.width
      label: "Shadows"
      checked: root.controller.barPresentation.shadow === true
      foreground: root.foreground
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      titleSize: Commons.Style.font.body * root.uiScale
      descriptionSize: Commons.Style.font.caption * root.uiScale
      onClicked: root.controller.setBarPresentation("shadow", !checked)
    }

    MenuToggle {
      width: parent.width
      label: "Frosted island"
      checked: root.controller.barPresentation.frost === true
      foreground: root.foreground
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      titleSize: Commons.Style.font.body * root.uiScale
      descriptionSize: Commons.Style.font.caption * root.uiScale
      onClicked: root.controller.setBarPresentation("frost", !checked)
    }

    MenuButtonGroup {
      id: radiusGroup
      options: [
        { value: "large", label: "Radius 12" },
        { value: "small", label: "Radius 6" }
      ]
      value: String(root.controller.barPresentation.radius || "large")
      foreground: root.foreground
      background: Commons.Color.menu.background
      accent: root.accent
      fontFamily: Commons.Style.font.menuFamily
      fontSize: Commons.Style.font.caption * root.uiScale
      onChanged: function(value) {
        root.controller.setBarPresentation("radius", value)
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
      background: Commons.Color.menu.background
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

  component AccentChoice: Rectangle {
    id: choice

    required property string label
    required property color swatch
    property bool selected: false
    property color foreground: Commons.Color.menu.text
    property color accent: Commons.Color.menu.selectedText
    signal clicked()

    implicitHeight: Commons.Style.spacing.controlHeight
    height: implicitHeight
    radius: root.controlRadius
    color: choiceMouse.containsMouse
      ? Commons.Style.hoverFillFor(foreground, accent)
      : selected ? Commons.Style.selectedFillFor(foreground, accent)
      : "transparent"
    border.width: 1
    border.color: selected || choiceMouse.containsMouse
      ? accent : Commons.Color.menu.border

    Row {
      anchors.centerIn: parent
      spacing: Commons.Style.spacing.xs

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.spacing.md
        height: width
        radius: Math.min(width / 2, Commons.Style.cornerRadius)
        color: choice.swatch
        border.width: 1
        border.color: Commons.Color.menu.text
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: choice.label
        color: choice.foreground
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: choiceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: choice.clicked()
    }
  }
}
