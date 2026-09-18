import QtQuick
import "../hancore.shibumi.bar/core" as Core
import "../hancore.shibumi.bar/core/V2LayoutModel.js" as V2LayoutModel
import "../hancore.shibumi.state/ShibumiConfig.js" as ShibumiConfig

Window {
  id: root

  property bool started: false
  onFrameSwapped: {
    if (!started) {
      started = true
      Qt.callLater(run)
    }
  }
  property int writes: 0
  visible: true
  width: 320
  height: 80

  function fail(message) {
    console.error("layout-controller-regression:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  function same(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  QtObject {
    id: fakeStateService
    property var config: ShibumiConfig.defaultConfig()
    property bool writePending: false
    property bool rejectWrites: false
    property bool holdWrites: false
    property var heldConfig: null

    function setLayout(order, splits) {
      if (rejectWrites) return false
      const next = ShibumiConfig.normalize(config)
      next.order = ShibumiConfig.normalizedOrder(order)
      next.v1SlotRoles = next.order
        ? ShibumiConfig.slotRolesForOrder(next.order) : null
      next.splits = next.order
        ? ShibumiConfig.normalizedSplits(splits, next.order) : null
      if (!next.order || !next.splits || root.same(config, next)) return false
      if (holdWrites) {
        heldConfig = ShibumiConfig.normalize(next)
        writePending = true
        return true
      }
      config = ShibumiConfig.normalize(next)
      root.writes++
      return true
    }

    function settleHeld(confirm) {
      if (!heldConfig) return false
      if (confirm === true) {
        config = heldConfig
        root.writes++
      }
      heldConfig = null
      writePending = false
      return true
    }

    function resetLayout() {
      return setLayout(ShibumiConfig.defaultOrder(), ShibumiConfig.defaultSplits())
    }

    function setV2Layout(value) {
      if (rejectWrites) return false
      const normalized = ShibumiConfig.normalizedV2Layout(value)
      if (!normalized
          || root.same(config.v2Layout, normalized)) return false
      const next = ShibumiConfig.normalize(config)
      next.v2Layout = normalized
      config = ShibumiConfig.normalize(next)
      root.writes++
      return true
    }

    function resetV2Layout() {
      const next = ShibumiConfig.normalize(config)
      next.v2Layout = ShibumiConfig.defaultV2Layout()
      next.v2Boundaries = ShibumiConfig.defaultV2Boundaries()
      config = ShibumiConfig.normalize(next)
      root.writes++
      return true
    }

    function toggleV2Boundary(indexValue) {
      const index = Number(indexValue)
      if (!Number.isInteger(index) || index < 0 || index > 1) return false
      const next = ShibumiConfig.normalize(config)
      next.v2Boundaries[index] = next.v2Boundaries[index] !== true
      config = ShibumiConfig.normalize(next)
      root.writes++
      return true
    }
  }

  QtObject {
    id: fakeBar
    property bool mutationAdmissionReady: true
    property bool layoutTransitionBusy: false
    property bool layoutTransitionsSupported: false
    property bool legacyLayoutMutationAllowed: true
    property int transitionRequests: 0

    function requestV2LayoutTransition(patch) {
      transitionRequests++
      return fakeStateService.setV2Layout(patch.v2Layout)
    }
  }

  QtObject {
    id: replacementStateService
    property var config: ShibumiConfig.defaultConfig()
    property bool writePending: false
    function setLayout(_order, _splits) { return false }
    function setV2Layout(_layout) { return false }
  }

  Core.LayoutController {
    id: controller
    bar: fakeBar
    stateService: fakeStateService
  }

  Core.LayoutController {
    id: orphanController
  }

  Core.DragSession {
    id: firstScreen
    screenName: "DP-1"
    layoutController: controller
  }

  Item {
    id: firstTarget
    x: 10
    y: 10
    width: 60
    height: 30
  }

  Item {
    id: secondTarget
    x: 100
    y: 10
    width: 70
    height: 30
  }

  Core.DragSession {
    id: orphanSession
    screenName: "HDMI-A-1"
  }

  Core.DragSession {
    id: secondScreen
    screenName: "eDP-1"
    layoutController: controller
  }

  function run() {
    if (controller.groupLocation("G8").region !== "center"
        || controller.splitEnabled("left", 0)
        || controller.swapGroups("G1", "G1")
        || controller.setAllSplits(false) || controller.resetLayout()
        || orphanController.swapGroups("G1", "G15")
        || orphanSession.begin("G1")
        || root.writes !== 0)
      fail("initial/no-op controller contract")

    if (!firstScreen.registerTarget("G3", firstTarget)
        || !firstScreen.registerTarget("G4", secondTarget)
        || firstScreen.registerTarget("G99", secondTarget)
        || firstScreen.targets.length !== 2
        || (firstScreen.targetAt(20, 20) || {}).groupId !== "G3"
        || (firstScreen.targetAt(120, 20) || {}).groupId !== "G4"
        || firstScreen.targetAt(250, 20) !== null)
      fail("per-output target registry")
    if (!firstScreen.setEditing(true) || firstScreen.setEditing(true)
        || !firstScreen.begin("G3", firstTarget, 20, 20)
        || firstScreen.sourceItem !== firstTarget
        || firstScreen.ghostWidth !== firstTarget.width
        || !firstScreen.move(120, 20)
        || firstScreen.targetGroupId !== "G4"
        || secondScreen.targets.length !== 0)
      fail("geometry-based drag target discovery")
    if (!firstScreen.setEditing(false) || firstScreen.active
        || firstScreen.sourceItem !== null || firstScreen.editing)
      fail("leaving edit mode cancels transient drag state")
    if (!firstScreen.unregisterTarget(secondTarget)
        || firstScreen.unregisterTarget(secondTarget)
        || firstScreen.targets.length !== 1
        || firstScreen.targetAt(120, 20) !== null)
      fail("target unregister lifecycle")

    if (!firstScreen.begin("G3", firstTarget, 20, 20)
        || firstScreen.drop() || firstScreen.active || !firstScreen.returning
        || firstScreen.ghostX !== firstScreen.ghostHomeX
        || firstScreen.ghostY !== firstScreen.ghostHomeY
        || !firstScreen.finishReturn() || firstScreen.returning
        || firstScreen.sourceItem !== null)
      fail("invalid drop return lifecycle")

    if (!firstScreen.begin("G1", firstTarget, 20, 20)
        || !firstScreen.updateTarget({ groupId: "G15" })
        || secondScreen.active || firstScreen.screenName !== "DP-1")
      fail("first output drag state")
    if (!secondScreen.begin("G2", secondTarget, 120, 20)
        || !secondScreen.updateTarget({ groupId: "G14" })
        || !firstScreen.active || firstScreen.targetGroupId !== "G15")
      fail("per-output drag isolation")
    if (!firstScreen.drop() || firstScreen.active
        || controller.order.left[0] !== "G15"
        || controller.order.right[6] !== "G1")
      fail("first output cross-region drop")
    if (!secondScreen.drop() || secondScreen.active
        || controller.groupLocation("G2").region !== "right"
        || controller.groupLocation("G2").index !== 3
        || controller.groupLocation("G14").region !== "left"
        || controller.groupLocation("G14").index !== 1)
      fail("second output drop after shared mutation")

    if (!firstScreen.begin("G3", firstTarget, 20, 20)
        || firstScreen.updateTarget({ groupId: "G3" })
        || firstScreen.updateTarget({ groupId: "G99" }) || firstScreen.drop())
      fail("invalid drag target handling")
    firstScreen.cancel()

    let protectedState = ShibumiConfig.normalize(fakeStateService.config)
    protectedState.layoutProtection.v1 = true
    fakeStateService.config = ShibumiConfig.normalize(protectedState)
    if (!controller.activeLayoutProtected
        || controller.interactiveMutationAllowed(false)
        || !controller.interactiveMutationAllowed(true)
        || controller.toggleSplit("left", 0)
        || !controller.toggleSplit("left", 0, true)
        || !controller.toggleSplit("left", 0, true))
      fail("protected V1 split mutation bypassed edit mode")
    protectedState = ShibumiConfig.normalize(fakeStateService.config)
    protectedState.layoutProtection.v1 = false
    fakeStateService.config = ShibumiConfig.normalize(protectedState)

    if (!controller.toggleSplit("left", 0)
        || !controller.splitEnabled("left", 0)
        || controller.toggleSplit("left", 6))
      fail("persisted split mutation")
    if (!controller.setAllSplits(true)
        || !controller.splits.boundaries.every(Boolean)
        || controller.setAllSplits(true))
      fail("split-all no-op contract")
    if (!controller.resetLayout()
        || !same(controller.order, ShibumiConfig.defaultOrder())
        || !same(controller.splits, ShibumiConfig.defaultSplits())
        || controller.resetLayout())
      fail("layout reset contract")

    if (!controller.addV1Slot("left")
        || !controller.addV1Slot("left")
        || controller.addV1Slot("left")
        || controller.addV1Slot("unknown")
        || controller.v1Slots.left.length !== 9
        || controller.splits.left.length !== 8
        || controller.baseV1SlotCount("left") !== 7
        || controller.maxV1SlotCount("left") !== 9
        || !controller.isExtraV1Slot("left", 8)
        || controller.isExtraV1Slot("left", 6))
      fail("V1 slot capacity controller contract")
    if (!controller.moveGroupToSlot("G1", "left", 8)
        || controller.v1Slots.left[0] !== ""
        || controller.v1Slots.left[8] !== "G1"
        || controller.removeV1SlotAt("left", 8)
        || !controller.removeV1SlotAt("left", 7)
        || controller.v1Slots.left.length !== 8
        || controller.v1Slots.left[7] !== "G1"
        || !controller.moveGroupToSlot("G1", "left", 0)
        || !controller.removeV1Slot("left")
        || !same(controller.order, ShibumiConfig.defaultOrder())
        || !same(controller.splits, ShibumiConfig.defaultSplits()))
      fail("V1 empty-slot swap/remove transaction")
    if (root.writes !== 13)
      fail("unexpected persistence count " + root.writes)

    if (!controller.reconcileV1PluginGroups([
          { pluginId: "custom.right", region: "right" },
          { pluginId: "custom.left", region: "left" }
        ])
        || controller.groupLocation("G:custom.left").region !== "left"
        || controller.groupLocation("G:custom.right").region !== "right"
        || !controller.reconcileV1PluginGroups([
          { pluginId: "custom.left", region: "left" },
          { pluginId: "custom.right", region: "right" }
        ])
        || !controller.moveGroupToSlot("G:custom.left", "left", 0)
        || controller.reconcileV1PluginGroups([
          { pluginId: "custom.right", region: "right" }
        ])
        || root.writes !== 15
        || !controller.moveGroupToSlot("G:custom.left", "left", 7)
        || !controller.reconcileV1PluginGroups([
          { pluginId: "custom.right", region: "right" }
        ])
        || controller.groupLocation("G:custom.left") !== null
        || controller.groupLocation("G1").region !== "left"
        || controller.groupLocation("G1").index !== 0
        || !controller.reconcileV1PluginGroups([])
        || !same(controller.order, ShibumiConfig.defaultOrder())
        || !same(controller.splits, ShibumiConfig.defaultSplits())
        || root.writes !== 18)
      fail("V1 plugin-group lifecycle transaction")

    const restoreOrder = controller.currentV1Order()
    const restoreSplits = controller.currentV1Splits(restoreOrder)
    const writesBeforeRestore = root.writes
    if (!controller.restoreV1Layout(restoreOrder, restoreSplits)
        || controller.restoreV1Layout({ left: [], center: [], right: [] }, restoreSplits)
        || controller.restoreV1Layout(restoreOrder, { left: [], right: [], boundaries: [] })
        || root.writes !== writesBeforeRestore
        || !controller.swapGroups("G1", "G6")
        || !controller.restoreV1Layout(restoreOrder, restoreSplits)
        || !same(controller.order, restoreOrder)
        || !same(controller.splits, restoreSplits))
      fail("V1 exact rollback validation/idempotence")

    const bASpecs = [{ pluginId: "custom.v2-to-v1", region: "right" }]
    if (!controller.reconcileV1PluginGroups(bASpecs)
        || controller.groupLocation("G:custom.v2-to-v1").region !== "right"
        || !controller.reconcileV1PluginGroups([])
        || controller.groupLocation("G:custom.v2-to-v1") !== null)
      fail("B(a) controller placement did not settle with free V1 capacity")

    const mixedSpecs = [
      { pluginId: "custom.a", region: "left" },
      { pluginId: "custom.b", region: "left" },
      { pluginId: "custom.c", region: "left" },
      { pluginId: "custom.d", region: "left" },
      { pluginId: "custom.e", region: "left" }
    ]
    const beforeCapacity = ShibumiConfig.normalize(fakeStateService.config)
    const writesBeforeCapacity = root.writes
    if (controller.reconcileV1PluginGroups(mixedSpecs)
        || !same(fakeStateService.config, beforeCapacity)
        || root.writes !== writesBeforeCapacity)
      fail("strict legacy reconciliation accepted a partial V1 plan")
    if (!same(controller.unplacedPluginIdsFor(mixedSpecs),
          mixedSpecs.map(spec => spec.pluginId)))
      fail("V1 capacity did not derive from the confirmed order")

    fakeBar.layoutTransitionBusy = true
    if (controller.reconcileV1PluginGroups(mixedSpecs, true)
        || !same(controller.unplacedPluginIdsFor(mixedSpecs),
          mixedSpecs.map(spec => spec.pluginId)))
      fail("busy V1 reconciliation changed confirmed capacity truth")
    fakeBar.layoutTransitionBusy = false
    fakeStateService.rejectWrites = true
    if (controller.reconcileV1PluginGroups(mixedSpecs, true)
        || !same(controller.unplacedPluginIdsFor(mixedSpecs),
          mixedSpecs.map(spec => spec.pluginId)))
      fail("rejected V1 reconciliation changed confirmed capacity truth")
    fakeStateService.rejectWrites = false
    fakeStateService.holdWrites = true
    if (!controller.reconcileV1PluginGroups(mixedSpecs, true)
        || !fakeStateService.writePending
        || !same(controller.unplacedPluginIdsFor(mixedSpecs),
          mixedSpecs.map(spec => spec.pluginId)))
      fail("queued V1 plan replaced confirmed capacity truth")
    fakeStateService.holdWrites = false
    if (!fakeStateService.settleHeld(true)
        || !same(controller.unplacedPluginIdsFor(mixedSpecs), ["custom.e"])
        || !controller.groupLocation("G:custom.a"))
      fail("confirmed mixed V1 plan did not derive its capacity remainder")
    const confirmedPartial = ShibumiConfig.normalize(fakeStateService.config)
    if (controller.unplacedPluginIdsFor([]).length !== 0
        || controller.unplacedPluginIdsFor(mixedSpecs.slice(0, 4)).length !== 0)
      fail("V1 spec changes retained an outdated capacity snapshot")
    fakeStateService.config = beforeCapacity
    if (!same(controller.unplacedPluginIdsFor(mixedSpecs),
          mixedSpecs.map(spec => spec.pluginId)))
      fail("revoked V1 state did not restore current capacity truth")
    fakeStateService.config = confirmedPartial
    if (!same(controller.unplacedPluginIdsFor(mixedSpecs), ["custom.e"]))
      fail("confirmed V1 target was ignored because of prior request state")
    if (!controller.reconcileV1PluginGroups(mixedSpecs.slice(1), true)
        || controller.unplacedPluginIdsFor(mixedSpecs.slice(1)).length !== 0
        || !controller.groupLocation("G:custom.e")
        || controller.groupLocation("G:custom.a") !== null)
      fail("V1 retry did not place the remainder and clear capacity")
    if (!controller.reconcileV1PluginGroups([]))
      fail("V1 capacity fixture cleanup failed")

    const protectedV2State = ShibumiConfig.normalize(fakeStateService.config)
    protectedV2State.presentation.shellStyle = "full"
    protectedV2State.layoutProtection.v2 = true
    fakeStateService.config = ShibumiConfig.normalize(protectedV2State)
    if (controller.restoreV1Layout(restoreOrder, restoreSplits)
        || !controller.v2Mode || !controller.v2LayoutProtected
        || !controller.activeLayoutProtected
        || controller.interactiveMutationAllowed(false)
        || !controller.interactiveMutationAllowed(true)
        || controller.toggleSplit("boundaries", 0)
        || !controller.toggleSplit("boundaries", 0, true)
        || controller.v2Boundaries[0] !== true)
      fail("protected V2 interaction state did not activate independently")

    const v2Baseline = ShibumiConfig.normalize(fakeStateService.config)
    const fullV2 = V2LayoutModel.defaultLayout()
    fullV2.left[3] = "G:custom.l1"
    fullV2.left[8] = "G:custom.l2"
    fullV2.left[9] = "G:custom.l3"
    fullV2.left.push("G:custom.l4", "G:custom.l5", "G:custom.l6")
    fullV2.right[10] = "G:custom.move"
    const fullV2State = ShibumiConfig.normalize(fakeStateService.config)
    fullV2State.v2Layout = fullV2
    fakeStateService.config = ShibumiConfig.normalize(fullV2State)
    const v2MixedSpecs = [
      { pluginId: "custom.blocked", region: "left" },
      { pluginId: "custom.l1", region: "left" },
      { pluginId: "custom.l2", region: "left" },
      { pluginId: "custom.l3", region: "left" },
      { pluginId: "custom.l4", region: "left" },
      { pluginId: "custom.l5", region: "left" },
      { pluginId: "custom.l6", region: "left" },
      { pluginId: "custom.move", region: "left" }
    ]
    fakeBar.layoutTransitionsSupported = true
    const requestsBeforeV2 = fakeBar.transitionRequests
    if (controller.reconcileV2PluginGroups(v2MixedSpecs, true, true)
        || fakeBar.transitionRequests !== requestsBeforeV2
        || !same(controller.unplacedPluginIdsFor(v2MixedSpecs),
          ["custom.blocked"]))
      fail("strict scoped reconciliation accepted a partial V2 plan")
    fakeStateService.rejectWrites = true
    if (controller.reconcileV2PluginGroups(v2MixedSpecs, true, true, true)
        || fakeBar.transitionRequests !== requestsBeforeV2 + 1
        || !same(controller.unplacedPluginIdsFor(v2MixedSpecs),
          ["custom.blocked"]))
      fail("rejected V2 request changed confirmed capacity truth")
    fakeStateService.rejectWrites = false
    if (!controller.reconcileV2PluginGroups(v2MixedSpecs, true, true, true)
        || fakeBar.transitionRequests !== requestsBeforeV2 + 2
        || !same(controller.unplacedPluginIdsFor(v2MixedSpecs),
          ["custom.blocked"])
        || controller.v2Slots.left[0] !== "G:custom.move"
        || controller.v2Slots.right[10] !== "G1")
      fail("confirmed V2 partial plan lost its swap or capacity remainder")
    fakeStateService.config = v2Baseline
    fakeBar.layoutTransitionsSupported = false
    if (controller.unplacedPluginIdsFor([]).length !== 0)
      fail("V2 spec changes retained an outdated capacity snapshot")

    if (!controller.reconcileV2PluginGroups([
          { pluginId: "custom.v2", region: "left" }
        ])
        || controller.groupLocation("G:custom.v2") === null
        || !controller.moveGroupToSlot("G:custom.v2", "right", 0)
        || controller.groupLocation("G:custom.v2").region !== "right"
        || !controller.reconcileV2PluginGroups([])
        || controller.groupLocation("G:custom.v2") !== null
        || !controller.reconcileV2PluginGroups([
          { pluginId: "custom.reset", region: "right" }
        ])
        || !controller.resetLayout()
        || controller.groupLocation("G:custom.reset") !== null)
      fail("V2 third-party group lifecycle transaction")

    console.log("layout controller regression passed")
    Qt.exit(0)
  }
}
