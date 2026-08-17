import QtQuick
import Quickshell

ShellRoot {
  id: root

  property int attempts: 0
  property int stage: 0
  property int screensaverStage: 0
  property var retainedItems: []
  property var inlineStateItem: null
  property var inlineStateSlot: null
  property string commandMarker: testCommandMarker

  function fail(message) {
    console.error("bar-host-registry-smoke:", message)
    Qt.exit(1)
  }

  function verifyTransparencyContract() {
    const trueBarConfig = JSON.parse(JSON.stringify(hostBar.barConfig))
    const trueStoredConfig = JSON.stringify(fakeShell.shellConfig)
    if (trueBarConfig.transparent !== true
        || fakeShell.shellConfig.bar.transparent !== true) {
      fail("enabled stock transparency preference was not present in the fixture")
      return false
    }

    hostBar.applyBarConfig()
    hostBar.setRequestedTransparency(true)
    if (hostBar.requestedTransparent || hostBar.transparent) {
      fail("barConfig.transparent=true made Shibumi transparent")
      return false
    }
    if (JSON.stringify(hostBar.barConfig) !== JSON.stringify(trueBarConfig)
        || JSON.stringify(fakeShell.shellConfig) !== trueStoredConfig) {
      fail("Shibumi rewrote the enabled stock transparency preference")
      return false
    }

    const originalState = JSON.parse(JSON.stringify(stateService.config))
    const variants = [
      { shellStyle: "shibumi", v2: false },
      { shellStyle: "full", v2: true },
      { shellStyle: "fit", v2: true },
      { shellStyle: "dock", v2: true },
      { shellStyle: "notch", v2: true }
    ]
    for (let index = 0; index < variants.length; index++) {
      const next = JSON.parse(JSON.stringify(originalState))
      if (!next.presentation) next.presentation = ({})
      next.presentation.shellStyle = variants[index].shellStyle
      stateService.config = next
      if (hostBar.layoutController.v2Mode !== variants[index].v2
          || hostBar.requestedTransparent || hostBar.transparent) {
        fail((variants[index].v2 ? "V2" : "V1")
          + " did not remain opaque")
        return false
      }
    }
    stateService.config = originalState

    const falseBarConfig = JSON.parse(JSON.stringify(trueBarConfig))
    falseBarConfig.transparent = false
    const falseShellConfig = JSON.parse(JSON.stringify(fakeShell.shellConfig))
    falseShellConfig.bar.transparent = false
    fakeShell.shellConfig = falseShellConfig
    const falseStoredConfig = JSON.stringify(fakeShell.shellConfig)
    hostBar.barConfig = falseBarConfig
    hostBar.applyBarConfig()
    hostBar.setRequestedTransparency(false)
    if (hostBar.requestedTransparent || hostBar.transparent
        || hostBar.barConfig.transparent !== false
        || JSON.stringify(fakeShell.shellConfig) !== falseStoredConfig) {
      fail("disabled stock transparency preference changed behavior")
      return false
    }

    trueBarConfig.transparent = true
    const restoredShellConfig = JSON.parse(JSON.stringify(fakeShell.shellConfig))
    restoredShellConfig.bar.transparent = true
    fakeShell.shellConfig = restoredShellConfig
    hostBar.barConfig = trueBarConfig
    hostBar.applyBarConfig()
    return !hostBar.requestedTransparent && !hostBar.transparent
  }

  QtObject {
    id: stateService

    readonly property bool ready: true
    property int revision: 0
    property var config: ({
      widgets: ({
        "G:example.inline-state": {
          groupOwned: "keep", collision: "same"
        }
      }),
      presentation: {
        border: true,
        shadow: false,
        frost: false,
        radius: "large"
      },
      reactor: { mode: 0 }
    })
    onConfigChanged: revision++

    readonly property color selectedColor: "#55aa77"
    property bool rejectGroupVariantStates: false
    property int separatorToggleCount: 0
    readonly property var appearanceKeys: [
      "displayMode", "compact", "mediaStyle", "color", "colorMode", "tone",
      "widgetBorder", "widgetBorderWidth", "widgetBorderColor",
      "widgetBorderUsesSurfaceColor", "widgetPadding", "widgetRadius",
      "surfaceOpacity"
    ]

    function groupSettingsForVariant(groupId, _variant) {
      return config.widgets ? config.widgets[String(groupId || "")] || ({})
        : ({})
    }

    function setLayout(order, splits) {
      const next = JSON.parse(JSON.stringify(config))
      next.order = order
      next.splits = splits
      config = next
      return true
    }

    function publishConfig(next) {
      config = next
      const shellConfig = JSON.parse(JSON.stringify(fakeShell.shellConfig))
      if (!shellConfig.bar) shellConfig.bar = ({})
      shellConfig.bar.shibumi = next
      fakeShell.shellConfig = shellConfig
    }

    function setGroupSetting(groupId, key, value) {
      const next = JSON.parse(JSON.stringify(config))
      if (!next.widgets) next.widgets = ({})
      if (!next.widgets[groupId]) next.widgets[groupId] = ({})
      if (next.widgets[groupId][key] === value) return false
      next.widgets[groupId][key] = value
      publishConfig(next)
      return true
    }

    function setGroupEnabledForVariant(groupId, variant, enabled) {
      if (["v1", "v2"].indexOf(variant) < 0
          || typeof enabled !== "boolean") return false
      const next = JSON.parse(JSON.stringify(config))
      if (!next.widgets) next.widgets = ({})
      if (!next.widgets[groupId]) next.widgets[groupId] = ({})
      const key = variant === "v2" ? "enabledV2" : "enabledV1"
      if (next.widgets[groupId][key] === enabled) return false
      next.widgets[groupId][key] = enabled
      publishConfig(next)
      return true
    }

    function setGroupVariantStates(stateValues) {
      if (rejectGroupVariantStates || !stateValues
          || Object.keys(stateValues).length === 0) return false
      const next = JSON.parse(JSON.stringify(config))
      if (!next.widgets) next.widgets = ({})
      let changed = false
      const groups = Object.keys(stateValues)
      for (let index = 0; index < groups.length; index++) {
        const group = groups[index]
        const states = stateValues[group]
        if (!states || typeof states.v1 !== "boolean"
            || typeof states.v2 !== "boolean") return false
        if (!next.widgets[group]) next.widgets[group] = ({})
        if (next.widgets[group].enabledV1 !== states.v1
            || next.widgets[group].enabledV2 !== states.v2) changed = true
        next.widgets[group].enabledV1 = states.v1
        next.widgets[group].enabledV2 = states.v2
      }
      if (!changed) return false
      publishConfig(next)
      return true
    }

    function setGroupsEnabledForAllVariants(groupValues, enabled) {
      if (!Array.isArray(groupValues) || groupValues.length === 0
          || typeof enabled !== "boolean") return false
      const states = ({})
      for (let index = 0; index < groupValues.length; index++) {
        const group = String(groupValues[index] || "")
        if (group === "") return false
        states[group] = { v1: enabled, v2: enabled }
      }
      return setGroupVariantStates(states)
    }

    function groupEnabledForVariant(groupId, variant) {
      const settings = config.widgets && config.widgets[groupId]
        ? config.widgets[groupId] : ({})
      const key = variant === "v2" ? "enabledV2" : "enabledV1"
      return Object.prototype.hasOwnProperty.call(settings, key)
        ? settings[key] !== false : settings.enabled !== false
    }

    function setGroupAppearanceSettingForVariant(
        groupId, variant, key, value) {
      if (["v1", "v2"].indexOf(variant) < 0
          || appearanceKeys.indexOf(key) < 0) return false
      const next = JSON.parse(JSON.stringify(config))
      if (!next.widgets) next.widgets = ({})
      if (!next.widgets[groupId]) next.widgets[groupId] = ({})
      const settings = next.widgets[groupId]
      if (!settings.appearance) settings.appearance = ({})
      if (!settings.appearance[variant]) settings.appearance[variant] = ({})
      if (settings.appearance[variant][key] === value) return false
      settings.appearance[variant][key] = value
      publishConfig(next)
      return true
    }

    function toggleGroupSeparator(groupId) {
      const group = String(groupId || "")
      if (group === "") return false
      const next = JSON.parse(JSON.stringify(config))
      if (!next.widgets) next.widgets = ({})
      if (!next.widgets[group]) next.widgets[group] = ({})
      next.widgets[group].separator = next.widgets[group].separator !== true
      separatorToggleCount++
      publishConfig(next)
      return true
    }

    function groupEnabled(groupId) {
      const settings = config.widgets && config.widgets[groupId]
        ? config.widgets[groupId] : ({})
      const variant = String(config.presentation.shellStyle || "shibumi")
        === "shibumi" ? "v1" : "v2"
      const key = variant === "v2" ? "enabledV2" : "enabledV1"
      return Object.prototype.hasOwnProperty.call(settings, key)
        ? settings[key] !== false : settings.enabled !== false
    }

    function resetLayout() { return false }
  }

  QtObject {
    id: reactorService
    readonly property int mode: 0
  }

  QtObject {
    id: idleService
    property bool screensaverStartedThisCycle: false
  }

  QtObject {
    id: fakePopout
    property int closeCount: 0

    function close() {
      closeCount++
      hostBar.releasePopout(fakePopout)
    }
  }

  QtObject { id: firstConnectedPanelOwner }
  QtObject { id: secondConnectedPanelOwner }
  QtObject { id: restoreOwnerA }
  QtObject { id: restoreOwnerB }

  QtObject {
    id: outputAFirst
    property int closeCount: 0
    function close() {
      closeCount++
      hostBar.releasePopout(outputAFirst, "DP-1")
    }
  }
  QtObject {
    id: outputASecond
    property int closeCount: 0
    function close() {
      closeCount++
      hostBar.releasePopout(outputASecond, "DP-1")
    }
  }
  QtObject {
    id: outputBFirst
    property int closeCount: 0
    function close() {
      closeCount++
      hostBar.releasePopout(outputBFirst, "HDMI-A-1")
    }
  }

  QtObject {
    id: fakeShell

    property var bar: null
    property var shellConfig: ({
      bar: ({ transparent: true, shibumi: stateService.config })
    })

    function serviceFor(pluginId) {
      if (pluginId === "hancore.shibumi.state") return stateService
      if (pluginId === "hancore.shibumi.reactor") return reactorService
      if (pluginId === "omarchy.idle") return idleService
      return null
    }

    function firstPartyServiceFor(pluginId) {
      return serviceFor(pluginId)
    }

    function mutateShellConfig(mutator) {
      const next = JSON.parse(JSON.stringify(shellConfig))
      mutator(next)
      shellConfig = next
    }
  }

  QtObject {
    id: fakePluginRegistry

    signal pluginsChanged()

    property url resolverUrl: Qt.resolvedUrl("fixtures/ResolverTestWidget.qml")

    property var installedPlugins: ({
      "hancore.shibumi.control-center": { id: "hancore.shibumi.control-center" },
      "hancore.shibumi.workspaces": { id: "hancore.shibumi.workspaces" },
      "hancore.shibumi.status": { id: "hancore.shibumi.status" },
      "hancore.shibumi.memory": { id: "hancore.shibumi.memory" },
      "hancore.shibumi.cpu": { id: "hancore.shibumi.cpu" },
      "hancore.shibumi.audio": { id: "hancore.shibumi.audio" },
      "hancore.shibumi.ai": { id: "hancore.shibumi.ai" },
      "hancore.shibumi.center": { id: "hancore.shibumi.center" },
      "hancore.shibumi.media": { id: "hancore.shibumi.media" },
      "hancore.shibumi.quick-access": { id: "hancore.shibumi.quick-access" },
      "hancore.shibumi.network": { id: "hancore.shibumi.network" },
      "hancore.shibumi.battery": { id: "hancore.shibumi.battery" },
      "hancore.shibumi.brightness": { id: "hancore.shibumi.brightness" },
      "hancore.shibumi.power-profile": { id: "hancore.shibumi.power-profile" },
      "hancore.shibumi.bluetooth": { id: "hancore.shibumi.bluetooth" },
      "omarchy.notifications": {
        id: "omarchy.notifications",
        kinds: ["service"],
        entryPoints: { service: "Service.qml" }
      },
      "omarchy.clock": {
        id: "omarchy.clock",
        kinds: ["bar-widget"],
        entryPoints: { barWidget: "Clock.qml" }
      },
      "omarchy.active-window": {
        id: "omarchy.active-window",
        kinds: ["bar-widget"],
        entryPoints: { barWidget: "ActiveWindow.qml" }
      },
      "omarchy.power": {
        id: "omarchy.power",
        kinds: ["bar-widget"],
        entryPoints: { barWidget: "Power.qml" }
      },
      "omarchy.spacer": {
        id: "omarchy.spacer",
        kinds: ["bar-widget"],
        entryPoints: { barWidget: "Spacer.qml" },
        barWidget: { allowMultiple: true }
      },
      "omarchy.weather": {
        id: "omarchy.weather",
        kinds: ["bar-widget"],
        entryPoints: { barWidget: "Weather.qml" }
      },
      "example.future-clock": {
        id: "example.future-clock",
        barWidget: {
          semanticCapabilities: ["clock"],
          allowMultiple: false
        }
      },
      "example.battery": {
        id: "example.battery",
        barWidget: {
          semanticCapabilities: ["battery"],
          allowMultiple: false
        }
      },
      "example.inline-state": {
        id: "example.inline-state",
        kinds: ["bar-widget"],
        entryPoints: { barWidget: "InlineState.qml" },
        barWidget: {
          displayName: "Inline state fixture",
          allowMultiple: false
        }
      }
    })

    function entryPointUrl(manifest, kind) {
      if (manifest && manifest.kinds
          && manifest.kinds.indexOf("bar-widget") < 0
          && (!manifest.entryPoints || !manifest.entryPoints.barWidget))
        return ""
      return manifest && kind === "barWidget"
        ? resolverUrl : ""
    }
  }

  QtObject {
    id: fakeBarWidgetRegistry
    property var widgets: ({})
  }

  Bar {
    id: hostBar

    omarchyPath: testOmarchyPath
    shell: fakeShell
    manifest: ({ id: "hancore.shibumi.bar", kinds: ["bar"] })
    pluginRegistry: fakePluginRegistry
    barWidgetRegistry: fakeBarWidgetRegistry
    barConfig: ({
      position: "top",
      transparent: true,
      style: "shibumi",
      centerAnchor: "hancore.shibumi.center",
      layout: {
        left: [], center: [],
        right: [{
          id: "example.inline-state", bestScore: 0,
          collision: "same", shibumiModule: true
        }]
      },
      shibumi: stateService.config
    })
    outputWindowsEnabled: false
  }

  Loader {
    active: hostBar.styleReady && hostBar.visualTokens !== null
    sourceComponent: active ? hostBar.activeStyle.barSurfaceComponent : null
    width: 1600
    height: 35
  }

  Timer {
    interval: 20
    repeat: true
    running: true

    onTriggered: {
      root.attempts++
      if ((!hostBar.hostReady || !hostBar.styleReady
           || !hostBar.barToggleStateLoaded
           || hostBar.moduleSlots.length < 16)
          && root.attempts < 100) return

      if (!hostBar.hostReady || !hostBar.styleReady
          || !hostBar.barToggleStateLoaded)
        return root.fail("bar host did not become ready")
      if (hostBar.moduleSlots.length !== 16)
        return root.fail("expected 16 registry slots, got "
                         + hostBar.moduleSlots.length)

      if (root.screensaverStage === 0) {
        if (hostBar.barHidden)
          return root.fail("bar started hidden without a toggle or screensaver")
        hostBar.requestPopout(fakePopout)
        idleService.screensaverStartedThisCycle = true
        root.screensaverStage = 1
        return
      }

      if (root.screensaverStage === 1) {
        if (!hostBar.screensaverPreHidden || !hostBar.barHidden)
          return root.fail("bar did not pre-hide for the screensaver cycle")
        if (fakePopout.closeCount !== 1 || hostBar.activePopout !== null)
          return root.fail("screensaver pre-hide did not dismiss the active popout")
        idleService.screensaverStartedThisCycle = false
        root.screensaverStage = 2
        return
      }

      if (root.screensaverStage === 2) {
        if (hostBar.screensaverPreHidden || hostBar.barHidden)
          return root.fail("bar did not restore after the screensaver cycle")
        hostBar.requestPopout(fakePopout)
        hostBar.barToggledOff = true
        idleService.screensaverStartedThisCycle = true
        root.screensaverStage = 3
        return
      }

      if (root.screensaverStage === 3) {
        if (fakePopout.closeCount !== 2 || hostBar.activePopout !== null)
          return root.fail("persistent bar hide did not dismiss the active popout")
        idleService.screensaverStartedThisCycle = false
        root.screensaverStage = 4
        return
      }

      if (root.screensaverStage === 4) {
        if (!hostBar.barHidden)
          return root.fail("screensaver restore overrode the persistent bar toggle")
        hostBar.barToggledOff = false
        root.screensaverStage = 5
        return
      }

      if (root.screensaverStage === 5) {
        if (hostBar.barHidden)
          return root.fail("bar toggle did not restore visibility")
        const strictLookup = hostBar.findPanelWidgetOnScreen(
          "hancore.shibumi.control-center", "DP-MISSING")
        if (strictLookup !== null)
          return root.fail("missing output restore fell back to another output")

        if (!hostBar.scheduleWidgetRestore(
              "hancore.shibumi.control-center", "bars", true,
              restoreOwnerA, "DP-A")
            || !hostBar.scheduleWidgetRestore(
              "hancore.shibumi.control-center", "bars", false,
              restoreOwnerB, "DP-B")
            || hostBar.pendingWidgetRestores.length !== 2
            || !hostBar.widgetRestorePendingForOwner(
              "hancore.shibumi.control-center", restoreOwnerA, "DP-A")
            || !hostBar.widgetRestorePendingForOwner(
              "hancore.shibumi.control-center", restoreOwnerB, "DP-B")
            || !hostBar.pendingWidgetRestores[0].needsReplacement
            || hostBar.pendingWidgetRestores[1].needsReplacement)
          return root.fail("output-local panel restores were not isolated")
        if (!hostBar.scheduleWidgetRestore(
              "hancore.shibumi.control-center", "bars-motion", false,
              restoreOwnerA, "DP-A")
            || hostBar.pendingWidgetRestores.length !== 2
            || hostBar.pendingWidgetRestores[0].page !== "bars-motion"
            || !hostBar.pendingWidgetRestores[0].needsReplacement
            || !hostBar.widgetRestorePendingForOutput(
              "hancore.shibumi.control-center", restoreOwnerB, "DP-A"))
          return root.fail("weaker lock restore downgraded V1/V2 handoff")
        if (!hostBar.cancelWidgetRestore(
              "hancore.shibumi.control-center", restoreOwnerB, "DP-B")
            || hostBar.pendingWidgetRestores.length !== 1
            || !hostBar.widgetRestorePendingForOwner(
              "hancore.shibumi.control-center", restoreOwnerA, "DP-A"))
          return root.fail("one output cancelled another output restore")
        if (!hostBar.cancelWidgetRestore(
              "hancore.shibumi.control-center", restoreOwnerA, "DP-A")
            || hostBar.pendingWidgetRestores.length !== 0)
          return root.fail("output-local panel restore did not clean up")
        root.screensaverStage = 6
      }

      if (root.stage === 13) {
        if (root.attempts < 2) return
        root.inlineStateSlot.ensureResolvedComponent()
        root.stage = 14
        root.attempts = 0
        return
      }

      const ids = []
      for (let index = 0; index < hostBar.moduleSlots.length; index++) {
        const slot = hostBar.moduleSlots[index]
        const expectedMarker = root.stage === 3
          ? "resolver-replaced" : "resolver-owned"
        if (!slot || !slot.activeItem
            || slot.activeItem.marker !== expectedMarker) {
          if ((root.stage === 11 || root.stage === 14)
              && root.attempts < 30) return
          return root.fail("registry widget did not load at slot " + index
            + " stage=" + root.stage + " attempts=" + root.attempts
            + " slots=" + hostBar.moduleSlots.length
            + " item=" + slot.activeItem
            + " marker=" + (slot.activeItem ? slot.activeItem.marker : "null")
            + " module=" + (slot ? slot.moduleName : "null"))
        }
        ids.push(slot.moduleName)
      }

      if (root.stage === 0) {
        hostBar.run("printf ok > " + root.commandMarker)
        const items = []
        for (let index = 0; index < hostBar.moduleSlots.length; index++)
          items.push(hostBar.moduleSlots[index].activeItem)
        root.retainedItems = items
        for (let index = 0; index < hostBar.moduleSlots.length; index++) {
          if (hostBar.moduleSlots[index].moduleName === "example.inline-state") {
            root.inlineStateSlot = hostBar.moduleSlots[index]
            root.inlineStateItem = hostBar.moduleSlots[index].activeItem
          }
        }
        if (!root.inlineStateItem
            || Number(root.inlineStateItem.settings.bestScore) !== 0
            || root.inlineStateItem.settings.groupOwned !== "keep"
            || root.inlineStateItem.settings.collision !== "same")
          return root.fail("inline-state fixture did not receive initial settings"
            + " region=" + (root.inlineStateSlot
              ? root.inlineStateSlot.region : "null")
            + " settings=" + JSON.stringify(root.inlineStateItem
              ? root.inlineStateItem.settings : null))
        root.stage = 1
        root.attempts = 0
        const nextConfig = JSON.parse(JSON.stringify(stateService.config))
        nextConfig.widgets.G8 = {
          "omarchy.weather": { unit: "imperial" }
        }
        stateService.config = nextConfig
        return
      }

      if (root.stage === 1) {
        for (let index = 0; index < hostBar.moduleSlots.length; index++) {
          if (hostBar.moduleSlots[index].activeItem !== root.retainedItems[index])
            return root.fail("settings update recreated slot " + index)
        }
        const nextBarConfig = JSON.parse(JSON.stringify(hostBar.barConfig))
        nextBarConfig.layout.right[0].bestScore = 3
        nextBarConfig.layout.right[0].collision = "host-next"
        if (hostBar.inlineSettingsDelta(
              hostBar.layoutConfig, nextBarConfig.layout) === null)
          return root.fail("inline settings fixture changed layout structure")
        const structuralCurrent = {
          left: [], center: [],
          right: [{ id: "example.inline-state", shibumiModule: true }]
        }
        const structuralNext = {
          left: [], center: [],
          right: [{ id: "example.inline-state", shibumiModule: false }]
        }
        if (hostBar.inlineSettingsDelta(
              structuralCurrent, structuralNext) !== null)
          return root.fail("slot-ownership change was treated as inline state")
        if (hostBar.applyInlineSettingsDelta([{
              region: "right", index: 0,
              entry: { id: "example.no-live-slot", value: 1 }
            }]) !== false)
          return root.fail("slotless inline state bypassed structural refresh")
        hostBar.barConfig = nextBarConfig
        root.stage = 11
        root.attempts = 0
        return
      }

      if (root.stage === 11) {
        let inlineSlot = null
        for (let index = 0; index < hostBar.moduleSlots.length; index++) {
          if (hostBar.moduleSlots[index].moduleName === "example.inline-state") {
            inlineSlot = hostBar.moduleSlots[index]
            break
          }
        }
        if (!inlineSlot || !inlineSlot.activeItem) {
          if (root.attempts < 30) return
          return root.fail("inline settings update removed its widget slot")
        }
        if (inlineSlot.activeItem !== root.inlineStateItem)
          return root.fail("inline settings update recreated the active widget")
        if (Number(inlineSlot.activeItem.settings.bestScore) !== 3) {
          if (root.attempts < 30) return
          return root.fail("inline settings update did not reach the active widget")
        }
        if (inlineSlot.activeItem.settings.groupOwned !== "keep"
            || inlineSlot.activeItem.settings.collision !== "same")
          return root.fail("inline settings update dropped merged group settings")
        const secondBarConfig = JSON.parse(JSON.stringify(hostBar.barConfig))
        secondBarConfig.layout.right[0].bestScore = 4
        secondBarConfig.layout.right[0].collision = "host-later"
        hostBar.barConfig = secondBarConfig
        root.stage = 15
        root.attempts = 0
        return
      }

      if (root.stage === 15) {
        if (Number(root.inlineStateSlot.activeItem.settings.bestScore) !== 4) {
          if (root.attempts < 30) return
          return root.fail("consecutive inline state write stayed stale")
        }
        if (root.inlineStateSlot.activeItem !== root.inlineStateItem)
          return root.fail("consecutive inline state write recreated the widget")
        if (root.inlineStateSlot.activeItem.settings.collision !== "same")
          return root.fail("equal-valued group override lost to host state")
        const updatedState = JSON.parse(JSON.stringify(stateService.config))
        updatedState.widgets["G:example.inline-state"].collision
          = "group-updated"
        stateService.config = updatedState
        root.stage = 16
        root.attempts = 0
        return
      }

      if (root.stage === 16) {
        if (root.inlineStateSlot.activeItem.settings.collision
              !== "group-updated") {
          if (root.attempts < 30) return
          return root.fail("group override update did not reach inline state")
        }
        const updatedState = JSON.parse(JSON.stringify(stateService.config))
        delete updatedState.widgets["G:example.inline-state"].collision
        stateService.config = updatedState
        root.stage = 17
        root.attempts = 0
        return
      }

      if (root.stage === 17) {
        if (root.inlineStateSlot.activeItem.settings.collision
              !== "host-later") {
          if (root.attempts < 30) return
          return root.fail("removed group override did not reveal host state")
        }
        root.inlineStateSlot.availableWidth += 1
        root.stage = 12
        root.attempts = 0
        return
      }

      if (root.stage === 12) {
        if (root.attempts < 2) return
        if (Number(root.inlineStateSlot.activeItem.settings.bestScore) !== 4
            || root.inlineStateSlot.activeItem.settings.groupOwned !== "keep"
            || root.inlineStateSlot.activeItem.settings.collision
              !== "host-later")
          return root.fail("property reinjection restored stale inline settings")
        root.inlineStateSlot.resolvedComponent = null
        root.stage = 13
        root.attempts = 0
        return
      }

      if (root.stage === 14) {
        if (!root.inlineStateSlot.activeItem) {
          if (root.attempts < 30) return
          return root.fail("inline-state provider did not reload")
        }
        if (root.inlineStateSlot.activeItem === root.inlineStateItem)
          return root.fail("inline-state reload fixture retained the old provider")
        if (Number(root.inlineStateSlot.activeItem.settings.bestScore) !== 4
            || root.inlineStateSlot.activeItem.settings.groupOwned !== "keep"
            || root.inlineStateSlot.activeItem.settings.collision
              !== "host-later")
          return root.fail("provider reload restored stale inline settings")
        const retained = root.retainedItems.slice()
        for (let index = 0; index < hostBar.moduleSlots.length; index++) {
          if (hostBar.moduleSlots[index] === root.inlineStateSlot)
            retained[index] = root.inlineStateSlot.activeItem
        }
        root.retainedItems = retained
        root.stage = 2
        root.attempts = 0
        fakePluginRegistry.pluginsChanged()
        return
      }

      if (root.stage === 2) {
        for (let index = 0; index < hostBar.moduleSlots.length; index++) {
          if (hostBar.moduleSlots[index].activeItem !== root.retainedItems[index])
            return root.fail("unchanged registry event recreated slot " + index)
        }
        fakePluginRegistry.resolverUrl = Qt.resolvedUrl(
          "fixtures/ResolverReplacementWidget.qml")
        root.stage = 3
        root.attempts = 0
        fakePluginRegistry.pluginsChanged()
        return
      }

      for (let index = 0; index < hostBar.moduleSlots.length; index++) {
        if (hostBar.moduleSlots[index].activeItem === root.retainedItems[index])
          return root.fail("changed registry URL retained slot " + index)
      }
      if (root.attempts < 20) return
      if (ids.indexOf("hancore.shibumi.control-center") < 0
          || ids.indexOf("hancore.shibumi.workspaces") < 0
          || ids.indexOf("hancore.shibumi.bar") >= 0
          || ids.indexOf("omarchy.workspaces") >= 0)
        return root.fail("G1/G2 did not resolve to extracted plugins")

      for (const propertyName of [
        "shibumiConfig", "internalWidgetRegistry", "systemTelemetry",
        "powerService", "statusService", "pickerService", "reactorService"
      ]) {
        if (propertyName in hostBar)
          return root.fail("bar retained feature property " + propertyName)
      }

      if (hostBar.visualTokens.seal !== stateService.selectedColor)
        return root.fail("style did not consume the shared state service")

      for (const optionalId of [
        "omarchy.dropbox", "omarchy.microphone", "omarchy.active-window",
        "omarchy.keyboard-layout", "omarchy.tailscale"
      ]) {
        hostBar.layoutConfig = {
          left: [{ id: optionalId }], center: [], right: []
        }
        if (!hostBar.layoutContains(optionalId))
          return root.fail("plain optional widget was not reported as installed: "
            + optionalId)
      }
      hostBar.layoutConfig = { left: [], center: [], right: [] }

      const v1Config = JSON.parse(JSON.stringify(stateService.config))
      if (!v1Config.presentation) v1Config.presentation = {}
      v1Config.presentation.shellStyle = "shibumi"
      stateService.config = v1Config
      hostBar.layoutConfig = {
        left: [
          { id: "example.future-clock" },
          { id: "example.future-clock" }
        ],
        center: [],
        right: [
          { id: "omarchy.spacer", shibumiModule: true },
          { id: "omarchy.spacer", shibumiModule: true }
        ]
      }
      if (hostBar.unassignedLayoutEntries("left").length !== 1
          || hostBar.unassignedLayoutEntries("right").length !== 2)
        return root.fail("V1 allowMultiple ownership deduplication")
      hostBar.layoutConfig = { left: [], center: [], right: [] }
      if (!stateService.setGroupVariantStates({
            G8: { v1: false, v2: true }
          }))
        return root.fail("provider migration setup")
      const migrationBarConfig = JSON.parse(JSON.stringify(hostBar.barConfig))
      migrationBarConfig.layout = {
        left: [],
        center: [
          { id: "example.future-clock" },
          { id: "omarchy.clock", shibumiModule: true }
        ],
        right: []
      }
      fakeShell.shellConfig.bar.layout = JSON.parse(
        JSON.stringify(migrationBarConfig.layout))
      hostBar.barConfig = migrationBarConfig
      hostBar.applyBarConfig()
      if (!hostBar.reconcileV1PluginGroups()
          || stateService.groupEnabledForVariant("G8", "v1")
          || stateService.groupEnabledForVariant("G8", "v2")
          || (fakeShell.shellConfig.bar.layout.center || []).length !== 1
          || String(fakeShell.shellConfig.bar.layout.center[0].id || "")
            !== "example.future-clock")
        return root.fail("persisted provider was not reconciled across variants")
      migrationBarConfig.layout = { left: [], center: [], right: [] }
      fakeShell.shellConfig.bar.layout = JSON.parse(
        JSON.stringify(migrationBarConfig.layout))
      hostBar.barConfig = migrationBarConfig
      hostBar.applyBarConfig()
      if (!hostBar.reconcileV1PluginGroups()
          || !hostBar.setWidgetGroupsEnabledForAllVariants(["G8"], true))
        return root.fail("provider migration cleanup")

      stateService.rejectGroupVariantStates = true
      if (hostBar.setBarWidgetInstalled("omarchy.clock", true, "right"))
        return root.fail("provider state rejection was reported as success")
      stateService.rejectGroupVariantStates = false
      const rejectedLayout = fakeShell.shellConfig.bar.layout || ({})
      if ((rejectedLayout.left || []).length !== 0
          || (rejectedLayout.center || []).length !== 0
          || (rejectedLayout.right || []).length !== 0
          || !stateService.groupEnabledForVariant("G8", "v1")
          || !stateService.groupEnabledForVariant("G8", "v2"))
        return root.fail("rejected provider install did not roll back")

      if (!hostBar.setBarWidgetInstalled(
            "omarchy.clock", true, "right"))
        return root.fail("Add plugin did not work with the active V1 layout")
      if (!stateService.config.widgets.G8
          || stateService.config.widgets.G8.enabledV1 !== false
          || stateService.config.widgets.G8.enabledV2 !== false)
        return root.fail("V1 provider replacement did not cover V2")
      if (!hostBar.removeWidgetFamilyAlternatives("G8"))
        return root.fail("V1 family alternative removal")
      const clockGroup = hostBar.layoutController.groupLocation(
        "G:omarchy.clock")
      if (!clockGroup || clockGroup.region === "center"
          || stateService.config.order[clockGroup.region][clockGroup.index]
            !== "G:omarchy.clock")
        return root.fail("V1 plugin did not receive an automatic G-group")

      const v2Config = JSON.parse(JSON.stringify(stateService.config))
      v2Config.presentation.shellStyle = "full"
      stateService.config = v2Config
      hostBar.layoutConfig = {
        left: [],
        center: [
          { id: "omarchy.clock", shibumiModule: true },
          { id: "omarchy.clock", shibumiModule: true }
        ],
        right: [
          { id: "omarchy.spacer", shibumiModule: true },
          { id: "omarchy.spacer", shibumiModule: true }
        ]
      }
      if (hostBar.unassignedLayoutEntries("center").length !== 1
          || hostBar.unassignedLayoutEntries("right").length !== 2)
        return root.fail("V2 allowMultiple ownership deduplication")
      hostBar.layoutConfig = { left: [], center: [], right: [] }
      if (hostBar.widgetReplacementLabel("omarchy.clock")
            !== "Replaces Shibumi Center"
          || JSON.stringify(hostBar.widgetReplacementGroups("omarchy.clock"))
            !== JSON.stringify(["G8"])
          || hostBar.widgetReplacementGroup("omarchy.clock") !== "G8"
          || hostBar.widgetReplacementTarget("omarchy.clock")
            !== "Shibumi Center"
          || hostBar.widgetReplacementLabel("example.future-clock")
            !== "Replaces Shibumi Center"
          || hostBar.widgetReplacementLabel("omarchy.notifications") !== ""
          || hostBar.setBarWidgetInstalled(
            "omarchy.notifications", true, "left")
          || !hostBar.setBarWidgetInstalled(
            "omarchy.clock", true, "right")) {
        return root.fail("Add plugin did not work with the active V2 layout")
      }
      const replacedConfig = fakeShell.shellConfig.bar
      const centerEntries = replacedConfig.layout.center || []
      if (!replacedConfig.shibumi
          || !replacedConfig.shibumi.widgets
          || !replacedConfig.shibumi.widgets.G8
          || replacedConfig.shibumi.widgets.G8.enabledV1 !== false
          || replacedConfig.shibumi.widgets.G8.enabledV2 !== false
          || centerEntries.length !== 1
          || String(centerEntries[0].id || centerEntries[0])
            !== "omarchy.clock") {
        return root.fail("Omarchy clock did not atomically replace"
          + " Shibumi Center in the center region")
      }
      if (!hostBar.removeWidgetFamilyAlternatives("G8")
          || (fakeShell.shellConfig.bar.layout.center || []).length !== 0) {
        return root.fail("Shibumi Center did not remove its alternatives")
      }

      const complementaryLayout = {
        left: [],
        center: [
          { id: "omarchy.clock", shibumiModule: true },
          { id: "omarchy.weather", shibumiModule: true }
        ],
        right: []
      }
      hostBar.layoutConfig = complementaryLayout
      fakeShell.shellConfig.bar.layout = JSON.parse(
        JSON.stringify(complementaryLayout))
      if (JSON.stringify(hostBar.conflictingLayoutProviderIds(
            "example.future-clock"))
            !== JSON.stringify(["example.future-clock", "omarchy.clock"])
          || !hostBar.setBarWidgetInstalled(
            "example.future-clock", true, "center"))
        return root.fail("same-capability provider replacement")
      const complementaryEntries = fakeShell.shellConfig.bar.layout.center
      if (complementaryEntries.length !== 2
          || String(complementaryEntries[0].id || complementaryEntries[0])
            !== "omarchy.weather"
          || String(complementaryEntries[1].id || complementaryEntries[1])
            !== "example.future-clock")
        return root.fail("complementary provider was removed with clock")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      if (!hostBar.removeBarWidgetAndRestoreFamilies(
            "omarchy.weather", ["G8"])
          || (fakeShell.shellConfig.bar.layout.center || []).length !== 1
          || String(fakeShell.shellConfig.bar.layout.center[0].id || "")
            !== "example.future-clock"
          || stateService.groupEnabledForVariant("G8", "v1")
          || stateService.groupEnabledForVariant("G8", "v2"))
        return root.fail("remaining provider lost family ownership")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      stateService.rejectGroupVariantStates = true
      if (hostBar.restoreWidgetFamilyProviderStates({
            G8: { v1: true, v2: false }
          }))
        return root.fail("rejected provider restore was reported as success")
      stateService.rejectGroupVariantStates = false
      if ((fakeShell.shellConfig.bar.layout.center || []).length !== 1
          || stateService.groupEnabledForVariant("G8", "v1")
          || stateService.groupEnabledForVariant("G8", "v2"))
        return root.fail("rejected provider restore did not roll back")
      if (!hostBar.restoreWidgetFamilyProviderStates({
            G8: { v1: true, v2: false }
          })
          || (fakeShell.shellConfig.bar.layout.center || []).length !== 0
          || !stateService.groupEnabledForVariant("G8", "v1")
          || stateService.groupEnabledForVariant("G8", "v2"))
        return root.fail("exact cross-variant provider restore")
      hostBar.layoutConfig = { left: [], center: [], right: [] }

      if (JSON.stringify(hostBar.widgetReplacementGroups("omarchy.power"))
            !== JSON.stringify(["G12", "G14"])
          || hostBar.widgetReplacementTarget("omarchy.power")
            !== "Shibumi Battery and Shibumi Power Profile"
          || hostBar.widgetReplacementLabel("omarchy.power")
            !== "Replaces Shibumi Battery and Shibumi Power Profile"
          || !hostBar.setBarWidgetInstalled("omarchy.power", true, "right"))
        return root.fail("Power multi-provider replacement contract")
      const powerWidgets = stateService.config.widgets
      if (!powerWidgets.G12 || !powerWidgets.G14
          || powerWidgets.G12.enabledV1 !== false
          || powerWidgets.G12.enabledV2 !== false
          || powerWidgets.G14.enabledV1 !== false
          || powerWidgets.G14.enabledV2 !== false)
        return root.fail("Power did not replace both groups in V1 and V2")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      if (!hostBar.restoreWidgetFamilyProviders(["G12"])
          || (fakeShell.shellConfig.bar.layout.right || []).length !== 0
          || !stateService.groupEnabledForVariant("G12", "v1")
          || !stateService.groupEnabledForVariant("G12", "v2")
          || !stateService.groupEnabledForVariant("G14", "v1")
          || !stateService.groupEnabledForVariant("G14", "v2"))
        return root.fail("native G12 selection orphaned G14")
      hostBar.layoutConfig = { left: [], center: [], right: [] }
      if (!hostBar.setBarWidgetInstalled("omarchy.power", true, "right"))
        return root.fail("Power reinstall before G14 restore")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      if (!hostBar.restoreWidgetFamilyProviders(["G14"])
          || (fakeShell.shellConfig.bar.layout.right || []).length !== 0
          || !stateService.groupEnabledForVariant("G12", "v1")
          || !stateService.groupEnabledForVariant("G12", "v2")
          || !stateService.groupEnabledForVariant("G14", "v1")
          || !stateService.groupEnabledForVariant("G14", "v2"))
        return root.fail("native G14 selection orphaned G12")
      hostBar.layoutConfig = { left: [], center: [], right: [] }
      if (!hostBar.setBarWidgetInstalled("omarchy.power", true, "right"))
        return root.fail("Power reinstall before partial replacement")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      if (!hostBar.setBarWidgetInstalled(
            "example.battery", true, "right"))
        return root.fail("Battery provider did not replace Power")
      const batteryEntries = fakeShell.shellConfig.bar.layout.right || []
      if (batteryEntries.length !== 1
          || String(batteryEntries[0].id || batteryEntries[0])
            !== "example.battery"
          || stateService.groupEnabledForVariant("G12", "v1")
          || stateService.groupEnabledForVariant("G12", "v2")
          || !stateService.groupEnabledForVariant("G14", "v1")
          || !stateService.groupEnabledForVariant("G14", "v2"))
        return root.fail("displaced Power left G14 without a provider")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      if (!hostBar.removeBarWidgetAndRestoreFamilies(
            "example.battery", ["G12"])
          || (fakeShell.shellConfig.bar.layout.right || []).length !== 0
          || !stateService.groupEnabledForVariant("G12", "v1")
          || !stateService.groupEnabledForVariant("G12", "v2")
          || !stateService.groupEnabledForVariant("G14", "v1")
          || !stateService.groupEnabledForVariant("G14", "v2"))
        return root.fail("Battery removal did not restore unowned providers")
      hostBar.layoutConfig = { left: [], center: [], right: [] }
      if (!stateService.setGroupVariantStates({
            G14: { v1: false, v2: false }
          })
          || !hostBar.setBarWidgetInstalled(
            "example.battery", true, "right"))
        return root.fail("provider snapshot setup")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      const providerSnapshot = hostBar.providerLayoutSnapshot(["G12", "G14"])
      if (!providerSnapshot
          || !hostBar.setBarWidgetInstalled("omarchy.power", true, "right"))
        return root.fail("multi-capability provider snapshot activation")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      if (!hostBar.restoreProviderLayoutSnapshot(providerSnapshot)
          || (fakeShell.shellConfig.bar.layout.right || []).length !== 1
          || String(fakeShell.shellConfig.bar.layout.right[0].id || "")
            !== "example.battery"
          || stateService.groupEnabledForVariant("G12", "v1")
          || stateService.groupEnabledForVariant("G12", "v2")
          || stateService.groupEnabledForVariant("G14", "v1")
          || stateService.groupEnabledForVariant("G14", "v2"))
        return root.fail("provider snapshot did not restore exact state")
      hostBar.layoutConfig = JSON.parse(JSON.stringify(
        fakeShell.shellConfig.bar.layout))
      if (!hostBar.removeBarWidgetAndRestoreFamilies(
            "example.battery", ["G12"])
          || !hostBar.setWidgetGroupsEnabledForAllVariants(
            ["G12", "G14"], true))
        return root.fail("provider snapshot cleanup")
      hostBar.layoutConfig = { left: [], center: [], right: [] }

      if (hostBar.setWidgetAppearance(
            "G1", "widgetPadding", '"roomy"') !== "variant-required"
          || hostBar.setWidgetAppearanceForVariant(
            "G1", "v3", "widgetPadding", '"roomy"') !== "invalid-variant"
          || hostBar.setWidgetAppearanceForVariant(
            "G1", "v2", "notAnAppearanceKey", "true") !== "invalid-key"
          || hostBar.setWidgetAppearanceForVariant(
            "G1", "v2", "widgetPadding", '"roomy"') !== "ok") {
        return root.fail("variant appearance IPC result contract")
      }
      const appearanceConfig = stateService.config.widgets.G1
      if (appearanceConfig.widgetPadding !== undefined
          || !appearanceConfig.appearance
          || !appearanceConfig.appearance.v2
          || appearanceConfig.appearance.v2.widgetPadding !== "roomy"
          || appearanceConfig.appearance.v1 !== undefined) {
        return root.fail("variant appearance IPC state isolation")
      }
      if (hostBar.setWidgetAppearance(
            "G1", "separator", "true") !== "ok"
          || stateService.config.widgets.G1.separator !== true) {
        return root.fail("shared appearance IPC compatibility")
      }
      if (!hostBar.toggleGroupSeparator("G1")
          || stateService.separatorToggleCount !== 1
          || stateService.config.widgets.G1.separator !== false)
        return root.fail("unprotected V2 separator route")
      const protectedLayout = JSON.parse(JSON.stringify(stateService.config))
      protectedLayout.layoutProtection = { v1: false, v2: true }
      stateService.config = protectedLayout
      if (!hostBar.layoutController.activeLayoutProtected
          || hostBar.toggleGroupSeparator("G1")
          || stateService.separatorToggleCount !== 1
          || !hostBar.toggleGroupSeparator("G1", true)
          || stateService.separatorToggleCount !== 2
          || stateService.config.widgets.G1.separator !== true)
        return root.fail("protected V2 separator edit override")

      hostBar.requestPopout(outputAFirst, "DP-1")
      hostBar.requestPopout(outputBFirst, "HDMI-A-1")
      if (outputAFirst.closeCount !== 0
          || outputBFirst.closeCount !== 0
          || hostBar.activePopoutForScreen("DP-1") !== outputAFirst
          || hostBar.activePopoutForScreen("HDMI-A-1") !== outputBFirst) {
        return root.fail("opening another output closed an unrelated popout")
      }
      hostBar.requestPopout(outputASecond, "DP-1")
      if (outputAFirst.closeCount !== 1
          || outputBFirst.closeCount !== 0
          || hostBar.activePopoutForScreen("DP-1") !== outputASecond
          || hostBar.activePopoutForScreen("HDMI-A-1") !== outputBFirst) {
        return root.fail("same-output sibling replacement was not isolated")
      }
      hostBar.releasePopoutsForScreen("DP-1")
      if (outputASecond.closeCount !== 1
          || hostBar.activePopoutForScreen("DP-1") !== null
          || hostBar.activePopoutForScreen("HDMI-A-1") !== outputBFirst) {
        return root.fail("output removal retained or cross-closed popout owners")
      }
      hostBar.releasePopoutsForScreen("HDMI-A-1")

      hostBar.requestPopout(firstConnectedPanelOwner, "DP-1")
      if (!hostBar.publishConnectedPanel(
            firstConnectedPanelOwner, "DP-1", 240, 1)) {
        return root.fail("first output connection was not published")
      }
      hostBar.requestPopout(secondConnectedPanelOwner, "HDMI-A-1")
      if (!hostBar.publishConnectedPanel(
            secondConnectedPanelOwner, "HDMI-A-1", 620, 1)
          || hostBar.connectedPanelForScreen("DP-1").owner
            !== firstConnectedPanelOwner
          || hostBar.connectedPanelForScreen("HDMI-A-1").owner
            !== secondConnectedPanelOwner
          || !hostBar.clearConnectedPanel(firstConnectedPanelOwner)
          || hostBar.connectedPanelForScreen("DP-1").owner !== null
          || hostBar.connectedPanelForScreen("HDMI-A-1").owner
            !== secondConnectedPanelOwner
          || !hostBar.clearConnectedPanel(secondConnectedPanelOwner)) {
        return root.fail("connected panel geometry was not output-local")
      }
      hostBar.releasePopoutsForScreen("DP-1")
      hostBar.releasePopoutsForScreen("HDMI-A-1")

      hostBar.requestPopout(firstConnectedPanelOwner, "DP-1")
      if (!hostBar.publishConnectedPanel(
            firstConnectedPanelOwner, "DP-1", 240, 1)) {
        return root.fail("first connected panel owner was not published")
      }
      hostBar.requestPopout(secondConnectedPanelOwner, "DP-1")
      if (!hostBar.publishConnectedPanel(
            secondConnectedPanelOwner, "DP-1", 620, 1)
          || hostBar.publishConnectedPanel(
            firstConnectedPanelOwner, "DP-1", 250, 1)
          || hostBar.clearConnectedPanel(firstConnectedPanelOwner)
          || hostBar.connectedPanelOwner !== secondConnectedPanelOwner
          || hostBar.connectedPanelX !== 620
          || !hostBar.clearConnectedPanel(secondConnectedPanelOwner)) {
        return root.fail("closing panel owner overwrote the active border seam")
      }

      if (!root.verifyTransparencyContract())
        return root.fail("transparency contract did not settle opaque")

      stop()
      console.log("bar host registry smoke passed")
      Qt.exit(0)
    }
  }
}
