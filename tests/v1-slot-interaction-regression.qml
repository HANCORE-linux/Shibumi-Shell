import QtQuick
import Quickshell
import "core" as Core
import "styles/shibumi" as ShibumiStyle

ShellRoot {
  Item {
    id: test

    width: 520
    height: 60

    property int writes: 0
    property int phase: 0
    property int attempts: 0
    property int selectedRadius: 12
    property bool smallRadiusChecked: false

    Component {
      id: markerWidget

      Item {
        property var bar: null
        property string moduleName: ""
        property var settings: ({})
        implicitWidth: 30
        implicitHeight: 20
      }
    }

    QtObject {
      id: fakeWidgetRegistry
      function componentFor(moduleName) { return moduleName ? markerWidget : null }
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

    function fail(message) {
      console.error("v1-slot-interaction-regression:", message)
      Qt.exit(1)
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
      return session.begin(sourceGroupId, source.item,
          sourceOrigin.x + source.item.width / 2,
          sourceOrigin.y + source.item.height / 2)
        && session.updateTarget(targetEntry)
        && session.drop()
    }

    Timer {
      interval: 10
      running: true
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
              || session.targets.length !== 8 || !emptyBase || !occupiedExtra) return
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
              || secondSession.targets.length !== 8) return
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
