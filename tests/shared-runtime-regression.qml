pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as StatePlugin
import "plugin/runtime" as Shared
import "host" as Host
import "bar" as BarProbe
import "left" as Left
import "right/deep" as Right

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property int stateDispatches: 0
  property int barDispatches: 0
  property bool finishRequested: false
  property bool observeOverlap: false
  property int overlapObservations: 0
  property var first: null
  property var second: null
  property var oldLease: null
  property var document: null
  FileView {
    id: writer
    path: Quickshell.env("XDG_CONFIG_HOME") + "/omarchy/shell.json"
    atomicWrites: true
    onLoaded: root.document = JSON.parse(text())
  }
  readonly property var initialBar: ({id: "hancore.shibumi.bar", transparent: true, unrelated: {nested: [1, 2]},
    shibumi: {version: 1, presentation: {accent: "color04"},
      widgets: {G4: {extra: {first: 1, second: 2}}}}})

  Left.Probe { id: left }
  Right.Probe { id: right }
  Host.PluginShellApi {
    id: stateApi
    pluginId: "hancore.shibumi.state"
    barConfig: root.initialBar
    _mutateBarConfig: function(callback) { root.check(false, "State requested Bar authority"); return false }
    _updateSettings: root.publishedWrite
  }
  Host.PluginShellApi {
    id: barApi
    pluginId: "hancore.shibumi.bar"
    barConfig: root.initialBar
    _mutateBarConfig: function(callback) { root.barDispatches++; return false }
  }
  Host.PluginShellApi { id: audioApi; pluginId: "hancore.shibumi.audio" }
  Host.PluginShellApi { id: replacementAudioApi; pluginId: "hancore.shibumi.audio" }
  StatePlugin.Service {
    id: state
    shell: stateApi
    omarchyPath: Quickshell.env("OMARCHY_PATH")
    manifest: ({id: "hancore.shibumi.state", version: "0.1.1-beta.14", kinds: ["service"]})
  }
  BarProbe.Marker { id: markerBar }
  Item {
    id: barOwner
    property var injectedHost: null
    property bool publishedReady: true
    property bool injectionComplete: injectedHost !== null && publishedReady
    property var barConfig: root.initialBar
    Shared.Provider {
      id: barProvider
      pluginId: "hancore.shibumi.bar"
      implementationVersion: "0.1.1-beta.14"
      owner: barOwner
      host: barOwner.injectedHost
      manifest: ({id: "hancore.shibumi.bar", version: "0.1.1-beta.14", kinds: ["bar"]})
    }
  }
  Shared.HostShell { id: client; host: stateApi }
  Component {
    id: serviceFactory
    Item {
      id: peer
      property var injectedHost: null
      property var injectedManifest: null
      property int value: 0
      Shared.Provider {
        pluginId: "hancore.shibumi.audio"
        implementationVersion: "0.1.1-beta.14"
        owner: peer
        host: peer.injectedHost
        manifest: peer.injectedManifest
      }
    }
  }

  function check(value, message) {
    if (value) return
    console.error("scoped-state-regression: " + message)
    Qt.exit(1)
    throw new Error(message)
  }
  function publishedWrite(id, entry) {
    check(id === "hancore.shibumi.state" && entry.id === id, "foreign dispatch")
    root.stateDispatches++
    const next = JSON.parse(JSON.stringify(document))
    const reordered = ({})
    // Complete-entry equality must not depend on JSON object key order.
    for (const key of Object.keys(entry).reverse()) reordered[key] = entry[key]
    next.plugins[0] = reordered
    document = next
    writer.setText(JSON.stringify(next))
    // Native publication refreshes retained manifests synchronously. Equivalent
    // metadata must retain the lease while the own-entry write is in flight.
    state.manifest = JSON.parse(JSON.stringify(state.manifest))
    return true
  }
  function advance() {
    if (++ticks > 250) check(false, "shared runtime readiness deadline " + phase + " " + state.writeStatus)
    if (phase === 0) {
      if (!Shared.Runtime.ready || left.state !== state || !state.suitePayloadLoaded
          || !markerBar.suitePayloadLoaded || !state.ready || !document) return
      check(left.instance === right.instance && left.instance === Shared.Runtime,
        "relative imports created multiple runtime instances")
      check(right.state === state, "independent importer could not see registered State")
      check(!Shared.Runtime.hasActiveBar, "bar published before host injection")
      check(state.setGroupSetting("G4", "compact", true), "stock own-entry write not queued")
      check(state.writePending && !state.groupSetting("G4", "compact", false), "stock optimistic publication")
      phase++
    } else if (phase === 1) {
      if (state.writePending) return
      check(state.writeStatus === "confirmed" && state.groupSetting("G4", "compact", false)
        && stateDispatches === 1 && barDispatches === 0, "stock own-entry write did not settle")
      barOwner.injectedHost = barApi
      check(Shared.Runtime.isActiveBar(barOwner) && barProvider.registered,
        "late bar injection was not reactive")
      barOwner.publishedReady = false
      check(state.ready, "State incorrectly depends on Bar publication")
      barOwner.publishedReady = true
      check(client.bar === stateApi.bar && client.bar !== barOwner,
        "client shell exported the whole active bar")
      check(client.firstPartyServiceFor("omarchy.nightlight") === null,
        "client shell expanded the native capability allowlist")
      check(state.setGroupSetting("G4", "compact", false), "suite own-entry write not queued")
      phase++
    } else if (phase === 2) {
      if (state.writePending) return
      check(state.writeStatus === "confirmed" && !state.groupSetting("G4", "compact", true)
        && stateDispatches === 2 && barDispatches === 0, "suite own-entry write did not settle")
      check(JSON.stringify(document.plugins[0].foreign) === '{"retained":[1,false]}'
        && stateApi.barConfig === root.initialBar && barApi.barConfig === root.initialBar,
        "write changed foreign fields or lagging Bar snapshots")
      oldLease = Shared.Runtime._selected("hancore.shibumi.state")
      check(state.setGroupSetting("G6", "enabledV2", false), "revocation control not queued")
      state.manifest = {id: "hancore.shibumi.state", version: "foreign", kinds: ["service"]}
      check(left.state === null && right.state === null && !state.ready && !state.writePending,
        "version drift retained State authority or queued intent")
      check(!state.setGroupSetting("G4", "compact", true), "revoked State accepted intent")
      state.manifest = {id: "hancore.shibumi.state", version: "0.1.1-beta.14", kinds: ["service"]}
      check(left.state === state && Shared.Runtime._selected("hancore.shibumi.state") !== oldLease,
        "State did not register a new lifetime")
      Shared.Runtime.unregisterProvider(oldLease)
      check(left.state === state, "old lease removed the new owner")
      first = serviceFactory.createObject(null)
      check(first !== null && client.serviceFor("hancore.shibumi.audio") === null,
        "parentless service published before injection")
      first.injectedHost = audioApi
      first.injectedManifest = {id: "hancore.shibumi.audio", version: "0.1.1-beta.14", kinds: ["service"]}
      check(client.serviceFor("hancore.shibumi.audio") === first, "provider registration failed")
      second = serviceFactory.createObject(null, {injectedHost: audioApi,
        injectedManifest: {id: "hancore.shibumi.audio", version: "0.1.1-beta.14", kinds: ["service"]}})
      check(client.serviceFor("hancore.shibumi.audio") === null,
        "duplicate provider was last-writer-wins: second=" + JSON.stringify({
          manifest: second.injectedManifest, kindsArray: Array.isArray(second.injectedManifest.kinds),
          host: second.injectedHost === audioApi, count: Shared.Runtime._leases.length})
        + " leases=" + JSON.stringify(Shared.Runtime._leases.map(function(lease) {
          return {id: lease.id, serial: lease.serial, first: lease.owner === first, second: lease.owner === second}
        })))
      const beforeRefresh = Shared.Runtime.revision
      observeOverlap = true
      second.injectedManifest = JSON.parse(JSON.stringify(second.injectedManifest))
      check(Shared.Runtime.revision === beforeRefresh, "equivalent metadata churned provider lifetime")
      second.injectedHost = replacementAudioApi
      observeOverlap = false
      check(overlapObservations > 0, "duplicate refresh observer was not exercised")
      second.destroy()
      phase++
    } else if (phase === 3) {
      check(client.serviceFor("hancore.shibumi.audio") === first,
        "duplicate destruction removed the surviving owner")
      first.injectedHost = "malformed-host"
      check(client.serviceFor("hancore.shibumi.audio") === null, "malformed scope retained provider")
      first.injectedHost = audioApi
      first.injectedHost = null
      check(client.serviceFor("hancore.shibumi.audio") === null, "scope loss retained provider")
      first.injectedHost = audioApi
      check(client.serviceFor("hancore.shibumi.audio") === first, "scope recovery stayed unavailable")
      let getterReached = false
      const malformed = {version: "0.1.1-beta.14", kinds: ["service"]}
      Object.defineProperty(malformed, "id", {get: function() {
        getterReached = true
        throw new Error("controlled malformed metadata getter")
      }})
      first.injectedManifest = malformed
      check(getterReached && client.serviceFor("hancore.shibumi.audio") === null,
        "metadata exception retained old authority")
      first.destroy()
      phase++
    } else if (phase === 4) {
      if (!state.ready) return
      check(stateDispatches === 2 && state.groupEnabledForVariant("G6", "v2"), "revoked queue survived recovery")
      check(client.serviceFor("hancore.shibumi.audio") === null, "destroyed provider remained reachable")
      check(client.serviceFor("omarchy.lock") === null
        && client.firstPartyServiceFor("omarchy.lock") === null, "unknown native capability was forwarded")
      console.log("shared runtime wiring and State own-entry writes passed")
      console.log("scoped state regression ready")
      phase++
    } else if (finishRequested) {
      check(Shared.Runtime.retired && !Shared.Runtime.ready, "marker change did not retire runtime")
      check(left.state === null && right.state === null && !Shared.Runtime.hasActiveBar,
        "retired runtime retained live exports")
      console.log("scoped state regression passed")
      Qt.exit(0)
    }
  }
  Connections {
    target: Shared.Runtime
    function onRevisionChanged() {
      if (root.observeOverlap) {
        root.overlapObservations++
        root.check(Shared.Runtime.serviceFor("hancore.shibumi.audio") === null,
          "provider refresh transiently exposed a duplicate owner")
      }
    }
  }
  Timer { interval: 30; running: true; repeat: true; onTriggered: root.advance() }
  IpcHandler {
    target: "scoped-state-test"
    function finish(): string { root.finishRequested = true; return "ok" }
  }
}
