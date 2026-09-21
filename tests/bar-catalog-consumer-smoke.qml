import QtQuick
import Quickshell
import "hancore.shibumi.bar" as BarPlugin
import "hancore.shibumi.state/runtime" as SuiteRuntime

ShellRoot {
  id: root

  property int stage: 0
  property int waits: 0
  property var bar: null
  property var firstService: null
  property var duplicateService: null
  property var replacementService: null
  property int writesBeforePublication: -1
  property int stateLayoutCallsBeforeMetadata: -1
  property int providerRevisionBeforeMetadata: -1
  property string layoutBeforeMetadata: ""
  property string orderBeforeMetadata: ""

  function fail(message) {
    console.error("bar-catalog-consumer-smoke:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  function observation(rows, generation) {
    const entries = []
    const byId = Object.create(null)
    for (let index = 0; index < rows.length; index++) {
      const source = rows[index]
      const row = Object.freeze({ id: source.id, name: source.id,
        kinds: Object.freeze(["bar-widget"]), enabled: source.enabled === true,
        active: false, canDisable: true, firstParty: false,
        clonedFrom: source.clonedFrom || "", description: "Fixture widget",
        author: "Fixture", version: "1.0.0", tags: Object.freeze(["fixture"]),
        barWidget: Object.freeze({displayName: source.id,
          description: "Fixture widget", category: "Fixture",
          semanticCapabilities: Object.freeze([]), defaultSection: "center",
          allowMultiple: false}) })
      entries.push(row)
      byId[row.id] = row
    }
    return Object.freeze({ serial: generation, generation: generation,
      snapshot: Object.freeze({ catalogKind: "native-listPlugins",
        entries: Object.freeze(entries), byId: Object.freeze(byId) }) })
  }

  QtObject {
    id: stateService
    property bool ready: true
    property int revision: 0
    property int setLayoutCalls: 0
    property color selectedColor: "#ffffff"
    property var config: ({ presentation: ({ shellStyle: "shibumi" }) })
    onConfigChanged: revision++
    function setLayout(order, splits) {
      setLayoutCalls++
      const next = JSON.parse(JSON.stringify(config))
      next.order = order
      next.splits = splits
      config = next
      return true
    }
  }
  QtObject { id: stateHost; property string pluginId: "hancore.shibumi.state" }
  SuiteRuntime.Provider {
    id: stateProvider
    pluginId: "hancore.shibumi.state"
    implementationVersion: "0.1.1-beta.15.2"
    owner: stateService
    host: stateHost
    manifest: ({ id: "hancore.shibumi.state", version: "0.1.1-beta.15.2",
      kinds: ["service"] })
  }

  QtObject {
    id: scopedBarHost
    property string pluginId: "hancore.shibumi.bar"
    property var bar: null
    property var barConfig: ({})
    property int mutateCalls: 0
    property int updateCalls: 0
    function mutateShellConfig(callback) { mutateCalls++; return false }
    function updateEntryInline(pluginId, settings) { updateCalls++; return false }
  }

  // Exact public shape of Omarchy 4.0.3 PluginRegistryApi.qml at
  // 0534987009061cbe2dacdde4ad564092ab698d12. It deliberately has no
  // pluginsChanged signal and exposes only the active full bar's own manifest.
  QtObject {
    id: fakePluginRegistry
    property string pluginId: "hancore.shibumi.bar"
    property var manifest: ({ id: "hancore.shibumi.bar",
      version: "0.1.1-beta.15.2", kinds: ["bar"] })
    property bool enabled: true
    property var _entryPointUrl: null
    readonly property var installedPlugins: {
      const out = ({})
      if (manifest) out[pluginId] = manifest
      return out
    }
    function isEnabled(id) {
      return String(id || "") === pluginId && enabled
    }
    function resolveEnabledId(id) {
      return String(id || "") === pluginId ? pluginId : ""
    }
    function entryPointUrl(candidate, kind) {
      if (!candidate || String(candidate.id || "") !== pluginId) return ""
      return _entryPointUrl ? _entryPointUrl(String(kind || "")) : ""
    }
  }
  QtObject {
    id: fakeWidgetRegistry
    property int revision: 0
    property var widgets: root.clockWidgetSnapshot()
  }

  function clockWidgetSnapshot() {
    return ({
      "local.clock": ({ component: null,
        metadata: ({ pluginId: "local.clock", allowMultiple: false }) })
    })
  }

  Component {
    id: catalogServiceFactory
    Item {
      id: service
      property int acquireCalls: 0
      property int releaseCalls: 0
      property int wrongReleaseCalls: 0
      property var token: null
      property var holder: null
      property var currentObservation: null
      property bool catalogReady: currentObservation !== null
      property int catalogReadSerial: currentObservation ? currentObservation.serial : 0
      property int catalogGeneration: currentObservation ? currentObservation.generation : 0
      property var providerManifest: ({ id: "hancore.shibumi.control-center",
        version: "0.1.1-beta.15.2", kinds: ["service"] })
      QtObject { id: serviceHost; property string pluginId: "hancore.shibumi.control-center" }
      SuiteRuntime.Provider {
        pluginId: "hancore.shibumi.control-center"
        implementationVersion: "0.1.1-beta.15.2"
        owner: service
        host: serviceHost
        manifest: service.providerManifest
      }
      function acquireCatalogConsumer(value) {
        if (token && holder === value) return token
        if (token) return null
        acquireCalls++
        holder = value
        token = Object.freeze({ service: service, serial: acquireCalls })
        return token
      }
      function releaseCatalogConsumer(value) {
        if (!token || value !== token) { wrongReleaseCalls++; return false }
        releaseCalls++
        token = null
        holder = null
        currentObservation = null
        return true
      }
      function hasCatalogConsumer(value) { return token !== null && value === token }
      function catalogObservation(value) {
        return hasCatalogConsumer(value) ? currentObservation : null
      }
      function isCatalogObservationCurrent(value, candidate) {
        return hasCatalogConsumer(value) && candidate !== null
          && candidate === currentObservation
      }
      function publish(value) { currentObservation = value }
    }
  }

  Component {
    id: barFactory
    BarPlugin.Bar { outputWindowsEnabled: false }
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      if (++root.waits > 150) root.fail("timed out at stage " + root.stage)
      if (root.stage === 0) {
        if (!SuiteRuntime.Runtime.ready || !stateProvider.registered) return
        root.firstService = catalogServiceFactory.createObject(root)
        root.bar = barFactory.createObject(root, {
          omarchyPath: "/fixture/omarchy",
          shell: scopedBarHost,
          manifest: ({ id: "hancore.shibumi.bar", version: "0.1.1-beta.15.2",
            kinds: ["bar"] }),
          pluginRegistry: fakePluginRegistry,
          barWidgetRegistry: fakeWidgetRegistry,
          barConfig: ({ id: "hancore.shibumi.bar", position: "top",
            style: "shibumi", centerAnchor: "omarchy.clock",
            layout: ({ left: [], center: [{ id: "local.clock",
              shibumiModule: true }], right: [] }) })
        })
        root.stage = 1; root.waits = 0
      } else if (root.stage === 1) {
        if (!root.bar || root.firstService.acquireCalls !== 1
            || root.firstService.holder !== root.bar) return
        const configured = ({ id: "hancore.shibumi.bar", position: "top",
          style: "shibumi", centerAnchor: "omarchy.clock",
          layout: ({ left: [], center: [{ id: "local.clock",
            shibumiModule: true }], right: [] }) })
        root.bar.barConfig = configured
        root.bar.layoutConfig = configured.layout
        root.writesBeforePublication = scopedBarHost.mutateCalls + scopedBarHost.updateCalls
        root.firstService.publish(root.observation([
          { id: "omarchy.clock", enabled: false },
          { id: "local.clock", clonedFrom: "omarchy.clock", enabled: true }
        ], 1))
        root.stage = 2; root.waits = 0
      } else if (root.stage === 2) {
        if (root.waits < 5) return
        if (!root.bar.catalogObservation
            || JSON.stringify(root.bar.widgetCapabilities("local.clock")) !== '["clock"]'
            || root.bar.widgetCapabilities("omarchy.clock").length !== 0
            || root.bar.v1FamilySlotBindings.G8 !== "local.clock")
          root.fail("current scoped observation did not classify the exact clone: observation="
            + root.bar.catalogObservation + " clone="
            + JSON.stringify(root.bar.widgetCapabilities("local.clock"))
            + " original=" + JSON.stringify(root.bar.widgetCapabilities("omarchy.clock"))
            + " binding=" + JSON.stringify(root.bar.v1FamilySlotBindings)
            + " specs=" + JSON.stringify(root.bar.v1PluginSpecs())
            + " layout=" + JSON.stringify(root.bar.layoutConfig)
            + " slots=" + JSON.stringify(root.bar.layoutController.v1Slots))
        if (scopedBarHost.mutateCalls + scopedBarHost.updateCalls
              !== root.writesBeforePublication)
          root.fail("catalog publication started a mutation/reconcile write")

        root.stateLayoutCallsBeforeMetadata = stateService.setLayoutCalls
        root.providerRevisionBeforeMetadata = root.bar.providerRegistryRevision
        root.layoutBeforeMetadata = JSON.stringify(root.bar.layoutConfig)
        root.orderBeforeMetadata = JSON.stringify(root.bar.layoutController.v1Slots)
        // The scoped API republishes these properties directly. There is no
        // pluginsChanged signal for Bar's legacy listener to receive.
        fakePluginRegistry.enabled = false
        fakePluginRegistry.manifest = ({ id: "hancore.shibumi.bar",
          version: "0.1.1-beta.15.2-metadata", kinds: ["bar"] })
        root.stage = 20; root.waits = 0
      } else if (root.stage === 20) {
        if (root.waits < 3) return
        if (fakePluginRegistry.installedPlugins["hancore.shibumi.bar"]
              !== fakePluginRegistry.manifest
            || root.bar.providerRegistryRevision
              !== root.providerRevisionBeforeMetadata
            || root.bar.v1FamilySlotBindings.G8 !== "local.clock"
            || JSON.stringify(root.bar.layoutConfig) !== root.layoutBeforeMetadata
            || JSON.stringify(root.bar.layoutController.v1Slots)
              !== root.orderBeforeMetadata
            || stateService.setLayoutCalls
              !== root.stateLayoutCallsBeforeMetadata)
          root.fail("scoped manifest/enabled publication reached the legacy listener or changed provider state")

        // Omarchy's real pluginsChanged fan-out separately republishes the
        // detached BarWidgetRegistry snapshot/revision after syncPluginWidgets.
        // Model a disabled widget while keeping bar.layout byte-for-byte fixed.
        fakeWidgetRegistry.widgets = ({})
        fakeWidgetRegistry.revision++
        root.firstService.publish(root.observation([
          { id: "omarchy.clock", enabled: false },
          { id: "local.clock", clonedFrom: "omarchy.clock", enabled: false }
        ], 2))
        root.stage = 21; root.waits = 0
      } else if (root.stage === 21) {
        if (root.waits < 3) return
        if (root.bar.v1FamilySlotBindings.G8 !== undefined
            || JSON.stringify(root.bar.widgetCapabilities("local.clock"))
              !== '["clock"]'
            || root.bar.providerRegistryRevision
              !== root.providerRevisionBeforeMetadata
            || JSON.stringify(root.bar.layoutConfig) !== root.layoutBeforeMetadata
            || JSON.stringify(root.bar.layoutController.v1Slots)
              !== root.orderBeforeMetadata
            || stateService.setLayoutCalls
              !== root.stateLayoutCallsBeforeMetadata)
          root.fail("scoped widget disable did not update only the reactive V1 binding")

        fakePluginRegistry.enabled = true
        fakeWidgetRegistry.widgets = root.clockWidgetSnapshot()
        fakeWidgetRegistry.revision++
        root.firstService.publish(root.observation([
          { id: "omarchy.clock", enabled: false },
          { id: "local.clock", clonedFrom: "omarchy.clock", enabled: true }
        ], 3))
        root.stage = 22; root.waits = 0
      } else if (root.stage === 22) {
        if (root.waits < 3) return
        if (root.bar.v1FamilySlotBindings.G8 !== "local.clock"
            || root.bar.providerRegistryRevision
              !== root.providerRevisionBeforeMetadata
            || JSON.stringify(root.bar.layoutConfig) !== root.layoutBeforeMetadata
            || JSON.stringify(root.bar.layoutController.v1Slots)
              !== root.orderBeforeMetadata
            || stateService.setLayoutCalls
              !== root.stateLayoutCallsBeforeMetadata)
          root.fail("scoped widget re-enable did not restore the reactive V1 binding")

        // A catalog metadata change can move the same rendered provider to a
        // different fixed family without a bar.layout assignment.
        root.firstService.publish(root.observation([
          { id: "omarchy.audio", enabled: false },
          { id: "local.clock", clonedFrom: "omarchy.audio", enabled: true }
        ], 4))
        root.stage = 23; root.waits = 0
      } else if (root.stage === 23) {
        if (root.waits < 3) return
        if (JSON.stringify(root.bar.widgetCapabilities("local.clock"))
              !== '["audio"]'
            || root.bar.v1FamilySlotBindings.G6 !== "local.clock"
            || root.bar.v1FamilySlotBindings.G8 !== undefined
            || root.bar.providerRegistryRevision
              !== root.providerRevisionBeforeMetadata
            || JSON.stringify(root.bar.layoutConfig) !== root.layoutBeforeMetadata
            || JSON.stringify(root.bar.layoutController.v1Slots)
              !== root.orderBeforeMetadata
            || stateService.setLayoutCalls
              !== root.stateLayoutCallsBeforeMetadata)
          root.fail("scoped catalog metadata did not reactively move the visible family binding")

        root.duplicateService = catalogServiceFactory.createObject(root)
        root.stage = 3; root.waits = 0
      } else if (root.stage === 3) {
        if (root.firstService.releaseCalls !== 1) return
        if (root.bar.catalogObservation
            || root.bar.widgetCapabilities("omarchy.clock").length !== 0
            || root.duplicateService.acquireCalls !== 0)
          root.fail("duplicate provider retained observation or legacy authority")
        root.duplicateService.destroy()
        root.duplicateService = null
        root.stage = 4; root.waits = 0
      } else if (root.stage === 4) {
        if (root.firstService.acquireCalls !== 2) return
        root.firstService.providerManifest = ({ id: "invalid",
          version: "0.1.1-beta.15.2", kinds: ["service"] })
        root.stage = 5; root.waits = 0
      } else if (root.stage === 5) {
        if (root.firstService.releaseCalls !== 2) return
        if (root.bar.catalogObservation
            || root.bar.widgetCapabilities("local.clock").length !== 0)
          root.fail("provider loss retained scoped classification")
        root.replacementService = catalogServiceFactory.createObject(root)
        root.stage = 6; root.waits = 0
      } else if (root.stage === 6) {
        if (root.replacementService.acquireCalls !== 1) return
        root.replacementService.publish(root.observation([
          { id: "omarchy.clock", enabled: true }
        ], 2))
        root.stage = 7; root.waits = 0
      } else if (root.stage === 7) {
        if (!root.bar.catalogObservation
            || JSON.stringify(root.bar.widgetCapabilities("omarchy.clock")) !== '["clock"]')
          return
        const providerRevision = root.bar.providerRegistryRevision
        if (!root.bar.prepareForShutdown()
            || root.replacementService.releaseCalls !== 1
            || root.bar.rebindCatalogConsumer()
            || root.replacementService.acquireCalls !== 1)
          root.fail("shutdown retained or reacquired the catalog consumer")
        fakePluginRegistry.manifest = ({ id: "hancore.shibumi.bar",
          version: "0.1.1-beta.15.2-shutdown", kinds: ["bar"] })
        if (root.bar.providerRegistryRevision !== providerRevision)
          root.fail("shutdown accepted a late scoped registry publication")
        root.stage = 8; root.waits = 0
      } else if (root.stage === 8) {
        if (root.waits < 5) return
        if (root.replacementService.acquireCalls !== 1
            || root.replacementService.releaseCalls !== 1)
          root.fail("shutdown callLater work rebound the catalog consumer")
        root.bar.destroy()
        root.bar = null
        root.stage = 9; root.waits = 0
      } else if (root.stage === 9) {
        if (root.replacementService.releaseCalls !== 1) return
        if (root.firstService.wrongReleaseCalls !== 0
            || root.replacementService.wrongReleaseCalls !== 0
            || scopedBarHost.mutateCalls + scopedBarHost.updateCalls
              !== root.writesBeforePublication)
          root.fail("catalog shutdown/destruction used a wrong token or mutated host state")
        console.log("bar catalog consumer smoke passed")
        Qt.exit(0)
      }
    }
  }
}
