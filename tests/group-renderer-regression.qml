import QtQuick
import Quickshell
import "core" as Core
import "styles/shibumi" as ShibumiStyle

ShellRoot {
  Item {
    id: test

    width: 1200
    height: 120
    property int narrowStage: 0

    Component {
      id: markerWidget

      Item {
        property var bar: null
        property string moduleName: ""
        property var settings: ({})
        property real availableWidth: -1

        visible: true
        implicitWidth: moduleName === "hancore.shibumi.center" ? 100
          : moduleName === "omarchy.active-window" ? 30 : 10
        implicitHeight: 12
      }
    }

    Component {
      id: delayedMarkerWidget

      Item {
        id: delayedMarker

        property var bar: null
        property string moduleName: ""
        property var settings: ({})
        property real availableWidth: -1
        property bool ready: false

        visible: true
        implicitWidth: ready ? 42 : 0
        implicitHeight: ready ? 12 : 0

        Timer {
          interval: 30
          running: true
          onTriggered: delayedMarker.ready = true
        }
      }
    }

    QtObject {
      id: fakeWidgetRegistry

      function componentFor(moduleName) {
        return moduleName ? markerWidget : null
      }
    }

    QtObject {
      id: delayedWidgetRegistry

      function componentFor(moduleName) {
        return moduleName ? delayedMarkerWidget : null
      }
    }

    QtObject {
      id: fakeStateService
      property var config: ({ widgets: ({}) })
      readonly property color selectedColor: "#88aaff"
    }

    QtObject {
      id: disabledStateService
      readonly property var config: ({
        widgets: ({ G8: { enabled: false } })
      })
      readonly property color selectedColor: "#88aaff"
    }

    QtObject {
      id: fakeShell
      function serviceFor(pluginId) {
        return pluginId === "hancore.shibumi.state" ? fakeStateService : null
      }
    }

    QtObject {
      id: disabledShell
      function serviceFor(pluginId) {
        return pluginId === "hancore.shibumi.state" ? disabledStateService : null
      }
    }

    QtObject {
      id: noSplitController

      readonly property var order: ({
        left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
        center: ["G8"],
        right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
      })
      readonly property var splits: ({
        left: [false, false, false, false, false, false],
        boundaries: [false, false],
        right: [false, false, false, false, false, false]
      })

      function splitEnabled(region, index) {
        return false
      }
    }

    QtObject {
      id: splitController

      readonly property var order: noSplitController.order

      function splitEnabled(region, index) {
        return region === "left" && index === 0
      }
    }

    QtObject {
      id: noSplitBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property bool transparent: false
      readonly property string fontFamily: "monospace"
      readonly property color foreground: "#eeeeee"
      readonly property color background: "#181818"
      readonly property color urgent: "#88aaff"
      readonly property var shell: fakeShell
      readonly property var visualTokens: ({
        islandRadius: 16,
        islandHeight: 32,
        islandInsetX: 5,
        islandOffsetY: 3,
        groupGap: 6,
        splitGap: 16,
        invalidDropDuration: 230,
        returnCleanupDuration: 240,
        pillRadius: 12,
        sumi: "#aaaaaa",
        pillBorderWidth: 1,
        islandBorder: "#505050"
      })
      readonly property var layoutConfig: ({ left: [], center: [], right: [] })
      readonly property var layoutController: noSplitController
      property var activePopout: null

      function entryId(entry) { return entry && entry.id ? String(entry.id) : "" }
      function entrySettings(entry) { return entry || ({}) }
      function registeredWidgetComponent(moduleName) {
        return fakeWidgetRegistry.componentFor(moduleName)
      }
      function registerModuleSlot(slot) {}
      function unregisterModuleSlot(slot) {}
      function hideTooltip(owner) {}
      function releasePopout(owner) {}
      function unassignedLayoutEntries(region) { return [] }
    }

    QtObject {
      id: splitBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property bool transparent: false
      readonly property string fontFamily: "monospace"
      readonly property color foreground: noSplitBar.foreground
      readonly property color background: noSplitBar.background
      readonly property color urgent: noSplitBar.urgent
      readonly property var shell: fakeShell
      readonly property var visualTokens: noSplitBar.visualTokens
      readonly property var layoutConfig: noSplitBar.layoutConfig
      readonly property var layoutController: splitController
      property var activePopout: null

      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(moduleName) {
        return fakeWidgetRegistry.componentFor(moduleName)
      }
      function registerModuleSlot(slot) {}
      function unregisterModuleSlot(slot) {}
      function hideTooltip(owner) {}
      function releasePopout(owner) {}
      function unassignedLayoutEntries(region) { return [] }
    }

    QtObject {
      id: v2SplitBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property bool transparent: false
      readonly property string fontFamily: "monospace"
      readonly property color foreground: noSplitBar.foreground
      readonly property color background: noSplitBar.background
      readonly property color urgent: noSplitBar.urgent
      readonly property var shell: fakeShell
      readonly property var visualTokens: ({
        islandRadius: 16,
        islandHeight: 32,
        islandInsetX: 5,
        islandOffsetY: 3,
        groupGap: 6,
        splitGap: 16,
        invalidDropDuration: 230,
        returnCleanupDuration: 240,
        pillRadius: 12,
        sumi: "#aaaaaa",
        separator: "#555555",
        pillHeight: 24,
        pillBorderWidth: 1,
        islandBorder: "#505050",
        v2Shell: true,
        widgetHasFill: function(settings) {
          return settings && settings.color === "color01"
        },
        widgetHasBorder: function(settings) { return false },
        widgetPadding: function(settings, decorated) {
          return decorated ? 3 : 0
        },
        widgetFillColor: function(settings) { return "#884422" },
        widgetBorderColor: function(settings) { return "transparent" },
        widgetSurfaceOpacity: function(settings) { return 1 },
        widgetRadius: function(settings) { return 10 }
      })
      readonly property var layoutConfig: noSplitBar.layoutConfig
      readonly property var layoutController: splitController
      property var activePopout: null
      property int separatorToggles: 0
      property string lastSeparatorGroup: ""

      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(moduleName) {
        return fakeWidgetRegistry.componentFor(moduleName)
      }
      function registerModuleSlot(slot) {}
      function unregisterModuleSlot(slot) {}
      function hideTooltip(owner) {}
      function releasePopout(owner) {}
      function unassignedLayoutEntries(region) { return [] }
      function toggleGroupSeparator(groupId) {
        separatorToggles++
        lastSeparatorGroup = String(groupId || "")
        return true
      }
    }

    QtObject {
      id: budgetBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property var shell: fakeShell
      readonly property var layoutConfig: ({
        left: [], center: [],
        right: [{ id: "omarchy.active-window" }]
      })
      property var activePopout: null

      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(moduleName) {
        return fakeWidgetRegistry.componentFor(moduleName)
      }
      function registerModuleSlot(_slot) {}
      function unregisterModuleSlot(_slot) {}
      function hideTooltip(_owner) {}
      function releasePopout(_owner) {}
    }

    QtObject {
      id: delayedBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property var shell: fakeShell
      readonly property var layoutConfig: ({ left: [], center: [], right: [] })
      property var activePopout: null

      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(moduleName) {
        return delayedWidgetRegistry.componentFor(moduleName)
      }
      function registerModuleSlot(_slot) {}
      function unregisterModuleSlot(_slot) {}
      function hideTooltip(_owner) {}
      function releasePopout(_owner) {}
    }

    QtObject {
      id: disabledGroupBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property var shell: disabledShell
      readonly property var layoutConfig: ({
        left: [], center: [],
        right: [{ id: "omarchy.active-window" }]
      })
      property var activePopout: null

      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(moduleName) {
        return fakeWidgetRegistry.componentFor(moduleName)
      }
      function registerModuleSlot(_slot) {}
      function unregisterModuleSlot(_slot) {}
      function hideTooltip(_owner) {}
      function releasePopout(_owner) {}
    }

    ShibumiStyle.GroupSection {
      id: leftWithoutSplit
      bar: noSplitBar
      region: "left"
    }

    ShibumiStyle.GroupSection {
      id: leftWithSplit
      bar: splitBar
      region: "left"
    }

    ShibumiStyle.GroupSection {
      id: v2LeftWithSplit
      bar: v2SplitBar
      region: "left"
    }

    ShibumiStyle.GroupSection {
      id: centerSection
      bar: noSplitBar
      region: "center"
    }

    ShibumiStyle.GroupSection {
      id: rightSection
      bar: noSplitBar
      region: "right"
    }

    ShibumiStyle.GroupSection {
      id: narrowLeftSection
      bar: noSplitBar
      region: "left"
      visibilityStage: test.narrowStage
    }

    ShibumiStyle.GroupSection {
      id: narrowRightSection
      bar: noSplitBar
      region: "right"
      visibilityStage: test.narrowStage
    }

    ShibumiStyle.BarSurface {
      id: fullSurface
      bar: noSplitBar
      width: 1200
      height: 26
      y: 50
    }

    Core.WidgetSlot {
      id: directWidget
      bar: noSplitBar
      entry: ({ id: "hancore.shibumi.control-center" })
      screenName: "DP-1"
    }

    Core.WidgetSlot {
      id: disabledWidget
      bar: noSplitBar
      entry: ({ id: "hancore.shibumi.memory", enabled: false })
    }

    Core.GroupSlot {
      id: directGroup
      bar: noSplitBar
      groupId: "G1"
    }

    Core.GroupSlot {
      id: v2FillGroup
      bar: v2SplitBar
      groupId: "G1"
    }

    Core.GroupSlot {
      id: budgetGroup
      bar: budgetBar
      groupId: "G8"
      availableWidth: 200
    }

    Core.GroupSlot {
      id: delayedGroup
      bar: delayedBar
      groupId: "G1"
    }

    Core.GroupSlot {
      id: disabledMultiGroup
      bar: disabledGroupBar
      groupId: "G8"
    }

    function fail(message) {
      console.error("group-renderer-regression:", message)
      Qt.exit(1)
    }

    function closeEnough(actual, expected) {
      return Math.abs(actual - expected) <= 0.5
    }

    function widgetSlots(item, result) {
      if (!item) return result
      if (item.activeItem) result.push(item)
      const children = item.children || []
      for (const child of children) widgetSlots(child, result)
      return result
    }

    function sectionState(section) {
      const result = []
      const children = section && section.contentItem
        ? section.contentItem.children || [] : []
      for (const child of children) {
        if (!("modelData" in child)) continue
        result.push({
          id: child.modelData,
          autoShown: child.autoShown,
          effective: child.effectiveHasContent,
          measured: child.measuredHasContent,
          natural: child.naturalGroupWidth,
          width: child.width,
          visible: child.visible
        })
      }
      return result
    }

    Timer {
      property int attempts: 0
      property bool narrowed: false

      interval: 10
      running: true
      repeat: true

      onTriggered: {
        attempts++
        if (leftWithoutSplit.implicitWidth <= 0
            || leftWithSplit.implicitWidth <= 0
            || centerSection.implicitWidth <= 0
            || rightSection.implicitWidth <= 0
            || narrowLeftSection.implicitWidth <= 0
            || narrowRightSection.implicitWidth <= 0
            || delayedGroup.implicitWidth <= 0
            || fullSurface.width !== 1200) {
          if (attempts < 50) return
          stop()
          test.fail("renderer loaders did not become ready: left="
            + leftWithoutSplit.implicitWidth + ", split="
            + leftWithSplit.implicitWidth + ", center="
            + centerSection.implicitWidth + ", right="
            + rightSection.implicitWidth + ", directWidget="
            + directWidget.implicitWidth + ", directGroup="
            + directGroup.implicitWidth + ", delayedGroup="
            + delayedGroup.implicitWidth + "x" + delayedGroup.implicitHeight
            + ", modules="
            + directGroup.moduleCount + ", groupItem="
            + directGroup.contentItem + ", itemWidth="
            + (directGroup.contentItem ? directGroup.contentItem.width : -1)
            + ", itemImplicit="
            + (directGroup.contentItem ? directGroup.contentItem.implicitWidth : -1)
            + ", childWidth="
            + (directGroup.contentItem ? directGroup.contentItem.childrenRect.width : -1))
          return
        }

        if (!narrowed) {
          narrowed = true
          attempts = 0
          test.narrowStage = 3
          return
        }

        if (!test.closeEnough(narrowLeftSection.implicitWidth, 42)
            || !test.closeEnough(narrowRightSection.implicitWidth, 26)) {
          if (attempts < 50) return
          stop()
          test.fail("responsive stage did not settle: left="
            + narrowLeftSection.implicitWidth + ", right="
            + narrowRightSection.implicitWidth + ", stage="
            + test.narrowStage + ", leftState="
            + JSON.stringify(test.sectionState(narrowLeftSection))
            + ", rightState="
            + JSON.stringify(test.sectionState(narrowRightSection)))
          return
        }

        stop()
        const spacing = leftWithoutSplit.groupSpacing
        const expectedLeft = 70 + 6 * spacing
        const expectedCenter = 100
        const expectedRight = 70 + 6 * spacing

        if (!test.closeEnough(leftWithoutSplit.markerGapWidth(false), 6)
            || !test.closeEnough(leftWithSplit.markerGapWidth(true), 22)) {
          test.fail("V1 split-marker gap geometry drifted: unsplit="
            + leftWithoutSplit.markerGapWidth(false) + ", split="
            + leftWithSplit.markerGapWidth(true))
          return
        }
        if (leftWithSplit.persistentSeparators
            || !v2LeftWithSplit.persistentSeparators) {
          test.fail("separator visibility must stay transient in Shibumi"
            + " and persist in V2 shell styles")
          return
        }
        const separatorBeforeFill = v2LeftWithSplit.separatorGeometry.find(
          function(entry) { return entry.groupId === "G1" })
        fakeStateService.config = ({
          widgets: ({ G1: { color: "color01" } })
        })
        const separatorAfterFill = v2LeftWithSplit.separatorGeometry.find(
          function(entry) { return entry.groupId === "G1" })
        if (!separatorBeforeFill || !separatorAfterFill
            || !v2FillGroup.decorated
            || !test.closeEnough(v2FillGroup.visualSurfaceItem.height, 24)
            || !test.closeEnough(v2FillGroup.implicitHeight, 24)
            || !test.closeEnough(
              separatorAfterFill.visualRight
                - separatorBeforeFill.visualRight, 6)
            || !test.closeEnough(
              separatorAfterFill.markerCenter
                - separatorBeforeFill.markerCenter, 6)) {
          test.fail("V2 fill height or separator edge tracking drifted: before="
            + JSON.stringify(separatorBeforeFill) + ", after="
            + JSON.stringify(separatorAfterFill) + ", surface="
            + v2FillGroup.visualSurfaceItem.height + ", group="
            + v2FillGroup.implicitHeight)
          return
        }
        if (leftWithSplit.toggleSeparator("G1")
            || !v2LeftWithSplit.toggleSeparator("G1")
            || v2SplitBar.separatorToggles !== 1
            || v2SplitBar.lastSeparatorGroup !== "G1") {
          test.fail("locked separator interaction is not exclusive to V2")
          return
        }

        if (!test.closeEnough(leftWithoutSplit.implicitWidth, expectedLeft)) {
          test.fail("left group composition: got "
            + leftWithoutSplit.implicitWidth + ", expected " + expectedLeft)
          return
        }
        if (!test.closeEnough(leftWithSplit.implicitWidth,
            expectedLeft + leftWithSplit.splitGrow)) {
          test.fail("positional split growth: got "
            + leftWithSplit.implicitWidth + ", expected "
            + (expectedLeft + leftWithSplit.splitGrow))
          return
        }
        if (!test.closeEnough(centerSection.implicitWidth, expectedCenter)) {
          test.fail("center group composition: got "
            + centerSection.implicitWidth + ", expected " + expectedCenter)
          return
        }
        if (!test.closeEnough(rightSection.implicitWidth, expectedRight)) {
          test.fail("right-side G9-G15 composition: got "
            + rightSection.implicitWidth + ", expected " + expectedRight)
          return
        }
        if (!test.closeEnough(narrowLeftSection.implicitWidth, 42)
            || !test.closeEnough(narrowRightSection.implicitWidth, 26)) {
          test.fail("responsive group presentation drifted: left="
            + narrowLeftSection.implicitWidth + ", right="
            + narrowRightSection.implicitWidth)
          return
        }
        if (!test.closeEnough(narrowLeftSection.stageBudgetWidths[0],
            expectedLeft)
            || !test.closeEnough(narrowRightSection.stageBudgetWidths[0],
              expectedRight)) {
          test.fail("responsive width budgets collapsed with hidden groups: left="
            + narrowLeftSection.stageBudgetWidths[0] + ", right="
            + narrowRightSection.stageBudgetWidths[0])
          return
        }
        if (directWidget.screenName !== "DP-1") {
          test.fail("explicit output identity did not reach widget slot")
          return
        }
        if (!test.closeEnough(delayedGroup.implicitWidth, 42)
            || !test.closeEnough(delayedGroup.implicitHeight, 12)) {
          test.fail("asynchronous widget size did not propagate through group: "
            + delayedGroup.implicitWidth + "x" + delayedGroup.implicitHeight)
          return
        }
        if (disabledWidget.moduleEnabled || disabledWidget.activeItem !== null
            || disabledWidget.implicitWidth !== 0
            || disabledWidget.implicitHeight !== 0) {
          test.fail("disabled widget was instantiated")
          return
        }
        if (disabledMultiGroup.groupEnabled
            || disabledMultiGroup.moduleCount !== 2
            || disabledMultiGroup.contentItem !== null
            || disabledMultiGroup.implicitWidth !== 0
            || disabledMultiGroup.implicitHeight !== 0) {
          test.fail("disabled multi-module group was instantiated")
          return
        }
        const budgetSlots = test.widgetSlots(budgetGroup.contentItem, [])
        const centerSlot = budgetSlots.find(slot =>
          slot.moduleName === "hancore.shibumi.center")
        const optionalSlot = budgetSlots.find(slot =>
          slot.moduleName === "omarchy.active-window")
        if (!centerSlot || !optionalSlot
            || !test.closeEnough(centerSlot.activeItem.availableWidth, 170)
            || !test.closeEnough(optionalSlot.activeItem.availableWidth, 100)) {
          test.fail("monitor width budget did not subtract optional siblings")
          return
        }

        console.log("group renderer regression passed")
        Qt.exit(0)
      }
    }
  }
}
