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

    function setLayout(order, splits) {
      const next = JSON.parse(JSON.stringify(config))
      next.order = order
      next.splits = splits
      config = next
      return true
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
        idleService.screensaverStartedThisCycle = true
        root.screensaverStage = 1
        return
      }

      if (root.screensaverStage === 1) {
        if (!hostBar.screensaverPreHidden || !hostBar.barHidden)
          return root.fail("bar did not pre-hide for the screensaver cycle")
        idleService.screensaverStartedThisCycle = false
        root.screensaverStage = 2
        return
      }

      if (root.screensaverStage === 2) {
        if (hostBar.screensaverPreHidden || hostBar.barHidden)
          return root.fail("bar did not restore after the screensaver cycle")
        hostBar.barToggledOff = true
        idleService.screensaverStartedThisCycle = true
        root.screensaverStage = 3
        return
      }

      if (root.screensaverStage === 3) {
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

      if (hostBar.widgetReplacementLabel("omarchy.clock")
            !== "Replaces Shibumi Center"
          || hostBar.widgetReplacementLabel("example.future-clock")
            !== "Replaces Shibumi Center"
          || hostBar.widgetReplacementLabel("omarchy.notifications") !== ""
          || hostBar.setBarWidgetInstalled(
            "omarchy.notifications", true, "left")
          || !hostBar.setBarWidgetInstalled(
            "omarchy.clock", true, "right")) {
        return root.fail("clock replacement contract was rejected")
      }
      const replacedConfig = fakeShell.shellConfig.bar
      const centerEntries = replacedConfig.layout.center || []
      if (!replacedConfig.shibumi
          || !replacedConfig.shibumi.widgets
          || !replacedConfig.shibumi.widgets.G8
          || replacedConfig.shibumi.widgets.G8.enabled !== false
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

      stop()
      console.log("bar host registry smoke passed")
      Qt.exit(0)
    }
  }
}
