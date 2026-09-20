pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../hancore.shibumi.state/runtime" as SuiteRuntime

// One process-wide AudioBackendAdapter owns PipeWire and actions. Widgets
// report presentation state; neither output count nor IPC creates an owner.
Item {
  id: root

  property var shell: null
  property var manifest: null
  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.audio"
    implementationVersion: "0.1.1-beta.15"
    owner: root
    host: root.shell
    manifest: root.manifest
  }
  readonly property bool backendAdmitted: runtimeProvider.registered
  property var reports: []
  // Native AudioBackendAdapter is now the sole Shibumi PipeWire owner.
  property bool nativeBackendEnabled: true
  property var nativeBackendOverride: null
  readonly property bool nativeBackendReady: root.backendAdmitted
    && root.nativeBackendEnabled && nativeBackendLoader.item ? nativeBackendLoader.item.ready === true : false
  readonly property var nativeAudioSinks: nativeBackendLoader.item
    ? nativeBackendLoader.item.audioSinks : []
  readonly property var nativeAudioSources: nativeBackendLoader.item
    ? nativeBackendLoader.item.audioSources : []
  readonly property var nativeAudioStreams: nativeBackendLoader.item
    ? nativeBackendLoader.item.audioStreams : []
  readonly property var nativeSinkSnapshot: nativeBackendLoader.item
    ? nativeBackendLoader.item.sinkSnapshot : null
  readonly property var nativeVolumeSinkSnapshot: nativeBackendLoader.item
    ? nativeBackendLoader.item.volumeSinkSnapshot : null
  readonly property var nativeSourceSnapshot: nativeBackendLoader.item
    ? nativeBackendLoader.item.sourceSnapshot : null
  readonly property real nativeOutputVolume: nativeBackendLoader.item
    ? Number(nativeBackendLoader.item.outputVolume || 0) : 0
  readonly property bool nativeOutputMuted: nativeBackendLoader.item
    ? nativeBackendLoader.item.outputMuted === true : false
  readonly property real nativeInputVolume: nativeBackendLoader.item
    ? Number(nativeBackendLoader.item.inputVolume || 0) : 0
  readonly property bool nativeInputMuted: nativeBackendLoader.item
    ? nativeBackendLoader.item.inputMuted === true : false
  readonly property real inputPeak: root.nativeBackendEnabled
    ? (nativeBackendLoader.item
      ? Number(nativeBackendLoader.item.inputPeak || 0) : 0)
    : (peakBackendLoader.item
      ? Number(peakBackendLoader.item.inputPeak || 0) : 0)
  property int peakMonitorClients: 0
  property bool ready: false
  property bool outputMuted: false

  visible: false
  width: 0
  height: 0

  Loader {
    id: peakBackendLoader
    active: root.backendAdmitted && !root.nativeBackendEnabled
    source: Qt.resolvedUrl("AudioPeakMonitor.qml")
    onLoaded: item.clients = root.peakMonitorClients
  }

  Loader {
    id: nativeBackendLoader
    active: root.backendAdmitted && root.nativeBackendEnabled
    source: Qt.resolvedUrl("AudioBackendAdapter.qml")
    onLoaded: {
      // Apply test/native injection before activation so a fake backend never
      // briefly evaluates the real PipeWire service.
      item.backendOverride = root.nativeBackendOverride
      item.peakMonitoringClients = root.peakMonitorClients
      item.active = root.backendAdmitted && root.nativeBackendEnabled
    }
  }

  onBackendAdmittedChanged: {
    if (!backendAdmitted) {
      reports = []
      syncSnapshot()
    }
  }

  onNativeBackendEnabledChanged: {
    if (root.nativeBackendEnabled) {
      if (peakBackendLoader.item) peakBackendLoader.item.clients = 0
    } else if (nativeBackendLoader.item) {
      nativeBackendLoader.item.peakMonitoringClients = 0
    }
  }

  onNativeBackendOverrideChanged: {
    if (!nativeBackendLoader.item) return
    nativeBackendLoader.item.active = false
    nativeBackendLoader.item.backendOverride = root.nativeBackendOverride
    nativeBackendLoader.item.active = root.backendAdmitted && root.nativeBackendEnabled
  }

  function acquirePeakMonitoring() {
    if (!backendAdmitted) return false
    const owner = root.nativeBackendEnabled
      ? nativeBackendLoader.item : peakBackendLoader.item
    const method = root.nativeBackendEnabled
      ? "acquirePeakMonitoring" : "acquire"
    if (!owner || typeof owner[method] !== "function") {
      peakMonitorClients++
      return true
    }
    const acquired = owner[method]() === true
    if (acquired) peakMonitorClients++
    return acquired
  }

  function releasePeakMonitoring() {
    if (peakMonitorClients <= 0) return false
    const owner = root.nativeBackendEnabled
      ? nativeBackendLoader.item : peakBackendLoader.item
    const method = root.nativeBackendEnabled
      ? "releasePeakMonitoring" : "release"
    peakMonitorClients--
    if (owner && typeof owner[method] === "function") owner[method]()
    return true
  }

  function nativeSetDefaultSink(id) {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.setDefaultSink(id) : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: String(id || ""), generation: 0
      })
  }
  function nativeSetDefaultSource(id) {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.setDefaultSource(id) : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: String(id || ""), generation: 0
      })
  }
  function nativeSetOutputVolume(value) {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.setOutputVolume(value) : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: "", generation: 0
      })
  }
  function nativeToggleOutputMute() {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.toggleOutputMute() : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: "", generation: 0
      })
  }
  function nativeSetInputVolume(value) {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.setInputVolume(value) : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: "", generation: 0
      })
  }
  function nativeToggleInputMute() {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.toggleInputMute() : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: "", generation: 0
      })
  }
  function nativeSetStreamVolume(id, value) {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.setStreamVolume(id, value) : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: String(id || ""), generation: 0
      })
  }
  function nativeToggleStreamMute(id) {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.toggleStreamMute(id) : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: String(id || ""), generation: 0
      })
  }
  function routeBluetoothDevice(request) {
    return backendAdmitted && nativeBackendLoader.item
      ? nativeBackendLoader.item.routeBluetoothDevice(request) : ({
        ok: false, code: "unavailable", message: "Audio backend is unavailable",
        entityId: "", generation: 0
      })
  }
  function report(owner, available, muted) {
    if (!backendAdmitted || !owner) return false
    const next = reports.filter(entry => entry.owner !== owner)
    next.push({ owner: owner, ready: available === true, muted: muted === true })
    reports = next
    syncSnapshot()
    return true
  }

  function release(owner) {
    if (!owner) return false
    const next = reports.filter(entry => entry.owner !== owner)
    if (next.length === reports.length) return false
    reports = next
    syncSnapshot()
    return true
  }

  function activeBar() {
    return shell && shell.bar ? shell.bar : null
  }

  function openPanel() {
    if (!backendAdmitted) return false
    if (shell && "pluginId" in shell)
      return typeof shell.summon === "function"
        && shell.summon("hancore.shibumi.audio", "") === true
    const bar = activeBar()
    return bar && typeof bar.summonBarWidget === "function"
      ? bar.summonBarWidget("omarchy.audio") : false
  }

  function closePanel() {
    if (!backendAdmitted) return false
    if (shell && "pluginId" in shell)
      return typeof shell.hide === "function"
        && shell.hide("hancore.shibumi.audio") === true
    const bar = activeBar()
    return bar && typeof bar.hideBarWidget === "function"
      ? bar.hideBarWidget("omarchy.audio") : false
  }

  function togglePanel() {
    if (!backendAdmitted) return false
    if (shell && "pluginId" in shell)
      return typeof shell.toggle === "function"
        && shell.toggle("hancore.shibumi.audio", "") === true
    const bar = activeBar()
    if (!bar) return false
    return typeof bar.isBarWidgetOpen === "function"
        && bar.isBarWidgetOpen("omarchy.audio")
      ? closePanel() : openPanel()
  }

  IpcHandler {
    enabled: root.backendAdmitted
    target: "omarchy.audio"

    function open(): void { root.openPanel() }
    function close(): void { root.closePanel() }
    function show(): void { root.openPanel() }
    function hide(): void { root.closePanel() }
    function toggle(): void { root.togglePanel() }
  }

  function syncSnapshot() {
    for (let index = 0; index < reports.length; index++) {
      if (!reports[index].ready) continue
      ready = true
      outputMuted = reports[index].muted
      return
    }
    ready = false
    outputMuted = false
  }
}
