import QtQuick
import Quickshell

ShellRoot {
  id: root

  property int attempts: 0
  property int stage: 0
  property int screensaverStage: 0
  property var retainedItems: []
  property string commandMarker: testCommandMarker

  function fail(message) {
    console.error("bar-host-registry-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: stateService

    readonly property bool ready: true
    property var config: ({
      widgets: ({}),
      presentation: {
        border: true,
        shadow: false,
        frost: false,
        radius: "large"
      },
      reactor: { mode: 0 }
    })
    readonly property color selectedColor: "#55aa77"
    readonly property var appearanceKeys: [
      "displayMode", "compact", "mediaStyle", "color", "colorMode", "tone",
      "widgetBorder", "widgetBorderWidth", "widgetBorderColor",
      "widgetBorderUsesSurfaceColor", "widgetPadding", "widgetRadius",
      "surfaceOpacity"
    ]

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

  QtObject {
    id: fakeShell

    property var bar: null
    property var shellConfig: ({ bar: ({ shibumi: stateService.config }) })

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
      "example.future-clock": {
        id: "example.future-clock",
        barWidget: {
          semanticCapabilities: ["clock"],
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
      transparent: false,
      style: "shibumi",
      centerAnchor: "hancore.shibumi.center",
      layout: { left: [], center: [], right: [] },
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
           || hostBar.moduleSlots.length < 15)
          && root.attempts < 100) return

      if (!hostBar.hostReady || !hostBar.styleReady
          || !hostBar.barToggleStateLoaded)
        return root.fail("bar host did not become ready")
      if (hostBar.moduleSlots.length !== 15)
        return root.fail("expected 15 registry slots, got "
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
        root.screensaverStage = 6
      }

      const ids = []
      for (let index = 0; index < hostBar.moduleSlots.length; index++) {
        const slot = hostBar.moduleSlots[index]
        const expectedMarker = root.stage < 3
          ? "resolver-owned" : "resolver-replaced"
        if (!slot || !slot.activeItem
            || slot.activeItem.marker !== expectedMarker)
          return root.fail("registry widget did not load at slot " + index)
        ids.push(slot.moduleName)
      }

      if (root.stage === 0) {
        hostBar.run("printf ok > " + root.commandMarker)
        const items = []
        for (let index = 0; index < hostBar.moduleSlots.length; index++)
          items.push(hostBar.moduleSlots[index].activeItem)
        root.retainedItems = items
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

      const v1Config = JSON.parse(JSON.stringify(stateService.config))
      if (!v1Config.presentation) v1Config.presentation = {}
      v1Config.presentation.shellStyle = "shibumi"
      stateService.config = v1Config
      if (!hostBar.setBarWidgetInstalled(
            "omarchy.clock", true, "right")
          || !hostBar.removeWidgetFamilyAlternatives("G8")) {
        return root.fail("Add plugin did not work with the active V1 layout")
      }
      const clockGroup = hostBar.layoutController.groupLocation(
        "G:omarchy.clock")
      if (!clockGroup || clockGroup.region === "center"
          || stateService.config.order[clockGroup.region][clockGroup.index]
            !== "G:omarchy.clock")
        return root.fail("V1 plugin did not receive an automatic G-group")

      const v2Config = JSON.parse(JSON.stringify(stateService.config))
      v2Config.presentation.shellStyle = "full"
      stateService.config = v2Config
      if (hostBar.widgetReplacementLabel("omarchy.clock")
            !== "Replaces Shibumi Center"
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

      hostBar.activePopout = firstConnectedPanelOwner
      if (!hostBar.publishConnectedPanel(
            firstConnectedPanelOwner, "DP-1", 240, 1)) {
        return root.fail("first connected panel owner was not published")
      }
      hostBar.activePopout = secondConnectedPanelOwner
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

      stop()
      console.log("bar host registry smoke passed")
      Qt.exit(0)
    }
  }
}
