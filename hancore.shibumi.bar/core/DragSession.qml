pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  property var layoutController: null
  property string screenName: ""
  property real originX: 0
  property real originY: 0
  property string geometryKey: ""
  property bool editing: false
  property bool active: false
  property bool returning: false
  property string sourceGroupId: ""
  property string targetGroupId: ""
  property string targetRegion: ""
  property int targetIndex: -1
  property Item targetItem: null
  property Item sourceItem: null
  property var sourceWindow: null
  property var targets: []
  property real ghostX: 0
  property real ghostY: 0
  property real ghostWidth: 0
  property real ghostHeight: 0
  property real ghostHomeX: 0
  property real ghostHomeY: 0
  property url ghostImageUrl: ""
  // The image-provider URL is valid only while its grab result is retained.
  property var ghostImageGrab: null
  property int captureGeneration: 0

  visible: false
  width: 0
  height: 0

  onOriginXChanged: cancelForGeometryChange()
  onOriginYChanged: cancelForGeometryChange()
  onGeometryKeyChanged: cancelForGeometryChange()
  onSourceItemChanged: {
    if (!sourceItem && (active || returning)) cancel()
  }
  Connections {
    target: root.sourceItem ? root.sourceItem.Window : null
    function onWindowChanged() {
      if (root.active || root.returning) root.cancel()
    }
  }
  Connections {
    target: root.sourceWindow
    function onVisibleChanged() {
      if (target && !target.visible) root.cancel()
    }
    function onWidthChanged() {
      if (target && !root.positiveSize(target)) root.cancel()
    }
    function onHeightChanged() {
      if (target && !root.positiveSize(target)) root.cancel()
    }
  }

  function cancelForGeometryChange() {
    if (!active && !returning) return false
    cancel()
    return true
  }

  function groupExists(groupId) {
    return layoutController
      && typeof layoutController.groupLocation === "function"
      && layoutController.groupLocation(groupId) !== null
  }

  function setEditing(value) {
    const next = value === true
    if (editing === next) return false
    editing = next
    if (!editing) cancel()
    return true
  }

  function toggleEditing() {
    return setEditing(!editing)
  }

  function registerTarget(groupId, item) {
    const group = String(groupId || "")
    if (!groupExists(group) || !item) return false
    const next = []
    for (let i = 0; i < targets.length; i++) {
      const current = targets[i]
      if (current && current.item !== item && current.groupId !== group)
        next.push(current)
    }
    next.push({ groupId: group, item: item })
    targets = next
    return true
  }

  function registerSlotTarget(region, index, groupId, item) {
    const targetRegionValue = String(region || "")
    const targetIndexValue = Math.floor(Number(index))
    if (!layoutController
        || ["left", "center", "right"].indexOf(targetRegionValue) < 0
        || !Number.isFinite(targetIndexValue) || targetIndexValue < 0
        || !item) return false
    const next = []
    for (let i = 0; i < targets.length; i++) {
      const current = targets[i]
      if (!current || current.item === item) continue
      if (current.region === targetRegionValue
          && current.index === targetIndexValue) continue
      if (groupId !== "" && current.groupId === String(groupId)) continue
      next.push(current)
    }
    next.push({
      groupId: String(groupId || ""),
      region: targetRegionValue,
      index: targetIndexValue,
      item: item
    })
    targets = next
    return true
  }

  function unregisterTarget(item) {
    if (!item) return false
    const next = []
    let removed = false
    for (let i = 0; i < targets.length; i++) {
      const current = targets[i]
      if (current && current.item === item) {
        removed = true
        if (current.item === targetItem) {
          targetGroupId = ""
          targetRegion = ""
          targetIndex = -1
          targetItem = null
        }
      } else if (current) {
        next.push(current)
      }
    }
    if (!removed) return false
    targets = next
    if (sourceItem === item) cancel()
    return true
  }

  function toOutputPoint(localX, localY) {
    const x = Number(localX)
    const y = Number(localY)
    const offsetX = Number(originX)
    const offsetY = Number(originY)
    if (!Number.isFinite(x) || !Number.isFinite(y)
        || !Number.isFinite(offsetX) || !Number.isFinite(offsetY)) return null
    return { x: x + offsetX, y: y + offsetY }
  }

  function itemOutputOrigin(item) {
    if (!item || typeof item.mapToItem !== "function") return null
    const local = item.mapToItem(null, 0, 0)
    return local ? toOutputPoint(local.x, local.y) : null
  }

  function targetAtOutput(outputX, outputY) {
    const px = Number(outputX)
    const py = Number(outputY)
    if (!Number.isFinite(px) || !Number.isFinite(py)) return ""
    for (let i = targets.length - 1; i >= 0; i--) {
      const target = targets[i]
      const item = target ? target.item : null
      if (!item || !item.visible || item.width <= 0.5 || item.height <= 0.5)
        continue
      const origin = itemOutputOrigin(item)
      if (origin && px >= origin.x && px <= origin.x + item.width
          && py >= origin.y && py <= origin.y + item.height)
        return target
    }
    return null
  }

  function targetAt(windowX, windowY) {
    const point = toOutputPoint(windowX, windowY)
    return point ? targetAtOutput(point.x, point.y) : ""
  }

  function positiveSize(item) {
    return item && Number.isFinite(item.width) && Number.isFinite(item.height)
      && item.width > 0 && item.height > 0
  }

  function begin(groupId, item, windowX, windowY) {
    const source = String(groupId || "")
    cancel()
    if (!groupExists(source) || !item || !item.visible || !positiveSize(item)
        || typeof item.mapToItem !== "function"
        || typeof item.grabToImage !== "function") return false
    const window = item.Window.window
    if (!window || !window.visible || !positiveSize(window)) return false
    const origin = itemOutputOrigin(item)
    if (!origin) return false
    const pointer = toOutputPoint(windowX, windowY)

    sourceGroupId = source
    sourceItem = item
    sourceWindow = window
    ghostHomeX = origin.x
    ghostHomeY = origin.y
    ghostWidth = item.width
    ghostHeight = item.height
    ghostX = pointer ? pointer.x - ghostWidth / 2 : ghostHomeX
    ghostY = pointer ? pointer.y - ghostHeight / 2 : ghostHomeY
    const generation = captureGeneration
    const capturedItem = sourceItem
    // Bound the raster to the source bar window's validated logical size,
    // preserving aspect ratio. Ghost geometry stays output-local and logical.
    const captureScale = Math.min(1,
      window.width / ghostWidth, window.height / ghostHeight)
    if (!sourceItem.grabToImage(function(result) {
      if (root) root.acceptGhostCapture(generation, capturedItem, result)
    }, Qt.size(Math.max(1, Math.ceil(ghostWidth * captureScale)),
      Math.max(1, Math.ceil(ghostHeight * captureScale))))) {
      cancel()
      return false
    }
    active = true
    return true
  }

  function acceptGhostCapture(generation, item, result) {
    if (generation !== captureGeneration || sourceItem !== item
        || (!active && !returning) || !result || !result.url) return false
    ghostImageGrab = result
    ghostImageUrl = result.url
    return true
  }

  function move(windowX, windowY) {
    if (!active) return false
    const point = toOutputPoint(windowX, windowY)
    if (!point) return false
    ghostX = point.x - ghostWidth / 2
    ghostY = point.y - ghostHeight / 2
    return updateTarget(targetAtOutput(point.x, point.y))
  }

  function updateTarget(target) {
    const group = target ? String(target.groupId || "") : ""
    const slotTarget = target && target.region !== undefined
    if (!active || !target
        || (group !== "" && group === sourceGroupId)
        || (!slotTarget && !groupExists(group))) {
      targetGroupId = ""
      targetRegion = ""
      targetIndex = -1
      targetItem = null
      return false
    }
    targetGroupId = group
    targetRegion = slotTarget ? String(target.region || "") : ""
    targetIndex = slotTarget ? Math.floor(Number(target.index)) : -1
    targetItem = target.item || null
    return true
  }

  function drop() {
    const source = sourceGroupId
    const target = targetGroupId
    const controller = layoutController
    if (source !== "" && targetRegion !== "" && targetIndex >= 0
        && controller && typeof controller.moveGroupToSlot === "function") {
      const region = targetRegion
      const index = targetIndex
      cancel()
      return controller.moveGroupToSlot(source, region, index)
    }
    if (source !== "" && target !== "" && controller
        && typeof controller.swapGroups === "function") {
      cancel()
      return controller.swapGroups(source, target)
    }
    if (active && sourceItem) {
      active = false
      returning = true
      targetGroupId = ""
      ghostX = ghostHomeX
      ghostY = ghostHomeY
    } else {
      cancel()
    }
    return false
  }

  function finishReturn() {
    if (!returning) return false
    cancel()
    return true
  }

  function cancel() {
    captureGeneration++
    // Disable return Behaviors before resetting their bound coordinates.
    active = false
    returning = false
    sourceGroupId = ""
    targetGroupId = ""
    targetRegion = ""
    targetIndex = -1
    targetItem = null
    sourceItem = null
    sourceWindow = null
    ghostX = 0
    ghostY = 0
    ghostWidth = 0
    ghostHeight = 0
    ghostHomeX = 0
    ghostHomeY = 0
    ghostImageUrl = ""
    ghostImageGrab = null
  }

  Component.onDestruction: {
    cancel()
    targets = []
  }
}
