import QtQuick
import "../hancore.shibumi.bar/core/LayoutModel.js" as LayoutModel
import "../hancore.shibumi.bar/core/V2LayoutModel.js" as V2LayoutModel
import "../hancore.shibumi.state/ShibumiConfig.js" as ShibumiConfig

QtObject {
  function fail(message) {
    console.error("layout-model-regression:", message)
    Qt.exit(1)
    throw new Error(message)
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
    const centerOrder = LayoutModel.addSlot(order, "center"), centerSplits = LayoutModel.resizeSplits(splits, centerOrder)
    const centerToggled = LayoutModel.toggleSplit(centerSplits, "center", 0, centerOrder)
    if (!toggled || !toggled.left[0] || splits.left[0]
        || !centerToggled || !centerToggled.center[0]
        || LayoutModel.toggleSplit(splits, "center", 0, order) !== null
        || LayoutModel.toggleSplit(splits, "left", 6, order) !== null)
      fail("split toggle contract")
    const boundary = LayoutModel.toggleSplit(
      splits, "boundaries", 1, order)
    if (!boundary || !boundary.boundaries[1]
        || LayoutModel.splitEnabled(splits, "boundaries", 1, order)
        || !LayoutModel.splitEnabled(boundary, "boundaries", 1, order))
      fail("boundary split contract")

    const splitAll = LayoutModel.allSplits(true, centerOrder)
    if (!LayoutModel.validSplits(splitAll, centerOrder)
        || !splitAll.left.every(Boolean) || !splitAll.center.every(Boolean)
        || !splitAll.right.every(Boolean) || !splitAll.boundaries.every(Boolean)
        || LayoutModel.allSplits("true") !== null)
      fail("split-all contract")

    const leftOne = LayoutModel.addSlot(order, "left")
    const leftTwo = LayoutModel.addSlot(leftOne, "left")
    const bothSides = LayoutModel.addSlot(leftTwo, "right")
    if (!leftOne || !leftTwo || !bothSides
        || leftTwo.left.length !== 9 || bothSides.right.length !== 8
        || LayoutModel.addSlot(leftTwo, "left") !== null
        || LayoutModel.maxCount("center") !== 2
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
    if (LayoutModel.reconcilePluginGroups(dynamicInBase, reconciled.splits,
          [{ pluginId: "custom.right", region: "right" }]) !== null)
      fail("ambiguous base repair guessed among fixed and dynamic extras")
    const returnedToExtra = LayoutModel.swapGroups(dynamicInBase, "G:custom.left", "G1")
    const withoutLeft = returnedToExtra
      ? LayoutModel.reconcilePluginGroups(
        returnedToExtra, reconciled.splits,
        [{ pluginId: "custom.right", region: "right" }]) : null
    if (!withoutLeft || withoutLeft.order.left.length !== 7
        || withoutLeft.order.left[0] !== "G1"
        || LayoutModel.locationFor(
          withoutLeft.order, "G:custom.left") !== null
        || withoutLeft.order.right[7] !== "G:custom.right"
        || !LayoutModel.validSplits(withoutLeft.splits, withoutLeft.order))
      fail("dynamic group removal did not repair a swapped base slot")

    const bA = LayoutModel.reconcilePluginGroups(order, splits, [
      { pluginId: "custom.v2-to-v1", region: "right" }
    ])
    if (!bA || bA.unplaced.length !== 0
        || LayoutModel.locationFor(bA.order, "G:custom.v2-to-v1").region !== "right"
        || !LayoutModel.validSplits(bA.splits, bA.order))
      fail("free V1 capacity did not place the V2-origin candidate")

    const full = LayoutModel.reconcilePluginGroups(order, splits, [
      { pluginId: "custom.a", region: "left" },
      { pluginId: "custom.b", region: "left" },
      { pluginId: "custom.c", region: "left" },
      { pluginId: "custom.d", region: "left" },
      { pluginId: "custom.e", region: "left" }
    ])
    if (!full || full.unplaced.length !== 1
        || full.unplaced[0] !== "custom.e"
        || full.order.left.length !== 9 || full.order.right.length !== 9
        || !LayoutModel.locationFor(full.order, "G:custom.a")
        || !LayoutModel.validSplits(full.splits, full.order))
      fail("mixed V1 plan lost placeable candidates or capacity remainder")

    const v2Fallback = V2LayoutModel.defaultLayout()
    v2Fallback.right[10] = "G:custom.r1"
    v2Fallback.right[11] = "G:custom.r2"
    v2Fallback.right[12] = "G:custom.r3"
    const v2FallbackSpecs = [
      { pluginId: "custom.r1", region: "right" },
      { pluginId: "custom.r2", region: "right" },
      { pluginId: "custom.r3", region: "right" },
      { pluginId: "custom.target", region: "right" }
    ]
    const v2FallbackPlan = V2LayoutModel.reconcilePluginGroups(
      v2Fallback, v2FallbackSpecs, true)
    const v2FallbackLocation = v2FallbackPlan
      ? V2LayoutModel.locationFor(
        v2FallbackPlan.layout, "G:custom.target") : null
    if (!v2FallbackPlan || v2FallbackPlan.unplaced.length !== 0
        || !v2FallbackLocation || v2FallbackLocation.region !== "left"
        || v2FallbackLocation.index !== 3
        || v2FallbackPlan.layout.right[10] !== "G:custom.r1"
        || v2FallbackPlan.layout.right[11] !== "G:custom.r2"
        || v2FallbackPlan.layout.right[12] !== "G:custom.r3")
      fail("V2 did not use an existing fallback-region slot")

    const v2Full = V2LayoutModel.defaultLayout()
    v2Full.left[3] = "G:custom.l1"
    v2Full.left[8] = "G:custom.l2"
    v2Full.left[9] = "G:custom.l3"
    v2Full.left.push("G:custom.l4", "G:custom.l5", "G:custom.l6")
    v2Full.right[10] = "G:custom.move"
    v2Full.right[11] = "G:custom.r1"
    v2Full.right[12] = "G:custom.r2"
    const v2Mixed = V2LayoutModel.reconcilePluginGroups(v2Full, [
      { pluginId: "custom.blocked", region: "left" },
      { pluginId: "custom.l1", region: "left" },
      { pluginId: "custom.l2", region: "left" },
      { pluginId: "custom.l3", region: "left" },
      { pluginId: "custom.l4", region: "left" },
      { pluginId: "custom.l5", region: "left" },
      { pluginId: "custom.l6", region: "left" },
      { pluginId: "custom.move", region: "left" },
      { pluginId: "custom.r1", region: "right" },
      { pluginId: "custom.r2", region: "right" }
    ], true)
    if (!v2Mixed || !V2LayoutModel.valid(v2Mixed.layout)
        || v2Mixed.unplaced.length !== 1
        || v2Mixed.unplaced[0] !== "custom.blocked"
        || v2Mixed.layout.left[0] !== "G:custom.move"
        || v2Mixed.layout.right[10] !== "G1")
      fail("V2 full-region swap was lost beside an unplaced candidate")

    console.log("layout model regression passed")
    Qt.exit(0)
  }
}
