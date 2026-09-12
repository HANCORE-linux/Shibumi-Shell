import QtQuick
import Quickshell.Io
import qs.Ui as Ui
import "core/V2LayoutModel.js" as Layout
import "../hancore.shibumi.state/runtime" as Shared
Bar {
  id: probe
  outputWindowsEnabled: false
  property var controlWidget: null
  property var transitionTarget: null
  property var capturedCatalogObservation: null
  QtObject {
    id: incompleteState
    property var source: null
    property var config: ({})
    property bool ready: true
    property bool writePending: false
    property int writeSerial: 0
    property int calls: 0
    signal persistenceSettled(int serial, string result)
    function same(a, b) { return source.same(a, b) }
    function normalizedLayoutFamilyPatch(value) { return source.normalizedLayoutFamilyPatch(value) }
    function layoutFamilySnapshot(value) { return source.layoutFamilySnapshot(value) }
    function setLayoutFamilyTransition(value) { calls++; return true }
    function setV2Layout(value) { calls++; return true }
    function resetV2Layout() { calls++; return true }
    // Deliberately missing compensation: scoped hosts must reject, not fall
    // back to the legacy chain. No method calls through to a native writer.
  }
  QtObject {
    id: controlSlot
    property string moduleName: "hancore.shibumi.control-center"
    property string screenName: ""
    property var activeItem: probe.controlWidget
    property bool visible: true
  }
  function controlObjectCount() {
    let count = 0
    for (let index = 0; index < children.length; index++)
      if (children[index].objectName === "native-fixture-control-widget") count++
    return count
  }
  Ui.PluginBarApi {
    id: controlApi
    pluginId: "hancore.shibumi.control-center"
    moduleName: "hancore.shibumi.control-center"
    foreground: "#eeeeee"
    barForeground: foreground
    background: "#181818"
    urgent: "#88bbee"
    fontFamily: "monospace"
    barSize: 28
    foregroundAnimationEnabled: false
  }
  IpcHandler {
    target: "native-runtime-probe"
    function status(): string {
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      const lease = Shared.Runtime._selected("hancore.shibumi.state")
      const updates = Shared.Runtime.serviceFor("hancore.shibumi.control-center")
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      return JSON.stringify({runtimeReady: Shared.Runtime.ready,
        barRegistered: Shared.Runtime.isActiveBar(probe),
        hostReady: probe.hostReady, styleReady: probe.styleReady,
        stateReady: !!state && state.ready,
        stateSerial: lease ? lease.serial : 0,
        stateObjectName: state ? state.objectName : "",
        controlLoaded: !!probe.controlWidget,
        controlObjectCount: probe.controlObjectCount(),
        restoreCount: probe.pendingWidgetRestores.length,
        restoreWaiting: probe.pendingWidgetRestores.some(record => record.waitingWrites && record.waitingWrites.length > 0),
        stateWritePending: !!state && state.writePending,
        layoutBusy: probe.layoutTransitionBusy,
        layoutSerial: probe.layoutTransitionSerial,
        layoutResult: probe.layoutTransitionResult,
        v2Mode: probe.layoutController.v2Mode,
        audioV1Enabled: !!state && state.groupEnabledForVariant("G6", "v1"),
        audioV2Enabled: !!state && state.groupEnabledForVariant("G6", "v2"),
        providerSnapshotBusy: probe.providerSnapshotTransitionBusy,
        providerSnapshotSerial: probe.providerSnapshotTransitionSerial,
        providerSnapshotResult: probe.providerSnapshotTransitionResult,
        stateTransitionBusy: probe.stateTransitionBusy,
        stateTransitionSerial: probe.stateTransitionSerial,
        stateTransitionResult: probe.stateTransitionResult,
        controlCatalogInstalled: panel && panel.settingsPageItem
          && typeof panel.settingsPageItem.entryById === "function"
          && panel.settingsPageItem.entryById("hancore.shibumi.control-center")
          ? panel.settingsPageItem.entryById(
              "hancore.shibumi.control-center").installedInBar : null,
        pageTransitionPending: !!panel && !!panel.settingsPageItem
          && panel.settingsPageItem.transitionPending,
        pageFeedbackTitle: panel && panel.settingsPageItem
          ? panel.settingsPageItem.feedbackTitle : "",
        pageFeedbackVisible: !!panel && !!panel.settingsPageItem
          && panel.settingsPageItem.feedbackVisible,
        pageUndoMode: panel && panel.settingsPageItem
          ? panel.settingsPageItem.undoMode : "",
        pageUndoSnapshot: panel && panel.settingsPageItem
          ? panel.settingsPageItem.undoProviderSnapshot : null,
        pageUndoSnapshotValid: !!panel && !!panel.settingsPageItem
          && probe.validScopedProviderSnapshot(
            panel.settingsPageItem.undoProviderSnapshot),
        pageUndoLayoutCurrent: !!panel && !!panel.settingsPageItem
          && !!panel.settingsPageItem.undoProviderSnapshot
          && JSON.stringify(probe.observedLayoutSnapshot()) === JSON.stringify(
            panel.settingsPageItem.undoProviderSnapshot.expectedLayout),
        catalogReadSerial: updates ? updates.catalogReadSerial : 0,
        catalogConsumerCount: updates ? updates.catalogConsumerCount : 0,
        panelPage: panel ? panel.settingsPage : "",
        panelPageReady: !!panel && panel.settingsPageReady,
        panelCatalog: panel && panel.pluginCatalogSnapshot
          ? panel.pluginCatalogSnapshot : null,
        injectedBar: probe.barConfig,
        panelLoaded: !!panel,
        panelStateMatches: !!panel && panel.stateService === state,
        panelUpdatesMatch: !!panel && !!updates && panel.effectivePluginUpdateService === updates,
        config: state ? state.config : null,
        hostBar: probe.shell ? probe.shell.barConfig : null})
    }
    function scopedServiceRoster(): string {
      const rows = []
      for (const id of Shared.Runtime.providerIds) {
        const owner = Shared.Runtime.serviceFor(id)
        const lease = Shared.Runtime._selected(id)
        rows.push({id: id, published: owner !== null,
          exactOwner: !!owner && !!lease && lease.owner === owner,
          manifestBound: !!owner && !!owner.manifest
            && owner.manifest.id === id
            && owner.manifest.version === Shared.Runtime.suiteVersion,
          scopedHostBound: !!lease && !!lease.host && "pluginId" in lease.host
            && lease.host.pluginId === id})
      }
      return JSON.stringify(rows)
    }
    function checkIncompleteState(): string {
      const original = probe.layoutController.stateService
      incompleteState.source = original
      incompleteState.config = Object.assign({}, original.config, {presentation: {shellStyle: "full"}})
      incompleteState.calls = 0
      probe.layoutController.stateService = incompleteState
      const refused = !probe.layoutTransitionsSupported && !probe.legacyFamilyMutationAllowed()
        && !probe.layoutController.persistV2Layout(Layout.defaultLayout())
        && !probe.layoutController.reconcileV2PluginGroups([], true, false)
        && !probe.layoutController.resetV2Layout()
        && !probe.setBarWidgetInstalled("hancore.shibumi.control-center", false, "left")
        && incompleteState.calls === 0
      probe.layoutController.stateService = original
      return refused ? "scoped-incomplete-no-writes" : "failed"
    }
    function prepareTransition(): string {
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      if (!state || !state.ready || state.writePending || probe.layoutTransitionBusy) return "not-ready"
      const initial = Layout.defaultLayout(); initial.left.push("G:fixture.layout-probe")
      const target = JSON.parse(JSON.stringify(initial)); target.left.pop()
      target.right[target.right.length - 1] = "G:fixture.layout-probe"
      probe.transitionTarget = target
      // A constructed, unregistered entry stays empty. No foreign manifest or
      // original-component fallback is supplied by this fixture.
      probe.shell.mutateShellConfig(function(config) {
        config.bar.layout.left.push({id: "fixture.layout-probe", opaque: {deep: [17]}})
      })
      return state.setLayoutFamilyTransition({v2Layout: initial}) ? "queued" : "failed"
    }
    function runTransition(): string {
      const before = JSON.stringify(probe.barConfig)
      const accepted = probe.layoutController.persistV2Layout(probe.transitionTarget)
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      return accepted && state.writePending && probe.layoutTransitionBusy
        && JSON.stringify(probe.barConfig) === before ? "queued-without-native-mutation" : "failed"
    }
    function rememberState(value: string): string {
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      if (!state) return "not-ready"
      state.objectName = value
      return "ok"
    }
    function openControl(): string {
      const entry = probe.barWidgetRegistry.widgets["hancore.shibumi.control-center"]
      const component = probe.hostWidgetResolver.ensureComponent("hancore.shibumi.control-center")
      if (!entry || !component || component !== entry.component
          || component.status !== Component.Ready) return "not-ready"
      if (!probe.controlWidget) {
        // The native factory mutates its cache; don't invoke it in a binding.
        controlApi.shell = probe.shell.pluginShellForBarEntry(
          "hancore.shibumi.bar", "hancore.shibumi.control-center")
        if (!controlApi.shell) return "not-ready"
        probe.controlWidget = component.createObject(probe,
          {bar: controlApi, objectName: "native-fixture-control-widget"})
      }
      if (!probe.controlWidget) return "not-ready"
      probe.controlWidget.open()
      return "ok"
    }
    function openPlugins(): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      return panel && panel.showSettingsPage("plugins") ? "ok" : "not-ready"
    }
    function captureCatalog(): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      const page = panel ? panel.settingsPageItem : null
      probe.capturedCatalogObservation = page ? page.catalogObservation : null
      return probe.capturedCatalogObservation ? "captured" : "not-ready"
    }
    function staleCatalogToggle(): string {
      const before = JSON.stringify(probe.barConfig)
      const accepted = probe.requestCatalogLayoutTransition(
        "fixture.native-widget", true, "left", probe.capturedCatalogObservation)
      return !accepted && JSON.stringify(probe.barConfig) === before
        && !probe.layoutTransitionBusy ? "stale-refused" : "failed"
    }
    function catalogDefaultCannotAuthorize(): string {
      // A valid-looking section for a catalog-only service must not fabricate
      // the host component authority needed for activation.
      const request = probe.catalogTransitionIntent(
        "fixture.catalog-service", true, "left")
      return !request && !probe.canSetBarWidgetInstalled(
        "fixture.catalog-service", true) ? "refused" : "failed"
    }
    function toggleCatalogWidget(): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      const page = panel ? panel.settingsPageItem : null
      const before = JSON.stringify(probe.barConfig)
      const accepted = page && page.togglePluginById("fixture.native-widget")
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      if (accepted && state && probe.layoutTransitionBusy
          && JSON.stringify(probe.barConfig) === before
          && page.transitionPending
          && page.feedbackTitle.indexOf("Updating") === 0
          && page.undoMode === "")
        return "queued-without-native-mutation"
      return "failed:" + JSON.stringify({accepted: accepted,
        state: !!state, pending: !!state && state.writePending,
        busy: probe.layoutTransitionBusy,
        layoutResult: probe.layoutTransitionResult,
        unchanged: JSON.stringify(probe.barConfig) === before,
        canSet: probe.canSetBarWidgetInstalled("fixture.native-widget", true),
        pageEntry: page ? page.entryById("fixture.native-widget") : null})
    }
    function setControlGroupVisible(enabled: bool): string {
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      return state && state.setGroupEnabledForVariant("G1", "v1", enabled)
        ? "queued" : "not-ready"
    }
    function toggleFixedControlGroup(): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      const page = panel ? panel.settingsPageItem : null
      const entry = page ? page.entryById("hancore.shibumi.control-center") : null
      const before = JSON.stringify(probe.barConfig)
      const accepted = entry && entry.enabled === true
        && entry.installedInBar === false && page.togglePlugin(entry)
      return accepted && probe.stateTransitionBusy && !probe.layoutTransitionBusy
          && page.transitionPending && page.undoMode === ""
          && JSON.stringify(probe.barConfig) === before
        ? "queued-without-native-mutation" : "failed"
    }
    function undoFixedControlGroup(): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      const page = panel ? panel.settingsPageItem : null
      return page && page.undoLastChange() && page.transitionPending
          && probe.stateTransitionBusy ? "queued" : "failed"
    }
    function toggleAudioProvider(): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      const page = panel ? panel.settingsPageItem : null
      const before = JSON.stringify(probe.barConfig)
      const accepted = page && page.togglePluginById("fixture.audio-provider")
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      return accepted && state && probe.layoutTransitionBusy
          && JSON.stringify(probe.barConfig) === before
          && page.transitionPending && page.undoMode === ""
        ? "queued-without-native-mutation" : "failed"
    }
    function restoreShibumiAudio(): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      const page = panel ? panel.settingsPageItem : null
      const entry = page ? page.entryById("hancore.shibumi.audio") : null
      const accepted = entry && entry.replaced === true
        && page.togglePlugin(entry)
      return accepted && page.transitionPending && probe.layoutTransitionBusy
        ? "queued" : "failed"
    }
    function activePluginRemovalRefused(pluginId: string): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      if (!panel) return "not-ready"
      const accepted = panel.removePlugin(pluginId)
      return !accepted && !panel.pluginRemovalRunning
          && (panel.pluginActionError.indexOf("Deactivate") === 0
            || panel.pluginActionError.indexOf("Wait for") === 0)
        ? "refused-before-process" : "failed"
    }
    function undoPluginChange(): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      const page = panel ? panel.settingsPageItem : null
      if (!page) return "not-ready"
      const accepted = page.undoLastChange()
      if (accepted && page.transitionPending
          && probe.providerSnapshotTransitionBusy)
        return "queued"
      return !accepted && !page.transitionPending
          && page.undoMode === "provider-snapshot"
          && page.feedbackTitle === "Undo could not be completed"
        ? "refused-retained" : "failed"
    }
    function setShellStyle(value: string): string {
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      return state && state.setPresentationSetting("shellStyle", value)
        ? "queued" : "not-ready"
    }
    function setUndoConflict(enabled: bool): string {
      if (probe.layoutTransitionBusy || probe.providerSnapshotTransitionBusy)
        return "busy"
      const target = enabled === true
      probe.shell.mutateShellConfig(function(config) {
        const entries = config.bar.layout.left
        for (let index = 0; index < entries.length; index++) {
          const id = String(entries[index] && entries[index].id || entries[index] || "")
          if (id !== "hancore.shibumi.control-center") continue
          entries[index] = target
            ? {id: id, fixtureConcurrent: {opaque: [31]}} : id
          break
        }
      })
      return "queued"
    }
    function closeControl(): string {
      probe.unregisterModuleSlot(controlSlot)
      if (probe.controlWidget) {
        probe.controlWidget.close()
        probe.controlWidget.destroy()
        probe.controlWidget = null
      }
      return "ok"
    }
    function panelSetting(value: bool): string {
      const panel = probe.controlWidget ? probe.controlWidget.panelItem : null
      return panel && panel.setGroupSetting("G4", "compact", value) ? "queued" : "not-ready"
    }
    function panelSettingWithRestore(value: bool): string {
      if (!probe.controlWidget || !probe.controlWidget.panelItem) return "not-ready"
      // Use the same visual Bar injection as production WidgetSlot, after the
      // narrower native PluginBarApi route above has also been exercised.
      probe.controlWidget.bar = probe
      probe.registerModuleSlot(controlSlot)
      const panel = probe.controlWidget.panelItem
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      if (!panel || !state || !panel.setGroupSetting("G4", "compact", value)) return "not-ready"
      const records = probe.pendingWidgetRestores
      return state.writePending && records.length === 1
        && records[0].waitingWrites.length === 1 ? "queued-awaiting-settlement" : "restore-not-held"
    }
    function revokeBarDuringRestore(value: bool): string {
      if (panelSettingWithRestore(value) !== "queued-awaiting-settlement") return "not-held"
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      probe.scheduleWidgetRestore("fixture.other", "", false, null, "fixture-output")
      const original = probe.manifest
      probe.manifest = Object.assign({}, original, {version: "0.0.0"})
      const revoked = !Shared.Runtime.isActiveBar(probe) && state && state.ready
        && probe.pendingWidgetRestores.length === 0
      probe.manifest = original
      return revoked && probe.pendingWidgetRestores.length === 0 ? "revoked-with-ready-state" : "restore-not-revoked"
    }
    function compact(value: bool): string {
      const state = Shared.Runtime.serviceFor("hancore.shibumi.state")
      return state && state.setGroupSetting("G4", "compact", value) ? "queued" : "not-ready"
    }
  }
}
