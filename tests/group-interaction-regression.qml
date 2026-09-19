import QtQuick
import Quickshell
import Quickshell.Io
import "core" as Core
import "core/GroupRegistry.js" as GroupRegistry
import "styles/shibumi" as ShibumiStyle

ShellRoot {
  Window {
    id: test
    visible: true
    property bool frameSeen: false
    readonly property string transferId: "fixture.p10.088.widget"
    readonly property string transferScreen: "fixture-output"
    property int transferStage: -1
    readonly property bool scopedTransfer: transferStage !== -1
    property string expectedPingContainer: ""
    property string pingNextAction: ""
    property string pingOutput: ""
    property string transitionResult: ""
    property double keepDeckInstance: 0
    property int keepDeckInstances: 0
    property int keepStableAttempts: 0
    property var nativeLayout: ({
      left: [{ id: "fixture.placed", shibumiModule: true }],
      center: [], right: []
    })
    onFrameSwapped: frameSeen = true

    width: 420
    height: 60

    property int writes: 0
    property var launcherView: null
    property var launcherSlot: null
    property var order: ({
      left: ["G1", "G2", "G3", "G4", "G5", "G6", "G7", "G:fixture.placed"],
      center: ["G8"],
      right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
    })

    Component {
      id: markerWidget

      Item {
        id: marker
        property var bar: null
        property string moduleName: ""
        property string hostGroupId: ""
        property var settings: ({})
        readonly property double instanceId: Date.now()
        implicitWidth: 30
        implicitHeight: 20
        IpcHandler {
          enabled: marker.moduleName === test.transferId
          target: "fixture.p10.088.target"
          function ping(): string { return marker.instanceId + "/" + marker.hostGroupId }
        }
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
      property bool ready: true
      property bool writePending: false
      property int writeSerial: 0
      property int writeCalls: 0
      property int revision: 0
      property var pendingPatch: null
      signal persistenceSettled(int serial, string result)

      function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
      function normalizedLayoutFamilyPatch(value) {
        return value && value.v1Layout
          ? JSON.parse(JSON.stringify(value)) : null
      }
      function layoutFamilySnapshot(value) {
        return value && value.v1Layout ? { v1Layout: {
          order: JSON.parse(JSON.stringify(test.order)),
          splits: { left: [], center: [], right: [] }
        } } : null
      }
      function setLayoutFamilyTransition(patch) {
        if (writePending || !patch || !patch.v1Layout) return false
        writeCalls++
        pendingPatch = JSON.parse(JSON.stringify(patch))
        writeSerial++
        writePending = true
        statePublishTimer.restart()
        return true
      }
      function compensateLayoutFamilyTransition(_serial, _expected, _before) {
        return false
      }
    }

    Timer {
      id: statePublishTimer
      interval: 25
      onTriggered: {
        const patch = fakeStateService.pendingPatch
        fakeStateService.pendingPatch = null
        test.order = JSON.parse(JSON.stringify(patch.v1Layout.order))
        fakeStateService.writePending = false
        fakeStateService.revision++
        fakeStateService.persistenceSettled(
          fakeStateService.writeSerial, "confirmed")
      }
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
      property bool mutationBusy: false
      property bool transferClaim: false
      property var order: test.order
      readonly property var v1Slots: order

      function groupLocation(groupId) {
        if (groupId === "G:" + test.transferId && transferClaim)
          return { region: "left", index: order.left.length, groupId: groupId }
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

      function interactiveMutationAllowed(_editing) { return !mutationBusy }

      function swapGroups(source, target) {
        if (mutationBusy) return false
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
      readonly property var pluginRegistry: test.scopedTransfer
        ? ({ pluginId: "fixture" }) : null
      readonly property var barWidgetRegistry: test.scopedTransfer ? ({ widgets: ({
        [test.transferId]: { component: markerWidget,
          metadata: { pluginId: test.transferId } } }) }) : null
      readonly property var visualTokens: ({
        groupGap: 6,
        splitGap: 16,
        invalidDropDuration: 230,
        returnCleanupDuration: 240,
        pillRadius: 12,
        sumi: "#aaaaaa"
      })
      readonly property var layoutConfig: test.nativeLayout
      readonly property var barConfig: ({ layout: test.nativeLayout })
      readonly property var layoutController: fakeController
      readonly property var layoutStateController: fakeController
      readonly property bool layoutTransitionBusy: layoutTransition.busy
      readonly property var v1FamilySlotBindings: ({})
      property var moduleSlots: []
      property var activePopout: null

      function entryId(entry) { return entry && entry.id ? String(entry.id) : "" }
      function entrySettings(entry) { return entry || ({}) }
      function widgetAllowsMultiple(_id) { return false }
      function isV1AdditionalSuiteWidget(_id) { return false }
      function registeredWidgetComponent(moduleName) {
        return fakeWidgetRegistry.componentFor(moduleName)
      }
      // INJECT_BAR_PROJECTION
      // INJECT_BAR_SLOT_REGISTRY
      function showTooltip(owner, text) {}
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
      screenName: test.transferScreen
      layoutSession: session
    }

    Core.BarSection {
      id: transferDeck
      bar: fakeBar
      region: "left-extra"
      screenName: test.transferScreen
      entries: fakeBar.unassignedLayoutEntries("left", test.transferScreen)
    }

    QtObject {
      id: failingState
      property bool ready: true
      property bool writePending: false
      property int writeSerial: 0
      property int writeCalls: 0
      readonly property int revision: 0
      signal persistenceSettled(int serial, string result)
      function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
      function normalizedLayoutFamilyPatch(value) { return value }
      function layoutFamilySnapshot(value) {
        return value && value.v1Layout ? { v1Layout: {
          order: JSON.parse(JSON.stringify(test.order)), splits: {
            left: [], center: [], right: [] } } } : null
      }
      function setLayoutFamilyTransition(_patch) { writeCalls++; return false }
      function compensateLayoutFamilyTransition(_serial, _expected, _before) {
        return false
      }
    }

    QtObject {
      id: fakeNativeWriter
      property var pendingLayout: null
      function mutateShellConfig(mutator) {
        const config = { bar: { layout: JSON.parse(JSON.stringify(test.nativeLayout)) } }
        mutator(config)
        pendingLayout = JSON.parse(JSON.stringify(config.bar.layout))
        nativePublishTimer.restart()
        return true
      }
    }

    Timer {
      id: nativePublishTimer
      interval: 40
      onTriggered: {
        test.nativeLayout = fakeNativeWriter.pendingLayout
        fakeNativeWriter.pendingLayout = null
      }
    }

    Core.LayoutTransition {
      id: layoutTransition
      stateService: fakeStateService
      nativeWriter: fakeNativeWriter
      observedBarConfig: fakeBar.barConfig
      planNativeLayout: test.planNativeLayout
      admitted: true
      onSettled: function(_serial, result) { test.transitionResult = result }
    }

    Core.LayoutTransition {
      id: failedTransition
      stateService: failingState
      nativeWriter: fakeNativeWriter
      observedBarConfig: fakeBar.barConfig
      planNativeLayout: test.planNativeLayout
      admitted: true
      onSettled: function(_serial, result) { test.transitionResult = result }
    }

    Process {
      id: pingProcess
      command: ["/usr/bin/quickshell", "ipc", "--pid",
        String(Quickshell.processId), "call", "--",
        "fixture.p10.088.target", "ping"]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: test.pingOutput = String(text || "").trim()
      }
      onExited: function(code) {
        Qt.callLater(function() { test.finishPing(code) })
      }
    }

    Timer {
      id: transferTimer
      property int transferAttempts: 0
      interval: 10
      repeat: true
      onTriggered: {
        transferAttempts++
        test.advanceTransfer()
      }
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

    function transferSlot(region) {
      return fakeBar.moduleSlots.find(slot => slot
        && slot.moduleName === transferId && slot.region === region
        && slot.screenName === transferScreen) || null
    }

    function transferGroupPresent() {
      return order.left.indexOf("G:" + transferId) >= 0
    }

    function transferNativePresent() {
      return nativeLayout.left.some(entry => fakeBar.entryId(entry) === transferId)
    }

    function setTransferNativePresent(present) {
      const next = JSON.parse(JSON.stringify(nativeLayout))
      next.left = next.left.filter(entry => fakeBar.entryId(entry) !== transferId)
      if (present) next.left.push({ id: transferId })
      nativeLayout = next
    }

    function withoutTransferGroup() {
      const next = JSON.parse(JSON.stringify(order))
      next.left = next.left.filter(id => id !== "G:" + transferId)
      return next
    }

    function catalogIntent(keepConfigured) {
      return { kind: "catalog-layout", id: transferId, installed: false,
        region: "left", removeIds: [transferId],
        keepConfigured: keepConfigured === true, providerGroups: [] }
    }

    function planNativeLayout(layoutValue, intent) {
      const next = JSON.parse(JSON.stringify(layoutValue))
      for (const region of ["left", "center", "right"])
        next[region] = next[region].filter(entry =>
          intent.removeIds.indexOf(fakeBar.entryId(entry)) < 0)
      if (intent.installed === true)
        next[intent.region].push({ id: intent.id, shibumiModule: true })
      else if (intent.keepConfigured === true)
        next[intent.region].push({ id: intent.id })
      return next
    }

    function requestTransfer(keepConfigured) {
      transitionResult = ""
      return layoutTransition.request({ v1Layout: {
        order: withoutTransferGroup(),
        splits: { left: [], center: [], right: [] }
      } }, catalogIntent(keepConfigured))
    }

    function startPing(container, action) {
      transferTimer.stop()
      expectedPingContainer = container
      pingNextAction = action
      pingOutput = ""
      pingProcess.running = true
    }

    function finishPing(code) {
      if (code !== 0 || !pingOutput.endsWith("/" + expectedPingContainer))
        return fail("private exact-PID ping failed for " + expectedPingContainer
          + ": code=" + code + " output=" + pingOutput)
      if (pingNextAction === "remove-group") {
        transferStage = 1
        if (!requestTransfer(false))
          return fail("real native-removal transition was refused")
      } else if (pingNextAction === "add-group") {
        fakeController.transferClaim = true
        transferStage = 4
      } else if (pingNextAction === "state-failure") {
        console.log("group transfer B passed")
        transitionResult = ""
        const accepted = failedTransition.request({ v1Layout: {
          order: withoutTransferGroup(),
          splits: { left: [], center: [], right: [] }
        } }, catalogIntent(false))
        if (accepted || failingState.writeCalls !== 1
            || transitionResult !== "state-refused" || !transferGroupPresent()
            || transferSlot("left-extra"))
          return fail("failed State write did not retain the group")
        console.log("failed State write retained grouped widget")
        startPing("G:" + transferId, "keep-configured")
        return
      } else if (pingNextAction === "keep-configured") {
        keepDeckInstance = 0
        keepDeckInstances = 0
        keepStableAttempts = 0
        transferStage = 5
        if (!requestTransfer(true))
          return fail("keepConfigured transition was refused")
      } else {
        if (keepDeckInstances !== 1 || layoutTransition.busy
            || transferGroupPresent() || !transferNativePresent())
          return fail("keepConfigured deck did not settle exactly once")
        console.log("keepConfigured deck appeared once after finish")
        console.log("group interaction regression passed")
        Qt.exit(0)
        return
      }
      transferTimer.transferAttempts = 0
      transferTimer.start()
    }

    function advanceTransfer() {
      const groupSlot = transferSlot("G:" + transferId)
      const deckSlot = transferSlot("left-extra")
      if (transferStage === -2 && transferTimer.transferAttempts >= 2) {
        setTransferNativePresent(true)
        transferStage = 0
      } else if (transferStage === 0 && groupSlot && groupSlot.loadedItem && !deckSlot) {
        startPing("G:" + transferId, "remove-group")
      } else if (transferStage === 1 && !layoutTransition.busy
          && transitionResult === "confirmed" && !transferGroupPresent()
          && !transferNativePresent() && !groupSlot && !deckSlot) {
        console.log("group transfer A passed")
        transferStage = 2
      } else if (transferStage === 2 && !groupSlot && !deckSlot) {
        setTransferNativePresent(true)
        transferStage = 3
      } else if (transferStage === 3 && deckSlot && deckSlot.loadedItem && !groupSlot) {
        startPing("left-extra", "add-group")
      } else if (transferStage === 4 && !groupSlot && !deckSlot) {
        const nextOrder = JSON.parse(JSON.stringify(fakeController.order))
        nextOrder.left.push("G:" + transferId)
        order = nextOrder
        fakeController.transferClaim = false
      } else if (transferStage === 4 && groupSlot && groupSlot.loadedItem && !deckSlot) {
        startPing("G:" + transferId, "state-failure")
      } else if (transferStage === 5 && !layoutTransition.busy
          && transitionResult === "confirmed" && !groupSlot
          && deckSlot && deckSlot.loadedItem) {
        const instance = Number(deckSlot.loadedItem.instanceId)
        if (keepDeckInstance !== instance) {
          keepDeckInstance = instance
          keepDeckInstances++
        }
        if (keepDeckInstances !== 1)
          return fail("keepConfigured created more than one deck instance")
        keepStableAttempts++
        if (keepStableAttempts >= 3) {
          startPing("left-extra", "done")
        }
      } else if (transferTimer.transferAttempts > 150) {
        fail("group transfer timed out at stage " + transferStage
          + " busy=" + layoutTransition.busy + " result=" + transitionResult
          + " order=" + JSON.stringify(fakeController.order) + " slots=" + fakeBar.moduleSlots.map(
            slot => slot.moduleName + "/" + slot.region).join(","))
      }
    }

    function startTransfer() {
      transferTimer.transferAttempts = 0
      transferStage = -2
      const nextOrder = JSON.parse(JSON.stringify(fakeController.order))
      nextOrder.left.push("G:" + transferId)
      order = nextOrder
      fakeController.order = Qt.binding(function() { return test.order })
      transferTimer.start()
    }

    function fail(message) {
      console.error("group-interaction-regression:", message)
      Qt.exit(1)
      throw new Error(message)
    }

    function verifyAfterSwap() {
      const ids = session.targets.map(entry => entry.groupId)
      const seen = ({})
      for (const id of ids) seen[id] = true
      const first = session.targets.find(
        entry => entry.groupId === "G:fixture.placed")
      const second = session.targets.find(entry => entry.groupId === "G2")
      if (ids.length !== 8 || Object.keys(seen).length !== 8 || !first || !second) {
        fail("target registry became stale after model mutation")
        return
      }
      const firstOrigin = first.item.mapToItem(null, 0, 0)
      const secondOrigin = second.item.mapToItem(null, 0, 0)
      if (firstOrigin.x >= secondOrigin.x) {
        fail("target ids no longer match the rendered order: ids="
          + ids.join(",") + " plugin=" + firstOrigin.x
          + " G2=" + secondOrigin.x
          + " geometry=" + JSON.stringify(section.groupGeometry))
        return
      }

      session.setEditing(false)
      if (session.active || session.editing || session.sourceItem !== null) {
        fail("edit cleanup retained transient state")
        return
      }

      Qt.callLater(startTransfer)
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
      if (session.targets.length !== 8) {
        fail("restored group did not re-register its drag target")
        return
      }
      const source = session.targets.find(
        entry => entry.groupId === "G:fixture.placed")
      const target = session.targets.find(entry => entry.groupId === "G2")
      if (!source || !target) {
        fail("expected placed plugin/G2 targets")
        return
      }

      const sourceOrigin = source.item.mapToItem(null, 0, 0)
      const targetOrigin = target.item.mapToItem(null, 0, 0)
      if (!session.setEditing(true)
          || !session.begin("G:fixture.placed", source.item,
            sourceOrigin.x + source.item.width / 2,
            sourceOrigin.y + source.item.height / 2)) {
        fail("drag did not begin")
        return
      }
      fakeController.mutationBusy = true
      if (!session.active || !session.editing
          || fakeController.interactiveMutationAllowed(true)) {
        fail("pending slot mutation did not protect the running edit drag")
        return
      }
      fakeController.mutationBusy = false
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
          || fakeController.order.left[1] !== "G:fixture.placed"
          || fakeController.order.left[7] !== "G2") {
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
        if (phase === 1 && session.targets.length === 7
            && !session.targets.some(entry => entry.groupId === "G1")) {
          test.launcherView.visible = true
          phase = 2
          attempts = 0
          return
        }
        if (phase === 2 && session.targets.length === 8) {
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
      running: test.frameSeen
      repeat: true

      onTriggered: {
        attempts++
        if (session.targets.length !== 8 || section.width <= 0) {
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
