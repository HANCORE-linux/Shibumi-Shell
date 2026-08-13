pragma ComponentBehavior: Bound

import QtQuick
import "LayoutModel.js" as LayoutModel
import "V2LayoutModel.js" as V2LayoutModel

Item {
  id: root

  property var bar: null
  property var stateService: null
  readonly property var config: stateService && stateService.config
    ? stateService.config : ({})
  readonly property bool v2Mode: config && config.presentation
    ? String(config.presentation.shellStyle || "shibumi") !== "shibumi"
    : false
  readonly property var layoutProtection: config && config.layoutProtection
    ? config.layoutProtection : ({ v1: false, v2: false })
  readonly property bool v1LayoutProtected: layoutProtection.v1 === true
  readonly property bool v2LayoutProtected: layoutProtection.v2 === true
  readonly property bool activeLayoutProtected: v2Mode
    ? v2LayoutProtected : v1LayoutProtected
  readonly property var v1Slots: LayoutModel.validOrder(
    config ? config.order : null)
    ? LayoutModel.copyOrder(config.order) : LayoutModel.defaultOrder()
  readonly property var v1SlotRoles: LayoutModel.validSlotRoles(
    config ? config.v1SlotRoles : null, v1Slots)
    ? config.v1SlotRoles : LayoutModel.slotRoles(v1Slots)
  readonly property var v2Slots: V2LayoutModel.valid(
    config ? config.v2Layout : null)
    ? V2LayoutModel.copy(config.v2Layout) : V2LayoutModel.defaultLayout()
  readonly property var v2Boundaries: config
    && Array.isArray(config.v2Boundaries)
    && config.v2Boundaries.length === 2
      ? config.v2Boundaries.slice() : [false, false]
  readonly property var order: v2Mode
    ? V2LayoutModel.visibleOrder(v2Slots)
    : v1Slots
  readonly property var splits: LayoutModel.validSplits(
    config ? config.splits : null, v1Slots)
    ? LayoutModel.copySplits(config.splits, v1Slots)
    : LayoutModel.resizeSplits(LayoutModel.defaultSplits(), v1Slots)

  visible: false
  width: 0
  height: 0

  function interactiveMutationAllowed(editingValue) {
    return editingValue === true || !activeLayoutProtected
  }

  function groupLocation(groupId) {
    return v2Mode
      ? V2LayoutModel.locationFor(v2Slots, groupId)
      : LayoutModel.locationFor(currentV1Order(), groupId)
  }

  function currentV1Order() {
    const liveOrder = stateService && stateService.config
      ? stateService.config.order : null
    return LayoutModel.validOrder(liveOrder)
      ? LayoutModel.copyOrder(liveOrder) : LayoutModel.copyOrder(v1Slots)
  }

  function currentV1Splits(orderValue) {
    const sourceOrder = LayoutModel.validOrder(orderValue)
      ? orderValue : currentV1Order()
    const liveSplits = stateService && stateService.config
      ? stateService.config.splits : null
    return LayoutModel.validSplits(liveSplits, sourceOrder)
      ? LayoutModel.copySplits(liveSplits, sourceOrder)
      : LayoutModel.resizeSplits(splits, sourceOrder)
  }

  function splitEnabled(region, index) {
    if (v2Mode && String(region || "") === "boundaries") {
      const value = Number(index)
      return Number.isInteger(value) && value >= 0 && value < 2
        && v2Boundaries[value] === true
    }
    return LayoutModel.splitEnabled(splits, region, index, v1Slots)
  }

  function persist(nextOrder, nextSplits) {
    if (!stateService || typeof stateService.setLayout !== "function") return false
    if (!LayoutModel.validOrder(nextOrder)
        || !LayoutModel.validSplits(nextSplits, nextOrder)) return false
    const currentOrder = currentV1Order()
    const currentSplits = currentV1Splits(currentOrder)
    if (LayoutModel.sameOrder(currentOrder, nextOrder)
        && LayoutModel.sameSplits(currentSplits, nextSplits, nextOrder)) return false
    return stateService.setLayout(LayoutModel.copyOrder(nextOrder),
      LayoutModel.copySplits(nextSplits, nextOrder))
  }

  function swapGroups(sourceGroupId, targetGroupId) {
    if (v2Mode) {
      const nextSlots = V2LayoutModel.swapGroups(
        v2Slots, sourceGroupId, targetGroupId)
      return nextSlots && stateService
        && typeof stateService.setV2Layout === "function"
        ? stateService.setV2Layout(nextSlots) : false
    }
    const currentOrder = currentV1Order()
    const nextOrder = LayoutModel.swapGroups(
      currentOrder, sourceGroupId, targetGroupId)
    return nextOrder ? persist(nextOrder, currentV1Splits(currentOrder)) : false
  }

  function moveGroupToSlot(sourceGroupId, targetRegion, targetIndex) {
    if (v2Mode) {
      if (!stateService || typeof stateService.setV2Layout !== "function")
        return false
      const nextSlots = V2LayoutModel.moveGroupToSlot(
        v2Slots, sourceGroupId, targetRegion, targetIndex)
      return nextSlots ? stateService.setV2Layout(nextSlots) : false
    }
    const currentOrder = currentV1Order()
    const nextOrder = LayoutModel.moveGroupToSlot(
      currentOrder, sourceGroupId, targetRegion, targetIndex)
    return nextOrder ? persist(nextOrder, currentV1Splits(currentOrder)) : false
  }

  function addV1Slot(region) {
    if (v2Mode) return false
    const currentOrder = currentV1Order()
    const nextOrder = LayoutModel.addSlot(currentOrder, region)
    const nextSplits = nextOrder
      ? LayoutModel.resizeSplits(currentV1Splits(currentOrder), nextOrder) : null
    return nextOrder && nextSplits ? persist(nextOrder, nextSplits) : false
  }

  function removeV1Slot(region) {
    if (v2Mode) return false
    const currentOrder = currentV1Order()
    const next = LayoutModel.removeSlot(
      currentOrder, currentV1Splits(currentOrder), region)
    return next ? persist(next.order, next.splits) : false
  }

  function removeV1SlotAt(region, index) {
    if (v2Mode) return false
    const currentOrder = currentV1Order()
    const next = LayoutModel.removeSlotAt(
      currentOrder, currentV1Splits(currentOrder), region, index)
    return next ? persist(next.order, next.splits) : false
  }

  function reconcileV1PluginGroups(specs) {
    const currentOrder = currentV1Order()
    const currentSplits = currentV1Splits(currentOrder)
    const next = LayoutModel.reconcilePluginGroups(
      currentOrder, currentSplits, specs)
    if (!next || next.unplaced.length > 0) return false
    if (LayoutModel.sameOrder(currentOrder, next.order)
        && LayoutModel.sameSplits(currentSplits, next.splits, next.order))
      return true
    return persist(next.order, next.splits)
  }

  function baseV1SlotCount(region) {
    return LayoutModel.baseCount(region)
  }

  function maxV1SlotCount(region) {
    return LayoutModel.maxCount(region)
  }

  function isExtraV1Slot(region, index) {
    return LayoutModel.isExtraSlot(currentV1Order(), region, index)
  }

  function addV2Slot(region) {
    if (!v2Mode || !stateService
        || typeof stateService.setV2Layout !== "function") return false
    const next = V2LayoutModel.addSlot(v2Slots, region)
    return next ? stateService.setV2Layout(next) : false
  }

  function removeV2Slot(region) {
    if (!v2Mode || !stateService
        || typeof stateService.setV2Layout !== "function") return false
    const next = V2LayoutModel.removeSlot(v2Slots, region)
    return next ? stateService.setV2Layout(next) : false
  }

  function baseV2SlotCount(region) {
    const limit = V2LayoutModel.Limits[String(region || "")]
    return limit ? Number(limit.min) || 0 : 0
  }

  function maxV2SlotCount(region) {
    const limit = V2LayoutModel.Limits[String(region || "")]
    return limit ? Number(limit.max) || 0 : 0
  }

  function removeV2SlotAt(region, index) {
    if (!v2Mode || !stateService
        || typeof stateService.setV2Layout !== "function") return false
    const next = V2LayoutModel.removeSlotAt(v2Slots, region, index)
    return next ? stateService.setV2Layout(next) : false
  }

  function toggleSplit(region, index, editingValue) {
    if (!interactiveMutationAllowed(editingValue)) return false
    if (v2Mode && String(region || "") === "boundaries")
      return stateService
        && typeof stateService.toggleV2Boundary === "function"
        ? stateService.toggleV2Boundary(index) : false
    const currentOrder = currentV1Order()
    const nextSplits = LayoutModel.toggleSplit(
      currentV1Splits(currentOrder), region, index, currentOrder)
    return nextSplits ? persist(currentOrder, nextSplits) : false
  }

  function setAllSplits(enabled) {
    if (v2Mode)
      return stateService
        && typeof stateService.setAllV2Separators === "function"
        ? stateService.setAllV2Separators(enabled) : false
    const currentOrder = currentV1Order()
    const nextSplits = LayoutModel.allSplits(enabled, currentOrder)
    return nextSplits ? persist(currentOrder, nextSplits) : false
  }

  function resetLayout() {
    if (v2Mode && stateService
        && typeof stateService.resetV2Layout === "function")
      return stateService.resetV2Layout()
    return stateService && typeof stateService.resetLayout === "function"
      ? stateService.resetLayout() : false
  }
}
