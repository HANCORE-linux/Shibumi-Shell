.pragma library

function isPanel(item) {
  return !!item
    && typeof item.open === "function"
    && typeof item.close === "function"
    && item.opened !== undefined
}

function childPanel(item, pluginId) {
  if (!item || typeof item.childPanelWidget !== "function") return null
  var child = item.childPanelWidget(pluginId)
  return isPanel(child) ? child : null
}

function panelForSlot(slot, pluginId) {
  if (!slot || !slot.activeItem) return null
  if (slot.moduleName === pluginId && isPanel(slot.activeItem))
    return slot.activeItem
  return childPanel(slot.activeItem, pluginId)
}

function panelWidgets(moduleSlots, pluginId) {
  var id = String(pluginId || "")
  var slots = Array.isArray(moduleSlots) ? moduleSlots : []
  var result = []
  for (var i = 0; i < slots.length; i++) {
    var panel = panelForSlot(slots[i], id)
    if (panel && result.indexOf(panel) === -1) result.push(panel)
  }
  return result
}

function findPanelWidget(moduleSlots, pluginId) {
  var id = String(pluginId || "")
  var slots = Array.isArray(moduleSlots) ? moduleSlots : []
  for (var i = 0; i < slots.length; i++) {
    var panel = panelForSlot(slots[i], id)
    if (panel) return panel
  }
  return null
}

function findPanelWidgetForScreen(moduleSlots, pluginId, screenName) {
  var id = String(pluginId || "")
  var requested = String(screenName || "")
  var slots = Array.isArray(moduleSlots) ? moduleSlots : []
  if (requested !== "") {
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || String(slot.screenName || "") !== requested) continue
      var panel = panelForSlot(slot, id)
      if (panel) return panel
    }
  }
  return findPanelWidget(slots, id)
}
