pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "telemetry" as Telemetry
import "cpu" as Cpu
import "memory" as Memory
import "gpu" as Gpu
import "temperature" as Temperature
import "storage" as Storage
import "hancore.shibumi.state/runtime" as SuiteRuntime

ShellRoot {
  id: root
  property int phase: 0
  property int ticks: 0
  property var panels: []
  property var firstGpu: null
  function check(value, message) {
    if (value) return
    console.error("telemetry-runtime-smoke:", message)
    Qt.exit(1)
    throw new Error(message)
  }
  function manifest(id) { return {id: id, version: "0.1.1-beta.15", kinds: ["service"]} }
  component ScopedHost: QtObject {
    property string pluginId: ""
    function serviceFor(id) { root.check(false, "raw scoped lookup: " + id); return null }
  }
  ScopedHost { id: cpuHost; pluginId: "hancore.shibumi.cpu" }
  ScopedHost { id: telemetryHost; pluginId: "hancore.shibumi.telemetry" }
  ScopedHost { id: storageHost; pluginId: "hancore.shibumi.storage" }
  ScopedHost { id: stateHost; pluginId: "hancore.shibumi.state" }
  Cpu.Service { id: cpu; gpuProbeEnabled: false }
  Cpu.Service { id: duplicateCpu; gpuProbeEnabled: false }
  Telemetry.Service { id: telemetry; thermalProbeEnabled: false }
  Storage.Service { id: storage; storageProbeEnabled: false }
  QtObject {
    id: state
    property var config: ({})
    function setGroupSetting(group, key, value) { return false }
    function paletteColor(name) { return "#8899aa" }
  }
  SuiteRuntime.Provider {
    pluginId: "hancore.shibumi.state"
    implementationVersion: "0.1.1-beta.15"
    host: stateHost
    owner: state
    manifest: root.manifest("hancore.shibumi.state")
  }
  component LocalBar: QtObject {
    property var shell: cpuHost
    property bool vertical: false
    property int barSize: 35
    property int sizeHorizontal: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color background: "#111111"
    property color foreground: "#eeeeee"
    readonly property color barForeground: foreground
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var clickTargets: []
    function registerClickTarget(target) { clickTargets = clickTargets.concat([target]) }
    function unregisterClickTarget(target) {
      clickTargets = clickTargets.filter(function(item) { return item !== target })
    }
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function switchPanelFrom(owner, direction) { return false }
  }
  // Separate presentation owners; these are not physical output surfaces.
  LocalBar { id: cpuBar }
  LocalBar { id: memoryBar; position: "bottom" }
  LocalBar { id: gpuBar }
  LocalBar { id: thermalBar }
  LocalBar { id: storageBar }
  LocalBar { id: replacementBar; position: "bottom" }
  Loader {
    id: views
    sourceComponent: Item {
      readonly property alias cpuWidget: cpuWidget
      readonly property alias memoryWidget: memoryWidget
      readonly property alias gpuWidget: gpuWidget
      readonly property alias thermalWidget: thermalWidget
      readonly property alias storageWidget: storageWidget
      Cpu.BarWidget { id: cpuWidget; bar: cpuBar }
      Memory.BarWidget { id: memoryWidget; bar: memoryBar }
      Gpu.BarWidget { id: gpuWidget; bar: gpuBar }
      Temperature.BarWidget { id: thermalWidget; bar: thermalBar }
      Storage.BarWidget { id: storageWidget; bar: storageBar }
    }
  }
  function widgets() {
    return views.item ? [views.item.cpuWidget, views.item.memoryWidget,
      views.item.gpuWidget, views.item.thermalWidget, views.item.storageWidget] : []
  }
  function admitOwners() {
    cpu.shell = cpuHost; cpu.manifest = manifest(cpuHost.pluginId)
    telemetry.shell = telemetryHost; telemetry.manifest = manifest(telemetryHost.pluginId)
    storage.shell = storageHost; storage.manifest = manifest(storageHost.pluginId)
  }
  function samePanels() {
    const items = widgets()
    for (let index = 0; index < items.length; index++)
      check(items[index].panelItem === panels[index] && panels[index].open,
        "open panel recreated or closed at index " + index)
  }

  Timer {
    interval: 40
    repeat: true
    running: true
    onTriggered: {
      root.check(++root.ticks < 120, "deadline at phase " + root.phase)
      const items = root.widgets()
      if (root.phase === 0) {
        if (root.ticks < 3) return
        root.check(!cpu.ready && !telemetry.ready && !storage.ready
          && !cpu.backendLoaded && !telemetry.backendLoaded && !storage.backendLoaded
          && !duplicateCpu.backendLoaded
          && cpu.gpu === null && telemetry.system === null && telemetry.thermal === null
          && storage.storage === null, "backend created before injection")
        cpu.manifest = root.manifest(cpuHost.pluginId)
        telemetry.shell = telemetryHost
        root.phase++
      } else if (root.phase === 1) {
        root.check(!cpu.ready && !telemetry.ready && !cpu.backendLoaded
          && !telemetry.backendLoaded && cpu.gpu === null
          && telemetry.system === null, "incomplete injection admitted a backend")
        root.admitOwners()
        root.phase++
      } else if (root.phase === 2) {
        if (!cpu.ready || !telemetry.ready || !storage.ready || items.length !== 5) return
        root.check(items[0].telemetry === telemetry.system
          && items[1].telemetry === telemetry.system && items[2].gpu === cpu.gpu
          && items[3].telemetry === telemetry.thermal && items[4].storage === storage.storage
          && telemetry.gpuTelemetry === cpu.gpu, "shared scoped owner identity mismatch")
        root.check(!cpu.gpu.probeEnabled && !telemetry.thermal.probeEnabled
          && !storage.storage.runtimeProbesEnabled, "fixture probe suppression lost")
        cpu.gpu.parse("sysfs|42|61|0|0\nstatus|ok")
        telemetry.thermal.parseDetailed("55|63|80|100|44|70|90|39")
        storage.storage.parseUsage("/dev/fixture 1000 400 600 40%")
        for (const item of items) item.open()
        root.phase++
      } else if (root.phase === 3) {
        for (const item of items) if (!item.panelItem) return
        root.panels = items.map(function(item) { return item.panelItem })
        root.check(cpu.gpu.consumers === 3 && telemetry.system.cpuConsumers === 1
          && telemetry.system.memoryConsumers === 1 && storage.storage.consumers === 1
          && telemetry.thermal.consumers === 1, "open panel/widget leases unbalanced")
        root.firstGpu = cpu.gpu
        items[0].bar = replacementBar
        cpu.shell = null; telemetry.shell = null; storage.shell = null
        root.phase++
      } else if (root.phase === 4) {
        root.samePanels()
        root.check(!cpu.ready && !telemetry.ready && !storage.ready
          && !cpu.backendLoaded && !telemetry.backendLoaded && !storage.backendLoaded
          && cpu.gpu === null && telemetry.system === null && storage.storage === null
          && root.panels[0].gpuTelemetry === null && root.panels[0].systemTelemetry === null
          && root.panels[0].acquiredGpuTelemetry === null
          && root.panels[1].telemetry === null && root.panels[2].gpuTelemetry === null
          && root.panels[3].telemetry === null && root.panels[4].storage === null
          && root.panels[0].bar === replacementBar && root.panels[1].bar === memoryBar,
          "scope loss retained panel backend or crossed local bar")
        root.admitOwners()
        root.phase++
      } else if (root.phase === 5) {
        if (!cpu.ready || !telemetry.ready || !storage.ready) return
        root.samePanels()
        root.check(cpu.gpu !== root.firstGpu && cpu.gpu.consumers === 3
          && root.panels[0].gpuTelemetry === cpu.gpu
          && root.panels[0].acquiredGpuTelemetry === cpu.gpu
          && root.panels[1].telemetry === telemetry.system
          && root.panels[2].gpuTelemetry === cpu.gpu
          && root.panels[3].telemetry === telemetry.thermal
          && root.panels[4].storage === storage.storage,
          "restored providers did not rebind existing panels and leases")
        duplicateCpu.shell = cpuHost
        duplicateCpu.manifest = root.manifest(cpuHost.pluginId)
        root.phase++
      } else if (root.phase === 6) {
        root.check(!cpu.ready && !duplicateCpu.ready
          && !cpu.backendLoaded && !duplicateCpu.backendLoaded && cpu.gpu === null
          && duplicateCpu.gpu === null && telemetry.gpuTelemetry === null
          && root.panels[0].gpuTelemetry === null && root.panels[2].gpuTelemetry === null
          && telemetry.ready && storage.ready, "duplicate CPU exposed an owner or revoked peers")
        duplicateCpu.shell = null
        root.phase++
      } else if (root.phase === 7) {
        if (!cpu.ready) return
        root.samePanels()
        root.check(cpu.gpu.consumers === 3 && !duplicateCpu.ready,
          "duplicate removal did not restore the sole GPU owner")
        for (const item of items) item.close()
        root.phase++
      } else if (root.phase === 8) {
        root.check(cpu.gpu.consumers === 2, "CPU panel close retained its GPU lease")
        for (const item of items) root.check(item.panelItem === null, "closed panel retained")
        views.active = false
        root.phase++
      } else {
        root.check(telemetry.system.cpuConsumers === 0 && telemetry.system.memoryConsumers === 0
          && cpu.gpu.consumers === 0 && telemetry.thermal.consumers === 0
          && storage.storage.consumers === 0, "view destruction retained sampler leases")
        cpu.shell = null; telemetry.shell = null; storage.shell = null
        console.log("telemetry runtime smoke passed")
        Qt.exit(0)
      }
    }
  }
}
