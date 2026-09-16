pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "hancore.shibumi.bar" as BarPlugin
import "hancore.shibumi.bar/core" as Core
import "hancore.shibumi.state/runtime" as Shared

ShellRoot {
  id: root

  readonly property string privateCanary:
    "/home/private-user/.config/credential-token.json"
  property var fixtureObjects: []
  property bool fixtureReady: false

  function configuredLayout() {
    const left = []
    for (let index = 0; index < 70; index++)
      left.push({id: "fixture.widget-" + index})
    return {left: left, center: [], right: []}
  }

  function registrySnapshot() {
    const snapshot = ({})
    for (let index = 0; index < 300; index++) {
      const id = "fixture.widget-" + index
      snapshot[id] = {
        component: index === 1 ? statuslessObject
          : index === 2 ? malformedStatusObject
          : index === 3 ? readyWidgetComponent : null,
        metadata: {
          pluginId: id,
          sourceUrl: privateCanary,
          privateMetadata: privateCanary
        }
      }
    }
    return snapshot
  }

  function verifyOutputLifecycleDiagnostics() {
    if (!diagnosticBar.mutationAdmissionReady
        || diagnosticBar.moduleSlots.indexOf(unresolvedSlot) < 0)
      return false
    const configured = diagnosticBar.barConfig
    const pluginId = "fixture.widget-0"
    diagnosticBar.hostOutputPresenceObserved = false
    diagnosticBar.hostOutputLossObserved = false
    diagnosticBar.hostOutputReturnObserved = false
    diagnosticBar.hostOutputPreviouslyReadyWidgetIds = ({})
    diagnosticBar.hostOutputLossReadyWidgetIds = ({})
    unresolvedSlot.resolutionAttempts = 10

    // Cold zero outputs and a first positive output without a previously
    // loaded current widget are chronology only, never warning evidence.
    if (diagnosticBar.observeHostOutputCount(0)
        || !diagnosticBar.observeHostOutputCount(1)
        || diagnosticBar.hostWidgetResolutionWarningEvidence(
          unresolvedSlot, 1)) return false
    diagnosticBar.hostOutputPreviouslyReadyWidgetIds = ({
      "fixture.widget-0": true
    })
    if (diagnosticBar.hostWidgetResolutionWarningEvidence(unresolvedSlot, 1)
        || !diagnosticBar.observeHostOutputCount(0)
        || diagnosticBar.hostWidgetResolutionWarningEvidence(
          unresolvedSlot, 0)) return false

    // Screensaver pre-hide is excluded from output chronology and triggers no
    // IPC or other action.
    idleService.screensaverStartedThisCycle = true
    if (diagnosticBar.observeHostOutputCount(1)
        || diagnosticBar.hostOutputReturnObserved
        || diagnosticBar.hostWidgetResolutionWarningEvidence(
          unresolvedSlot, 1)) return false
    idleService.screensaverStartedThisCycle = false
    if (!diagnosticBar.observeHostOutputCount(1)) return false
    const evidence = diagnosticBar.hostWidgetResolutionWarningEvidence(
      unresolvedSlot, 1)
    if (!evidence || evidence.pluginId !== pluginId
        || evidence.screenLabel !== "unknown" || evidence.retryCount !== 10
        || evidence.facadeScoped !== true
        || evidence.facadeRegistryPresent !== true
        || evidence.facadeConfigured !== true
        || evidence.facadeEnabled !== true
        || evidence.previouslyResolved !== true
        || evidence.outputSequence !== true
        || evidence.shutdown !== false)
      return false

    unresolvedSlot.entry = ({id: pluginId, enabled: false})
    if (diagnosticBar.hostWidgetResolutionWarningEvidence(unresolvedSlot, 1))
      return false
    unresolvedSlot.entry = ({id: pluginId})
    unresolvedSlot.resolutionAttempts = 10
    diagnosticBar.barConfig = ({
      id: "hancore.shibumi.bar", position: "top", style: "shibumi",
      layout: ({left: [], center: [], right: []})
    })
    if (diagnosticBar.hostWidgetResolutionWarningEvidence(unresolvedSlot, 1))
      return false
    diagnosticBar.barConfig = configured
    unresolvedSlot.resolutionAttempts = 9
    if (diagnosticBar.hostWidgetResolutionWarningEvidence(unresolvedSlot, 1)
        || diagnosticBar.validDiagnosticPluginId("../private") !== "")
      return false
    unresolvedSlot.resolutionAttempts = 10

    const truthySlot = fakeSlotFactory.createObject(root, {
      moduleName: pluginId,
      screenName: "TEST-TRUTHY",
      resolutionAttempts: 10,
      resolvedComponent: statuslessObject
    })
    diagnosticBar.registerModuleSlot(truthySlot)
    const truthyRejected =
      !diagnosticBar.hostWidgetResolutionWarningCandidate(truthySlot, 1)
      && !diagnosticBar.hostWidgetSlotLoadedCurrent(truthySlot, pluginId)
      && !diagnosticBar.noteHostWidgetResolution(truthySlot, true)
    diagnosticBar.unregisterModuleSlot(truthySlot)
    truthySlot.destroy()
    if (!truthyRejected) return false

    // Additional flaps preserve the bounded chronology without dispatching a
    // rescan or replenishing the process-wide warning budget.
    if (diagnosticBar.observeHostOutputCount(0)
        || !diagnosticBar.observeHostOutputCount(1)
        || !diagnosticBar.hostWidgetResolutionWarningEvidence(
          unresolvedSlot, 1)
        || Shared.Runtime.hostWidgetResolutionWarningEmitted)
      return false

    unresolvedSlot.resolutionAttempts = 0
    return true
  }

  function populateBoundedCensus() {
    if (fixtureReady) return
    if (!verifyOutputLifecycleDiagnostics()) {
      console.error("WIDGET_PIPELINE_OUTPUT_LIFECYCLE_ASSERTION_FAILED")
      Qt.exit(1)
      return
    }
    const retained = []
    for (let index = 0; index < 140; index++) {
      const slot = fakeSlotFactory.createObject(root, {
        moduleName: "fixture.slot-" + index,
        screenName: index === 0 ? privateCanary : "TEST-" + index,
        resolutionAttempts: index === 0 ? 999 : 1,
        resolvedComponent: index === 0 ? statuslessObject
          : index === 1 ? malformedStatusObject
          : index === 2 ? readyWidgetComponent : null,
        loaderStatus: index === 0 ? 999 : Loader.Null
      })
      retained.push(slot)
      diagnosticBar.registerModuleSlot(slot)
    }
    for (let index = 0; index < 20; index++) {
      const session = fakeSessionFactory.createObject(root, {
        screenName: index === 0 ? privateCanary : "TEST-" + index
      })
      retained.push(session)
      diagnosticBar.registerLayoutSession(session)
    }
    fixtureObjects = retained
    const state = diagnosticBar.debugWidgetPipeline()
    const unresolved = state.widgetSlots.entries.filter(function(entry) {
      return entry.id === "fixture.widget-0"
    })
    const expectedById = Object.create(null)
    for (const entry of state.expected.entries) expectedById[entry.id] = entry
    const slotsById = Object.create(null)
    for (const entry of state.widgetSlots.entries) slotsById[entry.id] = entry
    const serialized = JSON.stringify(state)
    if (diagnosticBar.debugBarGeometry().length !== 0
        || state.version !== 2
        || unresolved.length !== 1
        || unresolved[0].resolvedComponentPresent
        || unresolved[0].resolvedComponentStatusKind !== "missing"
        || unresolved[0].resolvedStatus !== -1
        || unresolved[0].currentLoadReady
        || unresolved[0].loaderActive
        || unresolved[0].loaderItem
        || !expectedById["fixture.widget-0"]
        || expectedById["fixture.widget-0"].componentPresent
        || expectedById["fixture.widget-0"].componentStatusKind !== "missing"
        || !expectedById["fixture.widget-1"].componentPresent
        || expectedById["fixture.widget-1"].componentStatusKind !== "undefined"
        || expectedById["fixture.widget-1"].componentStatus !== -1
        || !expectedById["fixture.widget-2"].componentPresent
        || expectedById["fixture.widget-2"].componentStatusKind !== "other"
        || expectedById["fixture.widget-2"].componentStatus !== -1
        || !expectedById["fixture.widget-3"].componentPresent
        || expectedById["fixture.widget-3"].componentStatusKind !== "number"
        || !slotsById["fixture.slot-0"].resolvedComponentPresent
        || slotsById["fixture.slot-0"].resolvedComponentStatusKind !== "undefined"
        || slotsById["fixture.slot-0"].currentLoadReady
        || slotsById["fixture.slot-1"].resolvedComponentStatusKind !== "other"
        || slotsById["fixture.slot-1"].currentLoadReady
        || state.outputLifecycle.sequence !== "positive-zero-positive"
        || state.outputLifecycle.previouslyReadyWidgetCount !== 1
        || state.outputLifecycle.lossReadyWidgetCount !== 1
        || state.outputLifecycle.warningEmitted
        || !state.expected.truncated
        || state.expected.entries.length !== 64
        || !state.registry.snapshotKeyCountTruncated
        || state.registry.snapshotKeyCount !== 256
        || !state.outputs.truncated
        || state.outputs.sessions.length !== 16
        || !state.widgetSlots.truncated
        || state.widgetSlots.entries.length !== 128
        || serialized.indexOf(privateCanary) >= 0) {
      console.error("WIDGET_PIPELINE_DIAGNOSTICS_ASSERTION_FAILED")
      Qt.exit(1)
      return
    }
    fixtureReady = true
    console.log("WIDGET_PIPELINE_DIAGNOSTICS_READY")
  }

  QtObject {
    id: idleService
    property bool screensaverStartedThisCycle: false
  }

  QtObject {
    id: stateOwner
    property bool ready: true
  }

  QtObject {
    id: stateHost
    property string pluginId: "hancore.shibumi.state"
  }

  Shared.Provider {
    id: stateProvider
    pluginId: "hancore.shibumi.state"
    implementationVersion: "0.1.1-beta.14.1"
    owner: stateOwner
    host: stateHost
    manifest: ({ id: "hancore.shibumi.state",
      version: "0.1.1-beta.14.1", kinds: ["service"] })
  }

  QtObject {
    id: scopedShell
    readonly property string pluginId: "hancore.shibumi.bar"
    property var barConfig: diagnosticBar.barConfig
    property var bar: null
    function serviceFor(id) { return null }
    function firstPartyServiceFor(id) {
      return id === "omarchy.idle" ? idleService : null
    }
    function mutateShellConfig(mutator) { return false }
    function updateEntryInline(id, settings) { return false }
    function pluginShellForBarEntry(ownerId, moduleName) { return null }
    function summon(id, payloadJson) { return false }
    function hide(id) { return false }
    function toggle(id, payloadJson) { return false }
    function isPluginOpen(id) { return false }
  }

  QtObject {
    id: scopedPluginRegistry
    readonly property string pluginId: "hancore.shibumi.bar"
  }

  QtObject { id: statuslessObject }

  QtObject {
    id: malformedStatusObject
    property string status: "ready"
  }

  QtObject {
    id: scopedWidgetRegistry
    property var widgets: root.registrySnapshot()
    property int revision: 73
  }

  BarPlugin.Bar {
    id: diagnosticBar
    outputWindowsEnabled: false
    nativeRegistryPrimeEnabled: false
    omarchyPath: "/private/fixture/omarchy"
    shell: scopedShell
    pluginRegistry: scopedPluginRegistry
    barWidgetRegistry: scopedWidgetRegistry
    manifest: ({
      id: "hancore.shibumi.bar",
      version: "0.1.1-beta.14.1",
      kinds: ["bar"]
    })
    barConfig: ({
      id: "hancore.shibumi.bar",
      position: "top",
      style: "shibumi",
      layout: root.configuredLayout()
    })

    Core.WidgetSlot {
      id: unresolvedSlot
      bar: diagnosticBar
      entry: ({id: "fixture.widget-0"})
      screenName: root.privateCanary
    }
  }

  Component {
    id: readyWidgetComponent
    Item {
      implicitWidth: 10
      implicitHeight: 10
    }
  }

  Component {
    id: fakeSlotFactory
    QtObject {
      property string moduleName: ""
      property string screenName: ""
      property bool moduleEnabled: true
      property int resolutionAttempts: 0
      property var resolvedComponent: null
      property bool loaderActive: false
      property int loaderStatus: Loader.Null
      property bool loaderHasItem: false
      property var activeItem: null
    }
  }

  Component {
    id: fakeSessionFactory
    QtObject { property string screenName: "" }
  }

  Timer {
    interval: 25
    running: true
    repeat: true
    onTriggered: {
      root.populateBoundedCensus()
      if (root.fixtureReady) stop()
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: false
    onTriggered: {
      console.error("WIDGET_PIPELINE_DIAGNOSTICS_TIMEOUT")
      Qt.exit(1)
    }
  }
}
