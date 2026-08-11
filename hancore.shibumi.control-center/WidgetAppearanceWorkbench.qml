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
  property bool detailOpen: false
  property bool resetActionVisible: false
  property string resetActionLabel: ""
  property color resetActionColor: accent
  property string toggleErrorGroup: ""
  property string toggleErrorMessage: ""
  signal widgetRequested(string groupId, string pluginId)
  signal overviewRequested()
  signal resetActionRequested()

  readonly property var displayModeOptions: [
    { value: "icon", label: "Icon" },
    { value: "full", label: "Icon + text" },
    { value: "text", label: "Text" }
  ]
  readonly property var mediaStyleOptions: [
    { value: "default", label: "Default" },
    { value: "full", label: "Full" }
  ]
  readonly property var v1CompactGroupIds: [
    "G4", "G5", "G6", "G11", "G12", "G13", "G14", "G15", "G18"
  ]
  readonly property var v1CompactValueGroupIds: [
    "G4", "G5", "G6", "G12", "G13"
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
  readonly property var activeGroupIds: controller.v2LayoutActive === true
    ? [
        "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9",
        "G10", "G11", "G12", "G13", "G14", "G15", "G16", "G17", "G18"
      ]
    : [
        "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9",
        "G10", "G11", "G12", "G13", "G14", "G15"
      ]
  readonly property var overviewOptions: buildOverviewOptions()
  readonly property var activeOptions: overviewOptions.active
  readonly property var inactiveOptions: overviewOptions.inactive
  readonly property var editableOptions: activeOptions.concat(inactiveOptions)
  readonly property var selectedWidget: optionForSelection(
    selectedWidgetGroup, selectedWidgetId)
  readonly property string selectedCatalogGroup:
    String(selectedWidget ? selectedWidget.catalogGroup || "" : "")
  readonly property bool selectedLauncher: selectedCatalogGroup === "G1"
  readonly property bool selectedMedia: selectedCatalogGroup === "G9"
  readonly property bool v1LayoutActive: controller.v2LayoutActive !== true
  readonly property bool selectedV1Appearance: v1LayoutActive
    && selectedSupported
  readonly property bool selectedV1CpuCompact: selectedV1Appearance
    && selectedCatalogGroup === "G5" && selectedDisplayMode === "icon"
  readonly property var selectedModeOptions: modeOptionsForGroup(
    selectedWidget ? selectedWidget.group : "", selectedCatalogGroup)
  readonly property bool selectedActive:
    selectedWidget && selectedWidget.active === true
  readonly property bool selectedSupported: selectedWidget
    && String(selectedWidget.group || "") !== ""
  readonly property string selectedDisplayMode: selectedSupported
    ? selectedLauncher
      ? String(controller.launcherConfig.mode || "text")
      : widgetMode(selectedWidget.group, selectedCatalogGroup)
    : "full"
  readonly property bool selectedV1CompactShowsValue: selectedV1Appearance
    && selectedDisplayMode === "icon"
    && v1CompactValueGroupIds.indexOf(selectedCatalogGroup) >= 0
  readonly property string selectedV1CompactValue:
    selectedCatalogGroup === "G4" ? "12G" : "42%"
  readonly property string selectedSurfaceMode: selectedSupported
    ? String(widgetSetting(selectedWidget.group, "colorMode", "fill")) : "none"
  readonly property string selectedColor: selectedSupported
    ? String(widgetSetting(selectedWidget.group, "color", "inherit")) : "inherit"
  readonly property string selectedContentTone: selectedSupported
    ? String(widgetSetting(selectedWidget.group, "tone", "auto")) : "auto"
  readonly property real selectedSurfaceOpacity: selectedSupported
    ? Number(widgetSetting(selectedWidget.group, "surfaceOpacity", 1)) : 1
  readonly property real selectedOutlineWidth: selectedSupported
    ? Number(widgetSetting(selectedWidget.group, "widgetBorderWidth", 1)) : 1
  readonly property string selectedOutlineColor: selectedSupported
    ? String(widgetSetting(selectedWidget.group, "widgetBorderColor",
        widgetSetting(selectedWidget.group,
          "widgetBorderUsesSurfaceColor", false) === true
            ? selectedColor : "inherit"))
    : "inherit"
  readonly property bool selectedHasFill: selectedV1Appearance
    ? selectedColor !== "inherit"
    : !v1LayoutActive
      && (selectedSurfaceMode === "fill" || selectedSurfaceMode === "both")
  readonly property bool selectedHasBorder:
    !v1LayoutActive
      && (selectedSurfaceMode === "border" || selectedSurfaceMode === "both")
  readonly property color selectedFillColor: selectedColor === "inherit"
    ? controller.controlHoverFillColor
    : controller.accentColor(selectedColor)
  readonly property color selectedPreviewFillColor: selectedHasFill
    ? Qt.rgba(selectedFillColor.r, selectedFillColor.g, selectedFillColor.b,
        selectedFillColor.a * selectedSurfaceOpacity)
    : "transparent"
  readonly property color selectedPreviewContentColor: {
    if (!selectedHasFill || selectedColor === "inherit") return foreground
    if (selectedContentTone === "background")
      return "renderedSurfaceColor" in controller
        ? controller.renderedSurfaceColor : controller.controlFillColor
    if (selectedContentTone === "foreground") return foreground
    return controller.contrastColor(selectedColor)
  }
  readonly property color selectedBorderColor:
    selectedOutlineColor !== "inherit"
      ? controller.accentColor(selectedOutlineColor)
      : controller.controlBorderColor
  readonly property real choiceControlHeight: Commons.Style.space(40)
  readonly property real choiceListHeight: Commons.Style.space(48)
  readonly property real choiceRowHeight: Commons.Style.space(16)
  readonly property real surfaceChoiceHeight: choiceRowHeight * 4
  readonly property real choiceFontSize:
    Commons.Style.font.caption * uiScale
  readonly property int visibleOptionCount: activeOptions.length
  readonly property int inactiveOptionCount: inactiveOptions.length
  readonly property int overviewRowCount: Math.max(
    Math.ceil(activeOptions.length / 3),
    Math.ceil(inactiveOptions.length
      / (inactiveOptions.length <= 5 ? 1 : 2)))
  readonly property bool ready: widgetRepeater.count === activeOptions.length
    && inactiveWidgetRepeater.count === inactiveOptions.length
    && contentModeChoices.ready
    && profileModeChoices.ready
    && mediaContentToneChoices.ready
    && contentToneChoices.ready
    && surfaceModeChoices.ready
    && outlineChoices.ready
    && fillColorPalette.ready
    && outlineColorPalette.ready
    && opacityChoices.ready

  width: parent ? parent.width : 1
  spacing: Commons.Style.space(8)

  Timer {
    id: toggleErrorTimer
    interval: 4200
    onTriggered: {
      root.toggleErrorGroup = ""
      root.toggleErrorMessage = ""
    }
  }

  function editableOption(groupValue, idValue) {
    const group = String(groupValue || "")
    const id = String(idValue || "")
    for (let index = 0; index < editableOptions.length; index++) {
      const option = editableOptions[index]
      if (group !== "" && (String(option.group || "") === group
          || String(option.catalogGroup || "") === group))
        return option
      if (id !== "" && String(option.id || "") === id)
        return option
    }
    return null
  }

  function optionForSelection(groupValue, idValue) {
    const option = editableOption(groupValue, idValue)
    if (option) return option
    return editableOptions.length > 0 ? editableOptions[0] : ({
      group: "", catalogGroup: "", id: "", label: "Widget",
      glyph: "widgets", modes: ["full"], region: "",
      supported: false, active: false
    })
  }

  function isEditableWidget(groupValue, idValue) {
    return editableOption(groupValue, idValue) !== null
  }

  function pluginIdForGroup(groupValue) {
    const plugin = pluginForGroup(groupValue)
    if (plugin) return String(plugin.id || "")
    const ids = {
      G1: "hancore.shibumi.control-center",
      G2: "hancore.shibumi.workspaces",
      G3: "hancore.shibumi.status",
      G4: "hancore.shibumi.memory",
      G5: "hancore.shibumi.cpu",
      G6: "hancore.shibumi.audio",
      G7: "hancore.shibumi.ai",
      G8: "hancore.shibumi.center",
      G9: "hancore.shibumi.media",
      G10: "hancore.shibumi.quick-access",
      G11: "hancore.shibumi.network",
      G12: "hancore.shibumi.battery",
      G13: "hancore.shibumi.brightness",
      G14: "hancore.shibumi.power-profile",
      G15: "hancore.shibumi.bluetooth",
      G16: "hancore.shibumi.temperature",
      G17: "hancore.shibumi.gpu",
      G18: "hancore.shibumi.storage"
    }
    return String(ids[String(groupValue || "")] || "")
  }

  function catalogGroupForActiveGroup(groupValue) {
    const group = String(groupValue || "")
    if (catalogOptionForGroup(group)) return group
    if (group.indexOf("G:") !== 0) return ""
    return String(controller.shibumiWidgetGroup(group.slice(2)) || "")
  }

  function settingsGroupForCatalogGroup(groupValue) {
    const group = String(groupValue || "")
    if (controller.v2LayoutActive === true
        || activeGroupIds.indexOf(group) >= 0)
      return group
    const pluginId = pluginIdForGroup(group)
    return pluginId !== "" ? "G:" + pluginId : group
  }

  function optionModel(source, settingsGroup, catalogGroup, region, active) {
    return {
      group: settingsGroup,
      catalogGroup: catalogGroup,
      id: pluginIdForGroup(catalogGroup),
      label: source.label,
      glyph: source.glyph,
      modes: source.modes,
      region: region,
      supported: true,
      active: active === true
    }
  }

  function displayRank(groupValue) {
    const order = [
      "G1", "G2", "G3",
      "G5", "G6", "G7",
      "G9", "G10", "G11",
      "G12", "G13", "G15",
      "G4", "G8", "G14",
      "G16", "G17", "G18"
    ]
    const rank = order.indexOf(String(groupValue || ""))
    return rank >= 0 ? rank : order.length
  }

  function sortForOverview(options) {
    return options.slice().sort(function(left, right) {
      return displayRank(left.catalogGroup) - displayRank(right.catalogGroup)
    })
  }

  function isCatalogGroupActive(groupValue, activeValues) {
    const group = String(groupValue || "")
    return activeValues.some(function(option) {
      return String(option.catalogGroup || "") === group
    })
  }

  function buildInactiveOptions(activeValues) {
    const result = []
    for (let index = 0; index < widgetOptions.length; index++) {
      const source = widgetOptions[index]
      const catalogGroup = String(source.group || "")
      if (catalogGroup === ""
          || !isShibumiWidgetOption(source)
          || isCatalogGroupActive(catalogGroup, activeValues)) continue
      result.push(optionModel(source,
        settingsGroupForCatalogGroup(catalogGroup), catalogGroup, "", false))
    }
    return sortForOverview(result)
  }

  function buildOverviewOptions() {
    void(controller.activeWidgetOrder)
    void(controller.v2LayoutActive)
    void(activeGroupIds)
    const active = buildActiveOptions()
    return { active: active, inactive: buildInactiveOptions(active) }
  }

  function setWidgetActive(option, enabled) {
    if (!option) return false
    const catalogGroup = String(option.catalogGroup || "")
    const pluginId = String(option.id || "")
    if (catalogGroup === "G1") {
      toggleErrorGroup = catalogGroup
      toggleErrorMessage = "Control Center access stays active"
      toggleErrorTimer.restart()
      return false
    }
    if (pluginId !== ""
        && typeof controller.setPluginEnabled === "function"
        && controller.setPluginEnabled(pluginId, enabled === true)) {
      toggleErrorGroup = ""
      toggleErrorMessage = ""
      return true
    }
    toggleErrorGroup = catalogGroup
    toggleErrorMessage = String(controller.pluginActionError
      || "Widget state could not be changed")
    toggleErrorTimer.restart()
    return false
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

  function catalogOptionForGroup(groupValue) {
    const group = String(groupValue || "")
    for (let index = 0; index < widgetOptions.length; index++) {
      if (String(widgetOptions[index].group || "") === group)
        return widgetOptions[index]
    }
    return null
  }

  function isShibumiWidgetOption(source) {
    if (!source) return false
    return pluginIdForGroup(String(source.group || ""))
      .indexOf("hancore.shibumi.") === 0
  }

  function activeOrder() {
    const source = controller.activeWidgetOrder || ({})
    const regions = ["left", "center", "right"]
    const valid = regions.every(function(region) {
      return Array.isArray(source[region])
    })
    if (valid) return source
    return controller.v2LayoutActive === true
      ? {
          left: ["G1", "G2", "G3", "G5", "G6", "G4", "G7"],
          center: ["G8"],
          right: [
            "G9", "G10", "G11", "G14", "G12", "G13",
            "G16", "G18", "G17", "G15"
          ]
        }
      : {
          left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
          center: ["G8"],
          right: ["G9", "G10", "G11", "G12", "G13", "G14", "G15"]
        }
  }

  function buildActiveOptions() {
    void(controller.activeWidgetOrder)
    void(controller.v2LayoutActive)
    void(activeGroupIds)
    const result = []
    const seen = ({})
    const order = activeOrder()
    const regions = ["left", "center", "right"]
    for (let regionIndex = 0; regionIndex < regions.length; regionIndex++) {
      const region = regions[regionIndex]
      const groups = order[region] || []
      for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        const settingsGroup = String(groups[groupIndex] || "")
        const catalogGroup = catalogGroupForActiveGroup(settingsGroup)
        const source = catalogOptionForGroup(catalogGroup)
        const supportedGroup = activeGroupIds.indexOf(catalogGroup) >= 0
          || settingsGroup.indexOf("G:") === 0
        if (!source || !supportedGroup || seen[catalogGroup] === true
            || (typeof controller.groupEnabled === "function"
              ? !controller.groupEnabled(settingsGroup)
              : controller.groupSetting(
                  settingsGroup, "enabled", true) === false))
          continue
        seen[catalogGroup] = true
        result.push(optionModel(source, settingsGroup,
          catalogGroup, region, true))
      }
    }
    return sortForOverview(result)
  }

  function widgetSetting(group, key, fallback) {
    return controller.groupSetting(group, key, fallback)
  }

  function widgetAppearanceChanged(groupValue) {
    const group = String(groupValue || "")
    const catalogGroup = catalogGroupForSettingsGroup(group)
    if (controller.v2LayoutActive !== true) {
      const fillChanged =
        String(widgetSetting(group, "color", "inherit")) !== "inherit"
        || String(widgetSetting(group, "tone", "auto")) !== "auto"
        || Number(widgetSetting(group, "surfaceOpacity", 1)) !== 1
      if (catalogGroup === "G9")
        return widgetMode(group, catalogGroup) !== "default" || fillChanged
      const compactChanged = v1CompactGroupIds.indexOf(catalogGroup) >= 0
        && widgetMode(group, catalogGroup) !== "full"
      return compactChanged || fillChanged
    }
    const color = String(widgetSetting(group, "color", "inherit"))
    const usesSurfaceColor = widgetSetting(
      group, "widgetBorderUsesSurfaceColor", false) === true
    const borderColor = String(widgetSetting(group, "widgetBorderColor",
      usesSurfaceColor ? color : "inherit"))
    return (catalogGroup !== "G1"
        && widgetMode(group, catalogGroup) !== "full")
      || color !== "inherit"
      || String(widgetSetting(group, "colorMode", "fill")) !== "fill"
      || String(widgetSetting(group, "tone", "auto")) !== "auto"
      || widgetSetting(group, "widgetBorder", false) === true
      || Number(widgetSetting(group, "widgetBorderWidth", 1)) !== 1
      || borderColor !== "inherit"
      || usesSurfaceColor
      || String(widgetSetting(group, "widgetPadding", "auto")) !== "auto"
      || String(widgetSetting(group, "widgetRadius", "auto")) !== "auto"
      || Number(widgetSetting(group, "surfaceOpacity", 1)) !== 1
  }

  function widgetAppearanceIndicatorColor(groupValue) {
    return controller.accentColor("color03")
  }

  function isActiveWidget(groupValue) {
    const option = editableOption(groupValue, "")
    return option !== null && option.active === true
  }

  function catalogGroupForSettingsGroup(groupValue) {
    const group = String(groupValue || "")
    if (group.indexOf("G:") !== 0) return group
    return String(controller.shibumiWidgetGroup(group.slice(2)) || group)
  }

  function modeOptionsForGroup(groupValue, catalogGroupValue) {
    const catalogGroup = String(catalogGroupValue
      || catalogGroupForSettingsGroup(groupValue) || "")
    if (catalogGroup === "G1") return []
    if (catalogGroup === "G9") return mediaStyleOptions
    if (controller.v2LayoutActive === true) return displayModeOptions
    const compactAvailable = v1CompactGroupIds.indexOf(catalogGroup) >= 0
    return compactAvailable ? [
      { value: "full", label: "Default", enabled: true },
      { value: "icon", label: "Compact", enabled: true }
    ] : [
      { value: "full", label: "Default", enabled: true }
    ]
  }

  function widgetMode(group, catalogGroupValue) {
    const catalogGroup = String(catalogGroupValue
      || catalogGroupForSettingsGroup(group) || "")
    if (catalogGroup === "G9")
      return String(widgetSetting(group, "mediaStyle", "default")) === "full"
        ? "full" : "default"
    const stored = String(widgetSetting(group, "displayMode", ""))
    const mode = stored !== "" ? stored
      : widgetSetting(group, "compact", false) === true ? "icon" : "full"
    const options = modeOptionsForGroup(group, catalogGroup)
    for (let index = 0; index < options.length; index++) {
      if (String(options[index].value) === mode
          && options[index].enabled !== false) return mode
    }
    for (let index = 0; index < options.length; index++) {
      if (options[index].enabled !== false)
        return String(options[index].value)
    }
    return "full"
  }

  function displayModeLabel(group, mode) {
    const value = String(mode || "")
    const options = modeOptionsForGroup(group,
      catalogGroupForSettingsGroup(group))
    for (let index = 0; index < options.length; index++) {
      if (options[index].value === value)
        return options[index].label
    }
    return options.length > 0 ? String(options[0].label) : "Default"
  }

  function widgetPresentationLabel(group, catalogGroupValue) {
    const catalogGroup = String(catalogGroupValue
      || catalogGroupForSettingsGroup(group) || "")
    if (catalogGroup === "G1")
      return "Logo · " + (String(controller.launcherConfig.mode || "text")
        === "icon" ? "Icon" : "Wordmark")
    return displayModeLabel(group, widgetMode(group, catalogGroup))
  }

  function setWidgetMode(mode) {
    if (!selectedSupported || selectedLauncher) return false
    const value = String(mode)
    const available = selectedModeOptions.some(function(option) {
      return String(option.value) === value && option.enabled !== false
    })
    if (!available) return false
    if (selectedMedia)
      return controller.setGroupSetting(
        selectedWidget.group, "mediaStyle", value)
    return controller.setGroupSetting(
      selectedWidget.group, "displayMode", value)
  }

  function cycleWidgetMode() {
    if (!selectedSupported) return false
    const available = selectedModeOptions.filter(function(option) {
      return option.enabled !== false
    })
    if (available.length < 1) return false
    let currentIndex = 0
    for (let index = 0; index < available.length; index++) {
      if (available[index].value === selectedDisplayMode) {
        currentIndex = index
        break
      }
    }
    const nextIndex = (currentIndex + 1) % available.length
    return setWidgetMode(available[nextIndex].value)
  }

  function cycleWidgetOpacity() {
    if (!selectedSupported) return false
    const current = selectedSurfaceOpacity
    const next = current > 0.9 ? 0.8
      : current > 0.7 ? 0.6 : current > 0.5 ? 0.4 : 1
    controller.setGroupSetting(selectedWidget.group, "surfaceOpacity", next)
    return true
  }

  function cycleWidgetSurface() {
    if (!selectedSupported) return false
    const next = selectedSurfaceMode === "none" ? "fill"
      : selectedSurfaceMode === "fill" ? "border"
      : selectedSurfaceMode === "border" ? "both" : "none"
    return setWidgetSurface(next)
  }

  function setWidgetSurface(mode) {
    if (!selectedSupported) return false
    const value = String(mode)
    controller.setGroupSetting(selectedWidget.group, "colorMode", value)
    controller.setGroupSetting(selectedWidget.group, "widgetBorder",
      value === "border" || value === "both")
    return true
  }

  Item {
    width: parent.width
    readonly property real overviewHeight: Math.max(
      Commons.Style.space(105),
      Math.max(activeWidgetGrid.implicitHeight,
        inactiveWidgetGrid.implicitHeight) + Commons.Style.space(39))
    readonly property real routeHeight: root.detailOpen
      ? Commons.Style.space(34) : 0
    readonly property real inspectorHeight:
      inspector.implicitHeight + Commons.Style.space(20)
    height: root.detailOpen
      ? routeHeight + Commons.Style.space(8) + inspectorHeight
      : overviewHeight

    Item {
      id: detailRoute
      visible: root.detailOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: parent.routeHeight

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        spacing: Commons.Style.space(7)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(7)
          height: width
          radius: width / 2
          color: allWidgetsPointer.containsMouse
            ? root.accent : root.controller.controlBorderColor
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "ALL WIDGETS"
          color: allWidgetsPointer.containsMouse
            ? root.accent : root.foreground
          opacity: allWidgetsPointer.containsMouse ? 1 : 0.62
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
          font.letterSpacing: 0.8
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(42)
          height: 1
          color: root.controller.controlBorderColor
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(7)
          height: width
          radius: width / 2
          color: root.accent
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.selectedWidget.label.toUpperCase()
          color: root.foreground
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
          font.letterSpacing: 0.8
        }
      }

      MouseArea {
        id: allWidgetsPointer
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Commons.Style.space(116)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.overviewRequested()
      }
    }

    Rectangle {
      visible: !root.detailOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: parent.overviewHeight
      radius: root.controller.controlRadius
      color: root.controller.controlFillColor
      border.width: 1
      border.color: root.controller.controlBorderColor
      clip: true

      Row {
        id: widgetSections
        anchors.fill: parent
        anchors.margins: Commons.Style.space(5)
        spacing: Commons.Style.space(8)

        Column {
          width: Math.floor((parent.width - widgetSectionDivider.width
            - widgetSections.spacing * 2) * 0.66)
          spacing: Commons.Style.space(4)

          WidgetSectionHeader {
            title: "ACTIVE WIDGETS"
            count: root.activeOptions.length
            actionLabel: root.resetActionVisible
              ? root.resetActionLabel : ""
            actionColor: root.resetActionColor
            onActionRequested: root.resetActionRequested()
          }

          Grid {
            id: activeWidgetGrid
            width: parent.width
            columns: 3
            columnSpacing: Commons.Style.space(4)
            rowSpacing: Commons.Style.space(3)

            Repeater {
              id: widgetRepeater
              model: root.activeOptions

              delegate: WidgetOptionTile {
                required property var modelData
                option: modelData
                width: (parent.width - parent.columnSpacing * 2) / 3
              }
            }
          }
        }

        Rectangle {
          id: widgetSectionDivider
          width: 1
          height: parent.height
          color: root.controller.dividerColor
        }

        Column {
          width: parent.width - x
          spacing: Commons.Style.space(4)

          WidgetSectionHeader {
            title: "INACTIVE WIDGETS"
            count: root.inactiveOptions.length
          }

          Grid {
            id: inactiveWidgetGrid
            width: parent.width
            columns: root.inactiveOptions.length <= 5 ? 1 : 2
            columnSpacing: Commons.Style.space(4)
            rowSpacing: Commons.Style.space(3)

            Repeater {
              id: inactiveWidgetRepeater
              model: root.inactiveOptions

              delegate: WidgetOptionTile {
                required property var modelData
                option: modelData
                width: (parent.width - parent.columnSpacing
                  * (parent.columns - 1)) / parent.columns
              }
            }
          }
        }
      }
    }

    Rectangle {
      id: inspectorCard
      visible: root.detailOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: detailRoute.bottom
      anchors.topMargin: root.detailOpen ? Commons.Style.space(8) : 0
      height: parent.inspectorHeight
      radius: root.controller.controlRadius
      color: root.controller.controlFillColor
      border.width: 1
      border.color: root.controller.controlBorderColor
      clip: true

      Flickable {
        id: inspectorFlick
        anchors.fill: parent
        anchors.margins: Commons.Style.space(10)
        contentWidth: width
        contentHeight: inspector.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: false
        clip: true

        Column {
          id: inspector
          width: parent.width
          spacing: Commons.Style.space(7)

          Item {
            width: parent.width
            height: Commons.Style.space(32)

            Row {
              id: selectedTitle
              anchors.left: parent.left
              anchors.right: editorHeaderActions.left
              anchors.rightMargin: Commons.Style.space(10)
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
                width: parent.width - x
                text: root.selectedWidget.label
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.controller.marketFont
                font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
                font.weight: Font.DemiBold
              }
            }

            Row {
              id: editorHeaderActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              spacing: Commons.Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.detailOpen
                text: (root.controller.v2LayoutActive ? "V2 " : "V1 ")
                  + (root.selectedActive ? "ACTIVE" : "INACTIVE")
                color: root.accent
                font.family: root.controller.marketFont
                font.pixelSize:
                  Commons.Style.font.caption * root.uiScale * 0.9
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(Commons.Style.space(90),
                  integratedPreviewContent.implicitWidth
                    + Commons.Style.space(10))
                height: Commons.Style.space(20)
                radius: root.selectedHasFill
                  ? Commons.Style.space(10) : root.controller.controlRadius
                color: root.selectedPreviewFillColor
                opacity: 1
                border.width: root.selectedHasBorder
                  ? Number(root.widgetSetting(root.selectedWidget.group,
                      "widgetBorderWidth", 1)) : 0
                border.color: root.selectedHasBorder
                  ? root.selectedBorderColor : "transparent"

                Item {
                  id: integratedPreviewContent
                  anchors.centerIn: parent
                  width: implicitWidth
                  height: parent.height
                  implicitWidth: (previewGlyph.visible
                      ? previewGlyph.implicitWidth : 0)
                    + (previewGlyph.visible && previewLabel.visible
                      ? Commons.Style.space(5) : 0)
                    + (previewLabel.visible ? previewLabel.implicitWidth : 0)

                  IconText {
                    id: previewGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.selectedDisplayMode !== "text"
                    text: root.selectedV1CpuCompact
                      ? "planner_review" : root.selectedWidget.glyph
                    color: root.selectedPreviewContentColor
                    font.pixelSize:
                      Commons.Style.font.iconLarge * root.uiScale * 0.76
                  }

                  Text {
                    id: previewLabel
                    anchors.left: previewGlyph.visible
                      ? previewGlyph.right : parent.left
                    anchors.leftMargin: previewGlyph.visible
                      ? Commons.Style.space(5) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.selectedDisplayMode !== "icon"
                      || root.selectedV1CompactShowsValue
                    text: root.selectedV1CompactShowsValue
                      ? root.selectedV1CompactValue
                      : root.selectedLauncher
                        ? root.controller.launcherChoiceLabel("text")
                        : root.selectedWidget.label
                    color: root.selectedPreviewContentColor
                    elide: Text.ElideRight
                    font.family: root.controller.marketFont
                    font.pixelSize:
                      Commons.Style.font.caption * root.uiScale * 0.86
                    font.weight: Font.Medium
                  }
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.selectedSupported
                text: "Reset ↺"
                color: resetPointer.containsMouse
                  ? root.accent : root.foreground
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

          Row {
            visible: root.selectedSupported
              && (!root.v1LayoutActive || root.selectedV1Appearance)
            width: parent.width
            spacing: Commons.Style.space(8)

            Column {
              visible: !root.v1LayoutActive
              width: (parent.width - parent.spacing * 2) / 3
              spacing: Commons.Style.space(4)

              FieldLabel { text: "SURFACE" }

              SurfaceChoiceList {
                id: surfaceModeChoices
                height: root.surfaceChoiceHeight
                currentValue: root.selectedSurfaceMode
                onChosen: value => root.setWidgetSurface(value)
              }
            }

            Column {
              visible: !root.v1LayoutActive
              width: (parent.width - parent.spacing * 2) / 3
              spacing: Commons.Style.space(4)

              FieldLabel {
                text: "OUTLINE"
                opacity: root.selectedHasBorder ? 0.4 : 0.2
              }

              RadioChoiceList {
                id: outlineChoices
                height: root.choiceRowHeight * 4
                options: [
                  { value: 0.5, label: "0.5 px" },
                  { value: 1, label: "1 px" },
                  { value: 1.5, label: "1.5 px" },
                  { value: 2, label: "2 px" }
                ]
                currentValue: root.selectedOutlineWidth
                enabled: root.selectedHasBorder
                onChosen: value => root.controller.setGroupSetting(
                  root.selectedWidget.group, "widgetBorderWidth", value)
              }
            }

            Column {
              width: root.v1LayoutActive ? parent.width
                : (parent.width - parent.spacing * 2) / 3
              spacing: Commons.Style.space(4)

              FieldLabel { text: "OPACITY" }

              OpacityChoiceList {
                id: opacityChoices
                height: root.choiceRowHeight * 4
                currentValue: root.selectedSurfaceOpacity
                onChosen: value => root.controller.setGroupSetting(
                  root.selectedWidget.group, "surfaceOpacity", value)
              }
            }
          }

          Column {
            visible: root.selectedSupported
              && (root.selectedV1Appearance
                || (!root.v1LayoutActive && root.selectedHasFill))
            width: parent.width
            spacing: Commons.Style.space(4)

            SectionLabel { text: "FILL COLOR" }

            ColorPalette {
              id: fillColorPalette
              selectedValue: root.selectedColor
              onChosen: value => root.controller.setGroupSetting(
                root.selectedWidget.group, "color", value)
            }
          }

          Column {
            visible: root.selectedSupported
              && !root.v1LayoutActive
              && root.selectedHasBorder
            width: parent.width
            spacing: Commons.Style.space(4)

            SectionLabel { text: "OUTLINE COLOR" }

            ColorPalette {
              id: outlineColorPalette
              selectedValue: root.selectedOutlineColor
              onChosen: value => {
                root.controller.setGroupSetting(
                  root.selectedWidget.group, "widgetBorderColor", value)
                root.controller.setGroupSetting(
                  root.selectedWidget.group,
                  "widgetBorderUsesSurfaceColor", false)
              }
            }
          }

          Row {
            visible: root.selectedSupported && root.selectedMedia
            width: parent.width
            spacing: Commons.Style.space(8)

            Column {
              width: root.v1LayoutActive
                ? (parent.width - parent.spacing) * 2 / 3 : parent.width
              spacing: Commons.Style.space(4)

              FieldLabel { text: "NOW PLAYING STYLE" }

              RadioChoiceList {
                id: profileModeChoices
                height: root.choiceListHeight
                options: root.selectedModeOptions
                currentValue: root.selectedDisplayMode
                onChosen: value => root.setWidgetMode(value)
              }
            }

            Column {
              visible: root.v1LayoutActive
              width: (parent.width - parent.spacing) / 3
              spacing: Commons.Style.space(4)

              FieldLabel { text: "CONTENT TONE" }

              RadioChoiceList {
                id: mediaContentToneChoices
                height: root.choiceListHeight
                options: [
                  { value: "auto", label: "Auto" },
                  { value: "background", label: "BG" },
                  { value: "foreground", label: "FG" }
                ]
                currentValue: root.selectedContentTone
                onChosen: value => root.controller.setGroupSetting(
                  root.selectedWidget.group, "tone", value)
              }
            }
          }

          Row {
            visible: root.selectedSupported && !root.selectedMedia
            width: parent.width
            spacing: Commons.Style.space(8)

            Column {
              visible: !root.selectedLauncher
              width: root.v1LayoutActive
                ? (parent.width - parent.spacing) * 2 / 3
                : (parent.width - parent.spacing * 2) / 3 * 2
                  + parent.spacing
              spacing: Commons.Style.space(4)

              FieldLabel { text: "PRESENTATION" }

              RadioChoiceList {
                id: contentModeChoices
                height: root.choiceListHeight
                options: root.selectedModeOptions
                currentValue: root.selectedDisplayMode
                onChosen: value => root.setWidgetMode(value)
              }
            }

            Column {
              visible: !root.v1LayoutActive || root.selectedV1Appearance
              width: root.selectedLauncher ? parent.width
                : root.v1LayoutActive
                  ? (parent.width - parent.spacing) / 3
                  : (parent.width - parent.spacing * 2) / 3
              spacing: Commons.Style.space(4)

              FieldLabel { text: "CONTENT TONE" }

              RadioChoiceList {
                id: contentToneChoices
                height: root.choiceListHeight
                options: [
                  { value: "auto", label: "Auto" },
                  { value: "background", label: "BG" },
                  { value: "foreground", label: "FG" }
                ]
                currentValue: root.selectedContentTone
                onChosen: value => root.controller.setGroupSetting(
                  root.selectedWidget.group, "tone", value)
              }
            }
          }

          Column {
            visible: root.selectedSupported
              && !root.v1LayoutActive
              && root.detailOpen
            width: parent.width
            spacing: Commons.Style.space(7)

            GroupDivider {}

            SectionLabel { text: "GEOMETRY" }

            Row {
              width: parent.width
              spacing: Commons.Style.space(8)

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Commons.Style.space(4)

                FieldLabel { text: "SHAPE" }

                ShapeRow {
                  currentValue: String(root.widgetSetting(
                    root.selectedWidget.group, "widgetRadius", "auto"))
                  onChosen: value => root.controller.setGroupSetting(
                    root.selectedWidget.group, "widgetRadius", value)
                }
              }

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Commons.Style.space(4)

                FieldLabel { text: "INNER SPACE · AROUND CONTENT" }

                SpacingRow {
                  currentValue: String(root.widgetSetting(
                    root.selectedWidget.group, "widgetPadding", "auto"))
                  onChosen: value => root.controller.setGroupSetting(
                    root.selectedWidget.group, "widgetPadding", value)
                }
              }
            }

          }
        }
      }

      ThinScrollBar {
        z: 2
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Commons.Style.space(10)
        anchors.rightMargin: 1
        anchors.bottomMargin: Commons.Style.space(10)
        flickable: inspectorFlick
        foreground: root.foreground
        accent: root.accent
      }
    }
  }

  component WidgetSectionHeader: Item {
    id: sectionHeader

    required property string title
    required property int count
    property string actionLabel: ""
    property color actionColor: root.accent
    signal actionRequested()

    width: parent ? parent.width : 0
    height: Commons.Style.space(25)

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Commons.Style.space(5)
      anchors.right: sectionCount.left
      anchors.rightMargin: Commons.Style.space(5)
      height: parent.height
      spacing: Commons.Style.space(6)
      clip: true

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: sectionHeader.title
        color: root.foreground
        opacity: 0.54
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.weight: Font.DemiBold
        font.letterSpacing: 1
      }

      Text {
        visible: sectionHeader.actionLabel !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: "|"
        color: root.foreground
        opacity: 0.28
        font.family: root.controller.marketFont
        font.pixelSize: Commons.Style.font.caption * root.uiScale
        font.weight: Font.DemiBold
        font.letterSpacing: 1
      }

      FocusScope {
        id: sectionAction
        visible: sectionHeader.actionLabel !== ""
        width: visible ? sectionActionText.implicitWidth : 0
        height: parent.height
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: sectionHeader.actionLabel
        Accessible.onPressAction: sectionHeader.actionRequested()

        Text {
          id: sectionActionText
          anchors.centerIn: parent
          text: sectionHeader.actionLabel
          color: sectionHeader.actionColor
          opacity: sectionActionPointer.containsMouse
            || sectionAction.activeFocus ? 1 : 0.86
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
          font.letterSpacing: 1
        }

        MouseArea {
          id: sectionActionPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: sectionHeader.actionRequested()
        }

        Keys.onReturnPressed: function(event) {
          if (!event.isAutoRepeat) sectionHeader.actionRequested()
          event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
          if (!event.isAutoRepeat) sectionHeader.actionRequested()
          event.accepted = true
        }
        Keys.onSpacePressed: function(event) {
          if (!event.isAutoRepeat) sectionHeader.actionRequested()
          event.accepted = true
        }
      }
    }

    Text {
      id: sectionCount
      anchors.right: parent.right
      anchors.rightMargin: Commons.Style.space(5)
      anchors.verticalCenter: parent.verticalCenter
      text: String(sectionHeader.count)
      color: root.accent
      opacity: 0.82
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale * 0.9
      font.weight: Font.DemiBold
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: root.controller.dividerColor
    }
  }

  component WidgetOptionTile: Rectangle {
    id: widgetRow

    required property var option
    readonly property bool selected: root.detailOpen
      && String(root.selectedWidget.catalogGroup || "")
        === String(option.catalogGroup || "")
    readonly property bool active: option.active === true
    readonly property bool hasToggleError:
      root.toggleErrorGroup === String(option.catalogGroup || "")
    readonly property bool appearanceChanged:
      root.widgetAppearanceChanged(option.group)
    readonly property bool stateLocked:
      String(option.catalogGroup || "") === "G1"

    height: Commons.Style.space(38)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: option.label + (active
      ? ". Active. Move right to deactivate."
      : ". Inactive. Move left to activate.")
    radius: root.controller.controlRadius
    color: selected
      ? root.controller.buttonFillColor
      : editorPointer.containsMouse || moveAction.hovered || activeFocus
        ? root.controller.controlHoverFillColor : "transparent"
    border.width: selected || activeFocus ? 1 : 0
    border.color: root.accent

    Keys.onReturnPressed: openEditor()
    Keys.onEnterPressed: openEditor()
    Keys.onRightPressed: {
      if (active && !stateLocked) root.setWidgetActive(option, false)
    }
    Keys.onLeftPressed: {
      if (!active) root.setWidgetActive(option, true)
    }

    function openEditor() {
      root.selectedWidgetGroup = String(option.group || "")
      root.selectedWidgetId = String(option.id || "")
      root.widgetRequested(root.selectedWidgetGroup, root.selectedWidgetId)
    }

    Row {
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(7)
      anchors.rightMargin: Commons.Style.space(27)
      spacing: Commons.Style.space(6)

      IconText {
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(19)
        text: widgetRow.option.glyph
        color: widgetRow.selected || editorPointer.containsMouse
          ? root.accent : root.foreground
        opacity: widgetRow.active || widgetRow.selected
          || editorPointer.containsMouse ? 1 : 0.56
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x
        spacing: 0

        Text {
          width: parent.width
          text: widgetRow.option.label
          color: widgetRow.selected || editorPointer.containsMouse
            ? root.accent : root.foreground
          opacity: widgetRow.active || widgetRow.selected
            || editorPointer.containsMouse ? 1 : 0.68
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: widgetRow.selected ? Font.DemiBold : Font.Normal
        }

        Text {
          width: parent.width
          visible: widgetRow.active || widgetRow.hasToggleError
          text: widgetRow.hasToggleError
            ? root.toggleErrorMessage
            : root.widgetPresentationLabel(widgetRow.option.group,
                widgetRow.option.catalogGroup)
          color: widgetRow.hasToggleError
            ? root.controller.accentColor("color01")
            : widgetRow.selected || editorPointer.containsMouse
              ? root.accent : root.foreground
          opacity: widgetRow.selected || editorPointer.containsMouse
            ? 0.9 : 0.42
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale * 0.86
        }
      }
    }

    Rectangle {
      id: appearanceStateDot
      visible: widgetRow.active && widgetRow.appearanceChanged
      anchors.top: parent.top
      anchors.right: moveAction.left
      anchors.topMargin: Commons.Style.space(6)
      anchors.rightMargin: Commons.Style.space(3)
      width: Commons.Style.space(6)
      height: width
      radius: width / 2
      color: root.widgetAppearanceIndicatorColor(widgetRow.option.group)
    }

    MouseArea {
      id: editorPointer
      anchors.left: parent.left
      anchors.right: moveAction.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: widgetRow.openEditor()
    }

    WidgetMoveAction {
      id: moveAction
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      active: widgetRow.active
      locked: widgetRow.stateLocked
      label: widgetRow.option.label
      onRequested: root.setWidgetActive(
        widgetRow.option, !widgetRow.active)
    }
  }

  component WidgetMoveAction: FocusScope {
    id: moveActionControl

    required property bool active
    required property bool locked
    required property string label
    readonly property bool hovered: movePointer.containsMouse
    readonly property color actionAccent:
      root.controller.accentColor("color03")
    signal requested()

    width: Commons.Style.space(22)
    clip: true
    activeFocusOnTab: !locked
    Accessible.role: Accessible.Button
    Accessible.name: locked ? label + " stays active"
      : (active ? "Deactivate " : "Activate ") + label

    Keys.onSpacePressed: if (!locked) requested()
    Keys.onReturnPressed: if (!locked) requested()

    Rectangle {
      id: moveActionStrip
      anchors.fill: parent
      anchors.leftMargin: -root.controller.controlRadius
      radius: root.controller.controlRadius
      color: moveActionControl.hovered || moveActionControl.activeFocus
        ? Commons.Util.alpha(moveActionControl.actionAccent, 0.18)
        : Commons.Util.alpha(root.foreground, 0.06)
    }

    IconText {
      anchors.centerIn: parent
      text: moveActionControl.locked ? "lock"
        : moveActionControl.active ? "arrow_forward" : "arrow_back"
      color: moveActionControl.hovered || moveActionControl.activeFocus
        ? moveActionControl.actionAccent : root.foreground
      opacity: moveActionControl.hovered
        || moveActionControl.activeFocus ? 1 : 0.72
      font.pixelSize: Commons.Style.font.iconSmall * root.uiScale
    }

    MouseArea {
      id: movePointer
      anchors.fill: parent
      enabled: !moveActionControl.locked
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: moveActionControl.requested()
    }
  }

  component ContentCycleChoice: Rectangle {
    id: contentCycle

    required property string mode
    readonly property bool ready: true
    readonly property bool hovered: contentCyclePointer.containsMouse
    signal chosen()

    width: parent ? parent.width : 0
    height: root.choiceControlHeight
    radius: root.controller.controlRadius
    color: hovered ? root.controller.buttonHoverFillColor
      : root.controller.buttonFillColor
    border.width: 1
    border.color: root.accent

    Item {
      anchors.left: parent.left
      anchors.leftMargin: Commons.Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: implicitWidth
      height: parent.height
      implicitWidth: (contentCycleGlyph.visible
          ? contentCycleGlyph.implicitWidth : 0)
        + (contentCycleGlyph.visible && contentCycleText.visible
          ? Commons.Style.space(5) : 0)
        + (contentCycleText.visible ? contentCycleText.implicitWidth : 0)

      IconText {
        id: contentCycleGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: contentCycle.mode !== "text"
        text: root.selectedWidget.glyph
        color: root.accent
        font.pixelSize: Commons.Style.font.iconLarge * root.uiScale * 0.78
      }

      Text {
        id: contentCycleText
        anchors.left: contentCycleGlyph.visible
          ? contentCycleGlyph.right : parent.left
        anchors.leftMargin: contentCycleGlyph.visible
          ? Commons.Style.space(5) : 0
        anchors.verticalCenter: parent.verticalCenter
        visible: contentCycle.mode !== "icon"
        text: "Aa"
        color: root.accent
        font.family: root.controller.marketFont
        font.pixelSize: root.choiceFontSize
        font.weight: Font.Medium
        font.letterSpacing: 0.35
      }
    }

    Text {
      anchors.centerIn: parent
      text: root.displayModeLabel(contentCycle.mode)
      color: root.accent
      font.family: root.controller.marketFont
      font.pixelSize: root.choiceFontSize
      font.weight: Font.DemiBold
      font.letterSpacing: 0.35
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Commons.Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "↻"
      color: contentCycle.hovered ? root.accent : root.foreground
      opacity: contentCycle.hovered ? 1 : 0.58
      font.pixelSize: Commons.Style.font.body * root.uiScale
    }

    MouseArea {
      id: contentCyclePointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: contentCycle.chosen()
    }
  }

  component SurfaceCycleChoice: Rectangle {
    id: surfaceCycle

    required property string mode
    required property bool colorSelected
    readonly property bool ready: true
    readonly property bool hovered: surfaceCyclePointer.containsMouse
    readonly property bool hasFill:
      mode === "fill" || mode === "both"
    readonly property bool hasBorder:
      mode === "border" || mode === "both"
    signal chosen()
    signal colorRequested()

    width: parent ? parent.width : 0
    height: root.choiceControlHeight
    color: "transparent"

    Rectangle {
      id: surfaceCycleButton
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: parent.height * 2 / 3
      radius: root.controller.controlRadius
      color: surfaceCycle.hovered
        ? root.controller.buttonHoverFillColor
        : root.controller.buttonFillColor
      border.width: 1
      border.color: root.accent
    }

    Item {
      parent: surfaceCycleButton
      anchors.left: parent.left
      anchors.leftMargin: Commons.Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(18)
      height: Commons.Style.space(14)

      Rectangle {
        anchors.centerIn: parent
        width: Commons.Style.space(18)
        height: Commons.Style.space(11)
        radius: Math.min(root.controller.controlRadius,
          Commons.Style.space(4))
        color: surfaceCycle.hasFill
          ? root.controller.controlHoverFillColor : "transparent"
        border.width: surfaceCycle.hasBorder ? 1 : 0
        border.color: root.accent
      }

      Rectangle {
        anchors.centerIn: parent
        visible: surfaceCycle.mode === "none"
        width: Commons.Style.space(14)
        height: 1
        color: root.foreground
        opacity: 0.5
        rotation: -20
      }
    }

    Text {
      parent: surfaceCycleButton
      anchors.centerIn: parent
      text: surfaceCycle.mode === "none" ? "None"
        : surfaceCycle.mode === "fill" ? "Fill"
        : surfaceCycle.mode === "border" ? "Outline" : "Both"
      color: root.accent
      font.family: root.controller.marketFont
      font.pixelSize: root.choiceFontSize
      font.weight: Font.DemiBold
      font.letterSpacing: 0.35
    }

    Text {
      parent: surfaceCycleButton
      anchors.right: parent.right
      anchors.rightMargin: Commons.Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: "↻"
      color: root.accent
      opacity: surfaceCycle.hovered ? 1 : 0.58
      font.pixelSize: Commons.Style.font.body * root.uiScale
    }

    MouseArea {
      id: surfaceCyclePointer
      anchors.fill: surfaceCycleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: surfaceCycle.chosen()
    }

    Item {
      id: surfaceColorRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: surfaceCycleButton.bottom
      anchors.bottom: parent.bottom
      opacity: surfaceCycle.hasFill ? 1 : 0.34

      Rectangle {
        anchors.fill: parent
        radius: Math.min(root.controller.controlRadius,
          Commons.Style.space(4))
        color: surfaceColorPointer.containsMouse
          ? root.controller.buttonHoverFillColor : "transparent"
      }

      Rectangle {
        id: surfaceColorMarker
        anchors.left: parent.left
        anchors.leftMargin: Commons.Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
        width: Commons.Style.space(10)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: surfaceCycle.colorSelected
            || surfaceColorPointer.containsMouse
          ? root.accent : root.controller.controlBorderColor

        Rectangle {
          anchors.centerIn: parent
          visible: surfaceCycle.colorSelected
          width: Commons.Style.space(4)
          height: width
          radius: width / 2
          color: root.accent
        }
      }

      Text {
        anchors.left: surfaceColorMarker.right
        anchors.leftMargin: Commons.Style.space(7)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Color"
        color: surfaceCycle.colorSelected
            || surfaceColorPointer.containsMouse
          ? root.accent : root.foreground
        font.family: root.controller.marketFont
        font.pixelSize: root.choiceFontSize
        font.weight: surfaceCycle.colorSelected
          ? Font.DemiBold : Font.Normal
        font.letterSpacing: 0.35
      }

      MouseArea {
        id: surfaceColorPointer
        anchors.fill: parent
        enabled: surfaceCycle.hasFill
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: surfaceCycle.colorRequested()
      }
    }
  }

  component RadioChoiceList: Column {
    id: radioList

    required property var options
    required property var currentValue
    readonly property bool ready: radioRepeater.count === options.length
    signal chosen(var value)

    width: parent ? parent.width : 0
    opacity: enabled ? 1 : 0.34
    spacing: 0

    Repeater {
      id: radioRepeater
      model: radioList.options

      delegate: Item {
        id: radioRow

        required property var modelData
        readonly property bool selected:
          radioList.currentValue === modelData.value
        readonly property bool available: modelData.enabled !== false
        width: parent.width
        height: (radioList.height - radioList.spacing
          * (radioList.options.length - 1)) / radioList.options.length

        Rectangle {
          anchors.fill: parent
          radius: Math.min(root.controller.controlRadius,
            Commons.Style.space(4))
          color: radioRow.available && radioPointer.containsMouse
            ? root.controller.buttonHoverFillColor : "transparent"
        }

        Rectangle {
          id: radioMarker
          anchors.left: parent.left
          anchors.leftMargin: Commons.Style.space(3)
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(10)
          height: width
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: radioRow.selected
              || (radioRow.available && radioPointer.containsMouse)
            ? root.accent : root.controller.controlBorderColor
          opacity: radioRow.available ? 1 : 0.36

          Rectangle {
            anchors.centerIn: parent
            visible: radioRow.selected
            width: Commons.Style.space(4)
            height: width
            radius: width / 2
            color: root.accent
          }
        }

        Text {
          anchors.left: radioMarker.right
          anchors.leftMargin: Commons.Style.space(7)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: radioRow.modelData.label
          color: radioRow.selected
              || (radioRow.available && radioPointer.containsMouse)
            ? root.accent : root.foreground
          opacity: radioRow.available ? 1 : 0.34
          font.family: root.controller.marketFont
          font.pixelSize: root.choiceFontSize
          font.weight: radioRow.selected ? Font.DemiBold : Font.Normal
          font.letterSpacing: 0.35
          elide: Text.ElideRight
        }

        MouseArea {
          id: radioPointer
          anchors.fill: parent
          enabled: radioList.enabled && radioRow.available
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: radioList.chosen(radioRow.modelData.value)
        }
      }
    }
  }

  component SurfaceChoiceList: Column {
    id: surfaceList

    required property string currentValue
    readonly property bool ready: surfaceRepeater.count === 4
    signal chosen(string value)

    width: parent ? parent.width : 0
    spacing: 0

    Repeater {
      id: surfaceRepeater
      model: [
        { value: "none", label: "None" },
        { value: "fill", label: "Fill" },
        { value: "border", label: "Outline" },
        { value: "both", label: "Both" }
      ]

      delegate: Item {
        id: surfaceRow

        required property var modelData
        readonly property bool selected:
          surfaceList.currentValue === modelData.value
        readonly property bool hasFill:
          modelData.value === "fill" || modelData.value === "both"
        readonly property bool hasBorder:
          modelData.value === "border" || modelData.value === "both"
        width: parent.width
        height: surfaceList.height / 4

        Rectangle {
          anchors.fill: parent
          radius: Math.min(root.controller.controlRadius,
            Commons.Style.space(4))
          color: surfacePointer.containsMouse
            ? root.controller.buttonHoverFillColor : "transparent"
        }

        Rectangle {
          id: surfaceMarker
          anchors.left: parent.left
          anchors.leftMargin: Commons.Style.space(3)
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(10)
          height: width
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: surfaceRow.selected
              || surfacePointer.containsMouse
            ? root.accent : root.controller.controlBorderColor

          Rectangle {
            anchors.centerIn: parent
            visible: surfaceRow.selected
            width: Commons.Style.space(4)
            height: width
            radius: width / 2
            color: root.accent
          }
        }

        Rectangle {
          id: surfaceSymbol
          visible: surfaceRow.modelData.value !== "none"
          anchors.left: surfaceMarker.right
          anchors.leftMargin: Commons.Style.space(7)
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(16)
          height: Commons.Style.space(9)
          radius: Math.min(root.controller.controlRadius,
            Commons.Style.space(3))
          color: surfaceRow.hasFill
            ? root.selectedFillColor : "transparent"
          border.width: surfaceRow.hasBorder ? 1 : 0
          border.color: root.selectedBorderColor
        }

        Text {
          anchors.left: surfaceSymbol.visible
            ? surfaceSymbol.right : surfaceMarker.right
          anchors.leftMargin: Commons.Style.space(
            surfaceSymbol.visible ? 5 : 7)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: surfaceRow.modelData.label
          color: surfaceRow.selected || surfacePointer.containsMouse
            ? root.accent : root.foreground
          font.family: root.controller.marketFont
          font.pixelSize: root.choiceFontSize
          font.weight: surfaceRow.selected ? Font.DemiBold : Font.Normal
          font.letterSpacing: 0.35
          elide: Text.ElideRight
        }

        MouseArea {
          id: surfacePointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: surfaceList.chosen(
            String(surfaceRow.modelData.value))
        }
      }
    }
  }

  component ColorPalette: Grid {
    id: colorPalette

    required property string selectedValue
    readonly property bool ready:
      colorRepeater.count === root.colorOptions.length
    signal chosen(string value)

    width: parent ? parent.width : 0
    height: Commons.Style.space(25)
    columns: 10
    columnSpacing: Commons.Style.space(4)
    rowSpacing: Commons.Style.space(4)

    Repeater {
      id: colorRepeater
      model: root.colorOptions

      delegate: Rectangle {
        id: colorSwatch

        required property var modelData
        readonly property bool selected:
          colorPalette.selectedValue === modelData.value
        readonly property bool hovered: colorPointer.containsMouse
        width: (colorPalette.width - colorPalette.columnSpacing * 9) / 10
        height: colorPalette.height
        radius: root.controller.controlRadius
        color: modelData.value === "inherit"
          ? root.controller.controlHoverFillColor
          : root.controller.accentColor(modelData.value)
        border.width: 1
        border.color: root.controller.controlBorderColor
        scale: hovered ? 1.04 : 1
        z: hovered ? 1 : 0

        Behavior on scale {
          NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
          }
        }

        Text {
          anchors.centerIn: parent
          text: colorSwatch.modelData.label
          color: colorSwatch.modelData.value === "inherit"
            ? root.foreground
            : root.controller.contrastColor(
                colorSwatch.modelData.value)
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption
            * root.uiScale * 0.9
          font.weight: Font.Medium
        }

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Commons.Style.space(3)
          visible: colorSwatch.selected
          width: Commons.Style.space(16)
          height: 2
          radius: 1
          color: colorSwatch.modelData.value === "inherit"
            ? root.accent
            : root.controller.contrastColor(
                colorSwatch.modelData.value)
        }

        MouseArea {
          id: colorPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: colorPalette.chosen(
            String(colorSwatch.modelData.value))
        }
      }
    }
  }

  component OpacityChoiceList: Column {
    id: opacityList

    required property real currentValue
    readonly property bool ready: opacityRepeater.count === 4
    signal chosen(real value)

    width: parent ? parent.width : 0
    spacing: 0

    Repeater {
      id: opacityRepeater
      model: [
        { value: 1, label: "100%" },
        { value: 0.8, label: "80%" },
        { value: 0.6, label: "60%" },
        { value: 0.4, label: "40%" }
      ]

      delegate: Item {
        id: opacityRow

        required property var modelData
        readonly property bool selected:
          Math.abs(opacityList.currentValue - modelData.value) < 0.01
        width: parent.width
        height: opacityList.height / 4

        Rectangle {
          anchors.fill: parent
          radius: Math.min(root.controller.controlRadius,
            Commons.Style.space(4))
          color: opacityPointer.containsMouse
            ? root.controller.buttonHoverFillColor : "transparent"
        }

        Rectangle {
          id: opacityMarker
          anchors.left: parent.left
          anchors.leftMargin: Commons.Style.space(3)
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(10)
          height: width
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: opacityRow.selected
              || opacityPointer.containsMouse
            ? root.accent : root.controller.controlBorderColor

          Rectangle {
            anchors.centerIn: parent
            visible: opacityRow.selected
            width: Commons.Style.space(4)
            height: width
            radius: width / 2
            color: root.accent
          }
        }

        Text {
          anchors.left: opacityMarker.right
          anchors.leftMargin: Commons.Style.space(7)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: opacityRow.modelData.label
          color: opacityRow.selected || opacityPointer.containsMouse
            ? root.accent : root.foreground
          opacity: Math.max(0.6, opacityRow.modelData.value)
          font.family: root.controller.marketFont
          font.pixelSize: root.choiceFontSize
          font.weight: opacityRow.selected ? Font.DemiBold : Font.Normal
          font.letterSpacing: 0.35
        }

        MouseArea {
          id: opacityPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: opacityList.chosen(
            Number(opacityRow.modelData.value))
        }
      }
    }
  }

  component OutlineChoiceList: Column {
    id: outlineList

    required property real currentWidth
    required property bool colorSelected
    readonly property bool ready: outlineRepeater.count === 3
    signal widthChosen(real value)
    signal colorRequested()

    width: parent ? parent.width : 0
    opacity: enabled ? 1 : 0.34
    spacing: 0

    Repeater {
      id: outlineRepeater
      model: [
        { kind: "width", value: 1, label: "1 px" },
        { kind: "width", value: 2, label: "2 px" },
        { kind: "color", value: 0, label: "Color" }
      ]

      delegate: Item {
        id: outlineRow

        required property var modelData
        readonly property bool selected: modelData.kind === "color"
          ? outlineList.colorSelected
          : outlineList.currentWidth === modelData.value
        width: parent.width
        height: outlineList.height / 3

        Rectangle {
          anchors.fill: parent
          radius: Math.min(root.controller.controlRadius,
            Commons.Style.space(4))
          color: outlinePointer.containsMouse
            ? root.controller.buttonHoverFillColor : "transparent"
        }

        Rectangle {
          id: outlineMarker
          anchors.left: parent.left
          anchors.leftMargin: Commons.Style.space(3)
          anchors.verticalCenter: parent.verticalCenter
          width: Commons.Style.space(10)
          height: width
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: outlineRow.selected
              || outlinePointer.containsMouse
            ? root.accent : root.controller.controlBorderColor

          Rectangle {
            anchors.centerIn: parent
            visible: outlineRow.selected
            width: Commons.Style.space(4)
            height: width
            radius: width / 2
            color: root.accent
          }
        }

        Text {
          anchors.left: outlineMarker.right
          anchors.leftMargin: Commons.Style.space(7)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: outlineRow.modelData.label
          color: outlineRow.selected || outlinePointer.containsMouse
            ? root.accent : root.foreground
          font.family: root.controller.marketFont
          font.pixelSize: root.choiceFontSize
          font.weight: outlineRow.selected ? Font.DemiBold : Font.Normal
          font.letterSpacing: 0.35
          elide: Text.ElideRight
        }

        MouseArea {
          id: outlinePointer
          anchors.fill: parent
          enabled: outlineList.enabled
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            if (outlineRow.modelData.kind === "color")
              outlineList.colorRequested()
            else
              outlineList.widthChosen(outlineRow.modelData.value)
          }
        }
      }
    }
  }

  component OpacityCycleChoice: Rectangle {
    id: opacityCycle

    required property real currentValue
    readonly property bool hovered: opacityCyclePointer.containsMouse
    signal chosen()

    width: parent ? parent.width : 0
    height: root.choiceControlHeight
    radius: root.controller.controlRadius
    opacity: Math.max(0.6, Math.min(1, currentValue))
    color: hovered ? root.controller.buttonHoverFillColor
      : root.controller.buttonFillColor
    border.width: 1
    border.color: root.accent

    Behavior on opacity {
      NumberAnimation {
        duration: 120
        easing.type: Easing.OutCubic
      }
    }

    Text {
      anchors.centerIn: parent
      text: Math.round(opacityCycle.currentValue * 100) + "%"
      color: root.accent
      font.family: root.controller.marketFont
      font.pixelSize: root.choiceFontSize
      font.weight: Font.DemiBold
      font.letterSpacing: 0.35
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Commons.Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: "↻"
      color: root.accent
      opacity: opacityCycle.hovered ? 1 : 0.58
      font.pixelSize: Commons.Style.font.body * root.uiScale
    }

    MouseArea {
      id: opacityCyclePointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: opacityCycle.chosen()
    }
  }

  component SectionLabel: Text {
    color: root.foreground
    opacity: 0.48
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale
    font.letterSpacing: 1
  }

  component ShapeRow: Row {
    id: shapeRow

    required property var currentValue
    signal chosen(var value)

    width: parent.width
    height: root.choiceControlHeight
    spacing: Commons.Style.space(4)

    readonly property var options: [
      { value: "auto", label: "Auto" },
      { value: "square", label: "Square" },
      { value: "soft", label: "Soft" },
      { value: "round", label: "Round" }
    ]

    Repeater {
      model: shapeRow.options

      delegate: ShapeChoice {
        required property var modelData
        width: (parent.width - parent.spacing
          * (shapeRow.options.length - 1)) / shapeRow.options.length
        option: modelData
        selected: shapeRow.currentValue === modelData.value
        onChosen: shapeRow.chosen(modelData.value)
      }
    }
  }

  component ShapeChoice: Rectangle {
    id: shapeChoice

    required property var option
    property bool selected: false
    readonly property bool hovered: shapeChoicePointer.containsMouse
    signal chosen()

    height: parent ? parent.height : root.choiceControlHeight
    radius: option.value === "square" ? 0
      : option.value === "soft" ? Commons.Style.space(5)
      : option.value === "round" ? height / 2
      : root.controller.controlRadius
    color: hovered ? root.controller.buttonHoverFillColor
      : root.controller.buttonFillColor
    border.width: 1
    border.color: selected ? root.accent
      : hovered ? root.controller.buttonHoverBorderColor
      : root.controller.controlBorderColor

    Text {
      anchors.centerIn: parent
      width: parent.width - Commons.Style.space(4)
      text: shapeChoice.option.label
      color: shapeChoice.selected || shapeChoice.hovered
        ? root.accent : root.foreground
      font.family: root.controller.marketFont
      font.pixelSize: root.choiceFontSize
      font.weight: shapeChoice.selected ? Font.DemiBold : Font.Normal
      font.letterSpacing: 0.35
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    MouseArea {
      id: shapeChoicePointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: shapeChoice.chosen()
    }
  }

  component SpacingRow: Row {
    id: spacingRow

    required property var currentValue
    signal chosen(var value)

    width: parent.width
    height: root.choiceControlHeight
    spacing: Commons.Style.space(4)

    readonly property var options: [
      { value: "auto", label: "Auto", frameWidth: 22, frameHeight: 12 },
      { value: "none", label: "None", frameWidth: 10, frameHeight: 7 },
      { value: "compact", label: "Compact", frameWidth: 20, frameHeight: 11 },
      { value: "roomy", label: "Roomy", frameWidth: 30, frameHeight: 17 }
    ]

    Repeater {
      model: spacingRow.options

      delegate: SpacingChoice {
        required property var modelData
        width: (parent.width - parent.spacing
          * (spacingRow.options.length - 1)) / spacingRow.options.length
        option: modelData
        selected: spacingRow.currentValue === modelData.value
        onChosen: spacingRow.chosen(modelData.value)
      }
    }
  }

  component SpacingChoice: Rectangle {
    id: spacingChoice

    required property var option
    property bool selected: false
    readonly property bool hovered: spacingChoicePointer.containsMouse
    signal chosen()

    height: parent ? parent.height : root.choiceControlHeight
    radius: root.controller.controlRadius
    color: hovered ? root.controller.buttonHoverFillColor
      : root.controller.buttonFillColor
    border.width: 1
    border.color: selected ? root.accent
      : hovered ? root.controller.buttonHoverBorderColor
      : root.controller.controlBorderColor

    Item {
      anchors.top: parent.top
      anchors.topMargin: Commons.Style.space(3)
      anchors.horizontalCenter: parent.horizontalCenter
      width: Commons.Style.space(32)
      height: Commons.Style.space(19)

      Rectangle {
        anchors.centerIn: parent
        width: Commons.Style.space(spacingChoice.option.frameWidth)
        height: Commons.Style.space(spacingChoice.option.frameHeight)
        radius: Math.min(root.controller.controlRadius,
          Commons.Style.space(3))
        color: "transparent"
        border.width: 1
        border.color: spacingChoice.selected || spacingChoice.hovered
          ? root.accent : root.controller.controlBorderColor

        Rectangle {
          anchors.centerIn: parent
          width: Commons.Style.space(6)
          height: Commons.Style.space(3)
          radius: height / 2
          color: spacingChoice.selected || spacingChoice.hovered
            ? root.accent : root.foreground
        }
      }
    }

    Text {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Commons.Style.space(4)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Commons.Style.space(4)
      text: spacingChoice.option.label
      color: spacingChoice.selected || spacingChoice.hovered
        ? root.accent : root.foreground
      font.family: root.controller.marketFont
      font.pixelSize: root.choiceFontSize
      font.weight: spacingChoice.selected ? Font.DemiBold : Font.Normal
      font.letterSpacing: 0.35
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }

    MouseArea {
      id: spacingChoicePointer
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: spacingChoice.chosen()
    }
  }

  component FieldLabel: Text {
    color: root.foreground
    opacity: 0.4
    font.family: root.controller.marketFont
    font.pixelSize: Commons.Style.font.caption * root.uiScale * 0.88
    font.letterSpacing: 0.7
  }

  component GroupDivider: Rectangle {
    width: parent ? parent.width : 0
    height: 1
    color: root.controller.controlBorderColor
    opacity: 0.6
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
        fontSize: root.choiceFontSize
        onClicked: optionRow.chosen(modelData.value)
      }
    }
  }
}
