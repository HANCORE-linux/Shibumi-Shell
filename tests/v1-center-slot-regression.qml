import QtQuick
import "../core/LayoutModel.js" as Layout
import "../core/ShibumiConfig.js" as Config

QtObject {
  function require(value, message) {
    if (!value) throw new Error("v1-center-slot-regression: " + message)
  }
  function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

  Component.onCompleted: {
    try {
      const original = Config.defaultConfig()
      const before = JSON.stringify(original)
      const order = Layout.addSlot(original.order, "center")
      const splits = Layout.resizeSplits(original.splits, order)
      require(order && same(order.center, ["G8", ""]), "one optional center destination")
      require(Layout.maxCount("center") === 2 && Layout.addSlot(order, "center") === null,
        "third center slot refused")
      require(same(splits, original.splits) && JSON.stringify(original) === before,
        "legacy state and split schema unchanged")
      require(same(Layout.slotRoles(order).center, ["base", "extra"]), "center roles")
      const changed = JSON.parse(before)
      changed.order = order
      changed.splits = splits
      changed.v1SlotRoles = Layout.slotRoles(order)
      const reloaded = Config.normalize(JSON.parse(JSON.stringify(changed)))
      require(same(reloaded.order, order) && same(reloaded.v1SlotRoles, changed.v1SlotRoles)
        && same(reloaded.v2Layout, original.v2Layout) && reloaded.version === original.version,
        "round-trip without V2 or schema migration")
      for (const center of [[], ["G8", "", ""], ["G8", "G8"], ["G8", "unknown"]]) {
        const invalid = Layout.copyOrder(order)
        invalid.center = center
        require(!Layout.validOrder(invalid) && Config.normalizedOrder(invalid) === null,
          "model/normalizer malformed center agreement")
      }
      const badRoles = Layout.slotRoles(order)
      badRoles.center = ["base", "base"]
      require(!Layout.validSlotRoles(badRoles, order)
        && Config.normalizedV1SlotRoles(badRoles, order) === null, "invalid roles refused")
      const moved = Layout.moveGroupToSlot(order, "G4", "center", 1)
      require(moved && moved.left[3] === "" && same(moved.center, ["G8", "G4"])
        && !Layout.removeSlotAt(moved, splits, "center", 1)
        && !Layout.removeSlotAt(order, splits, "center", 0), "occupied/base removal refused")
      const returned = Layout.moveGroupToSlot(moved, "G4", "left", 3)
      const removed = Layout.removeSlot(returned, splits, "center")
      require(removed && same(removed.order, original.order)
        && same(removed.splits, original.splits), "empty center removal restores exact legacy layout")
      require(Layout.toggleSplit(splits, "center", 0, order) === null,
        "no implicit center separator field")

      const preferred = [{ pluginId: "custom.center", region: "center" }]
      const legacy = Layout.reconcilePluginGroups(original.order, original.splits, preferred)
      require(legacy && legacy.order.center.length === 1
        && Layout.locationFor(legacy.order, "G:custom.center").region !== "center",
        "reconciliation must not grow center or migrate legacy placement")
      const added = Layout.reconcilePluginGroups(order, splits, preferred)
      require(added && added.unplaced.length === 0
        && added.order.center[1] === "G:custom.center", "explicit center slot accepts provider")
      const preserved = Layout.reconcilePluginGroups(added.order, splits,
        [{ pluginId: "custom.center", region: "left" }])
      require(same(preserved.order, added.order), "existing placement is authoritative")
      const swapped = Layout.swapGroups(added.order, "G8", "G:custom.center")
      const clean = Layout.reconcilePluginGroups(swapped, splits, [])
      require(clean && same(clean.order, original.order) && same(clean.splits, original.splits),
        "removing center-base dynamic provider restores G8 from center extra")
      const outer = Layout.addDynamicGroup(order, splits, "custom.outer", "left")
      const inOuterBase = Layout.swapGroups(outer.order, "G:custom.outer", "G1")
      const g1InCenter = Layout.moveGroupToSlot(inOuterBase, "G1", "center", 1)
      const withoutOuterExtra = Layout.removeSlot(g1InCenter, outer.splits, "left")
      const cleanOuter = Layout.reconcilePluginGroups(
        withoutOuterExtra.order, withoutOuterExtra.splits, [])
      require(cleanOuter && same(cleanOuter.order, original.order),
        "base repair can recover fixed occupant from center extra")
      // Both occupied extras are plausible swap sources. Never choose the
      // center (or an outer region) merely because it is scanned first.
      const ambiguousAdded = Layout.addDynamicGroup(moved, splits, "custom.outer", "left")
      const ambiguousOrder = Layout.swapGroups(ambiguousAdded.order, "G:custom.outer", "G8")
      const ambiguousBefore = JSON.stringify({ order: ambiguousOrder, splits: ambiguousAdded.splits })
      require(Layout.reconcilePluginGroups(ambiguousOrder, ambiguousAdded.splits, []) === null
        && JSON.stringify({ order: ambiguousOrder, splits: ambiguousAdded.splits }) === ambiguousBefore,
        "ambiguous center/outer repair refuses without deleting the center slot")
      const extraHome = Layout.locationFor(ambiguousOrder, "G8")
      const returnedProvider = Layout.moveGroupToSlot(ambiguousOrder,
        "G:custom.outer", extraHome.region, extraHome.index)
      const removedProvider = Layout.reconcilePluginGroups(returnedProvider, ambiguousAdded.splits, [])
      require(removedProvider && same(removedProvider.order, moved)
        && same(removedProvider.splits, splits),
        "explicit return to extra then removal preserves center pair")
      const twoOuter = Layout.addDynamicGroup(original.order, original.splits, "custom.a", "left")
      const bothOuter = Layout.addDynamicGroup(twoOuter.order, twoOuter.splits, "custom.b", "right")
      const firstBase = Layout.swapGroups(bothOuter.order, "G:custom.a", "G1")
      const bothBase = Layout.swapGroups(firstBase, "G:custom.b", "G9")
      require(Layout.reconcilePluginGroups(bothBase, bothOuter.splits, []) === null,
        "multiple outer repair candidates also refuse instead of guessing")

      const fullSpecs = ["a", "b", "c", "d", "e"].map(id =>
        ({ pluginId: "custom." + id, region: "left" }))
      const full = Layout.reconcilePluginGroups(order, splits, fullSpecs)
      require(full.unplaced.length === 1 && full.order.center[1] === "",
        "outer additions do not silently consume the optional center slot")
      console.log("V1 center slot regression passed")
      Qt.exit(0)
    } catch (error) {
      console.error(String(error))
      Qt.exit(1)
    }
  }
}
