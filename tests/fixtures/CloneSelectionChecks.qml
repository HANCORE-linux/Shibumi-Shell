import QtQuick
import "../native" as Native
import "../core/LayoutModel.js" as Layout

Item {
  id: checks
  required property var bar
  required property var host
  required property var stateOwner
  required property string fixtureDir

  // Keep all registry decision/mutation methods unmodified. Only disable its
  // startup directory/watcher I/O; the fixture supplies in-memory manifests.
  Native.PluginRegistry {
    id: nativeRegistry
    function ensureUserDir() {}
    shellConfigProvider: () => checks.host.shellConfig
    shellConfigMutator: mutator => checks.host.mutateShellConfig(mutator)
  }
  QtObject {
    id: registry
    property var forcedSelection: null
    property string refusedId: ""
    property int enableCalls: 0
    property bool refuseEnable: false
    readonly property var installedPlugins: nativeRegistry.installedPlugins
    signal pluginsChanged()
    property Connections forwardEvents: Connections {
      target: nativeRegistry
      function onPluginsChanged() { registry.pluginsChanged() }
    }
    function resolveEnabledId(id) {
      // Missing/empty selection is a deliberate future-host refusal fixture.
      if (id === refusedId) return ""
      return forcedSelection === null ? nativeRegistry.resolveEnabledId(id) : forcedSelection
    }
    function entryPointUrl(manifest, kind) { return nativeRegistry.entryPointUrl(manifest, kind) }
    function isEnabled(id) { return nativeRegistry.isEnabled(id) }
    function setEnabled(id, enabled) {
      enableCalls++
      return refuseEnable ? false : nativeRegistry.setEnabled(id, enabled)
    }
  }
  QtObject {
    id: registryWithoutUrl
    readonly property var installedPlugins: nativeRegistry.installedPlugins
    signal pluginsChanged()
    function resolveEnabledId(id) { return nativeRegistry.resolveEnabledId(id) }
  }
  QtObject {
    id: registryWithoutEnable
    readonly property var installedPlugins: nativeRegistry.installedPlugins
    signal pluginsChanged()
    function resolveEnabledId(id) { return nativeRegistry.resolveEnabledId(id) }
    function entryPointUrl(manifest, kind) { return nativeRegistry.entryPointUrl(manifest, kind) }
    function isEnabled(id) { return nativeRegistry.isEnabled(id) }
  }
  function require(value, message) {
    if (!value) {
      console.error("clone-selection-regression:", message)
      Qt.exit(1)
      throw new Error(message)
    }
  }
  function copy(value) { return JSON.parse(JSON.stringify(value)) }
  function snapshot() {
    return JSON.stringify({ shell: host.shellConfig, layout: bar.layoutConfig,
      state: stateOwner.config, stateRevision: stateOwner.revision,
      writes: host.configWrites, enableCalls: registry.enableCalls,
      registryRevision: nativeRegistry.registryRevision })
  }
  function refuse(label) {
    const before = snapshot()
    require(!bar.setBarWidgetInstalled("omarchy.clock", true, "center")
      && snapshot() === before, label + " did not refuse before mutation")
  }
  function run() {
    const savedRegistry = bar.pluginRegistry
    const savedShell = copy(host.shellConfig)
    const savedState = copy(stateOwner.config)
    const savedLayout = copy(bar.layoutConfig)
    const entry = { id: "local.clock", format: "HH:mm", custom: { nested: [1, "keep"] } }
    const manifests = {
      "omarchy.clock": { id: "omarchy.clock", kinds: ["bar-widget"],
        __sourceDir: fixtureDir, __isFirstParty: true,
        entryPoints: { barWidget: "ResolverTestWidget.qml" } },
      "local.clock": { id: "local.clock", kinds: ["bar-widget"],
        __sourceDir: fixtureDir, omarchy: { clonedFrom: "omarchy.clock" },
        entryPoints: { barWidget: "ResolverReplacementWidget.qml" },
        barWidget: { allowMultiple: false } }
    }
    const initialState = copy(savedState)
    initialState.presentation.shellStyle = "shibumi"
    initialState.order = Layout.defaultOrder()
    initialState.splits = Layout.defaultSplits()
    initialState.widgets.G8 = { enabledV1: true, enabledV2: true }
    const initialShell = copy(savedShell)
    initialShell.bar.layout = { left: [], center: [entry], right: [] }
    initialShell.bar.shibumi = initialState
    initialShell.plugins = []
    initialShell.disabledPlugins = []
    try {
      nativeRegistry.installedPlugins = copy(manifests)
      host.shellConfig = copy(initialShell)
      stateOwner.config = copy(initialState)
      bar.layoutConfig = copy(initialShell.bar.layout)
      bar.pluginRegistry = registry
      require(nativeRegistry.resolveEnabledId("omarchy.clock") === "local.clock",
        "real registry did not select the active clone")
      // Prove the actual hazard, not a fake whose clone choice never changes.
      require(nativeRegistry.setEnabled("omarchy.clock", true)
        && nativeRegistry.resolveEnabledId("omarchy.clock") === "omarchy.clock"
        && host.shellConfig.bar.layout.center[0].id === "omarchy.clock"
        && host.shellConfig.bar.layout.center[0].custom.nested[1] === "keep",
        "real registry original-enable control did not restore the clone source")
      host.shellConfig = copy(initialShell)
      for (const value of ["local.missing", ""]) {
        registry.forcedSelection = value
        refuse("missing/empty selected clone")
      }
      registry.forcedSelection = null
      registry.refusedId = "local.clock"
      refuse("selected ID not independently resolvable")
      registry.refusedId = ""
      bar.pluginRegistry = registryWithoutUrl
      refuse("missing entry-point URL authority")
      bar.pluginRegistry = registryWithoutEnable
      const disabledShell = copy(initialShell)
      disabledShell.disabledPlugins = ["omarchy.clock", "local.clock"]
      host.shellConfig = disabledShell
      require(!nativeRegistry.isEnabled("omarchy.clock"), "missing enable fixture was already enabled")
      refuse("missing enable capability")
      host.shellConfig = copy(initialShell)
      bar.pluginRegistry = registry
      let changed = copy(manifests)
      changed["local.clock"].barWidget.allowMultiple = true
      nativeRegistry.installedPlugins = changed
      refuse("selected multi-instance clone")
      changed = copy(manifests)
      changed["local.clock"].entryPoints = {}
      nativeRegistry.installedPlugins = changed
      refuse("selected clone without entry point")
      changed = copy(manifests)
      changed["local.clock"].barWidget.semanticCapabilities = ["audio"]
      nativeRegistry.installedPlugins = changed
      refuse("conflicting selected family")
      nativeRegistry.installedPlugins = copy(manifests)
      const duplicateShell = copy(initialShell)
      duplicateShell.bar.layout.left.push(copy(entry))
      host.shellConfig = duplicateShell
      bar.layoutConfig = copy(duplicateShell.bar.layout)
      refuse("duplicate selected single-instance entry")
      host.shellConfig = copy(initialShell)
      bar.layoutConfig = copy(initialShell.bar.layout)
      const v2Before = JSON.stringify(stateOwner.config.v2Layout)
      const orderBefore = JSON.stringify(stateOwner.config.order)
      const splitsBefore = JSON.stringify(stateOwner.config.splits)
      const callsBefore = registry.enableCalls
      require(bar.setBarWidgetInstalled("omarchy.clock", true, "left"),
        "valid selected single-instance clone was refused")
      bar.layoutConfig = copy(host.shellConfig.bar.layout)
      const expected = copy(entry)
      expected.shibumiModule = true
      require(JSON.stringify(host.shellConfig.bar.layout) === JSON.stringify({ left: [], center: [expected], right: [] })
        && registry.enableCalls === callsBefore
        && nativeRegistry.resolveEnabledId("omarchy.clock") === "local.clock"
        && bar.v1FamilySlotBindings.G8 === "local.clock"
        && bar.layoutController.groupLocation("G:local.clock") === null
        && JSON.stringify(stateOwner.config.order) === orderBefore
        && JSON.stringify(stateOwner.config.splits) === splitsBefore
        && JSON.stringify(stateOwner.config.v2Layout) === v2Before,
        "selected clone lost identity/settings/slot or changed V2")
      const component = bar.hostWidgetResolver.ensureComponent("omarchy.clock")
      require(component !== null, "selected clone component unavailable after mutation")
      const view = component.createObject(checks)
      require(view && view.marker === "resolver-replaced", "original component loaded instead of selected clone")
      view.destroy()

      changed = copy(manifests)
      changed["local.inactive"] = copy(manifests["local.clock"])
      changed["local.inactive"].id = "local.inactive"
      nativeRegistry.installedPlugins = changed
      registry.refuseEnable = true
      const beforeRejectedEnable = JSON.parse(snapshot())
      require(!bar.setBarWidgetInstalled("local.inactive", true, "center"),
        "registry enable refusal was reported as success")
      registry.refuseEnable = false
      const afterRejectedEnable = JSON.parse(snapshot())
      require(afterRejectedEnable.enableCalls === beforeRejectedEnable.enableCalls + 1,
        "inactive clone did not use the guarded enable route")
      afterRejectedEnable.enableCalls = beforeRejectedEnable.enableCalls
      require(JSON.stringify(afterRejectedEnable) === JSON.stringify(beforeRejectedEnable),
        "registry refusal changed layout or family state")
      nativeRegistry.installedPlugins = copy(manifests)

      const legacy = copy(initialState)
      legacy.order.left.push("G:local.clock")
      legacy.splits = Layout.resizeSplits(legacy.splits, legacy.order)
      legacy.widgets.G8 = { enabledV1: false, enabledV2: false }
      stateOwner.config = legacy
      const legacyBefore = snapshot()
      require(bar.reconcileV1PluginGroups() && snapshot() === legacyBefore
        && !bar.v1FamilySlotBindings.G8,
        "existing explicit clone placement was migrated during reconciliation")

      const v2 = copy(initialState)
      v2.presentation.shellStyle = "full"
      stateOwner.config = v2
      host.shellConfig = copy(initialShell)
      bar.layoutConfig = copy(initialShell.bar.layout)
      changed = copy(manifests)
      changed["local.clock"].barWidget.allowMultiple = true
      nativeRegistry.installedPlugins = changed
      require(bar.setBarWidgetInstalled("omarchy.clock", true, "center")
        && nativeRegistry.resolveEnabledId("omarchy.clock") === "local.clock"
        && host.shellConfig.bar.layout.center[0].id === "local.clock",
        "V1 clone restriction leaked into V2")
      require(!nativeRegistry.initProcess.running && !nativeRegistry.scanProcess.running
        && !nativeRegistry.localPluginWatcher.running && !nativeRegistry.localPluginWatcherRestart.running,
        "native registry fixture started filesystem workers")
    } finally {
      registry.forcedSelection = null
      registry.refusedId = ""
      registry.refuseEnable = false
      bar.pluginRegistry = savedRegistry
      stateOwner.config = savedState
      host.shellConfig = savedShell
      bar.layoutConfig = savedLayout
    }
    console.log("clone selection regression passed (real registry methods, isolated fixture)")
    return true
  }
}
