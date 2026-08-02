import QtQuick
import Quickshell
import "core" as Core
import "styles/shibumi" as ShibumiStyle

ShellRoot {
  Item {
    id: test

    width: 420
    height: 60

    property int writes: 0
    property var launcherView: null
    property var launcherSlot: null
    property var order: ({
      left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7"],
      center: ["G8"],
      right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
    })

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
      readonly property var config: ({ widgets: ({}) })
      readonly property color selectedColor: "#88aaff"
    }

    QtObject {
      id: fakeShell
      function serviceFor(pluginId) {
        return pluginId === "hancore.shibumi.state" ? fakeStateService : null
      }
    }

    QtObject {
      id: fakeController

      readonly property bool v2Mode: false
      property var order: test.order
      readonly property var v1Slots: order

      function groupLocation(groupId) {
        for (const region of ["left", "center", "right"]) {
          const index = order[region].indexOf(groupId)
          if (index >= 0) return { region: region, index: index, groupId: groupId }
        }
        return null
      }

      function splitEnabled(region, index) { return false }
      function baseV1SlotCount(region) {
        return region === "center" ? 1 : 7
      }
      function maxV1SlotCount(region) {
        return region === "center" ? 1 : 9
      }
      function isExtraV1Slot(region, index) {
        return region !== "center" && index >= 7
      }

      function swapGroups(source, target) {
        const sourceLocation = groupLocation(source)
        const targetLocation = groupLocation(target)
        if (!sourceLocation || !targetLocation || source === target) return false
        const next = JSON.parse(JSON.stringify(order))
        next[sourceLocation.region][sourceLocation.index] = target
        next[targetLocation.region][targetLocation.index] = source
        order = next
        test.writes++
        return true
      }

      function toggleSplit(region, index) { return false }
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
        pillRadius: 12,
        sumi: "#aaaaaa"
      })
      readonly property var layoutConfig: ({ left: [], center: [], right: [] })
      readonly property var layoutController: fakeController
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
      layoutController: fakeController
      screenName: "DP-1"
    }

    ShibumiStyle.GroupSection {
      id: section
      bar: fakeBar
      region: "left"
      layoutSession: session
    }

    Item {
      id: ghostHost
      x: 37
      y: 29
      width: 300
      height: 26

      ShibumiStyle.DragGhost {
        id: dragGhost
        bar: fakeBar
        layoutSession: session
      }
    }

    function fail(message) {
      console.error("group-interaction-regression:", message)
      Qt.exit(1)
    }

    function verifyAfterSwap() {
      const ids = session.targets.map(entry => entry.groupId)
      const seen = ({})
      for (const id of ids) seen[id] = true
      const first = session.targets.find(entry => entry.groupId === "G2")
      const second = session.targets.find(entry => entry.groupId === "G1")
      if (ids.length !== 7 || Object.keys(seen).length !== 7 || !first || !second) {
        fail("target registry became stale after model mutation")
        return
      }
      const firstOrigin = first.item.mapToItem(null, 0, 0)
      const secondOrigin = second.item.mapToItem(null, 0, 0)
      if (firstOrigin.x >= secondOrigin.x) {
        fail("target ids no longer match the rendered order: ids="
          + ids.join(",") + " G2=" + firstOrigin.x
          + " G1=" + secondOrigin.x
          + " geometry=" + JSON.stringify(section.groupGeometry))
        return
      }

      session.setEditing(false)
      if (session.active || session.editing || session.sourceItem !== null) {
        fail("edit cleanup retained transient state")
        return
      }

      console.log("group interaction regression passed")
      Qt.exit(0)
    }

    function widgetSlotFor(groupId) {
      const target = session.targets.find(entry => entry.groupId === groupId)
      return target && target.item
        ? findWidgetSlot(target.item.contentItem) : null
    }

    function findWidgetSlot(item) {
      if (!item) return null
      if (item.activeItem) return item
      const children = item.children || []
      for (const child of children) {
        const result = findWidgetSlot(child)
        if (result) return result
      }
      return null
    }

    function runSwap() {
      if (session.targets.length !== 7) {
        fail("restored group did not re-register its drag target")
        return
      }
      const source = session.targets.find(entry => entry.groupId === "G1")
      const target = session.targets.find(entry => entry.groupId === "G2")
      if (!source || !target) {
        fail("expected G1/G2 targets")
        return
      }

      const sourceOrigin = source.item.mapToItem(null, 0, 0)
      const targetOrigin = target.item.mapToItem(null, 0, 0)
      if (!session.setEditing(true)
          || !session.begin("G1", source.item,
            sourceOrigin.x + source.item.width / 2,
            sourceOrigin.y + source.item.height / 2)) {
        fail("drag did not begin")
        return
      }
      const ghostHostOrigin = ghostHost.mapToItem(null, 0, 0)
      if (Math.abs(dragGhost.x - (session.ghostX - ghostHostOrigin.x)) > 0.5
          || Math.abs(dragGhost.y - (session.ghostY - ghostHostOrigin.y)) > 0.5) {
        fail("ghost coordinates are not relative to their output surface")
        return
      }
      if (!session.move(targetOrigin.x + target.item.width / 2,
            targetOrigin.y + target.item.height / 2)
          || session.targetGroupId !== "G2"
          || !session.drop()
          || writes !== 1
          || fakeController.order.left[0] !== "G2"
          || fakeController.order.left[1] !== "G1") {
        fail("registered-target drop did not swap exactly once")
        return
      }
      Qt.callLater(verifyAfterSwap)
    }

    Timer {
      id: lifecycleTimer
      property int phase: 0
      property int attempts: 0
      interval: 10
      repeat: true

      onTriggered: {
        attempts++
        if (phase === 1 && session.targets.length === 6
            && !session.targets.some(entry => entry.groupId === "G1")) {
          test.launcherView.visible = true
          phase = 2
          attempts = 0
          return
        }
        if (phase === 2 && session.targets.length === 7) {
          stop()
          test.runSwap()
          return
        }
        if (attempts < 50) return
        stop()
        test.fail(phase === 1
          ? "zero-width group retained a drag target: targets="
            + session.targets.map(entry => entry.groupId).join(",")
            + " geometry=" + JSON.stringify(section.groupGeometry)
            + " launcherVisible=" + (test.launcherView
              ? test.launcherView.visible : "null")
            + " launcherImplicit=" + (test.launcherView
              ? test.launcherView.implicitWidth : "null")
            + " slotVisible=" + (test.launcherSlot
              ? test.launcherSlot.visible : "null")
            + " slotImplicit=" + (test.launcherSlot
              ? test.launcherSlot.implicitWidth : "null")
            + " slotWidth=" + (test.launcherSlot
              ? test.launcherSlot.width : "null")
          : "restored group did not re-register its drag target")
      }
    }

    Timer {
      property int attempts: 0
      interval: 10
      running: true
      repeat: true

      onTriggered: {
        attempts++
        if (session.targets.length !== 7 || section.width <= 0) {
          if (attempts < 50) return
          stop()
          test.fail("group targets did not register: " + session.targets.length)
          return
        }

        stop()
        test.launcherSlot = test.widgetSlotFor("G1")
        test.launcherView = test.launcherSlot
          ? test.launcherSlot.activeItem : null
        if (!test.launcherSlot || !test.launcherView) {
          test.fail("could not resolve the launcher view for lifecycle testing")
          return
        }
        test.launcherView.visible = false
        lifecycleTimer.phase = 1
        lifecycleTimer.attempts = 0
        lifecycleTimer.start()
      }
    }
  }
}
