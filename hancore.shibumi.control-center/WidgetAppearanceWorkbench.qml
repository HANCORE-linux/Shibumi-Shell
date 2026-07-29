pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  required property var widgetOptions
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property string selectedWidgetGroup: "G4"
  property string selectedWidgetId: ""
  property string providerFilter: "All"
  property bool advancedOpen: false

  readonly property var providerOptions: [
    { value: "All", label: "All" },
    { value: "Shibumi", label: "Shibumi" },
    { value: "Omarchy Quattro", label: "Omarchy" },
    { value: "Third-party", label: "Third" }
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
  readonly property var appearanceOptions: buildAppearanceOptions()
  readonly property var filteredOptions: optionsForProvider(providerFilter)
  readonly property var selectedWidget: optionForSelection(
    selectedWidgetGroup, selectedWidgetId)
  readonly property bool selectedSupported: selectedWidget
    && String(selectedWidget.group || "") !== ""
  readonly property string selectedDisplayMode: selectedSupported
    ? widgetMode(selectedWidget.group) : "full"
  readonly property string selectedSurfaceMode: selectedSupported
    ? String(widgetSetting(selectedWidget.group, "colorMode", "fill")) : "none"
  readonly property string selectedColor: selectedSupported
    ? String(widgetSetting(selectedWidget.group, "color", "inherit")) : "inherit"
  readonly property bool selectedHasFill:
    selectedSurfaceMode === "fill" || selectedSurfaceMode === "both"
  readonly property bool selectedHasBorder:
    selectedSurfaceMode === "border" || selectedSurfaceMode === "both"
  readonly property color selectedFillColor: selectedColor === "inherit"
    ? controller.controlHoverFillColor
    : controller.accentColor(selectedColor)
  readonly property int visibleOptionCount: filteredOptions.length
  readonly property bool ready: providerRepeater.count === providerOptions.length
    && widgetRepeater.count === filteredOptions.length
    && displayModeRepeater.count === 3
    && surfaceModeRepeater.count === 4
    && widgetColorRepeater.count === colorOptions.length

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(8)

  function optionForSelection(groupValue, idValue) {
    const group = String(groupValue || "")
    const id = String(idValue || "")
    for (let index = 0; index < appearanceOptions.length; index++) {
      const option = appearanceOptions[index]
      if (group !== "" && String(option.group || "") === group)
        return option
      if (group === "" && id !== "" && String(option.id || "") === id)
        return appearanceOptions[index]
    }
    return appearanceOptions.length > 0 ? appearanceOptions[0] : ({
      group: "", id: "", label: "Widget", glyph: "widgets",
      modes: ["full"], provider: "Third-party"
    })
  }

  function pluginForGroup(groupValue) {
    const group = String(groupValue || "")
    const entries = controller.pluginEntries || []
    for (let index = 0; index < entries.length; index++) {
      const entry = entries[index]
      if (controller.shibumiWidgetGroup(entry.id) === group) return entry
    }
    return null
  }

  function buildAppearanceOptions() {
    void(controller.pluginEntries)
    const result = []
    const knownIds = ({})
    for (let index = 0; index < widgetOptions.length; index++) {
      const source = widgetOptions[index]
      const plugin = pluginForGroup(source.group)
      const id = plugin ? String(plugin.id || "") : ""
      if (id !== "") knownIds[id] = true
      result.push({
        group: source.group,
        id: id,
        label: source.label,
        glyph: source.glyph,
        modes: source.modes,
        provider: "Shibumi",
        supported: true
      })
    }

    const entries = controller.pluginEntries || []
    for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      const entry = entries[entryIndex]
      if (!entry.barWidget || !entry.installedInBar || knownIds[entry.id])
        continue
      result.push({
        group: "",
        id: entry.id,
        label: entry.name,
        glyph: entry.glyph || "widgets",
        modes: ["full"],
        provider: entry.provider || "Third-party",
        supported: false
      })
    }
    return result
  }

  function optionsForProvider(provider) {
    const value = String(provider || "All")
    if (value === "All") return appearanceOptions
    return appearanceOptions.filter(function(option) {
      return String(option.provider || "") === value
    })
  }

  function chooseProvider(provider) {
    const nextOptions = optionsForProvider(provider)
    providerFilter = String(provider)
    if (nextOptions.length > 0) {
      selectedWidgetGroup = String(nextOptions[0].group || "")
      selectedWidgetId = String(nextOptions[0].id || "")
    }
  }

  function widgetSetting(group, key, fallback) {
    return controller.groupSetting(group, key, fallback)
  }

  function widgetMode(group) {
    const stored = String(widgetSetting(group, "displayMode", ""))
    if (stored !== "") return stored
    return widgetSetting(group, "compact", false) === true ? "icon" : "full"
  }

  function setWidgetMode(mode) {
    if (!selectedSupported) return false
    const value = String(mode)
    controller.setGroupSetting(selectedWidget.group, "displayMode", value)
    controller.setGroupSetting(selectedWidget.group, "compact",
      selectedWidget.group === "G9" ? value === "full" : value === "icon")
    return true
  }

  function setWidgetSurface(mode) {
    if (!selectedSupported) return false
    const value = String(mode)
    controller.setGroupSetting(selectedWidget.group, "colorMode", value)
    controller.setGroupSetting(selectedWidget.group, "widgetBorder",
      value === "border" || value === "both")
    return true
  }

  Rectangle {
    width: parent.width
    height: Commons.Style.space(54)
    radius: 0
    color: "transparent"
    border.width: 1
    border.color: root.controller.controlBorderColor

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Commons.Style.space(10)
      height: Commons.Style.space(26)
      radius: 0
      color: root.controller.marketPanel
      border.width: 1
      border.color: root.controller.controlBorderColor

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Commons.Style.space(20),
          previewContent.implicitWidth + Commons.Style.space(18))
        height: Commons.Style.space(24)
        radius: root.selectedHasFill
          ? Commons.Style.space(12) : root.controller.controlRadius
        color: root.selectedHasFill ? root.selectedFillColor : "transparent"
        opacity: Number(root.widgetSetting(root.selectedWidget.group,
          "surfaceOpacity", 1))
        border.width: root.selectedHasBorder ? Number(root.widgetSetting(
          root.selectedWidget.group, "widgetBorderWidth", 1)) : 0
        border.color: root.selectedHasBorder
          ? root.selectedFillColor : "transparent"

        Row {
          id: previewContent
          anchors.centerIn: parent
          spacing: Commons.Style.space(5)

          IconText {
            visible: root.selectedDisplayMode !== "text"
            text: root.selectedWidget.glyph
            color: root.selectedHasFill && root.selectedColor !== "inherit"
              ? root.controller.contrastColor(root.selectedColor)
              : root.foreground
            font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
          }

          Text {
            visible: root.selectedDisplayMode !== "icon"
            text: root.selectedWidget.label
            color: root.selectedHasFill && root.selectedColor !== "inherit"
              ? root.controller.contrastColor(root.selectedColor)
              : root.foreground
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
            font.weight: Font.Medium
          }
        }
      }
    }
  }

  Row {
    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      id: providerRepeater
      model: root.providerOptions

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing * 3) / 4
        controller: root.controller
        label: modelData.label
        selected: root.providerFilter === modelData.value
        foreground: root.foreground
        accent: root.accent
        uiScale: root.uiScale
        onClicked: root.chooseProvider(modelData.value)
      }
    }
  }

  Row {
    width: parent.width
    height: Commons.Style.space(310)
    spacing: Commons.Style.space(10)

    Rectangle {
      width: Math.round(parent.width * 0.34)
      height: parent.height
      radius: 0
      color: root.controller.controlFillColor
      border.width: 1
      border.color: root.controller.controlBorderColor
      clip: true

      Flickable {
        anchors.fill: parent
        anchors.margins: Commons.Style.space(5)
        contentWidth: width
        contentHeight: widgetList.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        clip: true

        Column {
          id: widgetList
          width: parent.width
          spacing: Commons.Style.space(3)

          Repeater {
            id: widgetRepeater
            model: root.filteredOptions

            delegate: Rectangle {
              id: widgetRow
              required property var modelData
              readonly property bool selected:
                root.selectedWidgetGroup === String(modelData.group || "")
                  && (String(modelData.group || "") !== ""
                    || root.selectedWidgetId === modelData.id)
              width: parent.width
              height: Commons.Style.space(38)
              radius: 0
              color: selected
                ? root.controller.buttonFillColor
                : widgetPointer.containsMouse
                  ? root.controller.controlHoverFillColor : "transparent"
              border.width: selected ? 1 : 0
              border.color: root.accent

              Row {
                anchors.fill: parent
                anchors.leftMargin: Commons.Style.space(8)
                anchors.rightMargin: Commons.Style.space(7)
                spacing: Commons.Style.space(7)

                IconText {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Commons.Style.space(20)
                  text: widgetRow.modelData.glyph
                  color: widgetRow.selected ? root.accent : root.foreground
                  horizontalAlignment: Text.AlignHCenter
                  font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - x
                  spacing: 0

                  Text {
                    width: parent.width
                    text: widgetRow.modelData.label
                    color: root.foreground
                    elide: Text.ElideRight
                    font.family: root.controller.marketFont
                    font.pixelSize: Commons.Style.font.caption * root.uiScale
                    font.weight: widgetRow.selected ? Font.DemiBold : Font.Normal
                  }

                  Text {
                    width: parent.width
                    text: widgetRow.modelData.supported
                      ? root.widgetMode(widgetRow.modelData.group)
                      : widgetRow.modelData.provider
                    color: widgetRow.selected ? root.accent : root.foreground
                    opacity: widgetRow.selected ? 0.9 : 0.42
                    elide: Text.ElideRight
                    font.family: root.controller.marketFont
                    font.pixelSize: Commons.Style.font.caption
                      * root.uiScale * 0.86
                  }
                }
              }

              MouseArea {
                id: widgetPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedWidgetGroup =
                    String(widgetRow.modelData.group || "")
                  root.selectedWidgetId = String(widgetRow.modelData.id || "")
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.filteredOptions.length === 0
            text: "No active widgets from this provider"
            color: root.foreground
            opacity: 0.46
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
          }
        }
      }
    }

    Rectangle {
      width: parent.width - x
      height: parent.height
      radius: 0
      color: root.controller.controlFillColor
      border.width: 1
      border.color: root.controller.controlBorderColor
      clip: true

      Flickable {
        anchors.fill: parent
        anchors.margins: Commons.Style.space(10)
        contentWidth: width
        contentHeight: inspector.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        clip: true

        Column {
          id: inspector
          width: parent.width
          spacing: Commons.Style.space(7)

          Item {
            width: parent.width
            height: Commons.Style.space(24)

            Row {
              anchors.left: parent.left
              height: parent.height
              spacing: Commons.Style.space(6)

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
                font.family: root.controller.marketFont
                font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
                font.weight: Font.DemiBold
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.selectedSupported
              text: "Reset ↺"
              color: resetPointer.containsMouse ? root.accent : root.foreground
              opacity: resetPointer.containsMouse ? 1 : 0.58
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.caption * root.uiScale

              MouseArea {
                id: resetPointer
                anchors.fill: parent
                anchors.margins: -Commons.Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.controller.resetGroupAppearance(
                  root.selectedWidget.group)
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.selectedSupported
            text: "This plugin does not expose the Shibumi appearance contract. "
              + "Its original rendering remains unchanged."
            color: root.foreground
            opacity: 0.58
            wrapMode: Text.WordWrap
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
          }

          SectionLabel {
            visible: root.selectedSupported
            text: "DISPLAY"
          }

          Row {
            visible: root.selectedSupported
            width: parent.width
            spacing: Commons.Style.space(4)

            Repeater {
              id: displayModeRepeater
              model: ["full", "icon", "text"]

              delegate: CompactSettingChoice {
                required property string modelData
                width: (parent.width - parent.spacing * 2) / 3
                controller: root.controller
                label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                selected: root.selectedDisplayMode === modelData
                foreground: root.foreground
                accent: root.accent
                uiScale: root.uiScale
                onClicked: root.setWidgetMode(modelData)
              }
            }
          }

          SectionLabel {
            visible: root.selectedSupported
            text: "SURFACE"
          }

          Row {
            visible: root.selectedSupported
            width: parent.width
            spacing: Commons.Style.space(4)

            Repeater {
              id: surfaceModeRepeater
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
                selected: root.selectedSurfaceMode === modelData.value
                foreground: root.foreground
                accent: root.accent
                fontSize: Commons.Style.font.caption * root.uiScale * 0.92
                onClicked: root.setWidgetSurface(modelData.value)
              }
            }
          }

          SectionLabel {
            visible: root.selectedSupported && root.selectedHasFill
            text: "COLOR"
          }

          Grid {
            visible: root.selectedSupported && root.selectedHasFill
            width: parent.width
            columns: 10
            columnSpacing: Commons.Style.space(4)
            rowSpacing: Commons.Style.space(4)

            Repeater {
              id: widgetColorRepeater
              model: root.colorOptions

              delegate: Rectangle {
                id: widgetSwatch
                required property var modelData
                readonly property bool selected:
                  root.selectedColor === modelData.value
                width: (parent.width - parent.columnSpacing * 9) / 10
                height: Commons.Style.space(25)
                radius: 0
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
                    : root.controller.contrastColor(
                        widgetSwatch.modelData.value)
                  font.family: root.controller.marketFont
                  font.pixelSize: Commons.Style.font.caption
                    * root.uiScale * 0.9
                  font.weight: Font.Medium
                }

                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 2
                  visible: widgetSwatch.selected
                  width: Commons.Style.space(9)
                  height: 2
                  radius: 1
                  color: widgetSwatch.modelData.value === "inherit"
                    ? root.accent
                    : root.controller.contrastColor(
                        widgetSwatch.modelData.value)
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.controller.setGroupSetting(
                    root.selectedWidget.group, "color",
                    widgetSwatch.modelData.value)
                }
              }
            }
          }

          Rectangle {
            visible: root.selectedSupported
            width: parent.width
            height: Commons.Style.space(31)
            radius: 0
            color: advancedPointer.containsMouse
              ? root.controller.controlHoverFillColor : "transparent"
            border.width: 1
            border.color: root.controller.controlBorderColor

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Commons.Style.space(9)
              anchors.verticalCenter: parent.verticalCenter
              text: root.advancedOpen ? "Advanced" : "More"
              color: root.foreground
              font.family: root.controller.marketFont
              font.pixelSize: Commons.Style.font.caption * root.uiScale
              font.weight: Font.Medium
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Commons.Style.space(9)
              anchors.verticalCenter: parent.verticalCenter
              text: root.advancedOpen ? "⌃" : "⌄"
              color: root.accent
              font.pixelSize: Commons.Style.font.caption * root.uiScale
            }

            MouseArea {
              id: advancedPointer
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.advancedOpen = !root.advancedOpen
            }
          }

          Column {
            visible: root.selectedSupported && root.advancedOpen
            width: parent.width
            spacing: Commons.Style.space(7)

            SectionLabel { text: "CONTENT TONE" }
            OptionRow {
              options: [
                { value: "auto", label: "Auto" },
                { value: "background", label: "Background" },
                { value: "foreground", label: "Foreground" }
              ]
              currentValue: String(root.widgetSetting(
                root.selectedWidget.group, "tone", "auto"))
              onChosen: value => root.controller.setGroupSetting(
                root.selectedWidget.group, "tone", value)
            }

            SectionLabel { text: "SHAPE" }
            OptionRow {
              options: [
                { value: "auto", label: "Default" },
                { value: "square", label: "Square" },
                { value: "soft", label: "Soft" },
                { value: "round", label: "Round" }
              ]
              currentValue: String(root.widgetSetting(
                root.selectedWidget.group, "widgetRadius", "auto"))
              onChosen: value => root.controller.setGroupSetting(
                root.selectedWidget.group, "widgetRadius", value)
            }

            SectionLabel { text: "SPACING" }
            OptionRow {
              options: [
                { value: "auto", label: "Auto" },
                { value: "none", label: "None" },
                { value: "compact", label: "Compact" },
                { value: "roomy", label: "Roomy" }
              ]
              currentValue: String(root.widgetSetting(
                root.selectedWidget.group, "widgetPadding", "auto"))
              onChosen: value => root.controller.setGroupSetting(
                root.selectedWidget.group, "widgetPadding", value)
            }

            SectionLabel { text: "OPACITY" }
            OptionRow {
              options: [
                { value: 1, label: "100%" },
                { value: 0.8, label: "80%" },
                { value: 0.6, label: "60%" }
              ]
              currentValue: Number(root.widgetSetting(
                root.selectedWidget.group, "surfaceOpacity", 1))
              onChosen: value => root.controller.setGroupSetting(
                root.selectedWidget.group, "surfaceOpacity", value)
            }

            CompactSettingChoice {
              width: parent.width
              controller: root.controller
              label: "2 px outline"
              selected: Number(root.widgetSetting(root.selectedWidget.group,
                "widgetBorderWidth", 1)) === 2
              foreground: root.foreground
              accent: root.accent
              uiScale: root.uiScale
              onClicked: root.controller.setGroupSetting(
                root.selectedWidget.group, "widgetBorderWidth",
                selected ? 1 : 2)
            }
          }
        }
      }
    }
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.48
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.letterSpacing: 1
  }

  component OptionRow: Row {
    id: optionRow
    required property var options
    required property var currentValue
    signal chosen(var value)

    width: parent.width
    spacing: Commons.Style.space(4)

    Repeater {
      model: optionRow.options

      delegate: CompactSettingChoice {
        required property var modelData
        width: (parent.width - parent.spacing
          * (optionRow.options.length - 1)) / optionRow.options.length
        controller: root.controller
        label: modelData.label
        selected: optionRow.currentValue === modelData.value
        foreground: root.foreground
        accent: root.accent
        fontSize: Commons.Style.font.caption * root.uiScale * 0.9
        onClicked: optionRow.chosen(modelData.value)
      }
    }
  }
}
