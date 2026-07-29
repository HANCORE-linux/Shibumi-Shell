pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property string selectedWidgetGroup: "G4"
  readonly property bool workbenchReady: appearanceWorkbench.ready

  readonly property var shellStyleOptions: [
    { value: "shibumi", label: "Shibumi" },
    { value: "full", label: "Full" },
    { value: "fit", label: "Fit" },
    { value: "dock", label: "Dock" },
    { value: "notch", label: "Notch" }
  ]
  readonly property var widgetOptions: [
    { group: "G1", label: "Launcher", glyph: "apps", modes: ["full", "icon", "text"] },
    { group: "G2", label: "Workspaces", glyph: "grid_view", modes: ["full", "icon", "text"] },
    { group: "G3", label: "Status", glyph: "notifications", modes: ["full", "icon", "text"] },
    { group: "G4", label: "Memory", glyph: "memory", modes: ["full", "icon", "text"] },
    { group: "G5", label: "CPU", glyph: "developer_board", modes: ["full", "icon", "text"] },
    { group: "G6", label: "Volume", glyph: "volume_up", modes: ["full", "icon", "text"] },
    { group: "G7", label: "AI usage", glyph: "neurology", modes: ["full", "icon", "text"] },
    { group: "G8", label: "Clock & weather", glyph: "schedule", modes: ["full", "icon", "text"] },
    { group: "G9", label: "Now playing", glyph: "music_note", modes: ["full", "icon", "text"] },
    { group: "G10", label: "Quick access", glyph: "bolt", modes: ["full", "icon", "text"] },
    { group: "G11", label: "Network", glyph: "wifi", modes: ["full", "icon", "text"] },
    { group: "G12", label: "Battery", glyph: "battery_5_bar", modes: ["full", "icon", "text"] },
    { group: "G13", label: "Brightness", glyph: "brightness_6", modes: ["full", "icon", "text"] },
    { group: "G14", label: "Power profile", glyph: "speed", modes: ["full", "icon", "text"] },
    { group: "G15", label: "Bluetooth", glyph: "bluetooth", modes: ["full", "icon", "text"] },
    { group: "G16", label: "Temperature", glyph: "device_thermostat", modes: ["full", "icon", "text"] },
    { group: "G17", label: "GPU", glyph: "memory_alt", modes: ["full", "icon", "text"] },
    { group: "G18", label: "Storage", glyph: "hard_drive", modes: ["full", "icon", "text"] }
  ]
  readonly property var colorOptions: [
    { value: "inherit", label: "Auto" },
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
  readonly property var selectedWidget: {
    for (let index = 0; index < widgetOptions.length; index++) {
      if (widgetOptions[index].group === selectedWidgetGroup)
        return widgetOptions[index]
    }
    return widgetOptions[0]
  }
  readonly property string selectedDisplayMode: widgetMode(selectedWidgetGroup)
  readonly property int widgetOptionCount: widgetOptions.length
  readonly property bool allWidgetModesReady: widgetOptions.every(function(option) {
    return option.modes.length === 3
      && option.modes[0] === "full"
      && option.modes[1] === "icon"
      && option.modes[2] === "text"
  })
  readonly property int colorSwatchCount: barColorRepeater.count
  readonly property int colorColumnCount: barColorGrid.columns
  readonly property real firstColorRadius: barColorRepeater.count > 0
    ? barColorRepeater.itemAt(0).radius : -1
  readonly property bool ready:
    shellStyleRepeater.count === shellStyleOptions.length
    && appearanceWorkbench.ready
    && widgetRepeater.count === widgetOptions.length
    && effectRepeater.count === 4
    && radiusRepeater.count === 2
    && positionRepeater.count === 2
    && logoRepeater.count === 2
    && workspaceModeRepeater.count === 3
    && workspaceStyleRepeater.count === 8
    && imagePickerRepeater.count === 4
    && mediaPickerRepeater.count === 3

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(10)

  function widgetSetting(group, key, fallback) {
    return controller.groupSetting(group, key, fallback)
  }

  function widgetMode(group) {
    const stored = String(widgetSetting(group, "displayMode", ""))
    if (stored !== "") return stored
    return widgetSetting(group, "compact", false) === true ? "icon" : "full"
  }

  function setWidgetMode(group, mode) {
    const value = String(mode)
    controller.setGroupSetting(group, "displayMode", value)
    controller.setGroupSetting(group, "compact",
      group === "G9" ? value === "full" : value === "icon")
  }

  function setWidgetSurface(group, mode) {
    const value = String(mode)
    controller.setGroupSetting(group, "colorMode", value)
    // `widgetBorder` predates the unified surface selector. Keep the legacy
    // flag aligned so selecting "None" always removes the outline.
    controller.setGroupSetting(group, "widgetBorder",
      value === "border" || value === "both")
  }

  Text {
    text: "VISUAL REGISTRY"
    color: root.accent
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.weight: Font.Bold
    font.letterSpacing: 1.8
  }

  Text {
    text: "appearance"
    color: root.foreground
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.space(24) * root.uiScale
    font.weight: Font.Bold
  }

  Text {
    width: parent.width
    text: "Select a widget. Every primary appearance control stays in view."
    color: root.foreground
    opacity: 0.58
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  WidgetAppearanceWorkbench {
    id: appearanceWorkbench
    width: parent.width
    controller: root.controller
    widgetOptions: root.widgetOptions
    uiScale: root.uiScale
    foreground: root.foreground
    accent: root.accent
    selectedWidgetGroup: root.selectedWidgetGroup
    onSelectedWidgetGroupChanged:
      root.selectedWidgetGroup = selectedWidgetGroup
  }

  SectionLabel { text: "BAR & ADVANCED" }
  Separator {}
  SectionLabel { text: "BAR SHELL" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: shellStyleRepeater
      model: root.shellStyleOptions

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing * 4) / 5
        controller: root.controller
        label: modelData.label
        selected: String(root.controller.barPresentation.shellStyle
          || "shibumi") === modelData.value
        foreground: root.foreground
        accent: root.accent
        fontSize: Commons.Style.font.caption * root.uiScale
        onClicked: root.controller.setBarPresentation(
          "shellStyle", modelData.value)
      }
    }
  }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: positionRepeater
      model: [
        { value: "top", label: "Top" },
        { value: "bottom", label: "Bottom" }
      ]

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing) / 2
        controller: root.controller
        label: modelData.label
        selected: root.controller.barPosition === modelData.value
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setBarPosition(modelData.value)
      }
    }
  }

  Separator {}
  SectionLabel { text: "SURFACE" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: effectRepeater
      model: [
        { key: "border", label: "Border", fallback: true },
        { key: "panelBorder", label: "Panel borders", fallback: true },
        { key: "frost", label: "Frost", fallback: false },
        { key: "shadow", label: "Shadow", fallback: false }
      ]

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing * 3) / 4
        controller: root.controller
        label: modelData.label
        selected: root.controller.barPresentation[modelData.key] === undefined
          ? modelData.fallback
          : root.controller.barPresentation[modelData.key] === true
        foreground: root.foreground
        accent: root.accent
        fontSize: Commons.Style.font.caption * root.uiScale
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
      model: [
        { value: "large", label: "Radius 12" },
        { value: "small", label: "Radius 6" }
      ]

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

  SectionLabel { text: "BAR COLOR" }

  Grid {
    id: barColorGrid
    width: parent.width
    columns: 9
    columnSpacing: Commons.Style.space(6)
    rowSpacing: Commons.Style.space(6)

    Repeater {
      id: barColorRepeater
      model: root.colorOptions.slice(1)

      delegate: Rectangle {
        id: barSwatch
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
          text: barSwatch.modelData.label
          color: root.controller.contrastColor(barSwatch.modelData.value)
          font.family: Commons.Style.font.menuFamily
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.Medium
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.controller.setBarPresentation(
            "accent", barSwatch.modelData.value)
        }
      }
    }
  }

  Separator {}
  SectionLabel {
    visible: false
    text: "WIDGET APPEARANCE"
  }

  Text {
    visible: false
    width: parent.width
    text: "Choose a module, then tune only that module."
    color: root.foreground
    opacity: 0.52
    font.family: Commons.Style.font.menuFamily
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  Flow {
    visible: false
    width: parent.width
    spacing: Commons.Style.space(8)

    Repeater {
      id: widgetRepeater
      model: root.widgetOptions

      delegate: AppearanceWidgetTile {
        required property var modelData
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        glyph: modelData.glyph
        label: modelData.label
        mode: root.widgetMode(modelData.group)
        selected: root.selectedWidgetGroup === modelData.group
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onChosen: root.selectedWidgetGroup = modelData.group
      }
    }
  }

  Rectangle {
    visible: false
    width: parent.width
    implicitHeight: widgetInspector.implicitHeight
      + Commons.Style.space(22)
    radius: Math.max(root.controller.controlRadius, Commons.Style.space(7))
    color: root.controller.controlFillColor
    border.width: 1
    border.color: root.controller.controlBorderColor

    Column {
      id: widgetInspector
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Commons.Style.space(11)
      spacing: Commons.Style.space(8)

      Row {
        width: parent.width
        spacing: Commons.Style.space(7)

        IconText {
          anchors.verticalCenter: parent.verticalCenter
          text: root.selectedWidget.glyph
          color: root.accent
          font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.selectedWidget.label
          color: root.foreground
          font.family: Commons.Style.font.menuFamily
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
          font.weight: Font.DemiBold
        }
      }

      Text {
        text: "DISPLAY"
        color: root.foreground
        opacity: 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)

        Repeater {
          model: root.selectedWidget.modes

          delegate: CompactSettingChoice {
            required property string modelData
            width: (parent.width - parent.spacing
              * (root.selectedWidget.modes.length - 1))
              / root.selectedWidget.modes.length
            controller: root.controller
            label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
            selected: root.selectedDisplayMode === modelData
            foreground: root.foreground
            accent: root.accent
            uiScale: root.uiScale
            onClicked: root.setWidgetMode(
              root.selectedWidgetGroup, modelData)
          }
        }
      }

      Text {
        text: "COLOR"
        color: root.foreground
        opacity: 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1
      }

      Grid {
        width: parent.width
        columns: 10
        columnSpacing: Commons.Style.space(5)
        rowSpacing: Commons.Style.space(5)

        Repeater {
          model: root.colorOptions

          delegate: Rectangle {
            id: widgetSwatch
            required property var modelData
            readonly property bool selected: String(root.widgetSetting(
              root.selectedWidgetGroup, "color", "inherit"))
              === modelData.value
            width: (parent.width - parent.columnSpacing * 9) / 10
            height: Commons.Style.space(25)
            radius: root.controller.controlRadius
            color: modelData.value === "inherit"
              ? root.controller.controlHoverFillColor
              : root.controller.accentColor(modelData.value)
            border.width: selected ? 2 : 1
            border.color: selected ? root.accent
              : root.controller.controlBorderColor

            Text {
              anchors.centerIn: parent
              text: widgetSwatch.modelData.label
              color: widgetSwatch.modelData.value === "inherit"
                ? root.foreground
                : root.controller.contrastColor(widgetSwatch.modelData.value)
              font.family: Commons.Style.font.menuFamily
              font.pixelSize: Commons.Style.font.caption * root.uiScale
              font.weight: Font.Medium
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.controller.setGroupSetting(
                root.selectedWidgetGroup, "color",
                widgetSwatch.modelData.value)
            }
          }
        }
      }

      Text {
        text: "SURFACE"
        color: root.foreground
        opacity: 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)

        Repeater {
          model: [
            { value: "none", label: "None" },
            { value: "fill", label: "Fill" },
            { value: "border", label: "Outline" },
            { value: "both", label: "Both" }
          ]

          delegate: CompactSettingChoice {
            required property var modelData
            width: (parent.width - parent.spacing * 3) / 4
            controller: root.controller
            label: modelData.label
            selected: String(root.widgetSetting(
              root.selectedWidgetGroup, "colorMode", "fill"))
              === modelData.value
            foreground: root.foreground
            accent: root.accent
            uiScale: root.uiScale
            onClicked: root.setWidgetSurface(
              root.selectedWidgetGroup, modelData.value)
          }
        }
      }

      Text {
        text: "CONTENT TONE"
        color: root.foreground
        opacity: 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)

        Repeater {
          model: [
            { value: "auto", label: "Auto contrast" },
            { value: "background", label: "Background" },
            { value: "foreground", label: "Foreground" }
          ]

          delegate: CompactSettingChoice {
            required property var modelData
            width: (parent.width - parent.spacing * 2) / 3
            controller: root.controller
            label: modelData.label
            selected: String(root.widgetSetting(
              root.selectedWidgetGroup, "tone", "auto"))
              === modelData.value
            foreground: root.foreground
            accent: root.accent
            uiScale: root.uiScale
            onClicked: root.controller.setGroupSetting(
              root.selectedWidgetGroup, "tone", modelData.value)
          }
        }
      }

      Text {
        text: "SHAPE"
        color: root.foreground
        opacity: 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)

        Repeater {
          model: [
            { value: "auto", label: "Bar default" },
            { value: "square", label: "Square" },
            { value: "soft", label: "Soft" },
            { value: "round", label: "Round" }
          ]

          delegate: CompactSettingChoice {
            required property var modelData
            width: (parent.width - parent.spacing * 3) / 4
            controller: root.controller
            label: modelData.label
            selected: String(root.widgetSetting(
              root.selectedWidgetGroup, "widgetRadius", "auto"))
              === modelData.value
            foreground: root.foreground
            accent: root.accent
            uiScale: root.uiScale
            onClicked: root.controller.setGroupSetting(
              root.selectedWidgetGroup, "widgetRadius", modelData.value)
          }
        }
      }

      Text {
        text: "SPACING"
        color: root.foreground
        opacity: 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)

        Repeater {
          model: [
            { value: "auto", label: "Automatic" },
            { value: "none", label: "None" },
            { value: "compact", label: "Compact" },
            { value: "roomy", label: "Roomy" }
          ]

          delegate: CompactSettingChoice {
            required property var modelData
            width: (parent.width - parent.spacing * 3) / 4
            controller: root.controller
            label: modelData.label
            selected: String(root.widgetSetting(
              root.selectedWidgetGroup, "widgetPadding", "auto"))
              === modelData.value
            foreground: root.foreground
            accent: root.accent
            uiScale: root.uiScale
            onClicked: root.controller.setGroupSetting(
              root.selectedWidgetGroup, "widgetPadding", modelData.value)
          }
        }
      }

      Text {
        text: "SURFACE OPACITY"
        color: root.foreground
        opacity: 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.letterSpacing: 1
      }

      Row {
        width: parent.width
        spacing: Commons.Style.space(4)

        Repeater {
          model: [
            { value: 1, label: "100%" },
            { value: 0.8, label: "80%" },
            { value: 0.6, label: "60%" }
          ]

          delegate: CompactSettingChoice {
            required property var modelData
            width: (parent.width - parent.spacing * 2) / 3
            controller: root.controller
            label: modelData.label
            selected: Math.abs(Number(root.widgetSetting(
              root.selectedWidgetGroup, "surfaceOpacity", 1))
              - modelData.value) < 0.01
            foreground: root.foreground
            accent: root.accent
            uiScale: root.uiScale
            onClicked: root.controller.setGroupSetting(
              root.selectedWidgetGroup, "surfaceOpacity", modelData.value)
          }
        }
      }

      CompactSettingChoice {
        width: parent.width
        controller: root.controller
        label: "2 px outline"
        selected: Number(root.widgetSetting(root.selectedWidgetGroup,
          "widgetBorderWidth", 1)) === 2
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setGroupSetting(
          root.selectedWidgetGroup, "widgetBorderWidth", selected ? 1 : 2)
      }
    }
  }

  Separator {}
  SectionLabel { text: "WORKSPACES" }

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

  Flow {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: workspaceStyleRepeater
      model: [
        { value: "default", label: "Classic" },
        { value: "numbers", label: "Numbers" },
        { value: "magic", label: "Magic dots" },
        { value: "kanji", label: "Kanji" },
        { value: "rings", label: "Rings" },
        { value: "frame", label: "Frame" },
        { value: "aurora", label: "Aurora" },
        { value: "aurora-streak", label: "Aurora streak" }
      ]

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing * 3) / 4
        controller: root.controller
        label: modelData.label
        selected: String(root.controller.workspaceConfig.style || "default")
          === modelData.value
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setWorkspacePreference(
          "style", modelData.value)
      }
    }
  }

  Text {
    width: parent.width
    text: "Each marker is a workspace. The highlighted marker is the active one."
    color: root.foreground
    opacity: 0.52
    wrapMode: Text.WordWrap
    font.family: Commons.Style.font.menuFamily
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  Separator {}
  SectionLabel { text: "LOGO" }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: logoRepeater
      model: ["text", "icon"]

      delegate: CompactSettingChoice {
        required property string modelData
        width: (parent.width - parent.spacing) / 2
        controller: root.controller
        label: root.controller.launcherChoiceLabel(modelData)
        selected: String(root.controller.launcherConfig.mode || "text")
          === modelData
        foreground: root.foreground
        accent: root.accent
        fontSize: Commons.Style.font.caption * root.uiScale
        onClicked: root.controller.activateLauncherMode(modelData)
      }
    }
  }

  Separator {}
  SectionLabel { text: "PICKER STYLE" }

  Text {
    text: "Themes & wallpapers"
    color: root.foreground
    opacity: 0.64
    font.family: Commons.Style.font.menuFamily
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: imagePickerRepeater
      model: [
        { value: "omarchy", label: "Omarchy" },
        { value: "tanzaku", label: "Tanzaku" },
        { value: "hearthstone", label: "Hearthstone" },
        { value: "carousel", label: "Carousel" }
      ]

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing * 3) / 4
        controller: root.controller
        label: modelData.label
        selected: root.controller.imagePickerStyle === modelData.value
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setImagePickerStyle(modelData.value)
      }
    }
  }

  Text {
    text: "Screenshots & videos"
    color: root.foreground
    opacity: 0.64
    font.family: Commons.Style.font.menuFamily
    font.pixelSize: Commons.Style.font.caption * root.uiScale
  }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: mediaPickerRepeater
      model: [
        { value: "tanzaku", label: "Tanzaku" },
        { value: "hearthstone", label: "Hearthstone" },
        { value: "carousel", label: "Carousel" }
      ]

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing * 2) / 3
        controller: root.controller
        label: modelData.label
        selected: root.controller.mediaPickerStyle === modelData.value
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.controller.setMediaPickerStyle(modelData.value)
      }
    }
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.58
    font.family: Commons.Style.font.menuFamily
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
