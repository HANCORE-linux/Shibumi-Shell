import QtQuick
import "../core/GroupRegistry.js" as GroupRegistry
import "../core/ShibumiConfig.js" as ShibumiConfig
import "../core/WidgetFamilies.js" as WidgetFamilies
import "../core/LayoutModel.js" as LayoutModel

QtObject {
  function fail(message) {
    console.error("group-registry-regression:", message)
    Qt.exit(1)
    // Qt.exit schedules shutdown; abort this stack before the success exit.
    throw new Error(message)
  }

  Component.onCompleted: {
    if (JSON.stringify(GroupRegistry.GroupIds) !== JSON.stringify(ShibumiConfig.GroupIds))
      fail("group registry/config ids diverged")

    const layout = {
      left: [
        { id: "omarchy.clock", format: "HH:mm" },
        { id: "omarchy.workspaces" },
        { id: "custom.left", value: 7 }
      ],
      center: [{ id: "omarchy.menu" }],
      right: [
        { id: "omarchy.microphone", compact: true },
        { id: "omarchy.tailscale" }
      ]
    }
    const g4 = GroupRegistry.entriesFor("G4", { compact: true }, layout)
    const g7 = GroupRegistry.entriesFor("G7", {
      enabled: false,
      enabledV2: true,
      compact: true
    }, layout)
    const g3 = GroupRegistry.entriesFor("G3", {}, layout)
    const g6 = GroupRegistry.entriesFor("G6", {
      compact: true,
      "omarchy.microphone": { compact: false }
    }, layout)
    const g8 = GroupRegistry.entriesFor("G8", {}, layout)
    const g9 = GroupRegistry.entriesFor("G9", {}, layout)
    const g10 = GroupRegistry.entriesFor("G10", {}, layout)
    const clockSettings = GroupRegistry.childSettingsFor({}, layout,
      "omarchy.clock")
    const g11 = GroupRegistry.entriesFor("G11", { compact: true }, layout)
    const g13 = GroupRegistry.entriesFor("G13", { compact: true }, layout)
    const g12 = GroupRegistry.entriesFor("G12", { compact: true }, layout)
    const g14 = GroupRegistry.entriesFor("G14", { compact: true }, layout)
    const g15 = GroupRegistry.entriesFor("G15", { compact: true }, layout)
    const optionalLayout = {
      left: layout.left,
      center: layout.center,
      right: layout.right.concat([{ id: "omarchy.active-window", compact: true }])
    }
    const g8WithOptional = GroupRegistry.entriesFor("G8", {
      "omarchy.clock": { format: "local" }
    }, optionalLayout)
    const localClockSettings = GroupRegistry.childSettingsFor({
      "omarchy.clock": { format: "local" }
    }, layout, "omarchy.clock")
    const optionalOwners = {
      "omarchy.dropbox": "G3",
      "omarchy.microphone": "G6",
      "omarchy.active-window": "G8",
      "omarchy.keyboard-layout": "G8",
      "omarchy.tailscale": "G11"
    }
    const optionalIds = Object.keys(optionalOwners)
    for (let index = 0; index < optionalIds.length; index++) {
      const id = optionalIds[index]
      const owner = optionalOwners[id]
      const plainLayout = {
        left: [{ id: id }], center: [], right: []
      }
      const explicitLayout = {
        left: [{ id: id, shibumiModule: true }], center: [], right: []
      }
      const mixedLayout = {
        left: [{ id: id }, { id: id, shibumiModule: true }],
        center: [], right: []
      }
      const dynamicGroup = GroupRegistry.dynamicGroupIdForModule(id)
      if (!GroupRegistry.isOptionalModule(id)
          || GroupRegistry.moduleIdsFor(owner, plainLayout).indexOf(id) < 0
          || GroupRegistry.unassignedEntries(plainLayout, "left").length !== 0
          || GroupRegistry.moduleIdsFor(owner, explicitLayout).indexOf(id) >= 0
          || GroupRegistry.unassignedEntries(
            explicitLayout, "left").length !== 1
          || GroupRegistry.moduleIdsFor(
            dynamicGroup, explicitLayout).indexOf(id) < 0
          || GroupRegistry.moduleIdsFor(owner, mixedLayout).indexOf(id) >= 0)
        fail("optional/dynamic ownership exclusivity for " + id)
    }
    if (GroupRegistry.isOptionalModule("omarchy.clock"))
      fail("consumed alias classified as optional")

    const familyOwners = {
      "omarchy.workspaces": ["G2"],
      "omarchy.indicators": ["G3"],
      "omarchy.tray": ["G3"],
      "omarchy.audio": ["G6"],
      "omarchy.agents": ["G7"],
      "omarchy.model-usage": ["G7"],
      "omarchy.clock": ["G8"],
      "omarchy.weather": ["G8"],
      "omarchy.system-update": ["G8"],
      "omarchy.media": ["G9"],
      "omarchy.network": ["G11"],
      "omarchy.power": ["G12", "G14"],
      "omarchy.monitor": ["G13"],
      "omarchy.bluetooth": ["G15"]
    }
    const familyIds = Object.keys(familyOwners)
    for (let index = 0; index < familyIds.length; index++) {
      const id = familyIds[index]
      const groups = WidgetFamilies.familiesForPlugin(id, null).map(
        function(family) { return family.group })
      if (JSON.stringify(groups) !== JSON.stringify(familyOwners[id]))
        fail("provider family ownership for " + id)
    }
    if (WidgetFamilies.familiesForPlugin("custom.left", null).length !== 0
        || WidgetFamilies.replacementLabel("omarchy.power", null)
          !== "Replaces Shibumi Battery and Shibumi Power Profile")
      fail("provider family fallback/multi-group label")

    const fullOrder = LayoutModel.defaultOrder()
    fullOrder.left.push("G:custom.one", "G:custom.two")
    fullOrder.right.push("G:custom.three", "G:custom.four")
    const fullBefore = JSON.stringify(fullOrder)
    const familyBindings = WidgetFamilies.v1SlotBindings([
      { pluginId: "custom.one" }, { pluginId: "custom.two" },
      { pluginId: "custom.three" }, { pluginId: "custom.four" },
      { pluginId: "omarchy.audio" }, { pluginId: "omarchy.clock" },
      { pluginId: "omarchy.weather" }, { pluginId: "omarchy.power" },
      { pluginId: "omarchy.power" }
    ], fullOrder, null)
    if (familyBindings.G6 !== "omarchy.audio"
        || familyBindings.G8 !== "omarchy.clock"
        || familyBindings.G12 !== "omarchy.power"
        || Object.keys(familyBindings).length !== 3
        || JSON.stringify(fullOrder) !== fullBefore
        || LayoutModel.maxCount("left") !== 9
        || LayoutModel.maxCount("center") !== 2
        || LayoutModel.maxCount("right") !== 9)
      fail("slot-neutral family projection changed order or slot limits")
    const legacyOrder = LayoutModel.defaultOrder()
    legacyOrder.right.push("G:omarchy.clock")
    if (Object.keys(WidgetFamilies.v1SlotBindings(
          [{ pluginId: "omarchy.clock" }], legacyOrder, null)).length !== 0)
      fail("existing dynamic placement was silently migrated")
    const declaredBindings = WidgetFamilies.v1SlotBindings([
      { pluginId: "example.audio" }
    ], fullOrder, { installedPlugins: {
      "example.audio": { barWidget: { semanticCapabilities: ["audio"] } }
    } })
    if (declaredBindings.G6 !== "example.audio")
      fail("declared compatible provider did not reuse its family slot")
    const cloneRegistry = { installedPlugins: {
      "omarchy.clock": {},
      "local.clock": { omarchy: { clonedFrom: "omarchy.clock" } },
      "local.nested": { omarchy: { clonedFrom: "local.clock" } },
      "local.a": { omarchy: { clonedFrom: "local.b" } },
      "local.b": { omarchy: { clonedFrom: "local.a" } },
      "local.missing": { omarchy: { clonedFrom: "omarchy.absent" } },
      "local.inherited": { omarchy: { clonedFrom: "constructor" } }
    } }
    if (WidgetFamilies.v1SlotBindings([{ pluginId: "local.clock" }],
          fullOrder, cloneRegistry).G8 !== "local.clock"
        || JSON.stringify(WidgetFamilies.capabilitiesForPlugin("local.nested", cloneRegistry))
          !== '["clock"]')
      fail("clone family did not follow the installed source manifest")
    for (const id of ["local.a", "local.b", "local.missing", "local.inherited", "constructor"]) {
      if (WidgetFamilies.capabilitiesForPlugin(id, cloneRegistry).length !== 0)
        fail("cyclic, absent or inherited clone source acquired family authority")
    }
    const deepRegistry = { installedPlugins: { "omarchy.clock": {} } }
    for (let i = 0; i < 33; i++)
      deepRegistry.installedPlugins["local.depth" + i] = {
        omarchy: { clonedFrom: i === 32 ? "omarchy.clock" : "local.depth" + (i + 1) }
      }
    if (WidgetFamilies.capabilitiesForPlugin("local.depth0", deepRegistry).length !== 0)
      fail("clone family source traversal was not bounded")
    if (Object.keys(WidgetFamilies.v1SlotBindings([
          null, { pluginId: "Invalid Plugin" }, { pluginId: "custom.generic" }
        ], fullOrder, null)).length !== 0)
      fail("invalid or unrelated provider acquired a fixed family slot")

    if (g3.length !== 1 || g3[0].id !== "hancore.shibumi.status")
      fail("status presentation ownership")
    if (g4.length !== 1 || g4[0].id !== "hancore.shibumi.memory"
        || g4[0].compact !== true)
      fail("single-module group settings")
    if (g6.length !== 2 || g6[0].id !== "hancore.shibumi.audio"
        || g6[0].compact !== true || g6[1].id !== "omarchy.microphone"
        || g6[1].compact !== false)
      fail("optional module settings precedence")
    if (g7.length !== 1 || g7[0].id !== "hancore.shibumi.ai"
        || g7[0].enabled !== undefined || g7[0].enabledV2 !== undefined
        || g7[0].compact !== true)
      fail("variant group activation leaked into the module loader")
    if (g8.length !== 1 || g8[0].id !== "hancore.shibumi.center"
        || clockSettings.format !== "HH:mm")
      fail("center ownership/host child settings")
    if (g9.length !== 1 || g9[0].id !== "hancore.shibumi.media")
      fail("media service presentation ownership")
    if (g10.length !== 1 || g10[0].id !== "hancore.shibumi.quick-access")
      fail("quick-access presentation ownership")
    if (g11.length !== 2 || g11[0].id !== "hancore.shibumi.network"
        || g11[0].compact !== true
        || g11[1].id !== "omarchy.tailscale")
      fail("configured optional group module")
    if (g13.length !== 1 || g13[0].id !== "hancore.shibumi.brightness"
        || g13[0].compact !== true)
      fail("brightness presentation ownership/settings")
    if (g12.length !== 1 || g12[0].id !== "hancore.shibumi.battery"
        || g12[0].compact !== true)
      fail("battery presentation ownership/settings")
    if (g14.length !== 1 || g14[0].id !== "hancore.shibumi.power-profile"
        || g14[0].compact !== true)
      fail("power-profile presentation ownership/settings")
    if (g15.length !== 1 || g15[0].id !== "hancore.shibumi.bluetooth"
        || g15[0].compact !== true)
      fail("bluetooth presentation ownership/settings")
    if (g8WithOptional.length !== 2
        || g8WithOptional[0].id !== "hancore.shibumi.center"
        || g8WithOptional[1].id !== "omarchy.active-window"
        || localClockSettings.format !== "local")
      fail("center optional sibling/local child settings")
    if (GroupRegistry.entriesFor("G99", {}, layout).length !== 0)
      fail("invalid group contract")

    const assigned = GroupRegistry.assignedModuleIds()
    const seen = {}
    for (let i = 0; i < assigned.length; i++) {
      if (seen[assigned[i]]) fail("duplicate module owner " + assigned[i])
      seen[assigned[i]] = true
    }
    if (!GroupRegistry.isAssignedModule("omarchy.menu")
        || !GroupRegistry.isAssignedModule("omarchy.workspaces")
        || !GroupRegistry.isAssignedModule("omarchy.agents")
        || !GroupRegistry.isAssignedModule("omarchy.model-usage")
        || !GroupRegistry.isAssignedModule("omarchy.audio")
        || !GroupRegistry.isAssignedModule("omarchy.media")
        || !GroupRegistry.isAssignedModule("omarchy.system-update")
        || !GroupRegistry.isAssignedModule("omarchy.tray")
        || !GroupRegistry.isAssignedModule("omarchy.notifications")
        || !GroupRegistry.isAssignedModule("omarchy.network")
        || !GroupRegistry.isAssignedModule("omarchy.monitor")
        || !GroupRegistry.isAssignedModule("omarchy.bluetooth")
        || !GroupRegistry.isAssignedModule("omarchy.power")
        || !GroupRegistry.isAssignedModule("omarchy.weather")
        || !GroupRegistry.isAssignedModule("omarchy.clock")
        || !GroupRegistry.isAssignedModule("omarchy.indicators")
        || GroupRegistry.isAssignedModule("custom.left"))
      fail("consumed/unassigned classification")
    const extras = GroupRegistry.unassignedEntries(layout, "left")
    if (extras.length !== 1 || extras[0].id !== "custom.left"
        || extras[0].value !== 7)
      fail("custom host widget preservation")
    const dynamicId = GroupRegistry.dynamicGroupIdForModule("custom.left")
    const dynamicEntries = GroupRegistry.entriesFor(
      dynamicId, { compact: true }, layout)
    if (dynamicId !== "G:custom.left"
        || GroupRegistry.dynamicModuleIdForGroup(dynamicId) !== "custom.left"
        || dynamicEntries.length !== 1
        || dynamicEntries[0].id !== "custom.left"
        || dynamicEntries[0].value !== 7
        || dynamicEntries[0].compact !== true
        || GroupRegistry.dynamicGroupIdForModule("Invalid Plugin") !== ""
        || GroupRegistry.entriesFor("G:missing.plugin", {}, layout).length !== 0)
      fail("dynamic plugin group ownership/settings")

    console.log("group registry regression passed")
    Qt.exit(0)
  }
}
