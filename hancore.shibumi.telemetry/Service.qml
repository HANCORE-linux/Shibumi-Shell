pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/runtime" as SuiteRuntime

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  // Test fixtures may keep thermal state deterministic without host probes.
  property bool thermalProbeEnabled: true
  SuiteRuntime.HostShell { id: suiteShell; host: root.shell }
  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.telemetry"
    implementationVersion: "0.1.1-beta.13"
    owner: root
    host: root.shell
    manifest: root.manifest
  }

  readonly property int contractVersion: 1
  readonly property bool backendAdmitted: runtimeProvider.registered
  readonly property bool backendLoaded: systemLoader.item !== null || thermalLoader.item !== null
  readonly property bool ready: backendAdmitted && system !== null && thermal !== null
  readonly property var system: backendAdmitted ? systemLoader.item : null
  readonly property var thermal: backendAdmitted ? thermalLoader.item : null
  readonly property var cpuService: suiteShell.serviceFor("hancore.shibumi.cpu")
  readonly property var gpuTelemetry: cpuService ? cpuService.gpu : null

  // Invalidate publication before destroying sampler contexts held by peers.
  function syncBackends() {
    systemLoader.active = backendAdmitted
    thermalLoader.active = backendAdmitted
  }
  onBackendAdmittedChanged: Qt.callLater(syncBackends)
  Component.onCompleted: Qt.callLater(syncBackends)

  Loader {
    id: systemLoader
    active: false
    sourceComponent: SystemTelemetry {}
  }
  Loader {
    id: thermalLoader
    active: false
    sourceComponent: ThermalTelemetry {
      probeEnabled: root.thermalProbeEnabled
      gpuTelemetry: root.gpuTelemetry
    }
  }
}
