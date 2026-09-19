import QtQuick
import Quickshell
import Quickshell.Io
import "core" as Core
import "styles/shibumi" as ShibumiStyle
import "widgets" as Widgets

ShellRoot {
  id: fixtureRoot

  Item {
    id: test

    width: 1200
    height: 180
    property int narrowStage: 0
    readonly property string nativeOwnerId: "fixture.shibumi.106.owner"
    readonly property string outputOwnershipId: "fixture.shibumi.106.output"
    readonly property string multipleOwnershipId: "fixture.shibumi.106.multiple"
    readonly property string peerOwnershipId: "fixture.shibumi.106.peer"
    readonly property string abandonedOwnershipId: "fixture.shibumi.106.abandoned"
    property int nativeAlive: 0
    property int nativeSerial: 0
    property var nativeLoadOverlaps: []
    property var nativeIpcDestructions: []
    property var observedLoadedOwners: []
    property int nativePingExpected: 0
    property string nativePingOutput: ""
    property int nativePingExit: -1
    property bool nativePingReady: false
    property bool peerOwnerEnabled: true
    property var peerSentinel: null
    property bool abandonedOwnerEnabled: true
    property bool abandonedWaiterPresent: true

    Component {
      id: nativeOwnerWidget

      Item {
        id: nativeOwner

        property var bar: null
        property string moduleName: ""
        property var settings: ({})
        property real availableWidth: -1
        property int instanceSerial: 0
        implicitWidth: 18
        implicitHeight: 12

        Item {
          x: 10
          width: 10
          height: 1
        }

        IpcHandler {
          enabled: nativeOwner.moduleName === test.nativeOwnerId
          target: "fixture.shibumi.106.native-owner"
          function ping(): string { return String(nativeOwner.instanceSerial) }
          Component.onDestruction: {
            test.nativeIpcDestructions = test.nativeIpcDestructions.concat(
              [nativeOwner.instanceSerial])
            console.log("P10_106_IPC_QML_DESTRUCTION",
              nativeOwner.instanceSerial)
          }
        }

        onModuleNameChanged: {
          if (moduleName !== test.nativeOwnerId || instanceSerial !== 0) return
          instanceSerial = ++test.nativeSerial
          const overlap = test.nativeAlive > 0
          test.nativeAlive++
          test.nativeLoadOverlaps = test.nativeLoadOverlaps.concat([overlap])
          console.log("P10_106_LOAD", instanceSerial,
            "item=" + String(nativeOwner), "alive=" + test.nativeAlive,
            "overlap=" + overlap)
        }
        Component.onDestruction: {
          if (instanceSerial === 0) return
          console.log("P10_106_ITEM_QML_DESTRUCTION", instanceSerial)
          test.nativeAlive--
        }
      }
    }

    Component {
      id: actualBarFixture

      Item {
        id: root
        property bool teardownClaimed: false
        // INJECT_TEARDOWN_BAR_LOADED_OWNER_DECLARATIONS

        Item {
          id: teardownSlot
          property string moduleName: test.peerOwnershipId
          property string screenName: "DP-1"
        }

        Item { id: teardownItem }

        function widgetAllowsMultiple(_moduleName) { return false }
        // INJECT_TEARDOWN_BAR_LOADED_OWNER_FUNCTIONS

        Component.onCompleted: {
          teardownClaimed = claimLoadedOwner(teardownSlot, teardownItem)
          if (!teardownClaimed || loadedOwners.length !== 1)
            test.fail("actual Bar fixture did not claim its loaded owner")
        }
      }
    }

    Component {
      id: markerWidget

      Item {
        id: marker

        property var bar: null
        property string moduleName: ""
        property var settings: ({})
        property real availableWidth: -1
        readonly property bool suiteNativePill:
          [
            "hancore.shibumi.temperature",
            "hancore.shibumi.gpu",
            "hancore.shibumi.storage"
          ].indexOf(moduleName) >= 0
        readonly property int nativeSurfaceCount: nativePillLoader.item
          ? nativePillLoader.item.renderedSurfaceCount : 0

        visible: true
        implicitWidth: moduleName === "hancore.shibumi.center" ? 100
          : moduleName === "omarchy.active-window" ? 30 : 10
        implicitHeight: suiteNativePill ? 24 : 12

        Loader {
          id: nativePillLoader
          active: marker.suiteNativePill
          anchors.fill: parent
          sourceComponent: Component {
            Widgets.PillSurface {
              bar: marker.bar
              tokenSource: marker.bar ? marker.bar.visualTokens : null
              settings: marker.settings
              v1AppearanceEnabled: true
            }
          }
        }
      }
    }

    Component {
      id: mixedHeightExternalWidget

      Item {
        property var bar: null
        property string moduleName: ""
        property string hostGroupId: ""
        property var settings: ({})
        property real availableWidth: 0

        visible: true
        implicitWidth: 36
        implicitHeight: bar ? bar.externalWidgetHeight : 35
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
      property int revision: 0
      property var config: ({
        widgets: ({
          G1: { widgetPadding: "compact" },
          "G:hancore.shibumi.temperature": {
            color: "color01",
            colorMode: "border",
            surfaceOpacity: 0.4
          }
        })
      })
      readonly property color selectedColor: "#88aaff"

      function groupSetting(groupId, key, fallback) {
        const settings = config && config.widgets
          ? config.widgets[String(groupId || "")] || ({}) : ({})
        return Object.prototype.hasOwnProperty.call(settings, String(key || ""))
          ? settings[String(key || "")] : fallback
      }

      function setSeparator(enabled) {
        const next = JSON.parse(JSON.stringify(config))
        if (!next.widgets) next.widgets = ({})
        if (!next.widgets.G1) next.widgets.G1 = ({})
        next.widgets.G1.separator = enabled === true
        config = next
        revision++
      }
    }

    QtObject {
      id: disabledStateService
      property int revision: 0
      readonly property var config: ({
        widgets: ({
          G1: { separator: true },
          G2: { enabled: false },
          G8: { enabled: false }
        })
      })
      readonly property color selectedColor: "#88aaff"
    }

    QtObject {
      id: shapeStateService

      property int revision: 0
      property var config: ({
        presentation: ({ shellStyle: "notch", radius: "small" }),
        widgets: ({
          G1: ({ color: "color01", widgetRadius: "auto" })
        })
      })
      readonly property color selectedColor: "#88aaff"

      function groupSettingsForVariant(groupId, _variant) {
        return config && config.widgets
          ? config.widgets[String(groupId || "")] || ({}) : ({})
      }

      function groupEnabledForVariant(_groupId, _variant) { return true }
      function paletteColor(_colorId) { return "#884422" }

      function setShape(value) {
        const next = JSON.parse(JSON.stringify(config))
        next.widgets.G1.widgetRadius = String(value || "auto")
        config = next
        revision++
      }
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
      id: shapeShell

      function serviceFor(pluginId) {
        return pluginId === "hancore.shibumi.state" ? shapeStateService : null
      }
    }

    QtObject {
      id: noSplitController

      property int toggleCount: 0
      property string lastToggleRegion: ""
      property int lastToggleIndex: -1
      property bool activeLayoutProtected: false

      readonly property bool v2Mode: false
      readonly property var order: ({
        left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
        center: ["G8"],
        right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
      })
      readonly property var v1Slots: order
      readonly property var splits: ({
        left: [false, false, false, false, false, false],
        boundaries: [false, false],
        right: [false, false, false, false, false, false]
      })

      function splitEnabled(region, index) {
        return false
      }

      function toggleSplit(region, index) {
        toggleCount++
        lastToggleRegion = String(region || "")
        lastToggleIndex = Number(index)
        return true
      }
    }

    QtObject {
      id: editingSession
      property bool editing: false
      property bool active: false
      property string sourceGroupId: ""
    }

    QtObject {
      id: splitController

      readonly property bool v2Mode: false
      readonly property var order: noSplitController.order
      readonly property var v1Slots: order

      function splitEnabled(region, index) {
        return region === "left" && index === 0
      }
    }

    QtObject {
      id: hiddenGapController

      property bool splitOn: false
      property int toggleCount: 0
      property int lastToggleIndex: -1
      readonly property bool v2Mode: false
      readonly property var order: noSplitController.order
      readonly property var v1Slots: order
      readonly property var splits: ({
        left: [false, splitOn, false, false, false, false],
        boundaries: [false, false],
        right: [false, false, false, false, false, false]
      })

      function splitEnabled(region, index) {
        return region === "left" && index === 1 && splitOn
      }

      function toggleSplit(region, index) {
        toggleCount++
        lastToggleIndex = Number(index)
        if (region !== "left" || index !== 1) return false
        splitOn = !splitOn
        disabledStateService.revision++
        return true
      }
    }

    QtObject {
      id: centerRunController

      property int centerSplitMode: 0
      readonly property bool v2Mode: false
      readonly property var order: ({
        left: ["G1", "G2"],
        center: ["G8", "G7"],
        right: ["G9", "G10"]
      })
      readonly property var v1Slots: order
      readonly property var splits: ({
        left: [true],
        center: centerSplitMode === 0 ? [true]
          : centerSplitMode === 1 ? [false] : [],
        boundaries: [false, false],
        right: [true]
      })

      function splitEnabled(region, index) {
        const values = splits[String(region || "")] || []
        return values[Number(index)] === true
      }
    }

    QtObject {
      id: v2SplitController

      property bool activeLayoutProtected: false
      readonly property bool v2Mode: true
      readonly property var order: ({
        left: ["G1", "G2", "G3", "G5", "G6", "G4", "G7"],
        center: ["G8"],
        right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
      })
      readonly property var splits: noSplitController.splits

      function splitEnabled(region, index) {
        // Deliberately active: V1 positional splits must not leak into V2.
        return region === "left" && index === 0
      }
    }

    QtObject {
      id: noSplitBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property bool transparent: false
      property bool testShadowEnabled: true
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
        slotHeight: 28,
        pillHeight: 24,
        pill: "#242424",
        pillBorder: "#606060",
        sumi: "#aaaaaa",
        pillBorderWidth: 1,
        pillShadow: "#66000000",
        shadowEnabled: noSplitBar.testShadowEnabled,
        islandBorder: "#505050",
        v2Shell: false,
        widgetHasFill: function(settings) {
          return settings && settings.color === "color01"
        },
        widgetFillColor: function(settings) {
          return settings && settings.color === "color01"
            ? "#884422" : "transparent"
        },
        widgetSurfaceOpacity: function(settings) {
          return settings && settings.surfaceOpacity !== undefined
            ? Number(settings.surfaceOpacity) : 1
        }
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
      id: tallAlignmentBar

      property bool useV2: false
      property string position: "top"
      readonly property int externalWidgetHeight: 35
      readonly property bool vertical: false
      readonly property int barSize: useV2 ? 33 : 35
      readonly property bool transparent: false
      readonly property string fontFamily: "monospace"
      readonly property color foreground: noSplitBar.foreground
      readonly property color barForeground: noSplitBar.foreground
      readonly property color background: noSplitBar.background
      readonly property color urgent: noSplitBar.urgent
      readonly property bool foregroundAnimationEnabled: false
      readonly property var shell: fakeShell
      readonly property var visualTokens: useV2
        ? v2SplitBar.visualTokens : noSplitBar.visualTokens
      readonly property var layoutConfig: ({
        left: [{ id: "custom.tall-left" }],
        center: [{ id: "custom.tall-center" }],
        right: [{ id: "custom.tall-right" }]
      })
      readonly property var layoutController: useV2
        ? v2SplitController : noSplitController
      readonly property var pluginRegistry: ({ installedPlugins: ({}) })
      property var activePopout: null
      property var pendingTooltipTarget: null
      property var tooltipTarget: null

      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(moduleName) {
        return String(moduleName || "").indexOf("custom.tall-") === 0
          ? mixedHeightExternalWidget
          : fakeWidgetRegistry.componentFor(moduleName)
      }
      function registerModuleSlot(_slot) {}
      function unregisterModuleSlot(_slot) {}
      function showTooltip(_owner, _text) {}
      function hideTooltip(_owner) {}
      function releasePopout(_owner) {}
      function unassignedLayoutEntries(region) {
        return layoutConfig[String(region || "")] || []
      }
    }

    QtObject {
      id: shortAlignmentBar

      property bool useV2: false
      property string position: "top"
      readonly property int externalWidgetHeight: 8
      readonly property bool vertical: false
      readonly property int barSize: useV2 ? 33 : 35
      readonly property bool transparent: false
      readonly property string fontFamily: "monospace"
      readonly property color foreground: noSplitBar.foreground
      readonly property color barForeground: noSplitBar.foreground
      readonly property color background: noSplitBar.background
      readonly property color urgent: noSplitBar.urgent
      readonly property bool foregroundAnimationEnabled: false
      readonly property var shell: fakeShell
      readonly property var visualTokens: useV2
        ? v2SplitBar.visualTokens : noSplitBar.visualTokens
      readonly property var layoutConfig: ({
        left: [{ id: "custom.short-left" }],
        center: [{ id: "custom.short-center" }],
        right: [{ id: "custom.short-right" }]
      })
      readonly property var layoutController: useV2
        ? v2SplitController : noSplitController
      readonly property var pluginRegistry: ({ installedPlugins: ({}) })
      property var activePopout: null
      property var pendingTooltipTarget: null
      property var tooltipTarget: null

      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(moduleName) {
        return String(moduleName || "").indexOf("custom.short-") === 0
          ? mixedHeightExternalWidget
          : fakeWidgetRegistry.componentFor(moduleName)
      }
      function registerModuleSlot(_slot) {}
      function unregisterModuleSlot(_slot) {}
      function showTooltip(_owner, _text) {}
      function hideTooltip(_owner) {}
      function releasePopout(_owner) {}
      function unassignedLayoutEntries(region) {
        return layoutConfig[String(region || "")] || []
      }
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
      id: centerRunBar

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
      readonly property var layoutController: centerRunController
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
      function unassignedLayoutEntries(_region) { return [] }
    }

    QtObject {
      id: ownershipStateService

      property int revision: 0
      property var config: ({
        presentation: ({ shellStyle: "shibumi" }),
        widgets: ({}),
        order: ({
          left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7",
            "G:" + test.nativeOwnerId],
          center: ["G8"],
          right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15", ""]
        }),
        splits: ({
          left: [false, false, false, false, false, false, false],
          center: [], boundaries: [false, false],
          right: [false, false, false, false, false, false, false]
        }),
        v2Layout: ({
          left: ["G1", "G2", "G3", "", "G5", "G6", "G4", "G7", "", ""],
          center: ["G8"],
          right: ["G9", "G10", "G11", "G14", "G12", "G13", "G16",
            "G18", "G17", "G15", "", "G:" + test.nativeOwnerId, ""]
        })
      })
      readonly property color selectedColor: "#88aaff"

      function setStyle(style) {
        const next = JSON.parse(JSON.stringify(config))
        next.presentation.shellStyle = style
        config = next
        revision++
      }

      function moveV1OwnerRight() {
        const next = JSON.parse(JSON.stringify(config))
        next.order.right[7] = next.order.left[7]
        next.order.left[7] = ""
        config = next
        revision++
      }
    }

    QtObject {
      id: ownershipShell
      function serviceFor(pluginId) {
        return pluginId === "hancore.shibumi.state"
          ? ownershipStateService : null
      }
    }

    Core.LayoutController {
      id: ownershipController
      bar: root
      stateService: ownershipStateService
    }

    Connections {
      target: root
      function onLoadedOwnersChanged() {
        const previous = test.observedLoadedOwners.find(
          owner => owner.objectName === test.nativeOwnerId)
        const current = root.loadedOwners.find(
          owner => owner.objectName === test.nativeOwnerId)
        if (previous && !current && nativeOwnershipProbe.running) {
          const serial = test.nativeIpcDestructions.length > 0
            ? test.nativeIpcDestructions[test.nativeIpcDestructions.length - 1] : 0
          console.log("P10_106_SENTINEL_DESTRUCTION", serial)
          if (serial === 0)
            test.fail("owner sentinel died before its native IPC handler")
        }
        test.observedLoadedOwners = root.loadedOwners.slice()
      }
    }

    QtObject {
      id: root

      readonly property bool vertical: false
      readonly property int barSize: ownershipController.v2Mode ? 33 : 35
      readonly property bool transparent: false
      readonly property bool barHidden: false
      readonly property string position: "top"
      readonly property string fontFamily: "monospace"
      readonly property color foreground: noSplitBar.foreground
      readonly property color barForeground: noSplitBar.foreground
      readonly property color background: noSplitBar.background
      readonly property color urgent: noSplitBar.urgent
      readonly property bool foregroundAnimationEnabled: false
      readonly property var shell: ownershipShell
      readonly property var visualTokens: ownershipController.v2Mode
        ? v2SplitBar.visualTokens : noSplitBar.visualTokens
      readonly property var layoutConfig: ({
        left: [
          { id: test.nativeOwnerId },
          { id: test.outputOwnershipId },
          { id: test.multipleOwnershipId },
          { id: test.peerOwnershipId },
          { id: test.abandonedOwnershipId }
        ], center: [], right: []
      })
      readonly property var layoutController: ownershipController
      readonly property var pluginRegistry: ({ pluginId: "fixture" })
      readonly property var barWidgetRegistry: ({ widgets: ({
        [test.nativeOwnerId]: {
          component: nativeOwnerWidget,
          metadata: { pluginId: test.nativeOwnerId, allowMultiple: false }
        },
        [test.outputOwnershipId]: {
          component: markerWidget,
          metadata: { pluginId: test.outputOwnershipId, allowMultiple: false }
        },
        [test.multipleOwnershipId]: {
          component: markerWidget,
          metadata: { pluginId: test.multipleOwnershipId, allowMultiple: true }
        },
        [test.peerOwnershipId]: {
          component: markerWidget,
          metadata: { pluginId: test.peerOwnershipId, allowMultiple: false }
        },
        [test.abandonedOwnershipId]: {
          component: markerWidget,
          metadata: { pluginId: test.abandonedOwnershipId, allowMultiple: false }
        }
      }) })
      readonly property var v1FamilySlotBindings: ({})
      property var activePopout: null
      property var pendingTooltipTarget: null
      property var tooltipTarget: null
      property var moduleSlots: []
      // INJECT_BAR_LOADED_OWNER_DECLARATIONS

      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(moduleName) {
        const source = barWidgetRegistry.widgets[moduleName]
        return source ? source.component : null
      }
      function widgetAllowsMultiple(moduleName) {
        const source = barWidgetRegistry.widgets[moduleName]
        return !!(source && source.metadata.allowMultiple)
      }
      function registerModuleSlot(slot) {
        if (moduleSlots.indexOf(slot) < 0) moduleSlots = moduleSlots.concat([slot])
      }
      function unregisterModuleSlot(slot) {
        moduleSlots = moduleSlots.filter(item => item !== slot)
      }
      // INJECT_BAR_LOADED_OWNER_FUNCTIONS
      function showTooltip(_owner, _text) {}
      function hideTooltip(_owner) {}
      function releasePopout(_owner) {}
      function unassignedLayoutEntries(_region) { return [] }
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
        shellStyle: "full",
        shellWingWidth: 14,
        shellFitRadius: 6,
        shellDockRadius: 8,
        shellBorder: "#505050",
        shellShadow: "#66000000",
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
        pillShadow: "#66000000",
        shadowEnabled: true,
        islandBorder: "#505050",
        slotHeight: 28,
        tileRadius: 10,
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
      readonly property var layoutConfig: ({
        left: [], center: [],
        right: [{ id: "omarchy.active-window" }]
      })
      readonly property var layoutController: v2SplitController
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
      id: shapeBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property bool transparent: false
      readonly property string fontFamily: "monospace"
      readonly property color foreground: noSplitBar.foreground
      readonly property color background: noSplitBar.background
      readonly property color urgent: noSplitBar.urgent
      readonly property var shell: shapeShell
      readonly property var visualTokens: shapeTokens
      readonly property var layoutConfig: noSplitBar.layoutConfig
      readonly property var layoutController: v2SplitController
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
      function unassignedLayoutEntries(_region) { return [] }
    }

    QtObject {
      id: v2HiddenGapBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property bool transparent: false
      readonly property string fontFamily: "monospace"
      readonly property color foreground: noSplitBar.foreground
      readonly property color background: noSplitBar.background
      readonly property color urgent: noSplitBar.urgent
      readonly property var shell: disabledShell
      readonly property var visualTokens: v2SplitBar.visualTokens
      readonly property var layoutConfig: noSplitBar.layoutConfig
      readonly property var layoutController: v2SplitController
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
      function unassignedLayoutEntries(_region) { return [] }
    }

    ShibumiStyle.VisualTokens {
      id: shapeTokens
      bar: shapeBar
    }

    QtObject {
      id: placedDynamicController
      function groupLocation(groupId) {
        return groupId === "G:omarchy.active-window"
          ? {region: "right", index: 7, groupId: groupId} : null
      }
    }

    QtObject {
      id: budgetBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property var shell: fakeShell
      readonly property var visualTokens: noSplitBar.visualTokens
      readonly property var layoutController: placedDynamicController
      readonly property var layoutConfig: ({
        left: [], center: [],
        right: [
          { id: "omarchy.active-window" },
          { id: "hancore.shibumi.temperature" },
          { id: "hancore.shibumi.gpu" }
        ]
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
      id: familyResolver
      property int revision: 0
      function ensureComponent(id) { return id ? markerWidget : null }
      function manifestFor(id) {
        return id === "omarchy.clock"
          ? { id: "local.clock", name: "Local clock clone" } : null
      }
    }

    QtObject {
      id: familyBar
      property bool useV2: false
      property var v1FamilySlotBindings: ({ G8: "omarchy.clock" })
      readonly property var hostWidgetResolver: familyResolver
      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property var shell: disabledShell
      readonly property var visualTokens: useV2
        ? v2SplitBar.visualTokens : noSplitBar.visualTokens
      readonly property var layoutConfig: ({ left: [],
        center: [{ id: "omarchy.clock", shibumiModule: true, format: "HH:mm" }],
        right: [] })
      property var activePopout: null
      function entryId(entry) { return noSplitBar.entryId(entry) }
      function entrySettings(entry) { return noSplitBar.entrySettings(entry) }
      function registeredWidgetComponent(id) { return markerWidget }
      function registerModuleSlot(slot) {}
      function unregisterModuleSlot(slot) {}
      function hideTooltip(owner) {}
      function releasePopout(owner) {}
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

    QtObject {
      id: hiddenGapBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property bool transparent: false
      readonly property string fontFamily: "monospace"
      readonly property color foreground: noSplitBar.foreground
      readonly property color background: noSplitBar.background
      readonly property color urgent: noSplitBar.urgent
      readonly property var shell: disabledShell
      readonly property var visualTokens: noSplitBar.visualTokens
      readonly property var layoutConfig: noSplitBar.layoutConfig
      readonly property var layoutController: hiddenGapController
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
      function unassignedLayoutEntries(_region) { return [] }
    }

    QtObject {
      id: notchBar

      readonly property string position: "top"
      readonly property color background: "#181818"
      readonly property var visualTokens: ({
        shellStyle: "notch",
        shellWingWidth: 14,
        shellFitRadius: 6,
        shellDockRadius: 8,
        islandRadius: 12,
        shellBorder: "#aa88ff",
        islandBorder: "#aa88ff",
        pillBorderWidth: 1
      })
      readonly property string connectedPanelScreenName: ""
      readonly property real connectedPanelReveal: 0
      readonly property real connectedPanelX: 0
    }

    Repeater {
      id: notchBorderModes

      model: [
        { mode: "auto", width: 720 },
        { mode: "none", width: 712 },
        { mode: "compact", width: 724 },
        { mode: "roomy", width: 736 }
      ]

      delegate: ShibumiStyle.RunChrome {
        required property var modelData

        bar: notchBar
        width: modelData.width
        height: 33
        visible: false
      }
    }

    ShibumiStyle.GroupSection {
      id: leftWithoutSplit
      bar: noSplitBar
      region: "left"
      layoutSession: editingSession
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
      layoutSession: editingSession
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
      id: hiddenGapSection
      bar: hiddenGapBar
      region: "left"
    }

    ShibumiStyle.GroupSection {
      id: v2HiddenGapSection
      bar: v2HiddenGapBar
      region: "left"
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

    ShibumiStyle.BarSurface {
      id: centerRunSurface
      bar: centerRunBar
      width: 1200
      height: centerRunBar.barSize
    }

    ShibumiStyle.BarSurface {
      id: tallAlignmentSurface
      bar: tallAlignmentBar
      width: 1200
      height: tallAlignmentBar.barSize
      y: 80
    }

    ShibumiStyle.BarSurface {
      id: shortAlignmentSurface
      bar: shortAlignmentBar
      width: 1200
      height: shortAlignmentBar.barSize
      y: 120
    }

    ShibumiStyle.BarSurface {
      id: narrowExtraSurface
      bar: tallAlignmentBar
      width: fullSurface.responsiveProbe.candidates
        ? fullSurface.responsiveProbe.candidates[0] + 34 : 1200
      height: tallAlignmentBar.barSize
    }

    ShibumiStyle.BarSurface {
      id: narrowPlainSurface
      bar: noSplitBar
      width: narrowExtraSurface.width
      height: noSplitBar.barSize
    }

    Loader {
      id: actualBarFixtureLoader

      property bool teardownStarted: false
      active: false
      sourceComponent: actualBarFixture
      onLoaded: {
        if (!item.teardownClaimed)
          return test.fail("actual Bar fixture owner was not ready")
        Qt.callLater(function() { actualBarFixtureLoader.active = false })
      }
      onItemChanged: {
        if (!teardownStarted || item !== null) return
        Qt.callLater(function() {
          console.log("P10_106_ACTUAL_BAR_TEARDOWN")
          console.log("group renderer regression passed")
          Qt.exit(0)
        })
      }
    }

    ShibumiStyle.BarSurface {
      id: ownershipSurface
      bar: root
      screenName: "DP-1"
      width: 1200
      height: root.barSize
    }

    Core.WidgetSlot {
      id: outputOwnerA
      bar: root
      entry: ({ id: test.outputOwnershipId })
      screenName: "DP-1"
    }

    Core.WidgetSlot {
      id: outputOwnerB
      bar: root
      entry: ({ id: test.outputOwnershipId })
      screenName: "HDMI-A-1"
    }

    Core.WidgetSlot {
      id: multipleOwnerA
      bar: root
      entry: ({ id: test.multipleOwnershipId })
      screenName: "DP-1"
    }

    Core.WidgetSlot {
      id: multipleOwnerB
      bar: root
      entry: ({ id: test.multipleOwnershipId })
      screenName: "DP-1"
    }

    Core.WidgetSlot {
      id: peerOwner
      bar: root
      entry: ({ id: test.peerOwnershipId, enabled: test.peerOwnerEnabled })
      screenName: "DP-1"
    }

    Loader {
      id: peerWaiter
      active: nativeOwnershipProbe.running
      sourceComponent: Core.WidgetSlot {
        bar: root
        entry: ({ id: test.peerOwnershipId })
        screenName: "DP-1"
      }
    }

    Core.WidgetSlot {
      id: abandonedOwner
      bar: root
      entry: ({ id: test.abandonedOwnershipId,
        enabled: test.abandonedOwnerEnabled })
      screenName: "DP-1"
    }

    Loader {
      id: abandonedWaiter
      active: test.abandonedWaiterPresent && nativeOwnershipProbe.running
      sourceComponent: Core.WidgetSlot {
        bar: root
        entry: ({ id: test.abandonedOwnershipId })
        screenName: "DP-1"
      }
    }

    Core.GroupSlot {
      id: familySlot
      bar: familyBar
      groupId: "G8"
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
      id: dynamicV1Group
      bar: budgetBar
      groupId: "G:omarchy.active-window"
    }

    Core.GroupSlot {
      id: dynamicSuiteV1FillGroup
      bar: budgetBar
      groupId: "G:hancore.shibumi.temperature"
    }

    Core.GroupSlot {
      id: dynamicSuiteV1InheritedGroup
      bar: budgetBar
      groupId: "G:hancore.shibumi.gpu"
    }

    Core.GroupSlot {
      id: v2FillGroup
      bar: v2SplitBar
      groupId: "G1"
    }

    Core.GroupSlot {
      id: dynamicV2Group
      bar: v2SplitBar
      groupId: "G:omarchy.active-window"
    }

    Core.GroupSlot {
      id: shapeGroup
      bar: shapeBar
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
      throw new Error(message)
    }

    function closeEnough(actual, expected) {
      return Math.abs(actual - expected) <= 0.5
    }

    function uniformGapError(section, expected) {
      const geometry = section.groupGeometry
      for (let index = 1; index < geometry.length; index++) {
        const gap = geometry[index].left - geometry[index - 1].right
        if (!closeEnough(gap, expected))
          return "visible index " + index + " got " + gap
            + ", expected " + expected + ": " + JSON.stringify(geometry)
      }
      return ""
    }

    function widgetSlots(item, result) {
      if (!item) return result
      if (item.activeItem) result.push(item)
      const children = item.children || []
      for (const child of children) widgetSlots(child, result)
      return result
    }

    function groupCells(section) {
      const result = []
      const children = section && section.contentItem
        ? section.contentItem.children || [] : []
      for (const child of children) {
        if ("modelData" in child) result.push(child)
      }
      return result
    }

    function regionItem(item, region) {
      if (!item) return null
      if ("region" in item && "contentItem" in item
          && String(item.region || "") === region) return item
      const children = item.children || []
      for (const child of children) {
        const match = regionItem(child, region)
        if (match) return match
      }
      return null
    }

    function centerY(item, relativeTo) {
      const point = item.mapToItem(relativeTo, 0, 0)
      return point.y + item.height / 2
    }

    function runChromeItem(item) {
      if (!item) return null
      if ("runs" in item && "notchShoulderInset" in item) return item
      const children = item.children || []
      for (const child of children) {
        const match = runChromeItem(child)
        if (match) return match
      }
      return null
    }

    function cutsFromRuns(runs) {
      const result = []
      for (let index = 1; index < runs.length; index++) {
        result.push({
          from: runs[index - 1].x + runs[index - 1].width,
          to: runs[index].x
        })
      }
      return result
    }

    function expectedSectionCut(section, runChrome) {
      const geometry = section.groupGeometry
      if (geometry.length < 2) return null
      const origin = section.mapToItem(runChrome, 0, 0).x
      return {
        from: origin + geometry[0].right + 4,
        to: origin + geometry[1].left - 4,
        localFrom: geometry[0].right + 4,
        localTo: geometry[1].left - 4
      }
    }

    function sameCut(actual, expected) {
      return actual && expected
        && closeEnough(actual.from, expected.from)
        && closeEnough(actual.to, expected.to)
    }

    function hasCut(cuts, expected) {
      return cuts.some(function(cut) { return sameCut(cut, expected) })
    }

    function regionAlignmentError(surface, alignmentTestBar, region,
        expectedV2, expectedPosition, expectedExtraHeight) {
      const groups = regionItem(surface, region)
      const extras = regionItem(surface, region + "-extra")
      if (!groups || !extras || groups.implicitWidth <= 0
          || extras.implicitWidth <= 0)
        return region + " region did not load"
      if (alignmentTestBar.useV2 !== expectedV2
          || groups.v2Mode !== expectedV2)
        return region + " region did not enter "
          + (expectedV2 ? "V2" : "V1")
      if (alignmentTestBar.position !== expectedPosition)
        return region + " region did not enter " + expectedPosition
      if (!closeEnough(extras.implicitHeight, expectedExtraHeight)
          || closeEnough(extras.implicitHeight, groups.implicitHeight))
        return region + " fixture lost its mixed-height precondition: groups="
          + groups.implicitHeight + ", extras=" + extras.implicitHeight
          + ", expected extra=" + expectedExtraHeight
      const groupCenter = centerY(groups, surface)
      const extraCenter = centerY(extras, surface)
      const shibumiShell = String(
        alignmentTestBar.visualTokens.shellStyle || "shibumi") === "shibumi"
      const chromeHeight = shibumiShell
        ? Math.min(surface.height,
            alignmentTestBar.visualTokens.islandHeight)
        : surface.height
      const chromeY = shibumiShell
        ? expectedPosition === "bottom" ? 0
          : alignmentTestBar.visualTokens.islandOffsetY
        : expectedPosition === "bottom"
          ? surface.height - chromeHeight : 0
      const expectedCenter = chromeY + chromeHeight / 2
      if (!closeEnough(groupCenter, extraCenter)
          || !closeEnough(groupCenter, expectedCenter))
        return region + " centers differ: groups=" + groupCenter
          + ", extras=" + extraCenter + ", expected=" + expectedCenter
          + ", heights=" + groups.height + "/" + extras.height
      return ""
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
          nextShownIndex: child.nextShownIndex,
          separatorIndex: child.separatorIndex,
          separated: child.separated,
          x: child.x,
          width: child.width,
          visible: child.visible
        })
      }
      return result
    }

    Process {
      id: nativeOwnerPing
      command: ["/usr/bin/quickshell", "ipc", "--pid",
        String(Quickshell.processId), "call", "--",
        "fixture.shibumi.106.native-owner", "ping"]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: test.nativePingOutput = String(text || "").trim()
      }
      onExited: function(code) {
        test.nativePingExit = code
        Qt.callLater(function() { test.nativePingReady = true })
      }
    }

    Timer {
      id: nativeOwnershipProbe

      property int phase: 0
      property int waits: 0
      property var sourceSlot: null
      property var sourceItem: null
      property string sourceSlotPointer: ""
      property string sourceItemPointer: ""
      property bool v1ToV2Overlap: false
      property bool v2ToV1Overlap: false
      property bool regionOverlap: false
      property bool nativePingStarted: false
      property bool peerStartedWaiting: false
      property bool abandonedStartedWaiting: false
      interval: 10
      repeat: true

      function ownerSlot(region) {
        const section = test.regionItem(ownershipSurface, region)
        return test.widgetSlots(section, []).find(
          slot => slot.moduleName === test.nativeOwnerId) || null
      }

      function awaitOrFail(message) {
        waits++
        if (waits < 100) return true
        stop()
        test.fail(message)
        return false
      }

      function geometryUnchanged(item) {
        return item && item.children.length === 1
          && item.childrenRect.x === 10 && item.childrenRect.width === 10
      }

      function beginTransfer(label, next) {
        sourceSlot = ownerSlot(label === "V1_TO_V2" ? "left" : "right")
        sourceItem = sourceSlot ? sourceSlot.activeItem : null
        if (!sourceItem) return false
        if (!geometryUnchanged(sourceItem)) {
          test.fail("owner sentinel changed foreign item geometry")
          return false
        }
        sourceSlotPointer = String(sourceSlot)
        sourceItemPointer = String(sourceItem)
        console.log("P10_106_BEGIN", label, "sourceSlot=" + sourceSlotPointer,
          "sourceItem=" + sourceItemPointer, "alive=" + test.nativeAlive)
        next()
        sourceSlot = null
        sourceItem = null
        phase++
        waits = 0
        return true
      }

      function observeTransfer(label, region) {
        const targetSlot = ownerSlot(region)
        const targetItem = targetSlot ? targetSlot.activeItem : null
        if (!targetItem || String(targetItem) === sourceItemPointer) return false
        if (!geometryUnchanged(targetItem)) {
          test.fail("owner sentinel changed replacement item geometry")
          return false
        }
        const overlap = test.nativeLoadOverlaps[targetItem.instanceSerial - 1]
          === true
        console.log("P10_106_TARGET", label,
          "sourceSlot=" + sourceSlotPointer, "sourceItem=" + sourceItemPointer,
          "targetSlot=" + String(targetSlot), "targetItem=" + String(targetItem),
          "alive=" + test.nativeAlive, "overlap=" + overlap)
        if (label === "V1_TO_V2") v1ToV2Overlap = overlap
        else if (label === "V2_TO_V1") v2ToV1Overlap = overlap
        else regionOverlap = overlap
        sourceSlot = targetSlot
        sourceItem = targetItem
        phase++
        waits = 0
        return true
      }

      onTriggered: {
        if (phase === 0) {
          if (!beginTransfer("V1_TO_V2", function() {
              ownershipStateService.setStyle("full")
            })) awaitOrFail("V1 dynamic owner did not settle")
          return
        }
        if (phase === 1) {
          if (!observeTransfer("V1_TO_V2", "right"))
            awaitOrFail("V1 to V2 target did not settle")
          return
        }
        if (phase === 2) {
          if (test.nativeAlive > 1) {
            awaitOrFail("V1 owner did not release after V2 load")
            return
          }
          console.log("P10_106_RELEASED", "V1_TO_V2", "alive=" + test.nativeAlive)
          if (beginTransfer("V2_TO_V1", function() {
              ownershipStateService.setStyle("shibumi")
            })) phase = 3
          return
        }
        if (phase === 3) {
          if (!observeTransfer("V2_TO_V1", "left"))
            awaitOrFail("V2 to V1 target did not settle")
          return
        }
        if (phase === 4) {
          if (test.nativeAlive > 1) {
            awaitOrFail("V2 owner did not release after V1 load")
            return
          }
          console.log("P10_106_RELEASED", "V2_TO_V1", "alive=" + test.nativeAlive)
          sourceSlotPointer = String(sourceSlot)
          sourceItemPointer = String(sourceItem)
          console.log("P10_106_BEGIN", "V1_REGION",
            "sourceSlot=" + sourceSlotPointer,
            "sourceItem=" + sourceItemPointer, "alive=" + test.nativeAlive)
          ownershipStateService.moveV1OwnerRight()
          sourceSlot = null
          sourceItem = null
          phase = 5
          waits = 0
          return
        }
        if (phase === 5) {
          if (!observeTransfer("V1_REGION", "right"))
            awaitOrFail("V1 cross-region target did not settle")
          return
        }
        if (phase === 6) {
          if (test.nativeAlive > 1) {
            awaitOrFail("V1 region source did not release")
            return
          }
          if (!outputOwnerA.activeItem || !outputOwnerB.activeItem)
            return test.fail("same widget did not load on different outputs")
          if (!multipleOwnerA.activeItem || !multipleOwnerB.activeItem)
            return test.fail("allowMultiple widget did not load twice on one output")
          if (!directWidget.activeItem)
            return test.fail("legacy bar without admission API did not load")
          console.log("P10_106_ADMISSION_CONTROLS", "legacy=true",
            "output=true", "allowMultiple=true", "children="
            + sourceItem.children.length, "rect=" + sourceItem.childrenRect.x
            + ":" + sourceItem.childrenRect.width)
          if (!nativePingStarted) {
            test.nativePingExpected = sourceItem.instanceSerial
            if (test.nativePingExpected <= 1)
              return test.fail("replacement owner was not fresh")
            nativePingStarted = true
            nativeOwnerPing.running = true
            return
          }
          if (!test.nativePingReady) return
          if (test.nativePingExit !== 0
              || test.nativePingOutput !== String(test.nativePingExpected))
            return test.fail("private IPC did not route to the fresh owner")
          console.log("P10_106_PRIVATE_IPC", test.nativePingOutput)
          peerStartedWaiting = peerOwner.activeItem !== null
            && peerWaiter.item && peerWaiter.item.activeItem === null
          test.peerSentinel = root.loadedOwners.find(
            owner => owner.slot === peerOwner) || null
          if (!test.peerSentinel)
            return test.fail("peer owner sentinel was absent before item teardown")
          abandonedStartedWaiting = abandonedOwner.activeItem !== null
            && abandonedWaiter.item && abandonedWaiter.item.activeItem === null
          test.peerOwnerEnabled = false
          phase = 7
          waits = 0
          return
        }
        if (phase === 7) {
          if (peerOwner.activeItem !== null || !peerWaiter.item
              || peerWaiter.item.activeItem === null) {
            awaitOrFail("waiting peer did not load after owner item unload")
            return
          }
          if (root.loadedOwners.indexOf(test.peerSentinel) >= 0)
            return test.fail("peer owner sentinel survived item teardown")
          test.abandonedWaiterPresent = false
          phase = 8
          waits = 0
          return
        }
        if (phase === 8) {
          if (abandonedWaiter.item !== null) {
            awaitOrFail("waiting target slot was not destroyed")
            return
          }
          test.abandonedOwnerEnabled = false
          phase = 9
          waits = 0
          return
        }
        if (phase === 9) {
          if (abandonedOwner.activeItem !== null) {
            awaitOrFail("abandoned owner item did not unload")
            return
          }
          stop()
          console.log("P10_106_FAILURE_CONTROLS",
            "peerWaited=" + peerStartedWaiting,
            "destroyedTargetWaited=" + abandonedStartedWaiting)
          if (v1ToV2Overlap || v2ToV1Overlap || regionOverlap
              || !peerStartedWaiting || !abandonedStartedWaiting)
            return test.fail("native owner handoff overlapped or bypassed waiting")
          actualBarFixtureLoader.teardownStarted = true
          actualBarFixtureLoader.active = true
        }
      }
    }

    Timer {
      property int attempts: 0
      property bool narrowed: false
      property int separatorPhase: 0
      property real separatorBaseWidth: 0
      property int shapePhase: 0
      property int shadowPhase: 0
      property int hiddenGapPhase: 0
      property int alignmentPhase: 0
      property int centerRunPhase: 0
      property var centerSideCuts: []
      readonly property var alignmentCases: [
        { v2: false, position: "top" },
        { v2: false, position: "bottom" },
        { v2: true, position: "top" },
        { v2: true, position: "bottom" },
        { v2: false, position: "top" }
      ]
      readonly property var alignmentFixtures: [
        {
          name: "tall",
          surface: tallAlignmentSurface,
          bar: tallAlignmentBar,
          extraHeight: 35
        },
        {
          name: "short",
          surface: shortAlignmentSurface,
          bar: shortAlignmentBar,
          extraHeight: 8
        }
      ]

      property int familyPhase: 0
      property var retainedAlignmentCells: ({})
      readonly property var retainedAlignmentIds: [
        "G1", "G2", "G3", "G5", "G6", "G7"
      ]
      interval: 10
      running: true
      repeat: true

      onTriggered: {
        attempts++
        if (leftWithoutSplit.implicitWidth <= 0
            || leftWithSplit.implicitWidth <= 0
            || centerSection.implicitWidth <= 0
            || rightSection.implicitWidth <= 0
            || hiddenGapSection.implicitWidth <= 0
            || v2HiddenGapSection.implicitWidth <= 0
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

        if (familyPhase < 3) {
          if (familyPhase === 0) {
            const slots = test.widgetSlots(familySlot.contentItem, [])
            if (slots.length !== 1) {
              if (attempts < 50) return
              return test.fail("family replacement content did not load")
            }
            if (familySlot.groupId !== "G8"
                || familySlot.effectiveGroupId !== "G:omarchy.clock"
                || !familySlot.groupEnabled || !familySlot.dynamicV1Group
                || slots[0].moduleName !== "omarchy.clock"
                || slots[0].moduleManifest.id !== "local.clock"
                || slots[0].fallbackTooltipText !== "Local clock clone"
                || slots[0].activeItem.settings.format !== "HH:mm"
                || !familySlot.visualSurfaceItem.visible
                || !test.closeEnough(familySlot.visualSurfaceItem.radius, 12))
              return test.fail("fixed family slot lost provider identity/settings/surface")
            familyBar.v1FamilySlotBindings = ({})
          } else if (familyPhase === 1) {
            if (familySlot.contentItem !== null) {
              if (attempts < 50) return
              return test.fail("removed family projection retained its provider")
            }
            familyBar.useV2 = true
            familyBar.v1FamilySlotBindings = ({ G8: "omarchy.clock" })
          } else {
            if (familySlot.effectiveGroupId !== "G8"
                || familySlot.groupEnabled || familySlot.contentItem !== null)
              return test.fail("V1 family projection leaked into V2")
            familyBar.useV2 = false
          }
          familyPhase++
          attempts = 0
          return
        }

        if (centerRunPhase < 3) {
          const runChrome = test.runChromeItem(centerRunSurface)
          const left = test.regionItem(centerRunSurface, "left")
          const center = test.regionItem(centerRunSurface, "center")
          const right = test.regionItem(centerRunSurface, "right")
          if (!runChrome || !left || !center || !right
              || left.groupGeometry.length !== 2
              || center.groupGeometry.length !== 2
              || right.groupGeometry.length !== 2) {
            if (attempts < 50) return
            stop()
            test.fail("full BarSurface run geometry did not settle")
            return
          }

          const cuts = test.cutsFromRuns(runChrome.runs)
          const leftCut = test.expectedSectionCut(left, runChrome)
          const centerCut = test.expectedSectionCut(center, runChrome)
          const rightCut = test.expectedSectionCut(right, runChrome)
          if (!test.hasCut(cuts, leftCut) || !test.hasCut(cuts, rightCut)) {
            stop()
            test.fail("left/right BarSurface cuts drifted: "
              + JSON.stringify(cuts))
            return
          }

          if (centerRunPhase === 0) {
            if (cuts.length !== 3 || !test.hasCut(cuts, centerCut)
                || centerCut.localFrom >= centerCut.localTo) {
              stop()
              test.fail("enabled center split did not cut the content gap: cuts="
                + JSON.stringify(cuts) + ", center="
                + JSON.stringify(centerCut) + ", runs="
                + JSON.stringify(runChrome.runs))
              return
            }
            centerSideCuts = [leftCut, rightCut]
            centerRunController.centerSplitMode = 1
          } else {
            if (cuts.length !== 2
                || !test.sameCut(cuts[0], centerSideCuts[0])
                || !test.sameCut(cuts[1], centerSideCuts[1])) {
              stop()
              test.fail("disabled/empty center split changed side cuts or cut center: "
                + JSON.stringify(cuts) + " versus "
                + JSON.stringify(centerSideCuts))
              return
            }
            if (centerRunPhase === 1)
              centerRunController.centerSplitMode = 2
          }
          centerRunPhase++
          attempts = 0
          return
        }

        if (alignmentPhase < alignmentCases.length) {
          const alignmentCase = alignmentCases[alignmentPhase]
          for (const fixture of alignmentFixtures) {
            for (const region of ["left", "center", "right"]) {
              const alignmentError = test.regionAlignmentError(
                fixture.surface, fixture.bar, region, alignmentCase.v2,
                alignmentCase.position, fixture.extraHeight)
              if (alignmentError !== "") {
                if (attempts < 50) return
                stop()
                test.fail("mixed-height extra shifted grouped widgets in "
                  + (alignmentCase.v2 ? "V2" : "V1") + " "
                  + alignmentCase.position + " with " + fixture.name
                  + " " + fixture.extraHeight + "px extra: "
                  + alignmentError)
                return
              }
            }
          }
          const alignmentLeft = test.regionItem(
            tallAlignmentSurface, "left")
          const alignmentCells = test.groupCells(alignmentLeft)
          const alignmentOrder = alignmentCells.map(function(cell) {
            return String(cell.modelData || "")
          })
          const expectedAlignmentOrder = alignmentCase.v2
            ? v2SplitController.order.left : noSplitController.v1Slots.left
          if (JSON.stringify(alignmentOrder)
              !== JSON.stringify(expectedAlignmentOrder)) {
            if (attempts < 50) return
            stop()
            test.fail("variant alignment order did not settle: "
              + JSON.stringify(alignmentOrder) + " expected "
              + JSON.stringify(expectedAlignmentOrder))
            return
          }
          if (alignmentPhase === 0) {
            const owners = ({})
            for (const cell of alignmentCells) owners[cell.modelData] = cell
            retainedAlignmentCells = owners
          } else {
            for (const groupId of retainedAlignmentIds) {
              const cell = alignmentCells.find(function(item) {
                return String(item.modelData || "") === groupId
              })
              if (cell !== retainedAlignmentCells[groupId]) {
                stop()
                test.fail("variant reorder replaced retained group owner "
                  + groupId + " in alignment phase " + alignmentPhase)
                return
              }
            }
          }
          if (!alignmentCase.v2) {
            const plain = fullSurface.responsiveProbe
            const extra = tallAlignmentSurface.responsiveProbe
            const slots = test.widgetSlots(tallAlignmentSurface, [])
            const center = slots.find(slot => slot.moduleName === "hancore.shibumi.center")
            const complete = extra.candidates && plain.candidates
              && extra.candidates.every((value, index) =>
                test.closeEnough(value - plain.candidates[index], 108))
            if (!complete || !center
                || !test.closeEnough(extra.centerAvailable, plain.centerAvailable - 108)
                || !test.closeEnough(center.activeItem.availableWidth, extra.centerAvailable)
                || narrowPlainSurface.responsiveStage !== 0
                || narrowExtraSurface.responsiveStage === 0) {
              if (attempts < 50) return
              return test.fail("unassigned extras omitted from output-local width/staging: "
                + JSON.stringify(extra) + " versus " + JSON.stringify(plain))
            }
          }
          alignmentPhase++
          if (alignmentPhase < alignmentCases.length) {
            const nextAlignmentCase = alignmentCases[alignmentPhase]
            tallAlignmentBar.useV2 = nextAlignmentCase.v2
            tallAlignmentBar.position = nextAlignmentCase.position
            shortAlignmentBar.useV2 = nextAlignmentCase.v2
            shortAlignmentBar.position = nextAlignmentCase.position
            attempts = 0
            return
          }
          attempts = 0
        }

        if (hiddenGapPhase === 0) {
          const spacingChecks = [
            { name: "V1 left", section: leftWithoutSplit },
            { name: "V1 right", section: rightSection },
            { name: "V2 left", section: v2LeftWithSplit }
          ]
          for (const check of spacingChecks) {
            const spacingError = test.uniformGapError(
              check.section, check.section.groupSpacing)
            if (spacingError !== "") {
              if (attempts < 50) return
              stop()
              test.fail(check.name + " group spacing drifted: "
                + spacingError)
              return
            }
          }
          const geometry = hiddenGapSection.groupGeometry
          if (geometry.length !== 6) {
            if (attempts < 50) return
            stop()
            test.fail("hidden-slot spacing geometry did not settle: "
              + JSON.stringify(geometry))
            return
          }
          for (let index = 1; index < geometry.length; index++) {
            const gap = geometry[index].left - geometry[index - 1].right
            if (!test.closeEnough(gap, hiddenGapSection.groupSpacing)) {
              stop()
              test.fail("normal group gap drifted at visible index " + index
                + ": got " + gap + ", expected "
                + hiddenGapSection.groupSpacing)
              return
            }
          }
          const v2Geometry = v2HiddenGapSection.groupGeometry
          const v2Marker = v2HiddenGapSection.separatorGeometry.find(
            function(entry) { return entry.groupId === "G1" })
          if (v2Geometry.length !== 6 || !v2Marker
              || v2Marker.index !== 0) {
            if (attempts < 50) return
            stop()
            test.fail("V2 hidden-slot separator geometry did not settle: "
              + JSON.stringify(v2Geometry) + ", marker="
              + JSON.stringify(v2Marker))
            return
          }
          for (let index = 1; index < v2Geometry.length; index++) {
            const gap = v2Geometry[index].left - v2Geometry[index - 1].right
            const expected = index === 1 ? 22 : 6
            if (!test.closeEnough(gap, expected)) {
              if (attempts < 50) return
              stop()
              test.fail("V2 separator across hidden slot drifted at "
                + index + ": got " + gap + ", expected " + expected
                + ", state=" + JSON.stringify(
                  test.sectionState(v2HiddenGapSection)))
              return
            }
          }
          const marker = hiddenGapSection.separatorGeometry.find(
            function(entry) { return entry.groupId === "G1" })
          if (!marker || marker.index !== 1
              || !test.closeEnough(hiddenGapSection.implicitWidth, 90)
              || !hiddenGapSection.toggleSeparator(
                marker.groupId, marker.index)
              || hiddenGapController.toggleCount !== 1
              || hiddenGapController.lastToggleIndex !== 1) {
            stop()
            test.fail("split before visible G3 targeted the wrong V1 boundary: "
              + JSON.stringify(marker) + ", width="
              + hiddenGapSection.implicitWidth + ", toggleIndex="
              + hiddenGapController.lastToggleIndex)
            return
          }
          hiddenGapPhase = 1
          attempts = 0
          return
        }

        if (hiddenGapPhase === 1) {
          if (!test.closeEnough(hiddenGapSection.implicitWidth, 106)) {
            if (attempts < 50) return
            stop()
            test.fail("split before visible G3 did not add the 16px split gap: "
              + hiddenGapSection.implicitWidth)
            return
          }
          const geometry = hiddenGapSection.groupGeometry
          for (let index = 1; index < geometry.length; index++) {
            const gap = geometry[index].left - geometry[index - 1].right
            const expected = index === 1 ? 22 : 6
            if (!test.closeEnough(gap, expected)) {
              if (attempts < 50) return
              stop()
              test.fail("group spacing after hidden-slot split drifted at "
                + index + ": got " + gap + ", expected " + expected
                + ", state=" + JSON.stringify(
                  test.sectionState(hiddenGapSection))
                + ", geometry=" + JSON.stringify(geometry))
              return
            }
          }
          hiddenGapPhase = 2
          attempts = 0
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

        if (separatorPhase === 0) {
          separatorBaseWidth = v2LeftWithSplit.implicitWidth
          fakeStateService.setSeparator(true)
          separatorPhase = 1
          attempts = 0
          return
        }
        if (separatorPhase === 1) {
          if (!test.closeEnough(v2LeftWithSplit.implicitWidth,
                separatorBaseWidth + v2LeftWithSplit.splitGrow)) {
            if (attempts < 50) return
            stop()
            test.fail("V2 separator did not react to state revision: before="
              + separatorBaseWidth + ", after="
              + v2LeftWithSplit.implicitWidth + ", revision="
              + fakeStateService.revision)
            return
          }
          fakeStateService.setSeparator(false)
          separatorPhase = 2
          attempts = 0
          return
        }
        if (separatorPhase === 2
            && !test.closeEnough(v2LeftWithSplit.implicitWidth,
              separatorBaseWidth)) {
          if (attempts < 50) return
          stop()
          test.fail("V2 separator did not clear after state revision: before="
            + separatorBaseWidth + ", after=" + v2LeftWithSplit.implicitWidth)
          return
        }

        const shapeMatrix = [
          { value: "auto", radius: 10 },
          { value: "square", radius: 0 },
          { value: "soft", radius: 6 },
          { value: "round", radius: 12 }
        ]
        if (shapePhase < shapeMatrix.length) {
          const expectedShape = shapeMatrix[shapePhase]
          if (!shapeGroup.decorated
              || !test.closeEnough(shapeGroup.visualSurfaceItem.height, 24)
              || !test.closeEnough(shapeGroup.visualSurfaceItem.radius,
                expectedShape.radius)) {
            if (attempts < 50) return
            stop()
            test.fail("V2 shape radius drifted for " + expectedShape.value
              + ": got " + shapeGroup.visualSurfaceItem.radius
              + " on " + shapeGroup.visualSurfaceItem.height + "px surface")
            return
          }
          shapePhase++
          if (shapePhase < shapeMatrix.length)
            shapeStateService.setShape(shapeMatrix[shapePhase].value)
          attempts = 0
          return
        }

        if (shadowPhase === 0) {
          const dynamicV2Slots = test.widgetSlots(
            dynamicV2Group.contentItem, [])
          if (dynamicV2Group.moduleCount !== 1
              || !dynamicV2Group.contentItem
              || dynamicV2Slots.length !== 1
              || !dynamicV2Slots[0].activeItem) {
            if (attempts < 50) return
            stop()
            test.fail("dynamic V2 external widget did not load: modules="
              + dynamicV2Group.moduleCount + ", content="
              + dynamicV2Group.contentItem + ", slots="
              + dynamicV2Slots.length)
            return
          }
          if (!dynamicV1Group.dynamicShadowLoaded) {
            if (attempts < 50) return
            stop()
            test.fail("dynamic V1 shadow did not load before lifecycle toggle")
            return
          }
          if (dynamicV2Group.dynamicShadowLoaded) {
            stop()
            test.fail("dynamic V2 group loaded a V1 pill shadow")
            return
          }
          noSplitBar.testShadowEnabled = false
          shadowPhase = 1
          attempts = 0
          return
        }
        if (shadowPhase === 1) {
          if (dynamicV1Group.dynamicShadowLoaded) {
            if (attempts < 50) return
            stop()
            test.fail("dynamic V1 shadow did not unload when disabled")
            return
          }
          noSplitBar.testShadowEnabled = true
          shadowPhase = 2
          attempts = 0
          return
        }
        if (shadowPhase === 2) {
          if (!dynamicV1Group.dynamicShadowLoaded) {
            if (attempts < 50) return
            stop()
            test.fail("dynamic V1 shadow did not reload when re-enabled")
            return
          }
          if (dynamicV2Group.dynamicShadowLoaded) {
            stop()
            test.fail("dynamic V2 group loaded a V1 pill shadow after toggle")
            return
          }
          shadowPhase = 3
          attempts = 0
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
            || !v2LeftWithSplit.persistentSeparators
            || leftWithoutSplit.enabledSeparatorHitTargetCount !== 6
            || v2LeftWithSplit.enabledSeparatorHitTargetCount !== 6) {
          test.fail("separator visibility must stay transient in Shibumi"
            + " and persist in V2 shell styles")
          return
        }
        const separatorBeforeFill = v2LeftWithSplit.separatorGeometry.find(
          function(entry) { return entry.groupId === "G1" })
        fakeStateService.config = ({
          widgets: ({
            G1: { color: "color01" },
            "G:hancore.shibumi.temperature": {
              color: "color01",
              colorMode: "border",
              surfaceOpacity: 0.4
            }
          })
        })
        const separatorAfterFill = v2LeftWithSplit.separatorGeometry.find(
          function(entry) { return entry.groupId === "G1" })
        if (!separatorBeforeFill || !separatorAfterFill
            || leftWithoutSplit.separatorHitTargetCount !== 6
            || v2LeftWithSplit.separatorHitTargetCount !== 6
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
            + JSON.stringify(separatorAfterFill) + ", hitTargets="
            + leftWithoutSplit.separatorHitTargetCount + "/"
            + v2LeftWithSplit.separatorHitTargetCount + ", surface="
            + v2FillGroup.visualSurfaceItem.height + ", group="
            + v2FillGroup.implicitHeight)
          return
        }
        if (!leftWithoutSplit.toggleSeparator("G1", 0)
            || noSplitController.toggleCount !== 1
            || noSplitController.lastToggleRegion !== "left"
            || noSplitController.lastToggleIndex !== 0
            || leftWithSplit.toggleSeparator("G1", 0)
            || !v2LeftWithSplit.toggleSeparator("G1", 0)
            || v2SplitBar.separatorToggles !== 1
            || v2SplitBar.lastSeparatorGroup !== "G1") {
          test.fail("live V1 splits and persistent V2 separators diverged")
          return
        }
        noSplitController.activeLayoutProtected = true
        v2SplitController.activeLayoutProtected = true
        if (leftWithoutSplit.separatorChangesAllowed
            || v2LeftWithSplit.separatorChangesAllowed
            || leftWithoutSplit.enabledSeparatorHitTargetCount !== 6
            || v2LeftWithSplit.enabledSeparatorHitTargetCount !== 6
            || leftWithoutSplit.toggleSeparator("G1", 0)
            || v2LeftWithSplit.toggleSeparator("G1", 0)
            || noSplitController.toggleCount !== 1
            || v2SplitBar.separatorToggles !== 1) {
          test.fail("protected layouts accepted direct separator changes")
          return
        }
        editingSession.editing = true
        if (!leftWithoutSplit.separatorChangesAllowed
            || !v2LeftWithSplit.separatorChangesAllowed
            || !leftWithoutSplit.toggleSeparator("G1", 0)
            || !v2LeftWithSplit.toggleSeparator("G1", 0)
            || noSplitController.toggleCount !== 2
            || v2SplitBar.separatorToggles !== 2) {
          test.fail("edit mode did not override V1/V2 layout protection")
          return
        }
        editingSession.editing = false

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
        const directSlots = test.widgetSlots(directGroup.contentItem, [])
        if (!test.closeEnough(directGroup.implicitHeight, 28)
            || directSlots.length !== 1
            || !test.closeEnough(directSlots[0].height, 28)
            || !test.closeEnough(directSlots[0].activeItem.height, 28)) {
          test.fail("V1 widgets did not inherit the original 28px host: group="
            + directGroup.implicitHeight + ", slot="
            + (directSlots[0] ? directSlots[0].height : -1) + ", item="
            + (directSlots[0] && directSlots[0].activeItem
              ? directSlots[0].activeItem.height : -1))
          return
        }
        const placedDynamicLocation = budgetBar.layoutController.groupLocation(
          "G:omarchy.active-window")
        if (!placedDynamicLocation || placedDynamicLocation.region !== "right"
            || placedDynamicLocation.index !== 7
            || !dynamicV1Group.dynamicV1Group
            || dynamicV1Group.dynamicV1CustomFill
            || !dynamicV1Group.visualSurfaceItem.visible
            || !test.closeEnough(dynamicV1Group.visualSurfaceItem.height, 24)
            || !test.closeEnough(dynamicV1Group.visualSurfaceItem.radius, 12)
            || dynamicV1Group.visualSurfaceItem.border.width !== 1) {
          test.fail("dynamic V1 plugin lost the standard pill surface: height="
            + dynamicV1Group.visualSurfaceItem.height + ", radius="
            + dynamicV1Group.visualSurfaceItem.radius + ", border="
            + dynamicV1Group.visualSurfaceItem.border.width)
          return
        }
        if (directGroup.dynamicShadowLoaded !== false
            || dynamicV1Group.dynamicShadowLoaded !== true
            || dynamicSuiteV1FillGroup.dynamicShadowLoaded !== false
            || dynamicSuiteV1InheritedGroup.dynamicShadowLoaded !== false
            || v2FillGroup.dynamicShadowLoaded !== false
            || dynamicV2Group.dynamicShadowLoaded !== false) {
          test.fail("dynamic V1 shadow lifecycle is not load-gated: fixed="
            + directGroup.dynamicShadowLoaded + ", external="
            + dynamicV1Group.dynamicShadowLoaded + ", suiteFill="
            + dynamicSuiteV1FillGroup.dynamicShadowLoaded
            + ", suiteInherited="
            + dynamicSuiteV1InheritedGroup.dynamicShadowLoaded + ", v2="
            + v2FillGroup.dynamicShadowLoaded + ", dynamicV2="
            + dynamicV2Group.dynamicShadowLoaded)
          return
        }
        const dynamicFillSlots = test.widgetSlots(
          dynamicSuiteV1FillGroup.contentItem, [])
        const dynamicInheritedSlots = test.widgetSlots(
          dynamicSuiteV1InheritedGroup.contentItem, [])
        if (!dynamicSuiteV1FillGroup.dynamicV1Group
            || !dynamicSuiteV1FillGroup.dynamicV1WidgetOwnsSurface
            || !dynamicSuiteV1FillGroup.dynamicV1CustomFill
            || dynamicSuiteV1FillGroup.visualSurfaceItem.visible
            || dynamicFillSlots.length !== 1
            || !dynamicFillSlots[0].activeItem
            || dynamicFillSlots[0].activeItem.nativeSurfaceCount !== 1
            || !dynamicSuiteV1InheritedGroup.dynamicV1Group
            || !dynamicSuiteV1InheritedGroup.dynamicV1WidgetOwnsSurface
            || dynamicSuiteV1InheritedGroup.dynamicV1CustomFill
            || dynamicSuiteV1InheritedGroup.visualSurfaceItem.visible
            || dynamicInheritedSlots.length !== 1
            || !dynamicInheritedSlots[0].activeItem
            || dynamicInheritedSlots[0].activeItem.nativeSurfaceCount !== 1) {
          test.fail("suite-native dynamic V1 surface ownership drifted: custom="
            + JSON.stringify({
              owns: dynamicSuiteV1FillGroup.dynamicV1WidgetOwnsSurface,
              fill: dynamicSuiteV1FillGroup.dynamicV1CustomFill,
              wrapper: dynamicSuiteV1FillGroup.visualSurfaceItem.visible,
              slots: dynamicFillSlots.length,
              native: dynamicFillSlots[0] && dynamicFillSlots[0].activeItem
                ? dynamicFillSlots[0].activeItem.nativeSurfaceCount : -1
            }) + ", inherited=" + JSON.stringify({
              owns: dynamicSuiteV1InheritedGroup.dynamicV1WidgetOwnsSurface,
              fill: dynamicSuiteV1InheritedGroup.dynamicV1CustomFill,
              wrapper: dynamicSuiteV1InheritedGroup.visualSurfaceItem.visible,
              slots: dynamicInheritedSlots.length,
              native: dynamicInheritedSlots[0]
                  && dynamicInheritedSlots[0].activeItem
                ? dynamicInheritedSlots[0].activeItem.nativeSurfaceCount : -1
            }))
          return
        }
        if (!test.closeEnough(delayedGroup.implicitWidth, 42)
            || !test.closeEnough(delayedGroup.implicitHeight, 28)) {
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
        const expectedNotchModes = ["auto", "none", "compact", "roomy"]
        if (notchBorderModes.count !== expectedNotchModes.length) {
          test.fail("Notch border matrix did not instantiate every spacing mode")
          return
        }
        for (let index = 0; index < expectedNotchModes.length; index++) {
          const chrome = notchBorderModes.itemAt(index)
          if (!chrome
              || chrome.modelData.mode !== expectedNotchModes[index]
              || !test.closeEnough(chrome.notchShoulderInset,
                chrome.desktopEdgeInset)
              || !test.closeEnough(chrome.wing, 14)
              || !test.closeEnough(chrome.notchBodyRadius, 9)
              || !test.closeEnough(chrome.desktopEdgeInset,
                chrome.wing + chrome.notchBodyRadius)) {
            test.fail("Notch border shoulder seam drifted for "
              + expectedNotchModes[index])
            return
          }
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

        budgetGroup.availableWidth = 20
        if (centerSlot.availableWidth !== 1 || optionalSlot.availableWidth !== 1)
          return test.fail("exhausted sibling budget became unconstrained")

        nativeOwnershipProbe.start()
      }
    }
  }
}
