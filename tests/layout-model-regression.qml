import QtQuick
import "../core/LayoutModel.js" as LayoutModel
import "../core/ShibumiConfig.js" as ShibumiConfig

QtObject {
  function fail(message) {
    console.error("layout-model-regression:", message)
    Qt.exit(1)
  }

  function same(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  }

  Component.onCompleted: {
    const order = ShibumiConfig.defaultOrder()
    const splits = ShibumiConfig.defaultSplits()
    if (!same(LayoutModel.GroupIds, ShibumiConfig.V1GroupIds)
        || !LayoutModel.validOrder(order)
        || !LayoutModel.validSplits(splits, order)
        || !LayoutModel.validSlotRoles(
          ShibumiConfig.slotRolesForOrder(order), order))
      fail("layout/config contracts diverged")

    const g8 = LayoutModel.locationFor(order, "G8")
    if (!g8 || g8.region !== "center" || g8.index !== 0
        || LayoutModel.locationFor(order, "G99") !== null)
      fail("group location contract")

    const swapped = LayoutModel.swapGroups(order, "G1", "G15")
    if (!swapped || swapped.left[0] !== "G15" || swapped.right[6] !== "G1"
        || order.left[0] !== "G1" || order.right[6] !== "G15")
      fail("cross-region swap or immutability")
    if (!LayoutModel.sameOrder(order, ShibumiConfig.defaultOrder())
        || LayoutModel.sameOrder(order, swapped)
        || !LayoutModel.sameSplits(
          splits, ShibumiConfig.defaultSplits(), order))
      fail("structural equality contract")
    if (LayoutModel.swapGroups(order, "G1", "G1") !== null
        || LayoutModel.swapGroups(order, "G1", "G99") !== null)
      fail("invalid swap was accepted")

    const duplicate = ShibumiConfig.defaultOrder()
    duplicate.left[0] = "G2"
    if (LayoutModel.validOrder(duplicate)
        || LayoutModel.swapGroups(duplicate, "G2", "G15") !== null)
      fail("malformed order was accepted")

    const toggled = LayoutModel.toggleSplit(splits, "left", 0, order)
    if (!toggled || !toggled.left[0] || splits.left[0]
        || LayoutModel.toggleSplit(splits, "center", 0, order) !== null
        || LayoutModel.toggleSplit(splits, "left", 6, order) !== null)
      fail("split toggle contract")
    const boundary = LayoutModel.toggleSplit(
      splits, "boundaries", 1, order)
    if (!boundary || !boundary.boundaries[1]
        || LayoutModel.splitEnabled(splits, "boundaries", 1, order)
        || !LayoutModel.splitEnabled(boundary, "boundaries", 1, order))
      fail("boundary split contract")

    const splitAll = LayoutModel.allSplits(true, order)
    if (!LayoutModel.validSplits(splitAll, order)
        || !splitAll.left.every(Boolean) || !splitAll.right.every(Boolean)
        || !splitAll.boundaries.every(Boolean)
        || LayoutModel.allSplits("true") !== null)
      fail("split-all contract")

    const leftOne = LayoutModel.addSlot(order, "left")
    const leftTwo = LayoutModel.addSlot(leftOne, "left")
    const bothSides = LayoutModel.addSlot(leftTwo, "right")
    if (!leftOne || !leftTwo || !bothSides
        || leftTwo.left.length !== 9 || bothSides.right.length !== 8
        || LayoutModel.addSlot(leftTwo, "left") !== null
        || LayoutModel.addSlot(order, "center") !== null
        || !LayoutModel.isExtraSlot(leftTwo, "left", 7)
        || LayoutModel.isExtraSlot(leftTwo, "left", 6))
      fail("V1 optional slot limits or roles")

    const expandedSplits = LayoutModel.resizeSplits(splits, leftTwo)
    if (!expandedSplits || expandedSplits.left.length !== 8
        || expandedSplits.left[6] || expandedSplits.left[7]
        || !LayoutModel.validSplits(expandedSplits, leftTwo))
      fail("split expansion contract")

    const movedToExtra = LayoutModel.moveGroupToSlot(
      leftTwo, "G1", "left", 8)
    if (!movedToExtra || movedToExtra.left[0] !== ""
        || movedToExtra.left[8] !== "G1"
        || LayoutModel.removeSlotAt(
          movedToExtra, expandedSplits, "left", 8) !== null
        || LayoutModel.removeSlotAt(
          movedToExtra, expandedSplits, "left", 0) !== null)
      fail("empty-target swap or base/occupied removal guard")

    const splitBeforeRemove = LayoutModel.copySplits(
      expandedSplits, movedToExtra)
    splitBeforeRemove.left[6] = true
    splitBeforeRemove.left[7] = false
    const removedMiddleExtra = LayoutModel.removeSlotAt(
      movedToExtra, splitBeforeRemove, "left", 7)
    if (!removedMiddleExtra || removedMiddleExtra.order.left.length !== 8
        || removedMiddleExtra.order.left[7] !== "G1"
        || removedMiddleExtra.splits.left.length !== 7
        || removedMiddleExtra.splits.left[6] !== true
        || !LayoutModel.validSplits(
          removedMiddleExtra.splits, removedMiddleExtra.order))
      fail("empty extra removal did not merge positional splits")

    const movedAgain = LayoutModel.moveGroupToSlot(
      removedMiddleExtra.order, "G1", "right", 0)
    if (!movedAgain || !LayoutModel.validSplits(
          removedMiddleExtra.splits, movedAgain)
        || removedMiddleExtra.splits.left[6] !== true)
      fail("widget move changed positional split state")

    const reconciled = LayoutModel.reconcilePluginGroups(order, splits, [
      { pluginId: "custom.right", region: "right" },
      { pluginId: "custom.left", region: "left" }
    ])
    if (!reconciled || reconciled.unplaced.length !== 0
        || reconciled.order.left[7] !== "G:custom.left"
        || reconciled.order.right[7] !== "G:custom.right"
        || reconciled.splits.left.length !== 7
        || reconciled.splits.right.length !== 7
        || LayoutModel.dynamicPluginId("G:custom.left") !== "custom.left"
        || LayoutModel.dynamicGroupId("CUSTOM") !== "")
      fail("deterministic dynamic plugin group creation")

    const dynamicInBase = LayoutModel.moveGroupToSlot(
      reconciled.order, "G:custom.left", "left", 0)
    const withoutLeft = dynamicInBase
      ? LayoutModel.reconcilePluginGroups(
        dynamicInBase, reconciled.splits,
        [{ pluginId: "custom.right", region: "right" }]) : null
    if (!withoutLeft || withoutLeft.order.left.length !== 7
        || withoutLeft.order.left[0] !== "G1"
        || LayoutModel.locationFor(
          withoutLeft.order, "G:custom.left") !== null
        || withoutLeft.order.right[7] !== "G:custom.right"
        || !LayoutModel.validSplits(withoutLeft.splits, withoutLeft.order))
      fail("dynamic group removal did not repair a swapped base slot")

    const full = LayoutModel.reconcilePluginGroups(order, splits, [
      { pluginId: "custom.a", region: "left" },
      { pluginId: "custom.b", region: "left" },
      { pluginId: "custom.c", region: "left" },
      { pluginId: "custom.d", region: "left" },
      { pluginId: "custom.e", region: "left" }
    ])
    if (!full || full.unplaced.length !== 1
        || full.unplaced[0] !== "custom.e"
        || full.order.left.length !== 9 || full.order.right.length !== 9)
      fail("dynamic group capacity must fail closed")

    console.log("layout model regression passed")
    Qt.exit(0)
  }
}
