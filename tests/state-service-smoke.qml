pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "state" as StatePlugin

ShellRoot {
  id: root
  property int stage: 0
  property int ticks: 0
  property int revisionBeforeExternalChange: 0
  property bool waitingExternal: false
  property var document: null
  property var steps: []
  property var familyPatch: null
  property var familyRollback: null
  property int familyWriteSerial: 0
  property int familyWrites: 0
  property bool waitingFamilyExternal: false
  property bool waitingDenseSettings: false
  function copy(value) { return JSON.parse(JSON.stringify(value)) }
  function check(value, message) {
    if (value) return
    console.error("state-service-smoke:", stage, message)
    Qt.exit(1)
    throw new Error(message)
  }
  function publish(value) { document = value; writer.setText(JSON.stringify(value)) }
  function appearance(group, variant, key) { return state.groupAppearanceSettingForVariant(group, variant, key, "") }
  QtObject {
    id: fakeShell
    readonly property string pluginId: "hancore.shibumi.state"
    property int writes: 0
    // Poisoned legacy publication must not replace canonical file truth.
    property var shellConfig: ({bar: {shibumi: {version: 1, presentation: {accent: "color07"}}}})
    property var barConfig: shellConfig.bar
    function updateEntryInline(id, entry) {
      root.check(id === pluginId && entry.id === pluginId, "foreign entry write")
      const next = root.copy(root.document)
      if (JSON.stringify(next.plugins[0]) === JSON.stringify(entry)) return false
      next.plugins[0] = entry
      writes++
      root.publish(next)
      return true
    }
    function mutateShellConfig(callback) { root.check(false, "legacy Bar writer was used"); return false }
  }
  FileView {
    id: writer
    path: Quickshell.env("XDG_CONFIG_HOME") + "/omarchy/shell.json"
    atomicWrites: true
    onLoaded: root.document = JSON.parse(text())
  }
  StatePlugin.Service {
    id: state
    omarchyPath: Quickshell.env("OMARCHY_PATH")
    shell: fakeShell
    manifest: ({id: "hancore.shibumi.state", version: "0.1.1-beta.14", kinds: ["service"]})
  }
  Component.onCompleted: steps = [
    function() {
      check(state.selectedAccent === "color02" && state.config.version === 1, "initial canonical state")
      check(!state.groupEnabled("G7") && !state.groupEnabled("G14") && !state.groupEnabled("G15"), "optional defaults")
      check(state.config.v2Layout.left.length === 10 && state.config.v2Layout.center.length === 1
        && state.config.v2Layout.right.length === 13 && state.config.v2Layout.right.indexOf("G18") >= 0
        && state.config.v2Boundaries.length === 2, "V2 defaults")
      check(!state.setGroupSetting("BAD", "compact", true) && !state.setGroupEnabledForVariant("G4", "v3", false), "invalid group/variant")
      check(!state.setWidgetSetting("G4", "example.widget", "number", Infinity), "non-finite setter accepted")
      check(state.setGroupEnabledForVariant("G4", "v1", false), "V1 disable queue")
      check(state.groupEnabledForVariant("G4", "v1")
        && !state.requestedGroupEnabledForVariant("G4", "v1")
        && fakeShell.writes === 0,
        "requested activation preview changed authoritative publication")
    }, function() {
      check(!state.groupEnabledForVariant("G4", "v1") && state.groupEnabledForVariant("G4", "v2")
        && state.groupSetting("G4", "enabled", true), "activation isolation")
      check(state.setGroupEnabledForVariant("G4", "v1", true), "V1 restore")
      check(state.setGroupsEnabledForAllVariants(["G6", "G8"], false), "bulk disable")
      check(!state.setGroupsEnabledForAllVariants(["G6", "G8"], false)
        && !state.setGroupsEnabledForAllVariants(["BAD"], true), "duplicate/invalid bulk request")
    }, function() {
      check(fakeShell.writes === 2 && !state.groupEnabledForVariant("G6", "v1")
        && !state.groupEnabledForVariant("G6", "v2") && !state.groupEnabledForVariant("G8", "v1")
        && !state.groupEnabledForVariant("G8", "v2"), "coalesced cross-variant write")
      check(state.setGroupVariantStates({G6: {v1: true, v2: false}, G8: {v1: false, v2: true}}), "mixed variants")
      check(!state.setGroupVariantStates({G6: {v1: true}}), "incomplete variants")
    }, function() {
      check(state.groupEnabledForVariant("G6", "v1") && !state.groupEnabledForVariant("G6", "v2")
        && !state.groupEnabledForVariant("G8", "v1") && state.groupEnabledForVariant("G8", "v2"), "mixed publication")
      check(state.setGroupsEnabledForAllVariants(["G6", "G8"], true), "bulk restore")
      check(!state.config.layoutProtection.v1 && !state.config.layoutProtection.v2, "protection defaults")
      check(state.setLayoutProtection("v1", true) && !state.setLayoutProtection("v1", true)
        && state.setLayoutProtection("v2", true) && state.setLayoutProtection("v2", false)
        && !state.setLayoutProtection("v3", true) && !state.setLayoutProtection("v1", "true"), "protection queue validation")
      check(state.setGroupSetting("G4", "compact", true) && !state.setGroupSetting("G4", "compact", true), "compact/no-op")
    }, function() {
      check(state.config.layoutProtection.v1 && !state.config.layoutProtection.v2
        && state.groupSetting("G4", "compact", false), "protection/compact publication")
      check(state.setGroupAppearanceSettingForVariant("G4", "v1", "displayMode", "icon")
        && state.setGroupAppearanceSettingForVariant("G4", "v2", "displayMode", "text")
        && state.setGroupAppearanceSettingForVariant("G:hancore.shibumi.storage", "v1", "displayMode", "icon"), "appearance queue")
    }, function() {
      check(appearance("G4", "v1", "displayMode") === "icon" && appearance("G4", "v2", "displayMode") === "text"
        && state.groupSettingsForVariant("G4", "v1").compact && !state.groupSettingsForVariant("G4", "v2").compact
        && appearance("G:hancore.shibumi.storage", "v1", "displayMode") === "icon"
        && appearance("G:hancore.shibumi.storage", "v2", "displayMode") === "full", "appearance isolation")
      check(state.resetGroupAppearanceForVariant("G4", "v1"), "local appearance reset")
    }, function() {
      check(appearance("G4", "v1", "displayMode") === "full" && appearance("G4", "v2", "displayMode") === "text", "local reset publication")
      check(state.setGroupAppearanceSettingForVariant("G4", "v1", "color", "color05")
        && state.setGroupAppearanceSettingForVariant("G9", "v1", "mediaStyle", "full")
        && state.setGroupSetting("G5", "color", "color06") && state.setGroupSetting("G4", "separator", true), "global reset setup")
    }, function() {
      check(state.resetAllGroupAppearancesForVariant("v1") && !state.resetAllGroupAppearancesForVariant("v3"), "V1 global reset")
    }, function() {
      check(appearance("G4", "v1", "color") === "inherit" && appearance("G9", "v1", "mediaStyle") === "default"
        && appearance("G5", "v1", "color") === "inherit" && appearance("G5", "v2", "color") === "color06"
        && appearance("G:hancore.shibumi.storage", "v1", "displayMode") === "full"
        && appearance("G4", "v2", "displayMode") === "text" && state.groupSetting("G4", "separator", false), "V1 global reset isolation")
      check(state.setGroupAppearanceSettingForVariant("G4", "v1", "color", "color04")
        && state.setGroupAppearanceSettingForVariant("G9", "v2", "mediaStyle", "full")
        && state.setGroupAppearanceSettingForVariant("G18", "v2", "widgetRadius", "round"), "V2 reset setup")
    }, function() {
      check(state.resetAllGroupAppearancesForVariant("v2"), "V2 global reset")
    }, function() {
      check(appearance("G4", "v2", "displayMode") === "full" && appearance("G5", "v2", "color") === "inherit"
        && appearance("G9", "v2", "mediaStyle") === "default" && appearance("G18", "v2", "widgetRadius") === "auto"
        && appearance("G4", "v1", "color") === "color04" && state.groupSetting("G4", "separator", false), "V2 global reset isolation")
      check(state.setWidgetSetting("G7", "hancore.shibumi.ai", "aiTool", "opencode"), "nested settings")
      check(state.requestedGroupSettings("G7")["hancore.shibumi.ai"].aiTool
        === "opencode" && !state.groupSettings("G7")["hancore.shibumi.ai"],
        "nested selection request was not previewed independently")
      check(state.setPresentationSetting("radius", "small") && !state.setPresentationSetting("radius", "unsafe")
        && state.setPresentationSetting("shellStyle", "notch") && !state.setPresentationSetting("shellStyle", "unsafe")
        && state.setPresentationSetting("border", false) && state.setPresentationSetting("accent", "color06")
        && !state.setPresentationSetting("accent", "unsafe") && !state.setPresentationSetting("height", "minimal"), "presentation validation")
    }, function() {
      check(state.groupSettings("G7")["hancore.shibumi.ai"].aiTool === "opencode"
        && state.config.presentation.radius === "small" && state.config.presentation.shellStyle === "notch"
        && state.config.presentation.v2ShellStyle === "notch" && !state.config.presentation.v2Border
        && state.config.presentation.v1Border && state.config.presentation.accent === "color06"
        && state.config.presentation.height === undefined, "presentation publication")
      check(state.setShellVariant("v1") && state.setPresentationSetting("border", false), "V1 variant queue")
    }, function() {
      check(state.config.presentation.shellStyle === "shibumi" && state.config.presentation.v2ShellStyle === "notch"
        && !state.config.presentation.v1Border && !state.config.presentation.v2Border, "V1 memory")
      check(state.setPresentationSetting("border", true) && state.setShellVariant("v2"), "V2 return queue")
    }, function() {
      check(state.config.presentation.shellStyle === "notch" && state.config.presentation.v1Border
        && !state.config.presentation.v2Border, "V2 memory")
      check(state.setImagePickerStyle("tanzaku") && state.setMediaPickerStyle("hearthstone"), "separate picker queue")
    }, function() {
      check(state.config.picker.imageStyle === "tanzaku" && state.config.picker.mediaStyle === "hearthstone", "picker isolation")
      check(state.setImagePickerStyle("default") && state.setMediaPickerStyle("default")
        && !state.setImagePickerStyle("carousel") && !state.setImagePickerStyle("unknown")
        && !state.setMediaPickerStyle("omarchy") && !state.setPickerStyle("unknown"), "picker validation/default aliases")
    }, function() {
      check(state.config.picker.imageStyle === "omarchy" && state.config.picker.mediaStyle === "carousel", "picker aliases publication")
      check(state.setPickerStyle("hearthstone"), "combined picker queue")
    }, function() {
      check(state.config.picker.imageStyle === "hearthstone" && state.config.picker.mediaStyle === "hearthstone", "combined picker publication")
      check(state.setPickerStyle("carousel") && state.setWorkspacePreference("mode", "active")
        && !state.setWorkspacePreference("mode", "invalid"), "picker/workspace validation")
      check(state.requestedConfig.workspace.mode === "active"
        && state.config.workspace.mode !== "active",
        "workspace request was not previewed before readback")
      const launcher = state.defaultLauncherConfig(); launcher.mode = "icon"; launcher.icon = "rebel"; launcher.text = "omarchy"
      check(state.setLauncherConfig(launcher) && state.normalizeLauncherConfig(launcher).icon === "rebel"
        && state.requestedConfig.launcher.icon === "rebel"
        && state.config.launcher.icon !== "rebel", "launcher queue/preview")
    }, function() {
      check(state.config.workspace.mode === "active" && state.config.launcher.icon === "rebel" && state.config.launcher.text === "omarchy"
        && state.config.picker.style === "carousel", "workspace/launcher publication")
      const order = copy(state.config.order); const first = order.left[0]; order.left[0] = order.left[1]; order.left[1] = first
      const splits = copy(state.config.splits); splits.left[0] = true
      check(state.setLayout(order, splits), "layout swap queue")
    }, function() {
      check(state.config.order.left[0] === "G2" && state.config.splits.left[0] && state.config.v1SlotRoles.left[0] === "base", "layout swap publication")
      const order = copy(state.config.order); order.left.push("")
      const splits = copy(state.config.splits); splits.left.push(false)
      check(state.setLayout(order, splits) && !state.setLayout(order, state.config.splits), "extra layout validation")
    }, function() {
      check(state.config.order.left.length === 8 && state.config.v1SlotRoles.left[7] === "extra" && state.config.splits.left.length === 7, "extra layout publication")
      const order = copy(state.config.order); order.center.push("")
      check(state.setLayout(order, state.config.splits), "second center queue")
    }, function() {
      check(state.config.order.center.length === 2 && state.config.v1SlotRoles.center[1] === "extra"
        && document.plugins[0].shibumi.order.center.length === 2 && state.config.v2Layout.center.length === 1, "persisted second center")
      const order = copy(state.config.order); order.center.push("")
      check(!state.setLayout(order, state.config.splits), "third center allowed")
      check(state.setGroupSetting("G:custom.widget", "compact", true)
        && state.setWidgetSetting("G:custom.widget", "custom.widget", "density", "small"), "dynamic deep settings queue")
    }, function() {
      check(state.groupSetting("G:custom.widget", "compact", false)
        && state.groupSettings("G:custom.widget")["custom.widget"].density === "small", "dynamic deep settings publication")
      check(state.resetLayout(), "V1 layout reset queue")
    }, function() {
      check(state.config.order.left[0] === "G1" && !state.config.splits.left[0] && state.config.order.center.length === 1, "V1 layout reset publication")
      check(state.toggleGroupSeparator("G16") && state.toggleV2Boundary(1) && !state.toggleV2Boundary(2), "V2 separator validation")
    }, function() {
      check(state.groupSetting("G16", "separator", false) && state.config.v2Boundaries[1], "V2 separators publication")
      check(state.setAllV2Separators(false), "V2 separators reset queue")
      const layout = copy(state.config.v2Layout)
      const a = layout.right.indexOf("G16"), b = layout.right.indexOf("G18")
      layout.right[a] = "G18"; layout.right[b] = "G16"
      check(state.setV2Layout(layout), "V2 layout swap queue")
    }, function() {
      check(!state.groupSetting("G16", "separator", true) && !state.config.v2Boundaries[1]
        && state.config.v2Layout.right.indexOf("G18") < state.config.v2Layout.right.indexOf("G16"), "V2 layout swap publication")
      check(state.resetV2Layout() && state.setReactorMode(8) && !state.setReactorMode(9), "V2 reset/reactor queue")
    }, function() {
      check(state.config.v2Layout.right.indexOf("G16") < state.config.v2Layout.right.indexOf("G18")
        && state.config.reactor.mode === 8 && state.config.layoutProtection.v1 && !state.config.layoutProtection.v2, "reset/reactor retained settings")
      let deep = document.plugins[0].deepFuture
      let widgetDeep = document.plugins[0].shibumi.widgets.G4.futureDeep
      for (let i = 0; i < 70; i++) {
        check(deep && deep.nested && widgetDeep && widgetDeep.nested, "unknown nested settings lost")
        deep = deep.nested; widgetDeep = widgetDeep.nested
      }
      check(JSON.stringify(deep) === '{"leaf":[false,0,"Malmö"]}' && JSON.stringify(widgetDeep) === JSON.stringify(deep), "deep settings lost")
      const saved = document.plugins[0].shibumi
      check(JSON.stringify(saved.futureState) === JSON.stringify({nested: [false, "Malmö", {n: 0}]})
        && JSON.stringify(saved.presentation.futurePresentation) === JSON.stringify({v: [1, 2]})
        && saved.layoutProtection.futureVariant === true, "unknown nested settings lost")
      revisionBeforeExternalChange = state.revision
      const next = copy(document); next.plugins[0].shibumi = {version: 1, reactor: {mode: 2}}
      waitingExternal = true
      publish(next)
    }, function() {
      check(state.config.reactor.mode === 2 && state.config.presentation.radius === "large"
        && state.selectedAccent === "color01" && !state.config.layoutProtection.v1 && !state.config.layoutProtection.v2
        && state.revision > revisionBeforeExternalChange, "external canonical reactivity")
      check(document.plugins[0].foreign.deep[0] === false && document.plugins[1].opaque.value === 42, "foreign field preservation")
    }, function() {
      const v1 = copy(state.config.order)
      const first = v1.left[0]; v1.left[0] = v1.left[1]; v1.left[1] = first
      const v2 = copy(state.config.v2Layout)
      const head = v2.left[0]; v2.left[0] = v2.left[1]; v2.left[1] = head
      familyPatch = {v1Layout: {order: v1, splits: copy(state.config.splits)},
        v2Layout: v2, v2Boundaries: [true, false], separators: {G1: null, G2: true, G3: false},
        familyStates: {G6: {v1: false, v2: true}, G7: {v1: null, v2: false}}}
      familyRollback = state.layoutFamilySnapshot(familyPatch)
      check(familyRollback && familyRollback.familyStates.G7.v1 === null
        && familyRollback.separators.G2 === null, "transition snapshot lost absent fields")
      const serial = state.writeSerial, writes = fakeShell.writes, before = copy(state.config)
      const badLayout = copy(v2); badLayout.left[0] = null
      const badV1 = copy(v1); badV1.center.push(false)
      for (const invalid of [null, [], {}, {unknown: true}, {familyStates: {}},
          {v1Layout: {order: v1}}, {v1Layout: {order: badV1, splits: state.config.splits}},
          {v1Layout: {order: v1, splits: {left: [], right: [], boundaries: []}}},
          {v2Layout: badLayout}, {v2Layout: Object.assign({}, v2, {extra: []})},
          {v2Boundaries: [true]}, {v2Boundaries: [true, 1]},
          {separators: {G2: "true"}}, {separators: {BAD: true}},
          {familyStates: {G6: {v1: true}}},
          {familyStates: {G6: {v1: true, v2: false, extra: true}}}])
        check(!state.setLayoutFamilyTransition(invalid), "invalid transition admitted")
      check(state.writeSerial === serial && fakeShell.writes === writes && !state.writePending,
        "invalid transition changed queue")
      familyWrites = writes
      check(state.setLayoutFamilyTransition(familyPatch), "atomic transition refused")
      familyWriteSerial = state.writeSerial
      check(familyWriteSerial === serial + 1 && fakeShell.writes === writes && state.writePending
        && state.same(state.config, before), "atomic transition published before readback")
    }, function() {
      check(fakeShell.writes === familyWrites + 1
        && state.same(state.layoutFamilySnapshot(familyPatch), familyPatch), "atomic transition did not publish together")
      check(document.plugins[0].foreign.deep[0] === false && document.plugins[1].opaque.value === 42
        && state.config.reactor.mode === 2 && !state.groupSetting("G7", "enabled", true), "transition lost unrelated settings")
      check(!state.compensateLayoutFamilyTransition(String(familyWriteSerial), familyPatch, familyRollback)
        && !state.compensateLayoutFamilyTransition(true, familyPatch, familyRollback), "invalid compensation serial admitted")
      const wrongScope = copy(familyRollback); delete wrongScope.familyStates.G7
      check(!state.compensateLayoutFamilyTransition(familyWriteSerial, familyPatch, wrongScope),
        "compensation accepted different fields")
      check(state.compensateLayoutFamilyTransition(familyWriteSerial, familyPatch, familyRollback),
        "conditional compensation refused")
      check(state.same(state.layoutFamilySnapshot(familyPatch), familyPatch), "compensation published optimistically")
    }, function() {
      check(fakeShell.writes === familyWrites + 2
        && state.same(state.layoutFamilySnapshot(familyPatch), familyRollback)
        && !Object.prototype.hasOwnProperty.call(state.groupSettings("G2"), "separator")
        && !Object.prototype.hasOwnProperty.call(state.groupSettings("G7"), "enabledV2"),
        "compensation failed to restore layout or field absence")
      check(state.setLayoutFamilyTransition(familyPatch), "second atomic transition refused")
      familyWriteSerial = state.writeSerial
    }, function() {
      check(state.setReactorMode(3), "intervening scalar write refused")
      check(!state.compensateLayoutFamilyTransition(familyWriteSerial, familyPatch, familyRollback),
        "compensation ignored pending write")
    }, function() {
      const serial = state.writeSerial
      check(serial > familyWriteSerial && state.config.reactor.mode === 3, "intervening write not confirmed")
      check(!state.compensateLayoutFamilyTransition(familyWriteSerial, familyPatch, familyRollback)
        && state.writeSerial === serial, "compensation ignored newer serial")
      familyWriteSerial = serial
      const next = copy(document)
      next.plugins[0].shibumi.widgets.G2.separator = false
      waitingFamilyExternal = true
      publish(next)
    }, function() {
      check(state.writeSerial === familyWriteSerial
        && !state.compensateLayoutFamilyTransition(familyWriteSerial, familyPatch, familyRollback),
        "compensation overwrote intervening file publication")
      check(!state.writePending && state.config.reactor.mode === 3
        && state.groupSettings("G2").separator === false, "compensation changed newer user settings")
      const next = copy(document)
      next.plugins[0].shibumi.widgets.G5 = {}
      for (let i = 0; i < 128; i++) next.plugins[0].shibumi.widgets.G5["field" + i] = i
      waitingDenseSettings = true
      publish(next)
    }, function() {
      const serial = state.writeSerial, writes = fakeShell.writes, before = copy(state.config)
      check(!state.setLayoutFamilyTransition({v2Boundaries: [false, true], familyStates: {G5: {v1: false, v2: false}}}),
        "normalization admitted a partial transition")
      check(state.writeSerial === serial && fakeShell.writes === writes && !state.writePending
        && state.same(state.config, before), "refused partial transition changed state")
      console.log("atomic layout-family State patch and conditional compensation passed")
    }
  ]
  Timer {
    interval: 10; repeat: true; running: true
    onTriggered: {
      if (++root.ticks > 1000) root.check(false, "deadline " + state.writeStatus)
      if (!state.ready || !root.document || state.writePending) return
      if (root.waitingDenseSettings) {
        if (Object.keys(state.groupSettings("G5")).length !== 128) return
        root.waitingDenseSettings = false
      }
      if (root.waitingFamilyExternal) {
        if (state.groupSettings("G2").separator !== false) return
        root.waitingFamilyExternal = false
      }
      if (root.waitingExternal) {
        if (state.config.reactor.mode !== 2) return
        root.waitingExternal = false
      }
      root.check(["idle", "unavailable", "confirmed", "unchanged"].indexOf(state.writeStatus) >= 0, "unsettled/failed write " + state.writeStatus)
      if (root.stage < root.steps.length) { root.steps[root.stage++](); return }
      console.log("state service smoke passed")
      Qt.exit(0)
    }
  }
}
