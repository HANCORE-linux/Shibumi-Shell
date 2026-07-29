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
  readonly property var v2Slots: V2LayoutModel.valid(
    config ? config.v2Layout : null)
    ? V2LayoutModel.copy(config.v2Layout) : V2LayoutModel.defaultLayout()
  readonly property var v2Boundaries: config
    && Array.isArray(config.v2Boundaries)
    && config.v2Boundaries.length === 2
      ? config.v2Boundaries.slice() : [false, false]
  readonly property var order: v2Mode
    ? V2LayoutModel.visibleOrder(v2Slots)
    : LayoutModel.validOrder(config ? config.order : null)
      ? LayoutModel.copyOrder(config.order) : LayoutModel.defaultOrder()
  readonly property var splits: LayoutModel.validSplits(config ? config.splits : null)
    ? LayoutModel.copySplits(config.splits) : LayoutModel.defaultSplits()

  visible: false
  width: 0
  height: 0

  function groupLocation(groupId) {
    return v2Mode
      ? V2LayoutModel.locationFor(v2Slots, groupId)
      : LayoutModel.locationFor(order, groupId)
  }

  function splitEnabled(region, index) {
    if (v2Mode && String(region || "") === "boundaries") {
      const value = Number(index)
      return Number.isInteger(value) && value >= 0 && value < 2
        && v2Boundaries[value] === true
    }
    return LayoutModel.splitEnabled(splits, region, index)
  }

  function persist(nextOrder, nextSplits) {
    if (!stateService || typeof stateService.setLayout !== "function") return false
    if (!LayoutModel.validOrder(nextOrder)
        || !LayoutModel.validSplits(nextSplits)) return false
    if (LayoutModel.sameOrder(order, nextOrder)
        && LayoutModel.sameSplits(splits, nextSplits)) return false
    return stateService.setLayout(LayoutModel.copyOrder(nextOrder),
      LayoutModel.copySplits(nextSplits))
  }

  function swapGroups(sourceGroupId, targetGroupId) {
    if (v2Mode) {
      const nextSlots = V2LayoutModel.swapGroups(
        v2Slots, sourceGroupId, targetGroupId)
      return nextSlots && stateService
        && typeof stateService.setV2Layout === "function"
        ? stateService.setV2Layout(nextSlots) : false
    }
    const nextOrder = LayoutModel.swapGroups(order, sourceGroupId, targetGroupId)
    return nextOrder ? persist(nextOrder, splits) : false
  }

  function moveGroupToSlot(sourceGroupId, targetRegion, targetIndex) {
    if (!v2Mode || !stateService
        || typeof stateService.setV2Layout !== "function") return false
    const nextSlots = V2LayoutModel.moveGroupToSlot(
      v2Slots, sourceGroupId, targetRegion, targetIndex)
    return nextSlots ? stateService.setV2Layout(nextSlots) : false
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

  function toggleSplit(region, index) {
    if (v2Mode && String(region || "") === "boundaries")
      return stateService
        && typeof stateService.toggleV2Boundary === "function"
        ? stateService.toggleV2Boundary(index) : false
    const nextSplits = LayoutModel.toggleSplit(splits, region, index)
    return nextSplits ? persist(order, nextSplits) : false
  }

  function setAllSplits(enabled) {
    if (v2Mode)
      return stateService
        && typeof stateService.setAllV2Separators === "function"
        ? stateService.setAllV2Separators(enabled) : false
    const nextSplits = LayoutModel.allSplits(enabled)
    return nextSplits ? persist(order, nextSplits) : false
  }

  function resetLayout() {
    if (v2Mode && stateService
        && typeof stateService.resetV2Layout === "function")
      return stateService.resetV2Layout()
    return stateService && typeof stateService.resetLayout === "function"
      ? stateService.resetLayout() : false
  }
}
