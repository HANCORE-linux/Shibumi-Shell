import QtQuick
import "../core" as Core
import "../core/ShibumiConfig.js" as ShibumiConfig

Item {
  id: root

  property int writes: 0
  visible: true
  width: 320
  height: 80

  function fail(message) {
    console.error("layout-controller-regression:", message)
    Qt.exit(1)
  }

  function same(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  QtObject {
    id: fakeStateService
    property var config: ShibumiConfig.defaultConfig()

    function setLayout(order, splits) {
      const next = ShibumiConfig.normalize(config)
      next.order = ShibumiConfig.normalizedOrder(order)
      next.v1SlotRoles = next.order
        ? ShibumiConfig.slotRolesForOrder(next.order) : null
      next.splits = next.order
        ? ShibumiConfig.normalizedSplits(splits, next.order) : null
      if (!next.order || !next.splits || root.same(config, next)) return false
      config = ShibumiConfig.normalize(next)
      root.writes++
      return true
    }

    function resetLayout() {
      return setLayout(ShibumiConfig.defaultOrder(), ShibumiConfig.defaultSplits())
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

  Core.LayoutController {
    id: controller
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

  Component.onCompleted: {
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
        || firstScreen.targetAt(20, 20) !== "G3"
        || firstScreen.targetAt(120, 20) !== "G4"
        || firstScreen.targetAt(250, 20) !== "")
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
        || firstScreen.targetAt(120, 20) !== "")
      fail("target unregister lifecycle")

    if (!firstScreen.begin("G3", firstTarget, 20, 20)
        || firstScreen.drop() || firstScreen.active || !firstScreen.returning
        || firstScreen.ghostX !== firstScreen.ghostHomeX
        || firstScreen.ghostY !== firstScreen.ghostHomeY
        || !firstScreen.finishReturn() || firstScreen.returning
        || firstScreen.sourceItem !== null)
      fail("invalid drop return lifecycle")

    if (!firstScreen.begin("G1") || !firstScreen.updateTarget("G15")
        || secondScreen.active || firstScreen.screenName !== "DP-1")
      fail("first output drag state")
    if (!secondScreen.begin("G2") || !secondScreen.updateTarget("G14")
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

    if (!firstScreen.begin("G3") || firstScreen.updateTarget("G3")
        || firstScreen.updateTarget("G99") || firstScreen.drop())
      fail("invalid drag target handling")

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
        || controller.addV1Slot("center")
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
        || !controller.reconcileV1PluginGroups([
          { pluginId: "custom.right", region: "right" }
        ])
        || controller.groupLocation("G:custom.left") !== null
        || controller.groupLocation("G1").region !== "left"
        || controller.groupLocation("G1").index !== 0
        || !controller.reconcileV1PluginGroups([])
        || !same(controller.order, ShibumiConfig.defaultOrder())
        || !same(controller.splits, ShibumiConfig.defaultSplits())
        || root.writes !== 17)
      fail("V1 plugin-group lifecycle transaction")

    const protectedV2State = ShibumiConfig.normalize(fakeStateService.config)
    protectedV2State.presentation.shellStyle = "full"
    protectedV2State.layoutProtection.v2 = true
    fakeStateService.config = ShibumiConfig.normalize(protectedV2State)
    if (!controller.v2Mode || !controller.v2LayoutProtected
        || !controller.activeLayoutProtected
        || controller.interactiveMutationAllowed(false)
        || !controller.interactiveMutationAllowed(true)
        || controller.toggleSplit("boundaries", 0)
        || !controller.toggleSplit("boundaries", 0, true)
        || controller.v2Boundaries[0] !== true)
      fail("protected V2 interaction state did not activate independently")

    console.log("layout controller regression passed")
    Qt.exit(0)
  }
}
