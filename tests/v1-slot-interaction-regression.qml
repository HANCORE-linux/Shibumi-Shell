import QtQuick
import Quickshell
import "core" as Core
import "styles/shibumi" as ShibumiStyle

ShellRoot {
  Window {
    id: test
    visible: true
    property bool frameSeen: false
    onFrameSwapped: frameSeen = true

    width: 520
    height: 60

    property int writes: 0
    property int phase: 0
    property int attempts: 0
    property int selectedRadius: 12
    property bool smallRadiusChecked: false
    property var originalClockTarget: null
    property var fallbackClockTarget: null
    property string centerLayoutSnapshot: ""
    property bool wideSibling: false
    property bool missingClock: false

    Component {
      id: markerWidget

      Item {
        property var bar: null
        property string moduleName: ""
        property var settings: ({})
        property real availableWidth: 0
        readonly property real naturalWidth: test.wideSibling
          && moduleName === "hancore.shibumi.ai" ? 300 : 30
        implicitWidth: availableWidth > 0
          && (moduleName === "hancore.shibumi.center" || naturalWidth === 300)
            ? Math.min(naturalWidth, availableWidth) : naturalWidth
        implicitHeight: 20
      }
    }

    QtObject {
      id: fakeWidgetRegistry
      function componentFor(moduleName) {
        return moduleName && !(test.missingClock && moduleName === "hancore.shibumi.center")
          ? markerWidget : null
      }
    }

    QtObject {
      id: fakeStateService

      property var config: ({
        presentation: ({ shellStyle: "shibumi" }),
        widgets: ({}),
        order: ({
          left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
          center: ["G8"],
          right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
        }),
        v1SlotRoles: ({
          left: ["base", "base", "base", "base", "base", "base", "base"],
          center: ["base"],
          right: ["base", "base", "base", "base", "base", "base", "base"]
        }),
        splits: ({
          left: [false, false, false, false, false, false],
          center: [],
          boundaries: [false, false],
          right: [false, false, false, false, false, false]
        })
      })
      readonly property color selectedColor: "#88aaff"

      function rolesFor(order) {
        const roles = ({ left: [], center: [], right: [] })
        for (const region of ["left", "center", "right"]) {
          const base = region === "center" ? 1 : 7
          for (let i = 0; i < order[region].length; i++)
            roles[region].push(i < base ? "base" : "extra")
        }
        return roles
      }

      function setLayout(order, splits) {
        config = ({
          presentation: config.presentation,
          widgets: config.widgets,
          order: order,
          v1SlotRoles: rolesFor(order),
          splits: splits
        })
        test.writes++
        return true
      }

      function setGroupEnabled(groupId, enabled) {
        const widgets = JSON.parse(JSON.stringify(config.widgets || ({})))
        widgets[groupId] = ({ enabled: enabled })
        config = ({
          presentation: config.presentation,
          widgets: widgets,
          order: config.order,
          v1SlotRoles: config.v1SlotRoles,
          splits: config.splits
        })
      }
    }

    QtObject {
      id: fakeShell
      function serviceFor(pluginId) {
        return pluginId === "hancore.shibumi.state" ? fakeStateService : null
      }
    }

    Core.LayoutController {
      id: controller
      stateService: fakeStateService
    }

    QtObject {
      id: fakeBar

      readonly property bool vertical: false
      readonly property int barSize: 26
      readonly property string fontFamily: "monospace"
      readonly property color foreground: "#eeeeee"
      readonly property color background: "#181818"
      readonly property color urgent: "#88aaff"
      readonly property var shell: fakeShell
      readonly property var visualTokens: ({
        groupGap: 6,
        splitGap: 16,
        invalidDropDuration: 230,
        returnCleanupDuration: 240,
        slotHeight: 28,
        pillHeight: 24,
        tileRadius: Math.max(1, test.selectedRadius - 2),
        pillRadius: test.selectedRadius,
        sumi: "#aaaaaa"
      })
      readonly property var layoutConfig: ({
        left: [{ id: "custom.widget", shibumiModule: true }],
        center: [],
        right: []
      })
      readonly property var layoutController: controller
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
    }

    Core.DragSession {
      id: session
      layoutController: controller
      screenName: "DP-1"
    }

    Core.DragSession {
      id: secondSession
      layoutController: controller
      screenName: "HDMI-A-1"
    }

    ShibumiStyle.GroupSection {
      id: section
      bar: fakeBar
      region: "left"
      layoutSession: session
    }

    ShibumiStyle.GroupSection {
      id: secondSection
      y: 32
      bar: fakeBar
      region: "left"
      layoutSession: secondSession
    }

    Loader {
      id: centerLoader
      x: 320
      active: test.phase >= 14
      sourceComponent: ShibumiStyle.GroupSection {
        bar: fakeBar
        region: "center"
        availableWidth: 160
        layoutSession: session
      }
    }
    Loader {
      id: secondCenterLoader
      x: 320
      y: 32
      active: test.phase >= 14
      sourceComponent: ShibumiStyle.GroupSection {
        bar: fakeBar
        region: "center"
        availableWidth: 230
        layoutSession: secondSession
      }
    }

    function fail(message) {
      console.error("v1-slot-interaction-regression:", message)
      Qt.exit(1)
      throw new Error(message)
    }

    function target(groupId, index) {
      return session.targets.find(entry => entry.groupId === groupId
        && (index === undefined || entry.index === index))
    }

    function dragTo(sourceGroupId, targetEntry) {
      const source = target(sourceGroupId)
      if (!source || !targetEntry || !source.item || !targetEntry.item)
        return false
      const sourceOrigin = source.item.mapToItem(null, 0, 0)
      const destination = targetEntry.item.mapToItem(null, 0, 0)
      return session.begin(sourceGroupId, source.item,
          sourceOrigin.x + source.item.width / 2,
          sourceOrigin.y + source.item.height / 2)
        && session.move(destination.x + targetEntry.item.width / 2,
          destination.y + targetEntry.item.height / 2)
        && session.drop()
    }

    Timer {
      interval: 10
      running: test.frameSeen
      repeat: true

      onTriggered: {
        test.attempts++
        if (test.attempts > 100) {
          stop()
          test.fail("phase " + test.phase + " timed out; targets="
            + session.targets.map(entry => entry.groupId + "@" + entry.index).join(","))
          return
        }

        if (test.phase === 0) {
          if (session.targets.length !== 7 || section.width <= 0) return
          if (!session.setEditing(true))
            return test.fail("could not enter V1 slot editing")
          test.phase = 1
          test.attempts = 0
          return
        }

        if (test.phase === 1) {
          if (session.targets.length !== 7
              || session.targets.some(entry => entry.region !== "left"
                || !Number.isInteger(entry.index))) return
          if (!controller.addV1Slot("left"))
            return test.fail("could not add an extra V1 slot")
          test.phase = 2
          test.attempts = 0
          return
        }

        if (test.phase === 2) {
          const emptyExtra = test.target("", 7)
          const firstGroup = test.target("G1", 0)
          if (controller.v1Slots.left.length !== 8
              || session.targets.length !== 8 || !emptyExtra || !firstGroup) return
          if (!test.smallRadiusChecked) {
            if (emptyExtra.item.radius !== 12)
              return test.fail("V1 extra slot did not use Radius 12")
            test.selectedRadius = 6
            test.smallRadiusChecked = true
            return
          }
          if (emptyExtra.item.radius !== 6) return
          test.selectedRadius = 12
          const emptyOrigin = emptyExtra.item.mapToItem(null, 0, 0)
          const groupOrigin = firstGroup.item.mapToItem(null, 0, 0)
          const emptyCenterY = emptyOrigin.y + emptyExtra.item.height / 2
          const groupCenterY = groupOrigin.y + firstGroup.item.height / 2
          if (emptyExtra.region !== "left" || emptyExtra.item.width !== 24
              || Math.abs(emptyCenterY - groupCenterY) > 0.5
              || !test.dragTo("G1", emptyExtra))
            return test.fail("V1 groups and empty slots were not centered drop targets")
          test.phase = 3
          test.attempts = 0
          return
        }

        if (test.phase === 3) {
          const emptyBase = test.target("", 0)
          const occupiedExtra = test.target("G1", 7)
          if (controller.v1Slots.left[0] !== ""
              || controller.v1Slots.left[7] !== "G1"
              || session.targets.length !== 8 || !emptyBase || !occupiedExtra
              || !("availableWidth" in occupiedExtra.item)
              || !occupiedExtra.item.visible || occupiedExtra.item.width <= 0) return
          if (controller.removeV1SlotAt("left", 0)
              || controller.removeV1SlotAt("left", 7))
            return test.fail("base or occupied extra slot was removable")
          if (!test.dragTo("G1", emptyBase))
            return test.fail("base placeholder did not accept its returning group")
          test.phase = 4
          test.attempts = 0
          return
        }

        if (test.phase === 4) {
          if (controller.v1Slots.left[0] !== "G1"
              || controller.v1Slots.left[7] !== ""
              || session.targets.length !== 8) return
          if (!controller.removeV1SlotAt("left", 7))
            return test.fail("empty extra slot could not be removed")
          test.phase = 5
          test.attempts = 0
          return
        }

        if (test.phase === 5) {
          if (controller.v1Slots.left.length !== 7
              || session.targets.length !== 7) return
          if (!controller.addV1Slot("left") || !controller.addV1Slot("left")
              || controller.addV1Slot("left"))
            return test.fail("V1 extra-slot capacity was not enforced")
          test.phase = 6
          test.attempts = 0
          return
        }

        if (test.phase === 6) {
          if (controller.v1Slots.left.length !== 9
              || session.targets.length !== 9 || section.canAddSlot) return
          fakeStateService.setGroupEnabled("G2", false)
          test.phase = 7
          test.attempts = 0
          return
        }

        if (test.phase === 7) {
          const proxy = test.target("G2", 1)
          if (!proxy || session.targets.length !== 9
              || proxy.item.width !== 24) return
          session.setEditing(false)
          test.phase = 8
          test.attempts = 0
          return
        }

        if (test.phase === 8) {
          if (session.targets.length !== 6) return
          if (!session.setEditing(true))
            return test.fail("could not restore slot editing")
          fakeStateService.setGroupEnabled("G2", true)
          test.phase = 9
          test.attempts = 0
          return
        }

        if (test.phase === 9) {
          if (session.targets.length !== 9) return
          if (!controller.removeV1SlotAt("left", 8)
              || !controller.removeV1SlotAt("left", 7))
            return test.fail("extra-slot cleanup failed")
          test.phase = 10
          test.attempts = 0
          return
        }

        if (test.phase === 10) {
          if (controller.v1Slots.left.length !== 7
              || session.targets.length !== 7 || test.writes !== 8) return
          if (!controller.reconcileV1PluginGroups([
                { pluginId: "custom.widget", region: "left" }
              ]) || !secondSession.setEditing(true))
            return test.fail("dynamic V1 plugin group could not be created")
          test.phase = 11
          test.attempts = 0
          return
        }

        if (test.phase === 11) {
          const dynamic = test.target("G:custom.widget", 7)
          if (!dynamic || session.targets.length !== 8
              || secondSession.targets.length !== 8
              || !("availableWidth" in dynamic.item)
              || !dynamic.item.visible || dynamic.item.width <= 0) return
          if (!test.dragTo("G:custom.widget", test.target("G1", 0)))
            return test.fail("dynamic V1 group did not share drag/drop")
          test.phase = 12
          test.attempts = 0
          return
        }

        if (test.phase === 12) {
          const shared = secondSession.targets.find(
            entry => entry.groupId === "G:custom.widget" && entry.index === 0)
          if (!shared || controller.v1Slots.left[0] !== "G:custom.widget") return
          if (!controller.reconcileV1PluginGroups([]))
            return test.fail("dynamic V1 plugin group could not be removed")
          test.phase = 13
          test.attempts = 0
          return
        }

        if (test.phase === 13) {
          if (controller.v1Slots.left.length !== 7
              || controller.v1Slots.left[0] !== "G1"
              || session.targets.length !== 7
              || secondSession.targets.length !== 7
              || test.writes !== 11) return
          test.phase = 14
          test.attempts = 0
          return
        }

        if (test.phase === 14) {
          const clock = test.target("G8", 0)
          if (!clock || !("availableWidth" in clock.item)
              || session.targets.length !== 8 || !centerLoader.item) return
          test.originalClockTarget = clock.item
          fakeStateService.setGroupEnabled("G7", false)
          if (!centerLoader.item.canAddSlot || !controller.addV1Slot("center")
              || controller.addV1Slot("center"))
            return test.fail("center plus/capacity contract")
          test.phase = 15
          test.attempts = 0
          return
        }
        if (test.phase === 15) {
          const extra = session.targets.find(entry => entry.region === "center" && entry.index === 1)
          if (!extra || session.targets.length !== 9 || secondSession.targets.length !== 9) return
          if (centerLoader.item.canAddSlot || extra.item.width !== 24
              || test.target("G8", 0).item !== test.originalClockTarget
              || controller.removeV1SlotAt("center", 0)
              || !test.dragTo("G7", extra))
            return test.fail("center addition replaced G8 owner or broke drop target")
          test.phase = 16
          test.attempts = 0
          return
        }
        if (test.phase === 16) {
          const moved = test.target("G7", 1)
          const clock = test.target("G8", 0)
          if (!moved || moved.region !== "center" || !clock || controller.v1Slots.left[6] !== "") return
          if (fakeStateService.config.widgets.G7.enabled === false) {
            if (moved.item.width !== 24 || centerLoader.item.separatorHitTargetCount !== 0)
              return test.fail("disabled G7 did not remain an editing proxy")
            fakeStateService.setGroupEnabled("G7", true)
            return
          }
          if (!controller.splitEnabled("center", 0)) {
            if (centerLoader.item.separatorHitTargetCount !== 1
                || !controller.toggleSplit("center", 0, true))
              return test.fail("center marker did not toggle its positional split")
            return
          }
          centerLoader.item.contentItem.forceLayout()
          const geometry = centerLoader.item.groupGeometry, marker = centerLoader.item.separatorGeometry[0]
          if (geometry.length !== 2 || !marker || marker.index !== 0
              || geometry[1].left - geometry[0].right !== 22
              || marker.markerCenter <= geometry[0].right || marker.markerCenter >= geometry[1].left)
            return test.fail("center split geometry or drag-marker relation changed")
          test.centerLayoutSnapshot = JSON.stringify(fakeStateService.config)
          centerLoader.item.availableWidth = 55
          test.phase = 17
          test.attempts = 0
          return
        }
        if (test.phase === 17) {
          const clock = test.target("G8", 0)
          if (!clock || clock.item.availableWidth !== 3 || centerLoader.item.width > 55) return
          const otherClock = secondSession.targets.find(entry => entry.groupId === "G8")
          if (!otherClock || otherClock.item.availableWidth !== 178
              || JSON.stringify(fakeStateService.config) !== test.centerLayoutSnapshot)
            return test.fail("output-local center budget changed another output or stored layout")
          // The preceding reorder may rebuild delegates; pin the current
          // G8 slot, not the owner saved before that drag.
          test.fallbackClockTarget = clock.item
          test.wideSibling = true
          fakeStateService.setGroupEnabled("G8", false)
          session.setEditing(false)
          secondSession.setEditing(false)
          test.centerLayoutSnapshot = JSON.stringify(fakeStateService.config)
          test.phase = 20
          test.attempts = 0
          return
        }
        if (test.phase === 20 || test.phase === 21 || test.phase === 22) {
          if (test.attempts < 8) return
          const sibling = session.targets.find(entry => entry.groupId === "G7")
          const otherSibling = secondSession.targets.find(entry => entry.groupId === "G7")
          const placeholderWidth = test.phase === 21 ? 30 : 0
          if (!sibling || !otherSibling || !("availableWidth" in sibling.item)
              || sibling.item.availableWidth !== 55 - placeholderWidth
              || otherSibling.item.availableWidth !== 230 - placeholderWidth
              || centerLoader.item.width > 55 || secondCenterLoader.item.width > 230
              || !test.fallbackClockTarget || test.fallbackClockTarget.hasLoadedWidgets
              || JSON.stringify(fakeStateService.config) !== test.centerLayoutSnapshot)
            return test.fail("disabled/unavailable G8 left the loaded center sibling unconstrained: phase="
              + test.phase + ", budget=" + (sibling ? sibling.item.availableWidth : -1))
          if (test.phase === 20) {
            session.setEditing(true)
            secondSession.setEditing(true)
            test.phase = 21
          } else if (test.phase === 21) {
            session.setEditing(false)
            secondSession.setEditing(false)
            test.missingClock = true
            fakeStateService.setGroupEnabled("G8", true)
            test.centerLayoutSnapshot = JSON.stringify(fakeStateService.config)
            test.phase = 22
          } else {
            test.missingClock = false
            fakeStateService.setGroupEnabled("G8", false)
            fakeStateService.setGroupEnabled("G8", true)
            test.wideSibling = false
            session.setEditing(true)
            secondSession.setEditing(true)
            test.centerLayoutSnapshot = JSON.stringify(fakeStateService.config)
            test.phase = 23
          }
          test.attempts = 0
          return
        }
        if (test.phase === 23) {
          const clock = test.target("G8", 0)
          if (!clock || !clock.item.hasLoadedWidgets || clock.item.availableWidth !== 3) return
          if (JSON.stringify(fakeStateService.config) !== test.centerLayoutSnapshot)
            return test.fail("center readiness recovery rewrote stored layout")
          const home = session.targets.find(entry => entry.region === "left" && entry.index === 6)
          if (!test.dragTo("G7", home)) return test.fail("center-to-outer return failed")
          test.phase = 18
          test.attempts = 0
          return
        }
        if (test.phase === 18) {
          if (controller.v1Slots.center[1] !== "" || !controller.removeV1Slot("center"))
            return test.fail("empty center slot removal failed")
          test.phase = 19
          test.attempts = 0
          return
        }
        if (test.phase === 19) {
          if (controller.v1Slots.center.length !== 1 || session.targets.length !== 8
              || secondSession.targets.length !== 8 || test.writes !== 16) return
          if (!centerLoader.item.canAddSlot || controller.splits.center.length !== 0)
            return test.fail("center cleanup changed split shape or plus availability")
          stop()
          session.setEditing(false)
          secondSession.setEditing(false)
          console.log("V1 slot interaction regression passed")
          Qt.exit(0)
        }
      }
    }
  }
}
