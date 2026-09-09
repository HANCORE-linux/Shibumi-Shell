pragma ComponentBehavior: Bound

import QtQuick
import "../hancore.shibumi.state/host" as ShibumiHost

Item {
  id: root

  readonly property var suiteHostShell: ShibumiHost.HostShell {
    pluginId: "hancore.shibumi.telemetry"
    owner: root
  }
  onShellChanged: if (shell && shell !== suiteHostShell) {
    suiteHostShell.host = shell
    shell = suiteHostShell
  }

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  // Test fixtures may keep thermal state deterministic without host probes.
  property bool thermalProbeEnabled: true

  readonly property int contractVersion: 1
  readonly property bool ready: true
  readonly property alias system: systemState
  readonly property alias thermal: thermalState
  readonly property var gpuTelemetry: shell
    && typeof shell.serviceFor === "function"
    && shell.serviceFor("hancore.shibumi.cpu")
    ? shell.serviceFor("hancore.shibumi.cpu").gpu : null

  SystemTelemetry {
    id: systemState
  }

  ThermalTelemetry {
    id: thermalState
    probeEnabled: root.thermalProbeEnabled
    gpuTelemetry: root.gpuTelemetry
  }
}
