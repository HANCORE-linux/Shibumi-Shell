pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "plugin" as StatePlugin

ShellRoot {
  id: root

  property int stage: 0
  property int revisionBeforeExternalChange: 0

  QtObject {
    id: fakeShell

    property int writes: 0
    property var shellConfig: ({
      version: 1,
      bar: {
        shibumi: {
          version: 1,
          presentation: { accent: "color02" }
        }
      }
    })

    function mutateShellConfig(mutator) {
      const next = JSON.parse(JSON.stringify(shellConfig))
      mutator(next)
      shellConfig = next
      writes++
    }
  }

  StatePlugin.Service {
    id: state
    shell: fakeShell
  }

  function fail(message) {
    console.error("state-service-smoke:", message)
    Qt.exit(1)
  }

  Timer {
    interval: 20
    running: true
    repeat: true
    onTriggered: {
      if (root.stage === 0) {
        if (!state.ready || state.config.version !== 1
            || state.selectedAccent !== "color02")
          return root.fail("initial normalized state")
        if (state.groupEnabled("G7") || state.groupEnabled("G14")
            || state.groupEnabled("G15"))
          return root.fail("V1 optional group defaults")
        if (!state.setGroupEnabledForVariant("G4", "v1", false)
            || state.groupEnabledForVariant("G4", "v1")
            || !state.groupEnabledForVariant("G4", "v2")
            || state.groupSetting("G4", "enabled", true) === false
            || !state.setGroupEnabledForVariant("G4", "v1", true)
            || !state.groupEnabledForVariant("G4", "v1")
            || state.setGroupEnabledForVariant("G4", "v3", false))
          return root.fail("V1/V2 group activation isolation")
        fakeShell.writes = 0
        if (!state.config.v2Layout
            || state.config.v2Layout.left.length !== 10
            || state.config.v2Layout.center.length !== 1
            || state.config.v2Layout.right.length !== 13
            || state.config.v2Layout.right.indexOf("G18") < 0
            || !Array.isArray(state.config.v2Boundaries)
            || state.config.v2Boundaries.length !== 2)
          return root.fail("V2 slot defaults")
        if (state.setGroupSetting("BAD", "compact", true)
            || fakeShell.writes !== 0)
          return root.fail("invalid group mutation")
        if (!state.setGroupSetting("G4", "compact", true)
            || fakeShell.writes !== 1
            || state.groupSetting("G4", "compact", false) !== true)
          return root.fail("group mutation")
        if (state.setGroupSetting("G4", "compact", true)
            || fakeShell.writes !== 1)
          return root.fail("no-op mutation persisted")
        if (!state.setGroupAppearanceSettingForVariant(
              "G4", "v1", "displayMode", "icon")
            || !state.setGroupAppearanceSettingForVariant(
              "G4", "v2", "displayMode", "text")
            || state.groupAppearanceSettingForVariant(
              "G4", "v1", "displayMode", "") !== "icon"
            || state.groupAppearanceSettingForVariant(
              "G4", "v2", "displayMode", "") !== "text"
            || state.groupSettingsForVariant("G4", "v1").compact !== true
            || state.groupSettingsForVariant("G4", "v2").compact !== false
            || !state.resetGroupAppearanceForVariant("G4", "v1")
            || state.groupAppearanceSettingForVariant(
              "G4", "v1", "displayMode", "") !== "full"
            || state.groupAppearanceSettingForVariant(
              "G4", "v2", "displayMode", "") !== "text")
          return root.fail("V1/V2 appearance isolation")
        root.stage = 1
        return
      }

      if (root.stage === 1) {
        if (!state.setWidgetSetting("G7", "hancore.shibumi.ai", "aiTool", "opencode")
            || state.groupSettings("G7")["hancore.shibumi.ai"].aiTool !== "opencode")
          return root.fail("nested widget mutation")
        if (!state.setPresentationSetting("radius", "small")
            || state.setPresentationSetting("radius", "unsafe")
            || !state.setPresentationSetting("shellStyle", "notch")
            || state.setPresentationSetting("shellStyle", "unsafe")
            || !state.setPresentationSetting("border", false)
            || state.config.presentation.v2Border !== false
            || state.config.presentation.v1Border !== true
            || !state.setPresentationSetting("accent", "color06")
            || state.setPresentationSetting("accent", "unsafe")
            || state.setPresentationSetting("height", "minimal")
            || state.config.presentation.height !== undefined
            || state.config.presentation.radius !== "small"
            || state.config.presentation.shellStyle !== "notch"
            || state.config.presentation.v2ShellStyle !== "notch"
            || state.config.presentation.accent !== "color06")
          return root.fail("presentation mutation validation")
        if (!state.setShellVariant("v1")
            || state.config.presentation.shellStyle !== "shibumi"
            || state.config.presentation.v2ShellStyle !== "notch"
            || !state.setPresentationSetting("border", false)
            || state.config.presentation.v1Border !== false
            || state.config.presentation.v2Border !== false
            || !state.setPresentationSetting("border", true)
            || state.config.presentation.v1Border !== true
            || state.config.presentation.v2Border !== false
            || !state.setShellVariant("v2")
            || state.config.presentation.shellStyle !== "notch"
            || state.config.presentation.v2ShellStyle !== "notch"
            || state.config.presentation.v2Border !== false
            || state.config.presentation.v1Border !== true)
          return root.fail("V1/V2 variant memory")
        if (!state.setImagePickerStyle("tanzaku")
            || !state.setImagePickerStyle("default")
            || state.config.picker.imageStyle !== "omarchy"
            || !state.setMediaPickerStyle("hearthstone")
            || !state.setMediaPickerStyle("default")
            || state.config.picker.mediaStyle !== "carousel"
            || !state.setImagePickerStyle("tanzaku")
            || !state.setMediaPickerStyle("hearthstone")
            || state.setImagePickerStyle("carousel")
            || state.setImagePickerStyle("unknown")
            || state.setMediaPickerStyle("omarchy")
            || !state.setPickerStyle("carousel")
            || state.setPickerStyle("unknown")
            || state.config.picker.imageStyle !== "omarchy"
            || state.config.picker.mediaStyle !== "carousel"
            || state.config.picker.style !== "carousel")
          return root.fail("picker mutation validation")
        if (!state.setWorkspacePreference("mode", "active")
            || state.setWorkspacePreference("mode", "invalid")
            || state.config.workspace.mode !== "active")
          return root.fail("workspace mutation validation")
        const launcherConfig = state.defaultLauncherConfig()
        launcherConfig.mode = "icon"
        launcherConfig.icon = "rebel"
        if (!state.setLauncherConfig(launcherConfig)
            || state.normalizeLauncherConfig(launcherConfig).icon !== "rebel"
            || state.config.launcher.icon !== "rebel")
          return root.fail("launcher configuration contract")
        root.stage = 2
        return
      }

      if (root.stage === 2) {
        const moved = JSON.parse(JSON.stringify(state.config.order))
        const first = moved.left[0]
        moved.left[0] = moved.left[1]
        moved.left[1] = first
        const splits = JSON.parse(JSON.stringify(state.config.splits))
        splits.left[0] = true
        if (!state.setLayout(moved, splits)
            || state.config.order.left[0] !== "G2"
            || state.config.splits.left[0] !== true
            || state.config.v1SlotRoles.left[0] !== "base")
          return root.fail("layout mutation")
        const extended = JSON.parse(JSON.stringify(state.config.order))
        extended.left.push("")
        const extendedSplits = JSON.parse(JSON.stringify(state.config.splits))
        extendedSplits.left.push(false)
        if (!state.setLayout(extended, extendedSplits)
            || state.config.order.left.length !== 8
            || state.config.v1SlotRoles.left[7] !== "extra"
            || state.config.splits.left.length !== 7
            || state.setLayout(extended, splits))
          return root.fail("atomic extended V1 layout mutation")
        if (!state.setGroupSetting("G:custom.widget", "compact", true)
            || !state.setWidgetSetting(
              "G:custom.widget", "custom.widget", "density", "small")
            || state.groupSetting(
              "G:custom.widget", "compact", false) !== true
            || state.groupSettings("G:custom.widget")["custom.widget"].density
              !== "small")
          return root.fail("dynamic V1 group settings")
        if (!state.resetLayout()
            || state.config.order.left[0] !== "G1"
            || state.config.splits.left[0] !== false)
          return root.fail("layout reset")
        const v2Layout = JSON.parse(JSON.stringify(state.config.v2Layout))
        const temperatureIndex = v2Layout.right.indexOf("G16")
        const storageIndex = v2Layout.right.indexOf("G18")
        v2Layout.right[temperatureIndex] = "G18"
        v2Layout.right[storageIndex] = "G16"
        if (!state.toggleGroupSeparator("G16")
            || state.groupSetting("G16", "separator", false) !== true
            || !state.toggleV2Boundary(1)
            || state.config.v2Boundaries[1] !== true
            || state.toggleV2Boundary(2)
            || !state.setAllV2Separators(false)
            || state.groupSetting("G16", "separator", true) !== false
            || state.config.v2Boundaries[1] !== false)
          return root.fail("V2 separator mutation")
        if (!state.setV2Layout(v2Layout)
            || state.config.v2Layout.right[temperatureIndex] !== "G18"
            || !state.resetV2Layout()
            || state.config.v2Layout.right[temperatureIndex] !== "G16"
            || state.groupSetting("G16", "separator", false) !== false
            || state.config.v2Boundaries[1] !== false)
          return root.fail("V2 slot mutation and reset")
        if (!state.setReactorMode(8) || state.setReactorMode(9)
            || state.config.reactor.mode !== 8)
          return root.fail("reactor mutation validation")

        root.revisionBeforeExternalChange = state.revision
        fakeShell.shellConfig = {
          version: 1,
          bar: { shibumi: { version: 1, reactor: { mode: 2 } } }
        }
        root.stage = 3
        return
      }

      if (state.config.reactor.mode !== 2
          || state.config.presentation.radius !== "large"
          || state.config.presentation.accent !== "color01"
          || state.revision <= root.revisionBeforeExternalChange)
        return root.fail("external shell config reactivity")

      stop()
      console.log("state service smoke passed")
      Qt.quit()
    }
  }
}
