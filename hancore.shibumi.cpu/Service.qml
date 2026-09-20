pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/runtime" as SuiteRuntime

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property bool gpuProbeEnabled: true
  SuiteRuntime.Provider {
    id: runtimeProvider
    pluginId: "hancore.shibumi.cpu"
    implementationVersion: "0.1.1-beta.15"
    owner: root
    host: root.shell
    manifest: root.manifest
  }

  readonly property int contractVersion: 1
  readonly property bool backendAdmitted: runtimeProvider.registered
  readonly property bool backendLoaded: gpuLoader.item !== null
  readonly property bool ready: backendAdmitted && gpu !== null
  readonly property var gpu: backendAdmitted ? gpuLoader.item : null

  // Publish loss first so peers release this sampler while its context lives.
  // Recheck current admission when draining; completion alone grants nothing.
  function syncBackend() { gpuLoader.active = backendAdmitted }
  onBackendAdmittedChanged: Qt.callLater(syncBackend)
  Component.onCompleted: Qt.callLater(syncBackend)

  Loader {
    id: gpuLoader
    active: false
    sourceComponent: GpuTelemetry {
      probeEnabled: root.gpuProbeEnabled
      helperPath: String(Qt.resolvedUrl(
        "scripts/shibumi-gpu-probe")).replace("file://", "")
    }
  }
}
