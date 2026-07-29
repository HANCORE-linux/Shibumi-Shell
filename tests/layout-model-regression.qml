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
    if (!same(LayoutModel.GroupIds, ShibumiConfig.GroupIds)
        || !LayoutModel.validOrder(order) || !LayoutModel.validSplits(splits))
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
        || !LayoutModel.sameSplits(splits, ShibumiConfig.defaultSplits()))
      fail("structural equality contract")
    if (LayoutModel.swapGroups(order, "G1", "G1") !== null
        || LayoutModel.swapGroups(order, "G1", "G99") !== null)
      fail("invalid swap was accepted")

    const duplicate = ShibumiConfig.defaultOrder()
    duplicate.left[0] = "G2"
    if (LayoutModel.validOrder(duplicate)
        || LayoutModel.swapGroups(duplicate, "G2", "G15") !== null)
      fail("malformed order was accepted")

    const toggled = LayoutModel.toggleSplit(splits, "left", 0)
    if (!toggled || !toggled.left[0] || splits.left[0]
        || LayoutModel.toggleSplit(splits, "center", 0) !== null
        || LayoutModel.toggleSplit(splits, "left", 6) !== null)
      fail("split toggle contract")
    const boundary = LayoutModel.toggleSplit(splits, "boundaries", 1)
    if (!boundary || !boundary.boundaries[1]
        || LayoutModel.splitEnabled(splits, "boundaries", 1)
        || !LayoutModel.splitEnabled(boundary, "boundaries", 1))
      fail("boundary split contract")

    const splitAll = LayoutModel.allSplits(true)
    if (!LayoutModel.validSplits(splitAll)
        || !splitAll.left.every(Boolean) || !splitAll.right.every(Boolean)
        || !splitAll.boundaries.every(Boolean)
        || LayoutModel.allSplits("true") !== null)
      fail("split-all contract")

    console.log("layout model regression passed")
    Qt.exit(0)
  }
}
