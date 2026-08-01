import QtQuick
import "../core/GroupRegistry.js" as GroupRegistry
import "../core/ShibumiConfig.js" as ShibumiConfig

QtObject {
  function fail(message) {
    console.error("group-registry-regression:", message)
    Qt.exit(1)
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
    const g7 = GroupRegistry.entriesFor("G7",
      ShibumiConfig.defaultConfig().widgets.G7, layout)
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
        || g7[0].enabled !== false)
      fail("optional group default visibility")
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
